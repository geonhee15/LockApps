import AppKit
import Darwin
import Observation

/// What the engine asks the unlock UI to show.
struct UnlockRequest {
    let pid: pid_t
    let bundleID: String
    let name: String
    let path: String?
}

/// Watches app launches / activations and holds locked apps until the right password is entered.
///
/// Two hold modes:
///  * **stopped** — the app was caught while launching; it gets SIGSTOP before it can draw a window,
///    SIGCONT on success, SIGKILL on cancel.
///  * **hidden** — the app was already running (e.g. activated from the Dock or locked while open);
///    it is hidden and re-hidden until unlocked, terminated on cancel.
/// An unlock lasts until that process quits.
@MainActor
@Observable
final class LockEngine {
    private(set) var isRunning = false
    private(set) var heldCount = 0

    private let store: LockStore
    private let prompt: UnlockPromptController

    private enum HoldMode { case stopped, hidden }

    private struct Held {
        let app: NSRunningApplication
        let mode: HoldMode
        var rehideTimer: Timer?
    }

    private var held: [pid_t: Held] = [:]
    private var unlocked: Set<pid_t> = []
    private var queue: [pid_t] = []
    private var current: pid_t?

    private var observers: [NSObjectProtocol] = []
    private var runningObservation: NSKeyValueObservation?
    private var knownPIDs: Set<pid_t> = []

    static let maxAttempts = 5

    init(store: LockStore, prompt: UnlockPromptController) {
        self.store = store
        self.prompt = prompt
        store.onChange = { [weak self] in self?.locksChanged() }
    }

    // MARK: Start / stop

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        knownPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))

        observers.append(center.addObserver(forName: NSWorkspace.willLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.appAppeared(app) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.appAppeared(app) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.appActivated(app) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.appTerminated(app) }
        })
        // KVO on runningApplications fires the moment a process registers — earlier than the launch notifications.
        runningObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] workspace, _ in
            let apps = workspace.runningApplications
            Task { @MainActor [weak self] in
                guard let self else { return }
                let now = Set(apps.map(\.processIdentifier))
                let fresh = apps.filter { !self.knownPIDs.contains($0.processIdentifier) }
                self.knownPIDs = now
                for app in fresh { self.appAppeared(app) }
            }
        }
        // A previous copy may have been killed while holding apps (they stay SIGSTOPped): adopt them and ask again.
        for app in NSWorkspace.shared.runningApplications where isLocked(app) && ProcessState.isStopped(app.processIdentifier) {
            NSLog("LockApps: adopting stopped \(app.bundleIdentifier ?? "?") pid \(app.processIdentifier)")
            hold(app, mode: .stopped)
        }
        NSLog("LockApps: engine started (\(store.count) locks)")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
        runningObservation = nil
        releaseAll()
        NSLog("LockApps: engine stopped")
    }

    /// Lets every held app go (used on stop and on quit so nothing stays frozen).
    func releaseAll() {
        prompt.dismiss()
        current = nil
        queue.removeAll()
        for pid in Array(held.keys) { resume(pid, activate: false) }
        unlocked.removeAll()
        heldCount = 0
    }

    // MARK: Workspace events

    private func isLocked(_ app: NSRunningApplication) -> Bool {
        guard let bid = app.bundleIdentifier else { return false }
        guard bid != Bundle.main.bundleIdentifier else { return false }
        return store.isLocked(bid)
    }

    private func appAppeared(_ app: NSRunningApplication) {
        guard isRunning, isLocked(app) else { return }
        let pid = app.processIdentifier
        guard pid > 0, !unlocked.contains(pid), held[pid] == nil, !app.isTerminated else { return }
        if !app.isFinishedLaunching {
            // Freeze before the first window shows up.
            if kill(pid, SIGSTOP) == 0 {
                hold(app, mode: .stopped)
                return
            }
            NSLog("LockApps: SIGSTOP failed for \(app.bundleIdentifier ?? "?") (\(errno)); falling back to hide")
        }
        app.hide()
        hold(app, mode: .hidden)
    }

    private func appActivated(_ app: NSRunningApplication) {
        guard isRunning, isLocked(app) else { return }
        let pid = app.processIdentifier
        guard !unlocked.contains(pid), held[pid] == nil else { return }
        NSLog("LockApps: locked app \(app.bundleIdentifier ?? "?") pid \(pid) became active → hiding")
        app.hide()
        hold(app, mode: .hidden)
    }

    private func appTerminated(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        unlocked.remove(pid)
        knownPIDs.remove(pid)
        guard held[pid] != nil else { return }
        clearHold(pid)
        if current == pid {
            current = nil
            prompt.dismiss()
        }
        queue.removeAll { $0 == pid }
        showNext()
    }

    private func locksChanged() {
        // A lock that was removed while its app is held → let the app go.
        for (pid, h) in held where !isLocked(h.app) {
            if current == pid { prompt.dismiss(); current = nil }
            queue.removeAll { $0 == pid }
            resume(pid, activate: true)
        }
        showNext()
    }

    // MARK: Holding

    private func hold(_ app: NSRunningApplication, mode: HoldMode) {
        let pid = app.processIdentifier
        var h = Held(app: app, mode: mode, rehideTimer: nil)
        if mode == .hidden {
            h.rehideTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak app] _ in
                guard let app, !app.isTerminated else { return }
                if !app.isHidden { app.hide() }
            }
        }
        held[pid] = h
        heldCount = held.count
        queue.append(pid)
        NSLog("LockApps: holding \(app.bundleIdentifier ?? "?") pid \(pid) (\(mode))")
        showNext()
    }

    private func clearHold(_ pid: pid_t) {
        held[pid]?.rehideTimer?.invalidate()
        held[pid] = nil
        heldCount = held.count
    }

    /// Resumes a held app (correct password, lock removed, engine stopped).
    private func resume(_ pid: pid_t, activate: Bool) {
        guard let h = held[pid] else { return }
        clearHold(pid)
        unlocked.insert(pid)
        let app = h.app
        switch h.mode {
        case .stopped:
            kill(pid, SIGCONT)
        case .hidden:
            app.unhide()
        }
        guard activate else { return }
        let bundleURL = app.bundleURL
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard !app.isTerminated else { return }
            app.unhide()
            app.activate(from: .current, options: [])
            // Cooperative activation (macOS 14+) can be refused when we are not the active app; asking
            // LaunchServices to open the already-running app is the same as clicking it in the Dock.
            if let bundleURL {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, error in
                    if let error { NSLog("LockApps: re-activate failed: \(error.localizedDescription)") }
                }
            }
        }
    }

    /// Cancelled / too many wrong passwords → the app is closed.
    private func deny(_ pid: pid_t) {
        guard let h = held[pid] else { return }
        clearHold(pid)
        let app = h.app
        switch h.mode {
        case .stopped:
            kill(pid, SIGKILL)
        case .hidden:
            if !app.terminate() { app.forceTerminate() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if !app.isTerminated { app.forceTerminate() }
            }
        }
    }

    // MARK: Prompt queue

    private func showNext() {
        guard current == nil else { return }
        while let pid = queue.first {
            queue.removeFirst()
            guard let h = held[pid], !h.app.isTerminated else { continue }
            current = pid
            let bid = h.app.bundleIdentifier ?? ""
            let entry = store.entry(for: bid)
            let request = UnlockRequest(pid: pid, bundleID: bid,
                                        name: entry?.name ?? h.app.localizedName ?? bid,
                                        path: h.app.bundleURL?.path ?? entry?.path)
            prompt.show(request: request, maxAttempts: Self.maxAttempts,
                        verify: { [weak self] password in self?.store.verify(bid, password: password) ?? false },
                        completion: { [weak self] success in
                            guard let self else { return }
                            self.current = nil
                            if success { self.resume(pid, activate: true) } else { self.deny(pid) }
                            self.showNext()
                        })
            return
        }
    }
}

enum ProcessState {
    /// True when the process is in the stopped state (SIGSTOP), via sysctl KERN_PROC_PID.
    static func isStopped(_ pid: pid_t) -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return false }
        return Int32(info.kp_proc.p_stat) == 4 /* SSTOP */
    }
}
