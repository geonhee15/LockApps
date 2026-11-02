import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let settings = AppSettings.shared
    let store = LockStore()
    let scanner = AppScanner()
    let ui = UIState()
    let prompt = UnlockPromptController()
    private(set) lazy var engine = LockEngine(store: store, prompt: prompt)

    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var sigterm: DispatchSourceSignal?
    private let env = ProcessInfo.processInfo.environment
    private static let showWindowNote = Notification.Name("com.geonhee.lockapps.showWindow")
    private static let handoffNote = Notification.Name("com.geonhee.lockapps.handoff")
    private static let handoffWindowKey = "handoffShowWindow"

    /// Screenshot / sample-data runs: separate data dir, nothing persisted, engine never started.
    private var isDebugRun: Bool { env["LOCKAPPS_DATA_DIR"] != nil }
    /// Debug runs normally never enforce locks; LOCKAPPS_DEBUG_ENGINE=1 opts in for end-to-end tests.
    private var debugEngineAllowed: Bool { isDebugRun && env["LOCKAPPS_DEBUG_ENGINE"] == "1" }
    /// Started by launchd through the embedded agent plist: stays in the menu bar unless a window was handed over.
    private var isAgentInstance: Bool { settings.isAgentInstance }

    // MARK: Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        enforceSingleInstance()
        settings.applyAppearance()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.build(
            openSettings: { [weak self] in self?.showWindow(); self?.ui.sheet = .settings },
            openWindow: { [weak self] in self?.showWindow() }
        )
        setupStatusItem()
        installSignalHandler()
        settings.onProtectionChanged = { [weak self] on in self?.applyProtection(on) }
        scanner.scan()

        if !isDebugRun {
            settings.migrateLegacyLoginItem()
            // Protection only survives quits/crashes with the agent registered; put it back if it went missing.
            if settings.protectionEnabled, !settings.launchAtLogin, !settings.launchAtLoginNeedsApproval {
                settings.setLaunchAtLogin(true)
            } else if settings.launchAtLogin, !isAgentInstance {
                // We are a hand-launched copy although the agent is enabled, so launchd's copy is not running
                // (typically a rebuilt bundle that no longer matches the registration). Register again; the fresh
                // launchd copy takes over from us.
                settings.refreshAgentRegistration()
            }
        }
        if settings.protectionEnabled, !isDebugRun || debugEngineAllowed { engine.start() }

        let tookOverWindow = UserDefaults.standard.bool(forKey: Self.handoffWindowKey)
        if tookOverWindow { UserDefaults.standard.removeObject(forKey: Self.handoffWindowKey) }
        let background = (isAgentInstance || launchedAsLoginItem(notification)) && !tookOverWindow
        if !background || isDebugRun { showWindow() }
        applyDebugFlags()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isDebugRun || quitRequestedBySystem() { return .terminateNow }
        guard settings.protectionEnabled, store.count > 0 else { return .terminateNow }
        let supervised = settings.launchAtLogin
        let alert = NSAlert()
        alert.messageText = "LockApps를 종료할까요?"
        alert.informativeText = supervised
            ? "보호 중이라 종료해도 백그라운드에서 몇 초 안에 다시 실행됩니다. 창만 닫으면 Dock에서 사라지고 메뉴 막대에서 계속 지킵니다. 잠금을 완전히 멈추려면 보호를 끄세요."
            : "종료하면 다시 실행할 때까지 잠근 앱 \(store.count)개에 비밀번호를 묻지 않습니다. 창만 닫으면 메뉴 막대에서 계속 지킵니다."
        alert.addButton(withTitle: "창만 닫기")
        alert.addButton(withTitle: supervised ? "보호 끄고 종료" : "종료 (보호 중단)")
        alert.addButton(withTitle: "취소")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if window?.isVisible == true { window?.close() } else { NSApp.setActivationPolicy(.accessory) }
            return .terminateCancel
        case .alertSecondButtonReturn:
            if supervised { settings.protectionEnabled = false }
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.releaseAll()
    }

    /// Logout / shutdown / restart quits carry a reason; never block those with a dialog.
    private func quitRequestedBySystem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == 0x7175_6974 /* 'quit' */ else { return false }
        return event.attributeDescriptor(forKeyword: 0x7768_793F /* 'why?' kAEQuitReason */) != nil
    }

    /// launchd (unregister, logout) and `kill` send SIGTERM; let held apps go before exiting. A non-zero exit while
    /// protecting makes launchd (KeepAlive.SuccessfulExit = false) start a fresh copy.
    private func installSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.engine.releaseAll()
                exit(self?.settings.protectionEnabled == true ? 1 : 0)
            }
        }
        source.resume()
        sigterm = source
    }

    // MARK: Window

    func showWindow() {
        NSApp.setActivationPolicy(.regular)
        if window == nil { window = makeWindow() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closing the window turns LockApps back into a menu-bar-only app (no Dock icon) that keeps protecting.
    func windowWillClose(_ notification: Notification) {
        guard !isDebugRun else { return }
        DispatchQueue.main.async { [weak self] in
            if self?.window?.isVisible != true { NSApp.setActivationPolicy(.accessory) }
        }
    }

    private func makeWindow() -> NSWindow {
        var size = NSSize(width: 620, height: 760)
        if let spec = env["LOCKAPPS_WINDOW_SIZE"], let x = spec.firstIndex(of: "x"),
           let w = Double(spec[..<x]), let h = Double(spec[spec.index(after: x)...]) {
            size = NSSize(width: w, height: h)
        }
        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        w.title = "LockApps"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.minSize = NSSize(width: 520, height: 580)
        w.isReleasedWhenClosed = false
        w.isOpaque = false
        w.backgroundColor = .clear
        w.delegate = self
        let root = RootView(scanner: scanner, store: store, settings: settings, engine: engine, ui: ui)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        w.contentView = hosting
        let autosave = "LockAppsMainWindow"
        if isDebugRun || !w.setFrameUsingName(autosave) { w.center() }
        if !isDebugRun { w.setFrameAutosaveName(autosave) }
        return w
    }

    // MARK: Protection

    private func applyProtection(_ on: Bool) {
        if on, !isDebugRun || debugEngineAllowed { engine.start() } else { engine.stop() }
        updateStatusIcon()
    }

    // MARK: Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        let name = settings.protectionEnabled ? "lock.fill" : "lock.open"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "LockApps")
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = settings.protectionEnabled ? "LockApps · 보호 중" : "LockApps · 보호 꺼짐"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = NSMenuItem(title: "LockApps 열기", action: #selector(menuOpen), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let status = NSMenuItem(title: settings.protectionEnabled ? "보호 중 · 잠근 앱 \(store.count)개" : "보호 꺼짐 · 잠근 앱 \(store.count)개", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        let background = NSMenuItem(title: settings.launchAtLogin ? "백그라운드 실행 · 켜짐 (종료돼도 다시 실행)" : "백그라운드 실행 · 꺼짐", action: nil, keyEquivalent: "")
        background.isEnabled = false
        menu.addItem(background)
        let toggle = NSMenuItem(title: settings.protectionEnabled ? "보호 끄기" : "보호 켜기 (적용)", action: #selector(menuToggleProtection), keyEquivalent: "")
        toggle.target = self
        toggle.isEnabled = settings.protectionEnabled || store.count > 0
        menu.addItem(toggle)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "LockApps 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func menuOpen() { showWindow() }

    @objc private func menuToggleProtection() {
        if settings.protectionEnabled {
            showWindow()
            ProtectionActions.turnOff(settings: settings, ui: ui)
        } else {
            ProtectionActions.apply(settings: settings, ui: ui)
        }
    }

    // MARK: Single instance / hand-off / login item

    private func enforceSingleInstance() {
        guard !isDebugRun, let bid = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        let center = DistributedNotificationCenter.default()
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first(where: { $0.processIdentifier != me }) {
            if isAgentInstance {
                // launchd started us while a hand-launched copy is running: ask it to step aside so the
                // supervised copy is the one that owns protection (it is the one launchd will relaunch).
                center.postNotificationName(Self.handoffNote, object: nil, userInfo: nil, deliverImmediately: true)
                let deadline = Date().addingTimeInterval(8)
                while !other.isTerminated, Date() < deadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                }
                if !other.isTerminated {
                    NSLog("LockApps: pid \(other.processIdentifier) did not hand off; launchd copy exits")
                    exit(0)
                }
                NSLog("LockApps: took over from pid \(other.processIdentifier)")
            } else {
                center.postNotificationName(Self.showWindowNote, object: nil, userInfo: nil, deliverImmediately: true)
                other.activate()
                exit(0)
            }
        }
        center.addObserver(forName: Self.showWindowNote, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showWindow() }
        }
        center.addObserver(forName: Self.handoffNote, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handOff() }
        }
    }

    /// The launchd-supervised copy is taking over: free held apps, remember whether the window was open, leave.
    private func handOff() {
        guard !isAgentInstance else { return }
        UserDefaults.standard.set(window?.isVisible == true, forKey: Self.handoffWindowKey)
        UserDefaults.standard.synchronize()
        engine.releaseAll()
        NSLog("LockApps: handing off to the launchd copy")
        exit(0)
    }

    private func launchedAsLoginItem(_ note: Notification) -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        // kAEOpenApplication 'oapp' carrying keyAEPropData 'prdt' == keyAELaunchedAsLogInItem 'lgit'
        guard event.eventID == 0x6F61_7070 else { return false }
        return event.paramDescriptor(forKeyword: 0x7072_6474)?.enumCodeValue == 0x6C67_6974
    }

    // MARK: Debug / screenshot flags (see README "개발용 환경 변수")

    private func applyDebugFlags() {
        guard isDebugRun else { return }
        if let typed = env["LOCKAPPS_DEBUG_AUTOTYPE"] { prompt.debugAutoType = typed }
        Task { @MainActor in
            while scanner.isScanning { try? await Task.sleep(for: .milliseconds(80)) }
            if let list = env["LOCKAPPS_DEBUG_LOCK"] {
                for bid in list.split(separator: ",").map(String.init) {
                    if let app = scanner.apps.first(where: { $0.bundleID == bid }) { store.setLock(for: app, password: "1234") }
                }
            }
            if env["LOCKAPPS_DEBUG_SAMPLE_LOCKS"] == "1" {
                let wanted = ["com.apple.calculator", "com.apple.weather", "com.apple.Notes", "com.apple.Safari", "com.apple.MobileSMS", "com.apple.Photos"]
                for bid in wanted {
                    if let app = scanner.apps.first(where: { $0.bundleID == bid }) { store.setLock(for: app, password: "1234") }
                }
            }
            if let filter = env["LOCKAPPS_DEBUG_FILTER"], let f = ListFilter(rawValue: filter) { ui.filter = f }
            if let search = env["LOCKAPPS_DEBUG_SEARCH"] { ui.search = search }
            if let spec = env["LOCKAPPS_DEBUG_SHEET"] {
                let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
                let app = parts.count > 1 ? scanner.apps.first(where: { $0.bundleID == parts[1] }) : nil
                switch parts[0] {
                case "set": if let app { ui.sheet = .setPassword(app) }
                case "change": if let app { ui.sheet = .changePassword(app) }
                case "remove": if let app { ui.sheet = .removeLock(app) }
                case "settings": ui.sheet = .settings
                default: break
                }
            }
            if let bid = env["LOCKAPPS_DEBUG_PROMPT"] {
                let app = scanner.apps.first(where: { $0.bundleID == bid })
                let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
                let size = NSSize(width: 900, height: 620)
                prompt.debugFrame = NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
                prompt.show(request: UnlockRequest(pid: 0, bundleID: bid, name: app?.name ?? bid, path: app?.path),
                            maxAttempts: LockEngine.maxAttempts, verify: { $0 == "1234" }, completion: { _ in })
                if env["LOCKAPPS_DEBUG_PROMPT_ERROR"] == "1" {
                    prompt.model.attempts = 1
                    prompt.model.errorText = "비밀번호가 맞지 않아요 · 4번 남음"
                }
            }
            let delay = Double(env["LOCKAPPS_SNAPSHOT_DELAY"] ?? "") ?? 2.5
            let mainPath = env["LOCKAPPS_SNAPSHOT"]
            let promptPath = env["LOCKAPPS_SNAPSHOT_PROMPT"]
            guard mainPath != nil || promptPath != nil else { return }
            try? await Task.sleep(for: .seconds(delay))
            if let mainPath { writeWindowSnapshot(to: mainPath) }
            if let promptPath { prompt.writeSnapshot(to: promptPath) }
            if env["LOCKAPPS_SNAPSHOT_EXIT"] != "0" { NSApp.terminate(nil) }
        }
    }

    private func writeWindowSnapshot(to path: String) {
        guard let window else { return }
        WindowSnapshot.write(window: window, to: path)
    }
}

/// Shared "적용" / "끄기" behaviour for the bottom bar, the settings card and the status-item menu.
@MainActor
enum ProtectionActions {
    static func apply(settings: AppSettings, ui: UIState) {
        settings.protectionEnabled = true
        if !settings.launchAtLogin { settings.setLaunchAtLogin(true) }
        if settings.launchAtLoginNeedsApproval {
            ui.flash("적용됐어요 · 시스템 설정에서 LockApps 백그라운드 실행을 허용해 주세요")
        } else if settings.launchAtLogin {
            ui.flash("적용됐어요 · 창을 닫거나 종료돼도 백그라운드에서 계속 지킵니다")
        } else {
            ui.flash("적용됐어요 · 이제 잠근 앱을 열면 비밀번호를 묻습니다")
        }
    }

    static func turnOff(settings: AppSettings, ui: UIState) {
        let alert = NSAlert()
        alert.messageText = "보호를 끌까요?"
        alert.informativeText = "잠금 설정은 그대로 남고, 다시 적용할 때까지 비밀번호를 묻지 않습니다."
        alert.addButton(withTitle: "끄기")
        alert.addButton(withTitle: "취소")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        settings.protectionEnabled = false
        ui.flash("보호를 껐어요 · 잠금 목록은 남아 있습니다")
    }

    /// Background-agent switch. Turning it off while launchd owns this process stops the process too, so ask first.
    static func setBackgroundAgent(_ enabled: Bool, settings: AppSettings, ui: UIState) {
        if !enabled, settings.isAgentInstance {
            let alert = NSAlert()
            alert.messageText = "백그라운드 실행을 끌까요?"
            alert.informativeText = "이 LockApps는 launchd가 띄운 사본이라, 끄면 지금 바로 종료되고 다음에 직접 실행할 때까지 잠금이 동작하지 않습니다."
            alert.addButton(withTitle: "끄고 종료")
            alert.addButton(withTitle: "취소")
            alert.alertStyle = .warning
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        settings.setLaunchAtLogin(enabled)
        if enabled, settings.launchAtLoginNeedsApproval {
            ui.flash("시스템 설정 › 로그인 항목에서 LockApps를 허용해 주세요")
        }
    }
}
