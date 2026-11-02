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

    private(set) var launchAtLogin: Bool = false
    private(set) var launchAtLoginError: String?

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
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard Self.persist else { launchAtLogin = enabled; return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            NSLog("LockApps: login item change failed: \(error)")
        }
        refreshLaunchAtLogin()
    }
}
