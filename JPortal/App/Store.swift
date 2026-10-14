import Foundation
import JPortalKit
import Observation

/**
 * one cached portal answer. starts from disk, refreshes over the network,
 * never throws the old data away on failure. concurrent refreshes collapse
 * into one request. data and error can both be set, that's the "offline,
 * showing yesterday's numbers" case.
 */
@Observable
final class Store<T: Codable & Sendable> {
    let key: String
    private(set) var data: T?
    private(set) var fetchedAt: Date?
    private(set) var refreshing = false
    private(set) var error: Error?
    /// false until the disk cache has been looked at, nothing is worth drawing before that
    private(set) var checked = false

    @ObservationIgnored private let maxAge: TimeInterval
    @ObservationIgnored private let fetch: @Sendable (Portal) async throws -> T
    @ObservationIgnored private unowned let repo: Repository
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var inflight: Task<Void, Never>?

    init(key: String, maxAge: TimeInterval, repo: Repository, fetch: @escaping @Sendable (Portal) async throws -> T) {
        self.key = key
        self.maxAge = maxAge
        self.repo = repo
        self.fetch = fetch
    }

    var isEmptyLoading: Bool { data == nil && refreshing }

    private func loadDisk() async {
        if loaded { return }
        loaded = true
        let entry = await repo.cache.get(key, as: T.self)
        if data == nil, let entry {
            data = entry.value
            fetchedAt = entry.fetchedAt
        }
        checked = true
    }

    /// paint from disk, then hit the network if stale or [force]
    @discardableResult
    func refresh(force: Bool = false) -> Task<Void, Never> {
        if let running = inflight { return running }
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.inflight = nil }
            await loadDisk()
            let age = fetchedAt.map { Date().timeIntervalSince($0) }
            if !repo.live || (!force && age != nil && age! < maxAge) { return }
            refreshing = true
            do {
                let fetch = self.fetch
                let value = try await repo.limiter.run { try await self.repo.sessions.call(fetch) }
                let now = Date()
                await repo.cache.put(key, value, at: now)
                data = value
                fetchedAt = now
                error = nil
            } catch is CancellationError {
            } catch {
                self.error = error
            }
            refreshing = false
            checked = true
        }
        inflight = task
        return task
    }

    func await_(force: Bool = false) async {
        await refresh(force: force).value
    }
}

/// at most [permits] portal calls at once, the portal gets cranky with a dozen in parallel
final class Limiter {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(permits: Int) {
        available = permits
    }

    func run<R>(_ body: () async throws -> R) async throws -> R {
        if available > 0 {
            available -= 1
        } else {
            await withCheckedContinuation { waiters.append($0) }
        }
        defer {
            if waiters.isEmpty { available += 1 } else { waiters.removeFirst().resume() }
        }
        return try await body()
    }
}
