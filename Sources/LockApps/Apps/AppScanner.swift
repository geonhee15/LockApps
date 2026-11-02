import AppKit
import Observation

/// Finds every .app in the usual application folders (user, local, system) and keeps the list sorted.
@MainActor
@Observable
final class AppScanner {
    private(set) var apps: [InstalledApp] = []
    private(set) var isScanning = false
    private(set) var lastScan: Date?

    /// Apps that must never be locked (locking them would wedge the session).
    nonisolated static let excludedBundleIDs: Set<String> = [
        "com.apple.finder", "com.apple.loginwindow", "com.apple.dock", "com.apple.systemuiserver",
        "com.apple.Terminal",
    ]

    static var searchRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            home.appendingPathComponent("Applications"),
        ]
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        let ownBundleID = Bundle.main.bundleIdentifier ?? "com.geonhee.lockapps"
        let roots = Self.searchRoots
        Task.detached(priority: .userInitiated) {
            let found = Self.collect(roots: roots, excluding: ownBundleID)
            await MainActor.run {
                self.apps = found
                self.isScanning = false
                self.lastScan = Date()
            }
        }
    }

    nonisolated private static func collect(roots: [URL], excluding ownBundleID: String) -> [InstalledApp] {
        let fm = FileManager.default
        var seen: Set<String> = []
        var result: [InstalledApp] = []

        func visit(_ dir: URL, depth: Int, isSystem: Bool) {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                          options: [.skipsHiddenFiles]) else { return }
            for url in items {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true else { continue }
                if url.pathExtension == "app" {
                    add(url, isSystem: isSystem)
                } else if depth < 1, values?.isSymbolicLink != true {
                    // One level of sub-folders (e.g. "Chrome Apps.localized", vendor folders).
                    visit(url, depth: depth + 1, isSystem: isSystem)
                }
            }
        }

        func add(_ url: URL, isSystem: Bool) {
            guard let bundle = Bundle(url: url), let bid = bundle.bundleIdentifier, !bid.isEmpty else { return }
            guard bid != ownBundleID, !excludedBundleIDs.contains(bid) else { return }
            // Only real launchable apps: needs an executable.
            guard bundle.executableURL != nil else { return }
            guard !seen.contains(bid) else { return }
            seen.insert(bid)
            let name = fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            result.append(InstalledApp(bundleID: bid, name: name, path: url.path, isSystem: isSystem))
        }

        for root in roots {
            let isSystem = root.path.hasPrefix("/System")
            visit(root, depth: 0, isSystem: isSystem)
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
