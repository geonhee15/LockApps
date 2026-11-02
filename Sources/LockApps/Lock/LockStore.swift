import Foundation
import Observation

/// One locked app: which bundle, and the salted PBKDF2 digest of its password.
struct LockEntry: Codable, Identifiable, Hashable {
    var bundleID: String
    var name: String
    var path: String
    var salt: Data
    var hash: Data
    var iterations: UInt32
    var createdAt: Date
    var updatedAt: Date

    var id: String { bundleID }
}

/// Persists the lock list as JSON in Application Support (0600). Passwords are never written, only digests.
@MainActor
@Observable
final class LockStore {
    private(set) var entries: [String: LockEntry] = [:]
    /// Bumped on every change so observers (engine, status item) can react.
    private(set) var revision = 0
    @ObservationIgnored var onChange: (() -> Void)?

    private struct FileFormat: Codable {
        var version: Int
        var locks: [LockEntry]
    }

    static let dataDirectory: URL = {
        if let override = ProcessInfo.processInfo.environment["LOCKAPPS_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("LockApps", isDirectory: true)
    }()

    static var fileURL: URL { dataDirectory.appendingPathComponent("locks.json") }

    init() {
        load()
    }

    var locks: [LockEntry] {
        entries.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var count: Int { entries.count }

    func isLocked(_ bundleID: String) -> Bool { entries[bundleID] != nil }

    func entry(for bundleID: String) -> LockEntry? { entries[bundleID] }

    /// Creates the lock or replaces its password.
    func setLock(for app: InstalledApp, password: String) {
        let salt = PasswordHasher.randomSalt()
        let hash = PasswordHasher.derive(password: password, salt: salt)
        let now = Date()
        var entry = entries[app.bundleID] ?? LockEntry(
            bundleID: app.bundleID, name: app.name, path: app.path, salt: salt, hash: hash,
            iterations: PasswordHasher.iterations, createdAt: now, updatedAt: now
        )
        entry.name = app.name
        entry.path = app.path
        entry.salt = salt
        entry.hash = hash
        entry.iterations = PasswordHasher.iterations
        entry.updatedAt = now
        entries[app.bundleID] = entry
        persist()
    }

    func verify(_ bundleID: String, password: String) -> Bool {
        guard let entry = entries[bundleID] else { return false }
        return PasswordHasher.verify(password: password, salt: entry.salt, iterations: entry.iterations, expected: entry.hash)
    }

    func removeLock(_ bundleID: String) {
        guard entries.removeValue(forKey: bundleID) != nil else { return }
        persist()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let file = try? decoder.decode(FileFormat.self, from: data) {
            entries = Dictionary(uniqueKeysWithValues: file.locks.map { ($0.bundleID, $0) })
        }
    }

    private func persist() {
        revision &+= 1
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: Self.dataDirectory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(FileFormat(version: 1, locks: locks))
            try data.write(to: Self.fileURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.fileURL.path)
        } catch {
            NSLog("LockApps: failed to save locks: \(error)")
        }
        onChange?()
    }
}
