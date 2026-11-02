import Foundation

/// One application bundle found on this Mac.
struct InstalledApp: Identifiable, Hashable, Sendable {
    let bundleID: String
    let name: String
    let path: String
    let isSystem: Bool

    var id: String { bundleID }
}
