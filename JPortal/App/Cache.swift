import Foundation

/**
 * last good response per key, so every screen can paint before the network
 * answers. one json file per key in application support, kept out of
 * backups: it's a copy of what the portal already has.
 */
actor Cache {
    nonisolated struct Entry<T: Codable & Sendable>: Codable, Sendable {
        let fetchedAt: Date
        let value: T
    }

    private let dir: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "cache")
        dir = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var url = base
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private func file(_ key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? String($0) : "_" }.joined()
        return dir.appending(path: "\(safe).json")
    }

    func get<T: Codable & Sendable>(_ key: String, as: T.Type) -> Entry<T>? {
        guard let data = try? Data(contentsOf: file(key)) else { return nil }
        return try? JSONDecoder().decode(Entry<T>.self, from: data)
    }

    func put<T: Codable & Sendable>(_ key: String, _ value: T, at: Date = Date()) {
        guard let data = try? JSONEncoder().encode(Entry(fetchedAt: at, value: value)) else { return }
        try? data.write(to: file(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func clear() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
