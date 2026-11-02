import Foundation
import Observation

/// Which sheet the main window shows. Driven by rows, the menu bar and debug flags.
enum SheetKind: Identifiable, Equatable {
    case setPassword(InstalledApp)       // new lock
    case changePassword(InstalledApp)    // existing lock, needs current password
    case removeLock(InstalledApp)        // needs current password
    case settings

    var id: String {
        switch self {
        case .setPassword(let a): return "set:\(a.bundleID)"
        case .changePassword(let a): return "change:\(a.bundleID)"
        case .removeLock(let a): return "remove:\(a.bundleID)"
        case .settings: return "settings"
        }
    }
}

enum ListFilter: String, CaseIterable, Identifiable {
    case all, locked
    var id: String { rawValue }
    var title: String { self == .all ? "전체" : "잠금" }
}

@MainActor
@Observable
final class UIState {
    var sheet: SheetKind?
    var filter: ListFilter = .all
    var search = ""
    /// Short confirmation shown in the bottom bar after an action.
    var toast: String?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    func flash(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            if !Task.isCancelled { toast = nil }
        }
    }
}
