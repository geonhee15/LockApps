import AppKit
import Observation
import ServiceManagement

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "시스템"
        case .light: return "라이트"
        case .dark: return "다크"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// User preferences (UserDefaults). In screenshot/debug runs (LOCKAPPS_DATA_DIR set) nothing is persisted.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private static let appearanceKey = "appearanceMode"
    private static let protectionKey = "protectionEnabled"
    private static let persist = ProcessInfo.processInfo.environment["LOCKAPPS_DATA_DIR"] == nil

    /// Embedded launchd agent (Contents/Library/LaunchAgents): starts LockApps at login and relaunches it
    /// when it is killed or crashes, so protection does not end with the process.
    nonisolated static let agentPlistName = "com.geonhee.lockapps.agent.plist"
    private var agent: SMAppService { SMAppService.agent(plistName: Self.agentPlistName) }

    var appearance: AppearanceMode {
        didSet {
            if Self.persist { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
            applyAppearance()
        }
    }

    /// "적용" state: when on, LockEngine watches launches and asks for passwords.
    var protectionEnabled: Bool {
        didSet {
            if Self.persist { UserDefaults.standard.set(protectionEnabled, forKey: Self.protectionKey) }
            onProtectionChanged?(protectionEnabled)
        }
    }

    @ObservationIgnored var onProtectionChanged: ((Bool) -> Void)?

    /// Background agent registered (login start + relaunch).
    private(set) var launchAtLogin: Bool = false
    /// macOS wants the user to allow the background item in System Settings first.
    private(set) var launchAtLoginNeedsApproval = false
    private(set) var launchAtLoginError: String?

    /// True when this process was started by launchd through the agent plist.
    var isAgentInstance: Bool { ProcessInfo.processInfo.environment["LOCKAPPS_AGENT"] == "1" }

    private init() {
        let env = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard
        appearance = AppearanceMode(rawValue: env["LOCKAPPS_APPEARANCE"] ?? defaults.string(forKey: Self.appearanceKey) ?? "") ?? .system
        if let forced = env["LOCKAPPS_DEBUG_PROTECTION"] {
            protectionEnabled = forced == "1" || forced == "on"
        } else {
            protectionEnabled = defaults.bool(forKey: Self.protectionKey)
        }
        refreshLaunchAtLogin()
    }

    func applyAppearance() {
        NSApp.appearance = appearance.nsAppearance
    }

    func refreshLaunchAtLogin() {
        if let forced = ProcessInfo.processInfo.environment["LOCKAPPS_DEBUG_LOGIN_ITEM"] {
            launchAtLogin = forced == "1"
            return
        }
        let status = agent.status
        launchAtLogin = status == .enabled
        launchAtLoginNeedsApproval = status == .requiresApproval
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard Self.persist else { launchAtLogin = enabled; return }
        do {
            if enabled {
                if agent.status != .enabled { try agent.register() }
            } else {
                try agent.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            NSLog("LockApps: agent \(enabled ? "register" : "unregister") failed: \(error)")
        }
        refreshLaunchAtLogin()
    }

    /// launchd pins the agent to the app's code signature at registration time; a rebuilt (re-signed) bundle then
    /// fails to spawn with EX_CONFIG / "Launch Constraint Violation" until it is registered again. Called when a
    /// hand-launched copy finds the agent enabled but not running.
    func refreshAgentRegistration() {
        guard Self.persist, agent.status == .enabled else { return }
        try? agent.unregister()
        do { try agent.register() } catch { launchAtLoginError = error.localizedDescription }
        refreshLaunchAtLogin()
        NSLog("LockApps: re-registered the background agent")
    }

    /// Earlier builds used a plain login item (SMAppService.mainApp); move it to the supervised agent.
    func migrateLegacyLoginItem() {
        guard Self.persist, SMAppService.mainApp.status == .enabled else { return }
        try? SMAppService.mainApp.unregister()
        setLaunchAtLogin(true)
        NSLog("LockApps: migrated login item to the launchd agent")
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
