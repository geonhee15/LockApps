import AppKit
import SwiftUI
import Observation

/// State shown by `UnlockPromptView`.
@MainActor
@Observable
final class UnlockPromptModel {
    var appName = ""
    var bundleID = ""
    var icon: NSImage = NSWorkspace.shared.icon(for: .applicationBundle)
    var password = ""
    var attempts = 0
    var maxAttempts = 5
    var shake = 0
    var errorText: String?
    @ObservationIgnored var onSubmit: (() -> Void)?
    @ObservationIgnored var onCancel: (() -> Void)?

    var remainingAttempts: Int { max(0, maxAttempts - attempts) }
}

final class UnlockPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// Full-screen frosted overlay with the password card. One at a time; the engine queues the rest.
@MainActor
final class UnlockPromptController {
    let model = UnlockPromptModel()
    private var panel: UnlockPanel?
    private var completion: ((Bool) -> Void)?
    private var verify: ((String) -> Bool)?
    private(set) var isShowing = false

    /// Debug: use this frame instead of the whole screen (README screenshots).
    var debugFrame: NSRect?
    /// Debug: submit this password automatically a second after the prompt appears (end-to-end tests).
    var debugAutoType: String?

    func show(request: UnlockRequest, maxAttempts: Int, verify: @escaping (String) -> Bool, completion: @escaping (Bool) -> Void) {
        self.verify = verify
        self.completion = completion
        model.appName = request.name
        model.bundleID = request.bundleID
        model.icon = AppIconCache.icon(path: request.path ?? "", size: 128)
        model.password = ""
        model.attempts = 0
        model.maxAttempts = maxAttempts
        model.errorText = nil
        model.onSubmit = { [weak self] in self?.submit() }
        model.onCancel = { [weak self] in self?.finish(success: false) }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(targetFrame(), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isShowing = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
        scheduleAutoType()
    }

    /// LOCKAPPS_DEBUG_AUTOTYPE: types the password a second after the card appears, again after each miss.
    private func scheduleAutoType() {
        guard let typed = debugAutoType else { return }
        let bid = model.bundleID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.isShowing, self.model.bundleID == bid else { return }
            self.model.password = typed
            self.submit()
        }
    }

    func dismiss() {
        guard isShowing, let panel else { return }
        isShowing = false
        completion = nil
        verify = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                if !self.isShowing { panel.orderOut(nil) }
            }
        }
    }

    private func submit() {
        guard let verify else { return }
        let password = model.password
        guard !password.isEmpty else { return }
        if verify(password) {
            finish(success: true)
            return
        }
        model.attempts += 1
        model.password = ""
        model.shake += 1
        if model.attempts >= model.maxAttempts {
            model.errorText = "비밀번호를 \(model.maxAttempts)번 틀려 앱을 닫습니다"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.finish(success: false)
            }
        } else {
            model.errorText = "비밀번호가 맞지 않아요 · \(model.remainingAttempts)번 남음"
            scheduleAutoType()
        }
    }

    private func finish(success: Bool) {
        let done = completion
        dismiss()
        done?(success)
    }

    // MARK: Panel

    private func makePanel() -> UnlockPanel {
        let panel = UnlockPanel(
            contentRect: targetFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.isMovable = false
        panel.isExcludedFromWindowsMenu = true
        panel.onEscape = { [weak self] in self?.finish(success: false) }
        let hosting = NSHostingView(rootView: UnlockPromptView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }

    private func targetFrame() -> NSRect {
        if let debugFrame { return debugFrame }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        return screen.frame
    }

    /// Captures the overlay window into a PNG (README screenshots).
    func writeSnapshot(to path: String) {
        guard let panel else { return }
        WindowSnapshot.write(window: panel, to: path)
    }
}
