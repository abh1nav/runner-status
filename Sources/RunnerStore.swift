import Foundation

struct RunnerRow: Identifiable {
    let runner: Runner
    let job: ActiveJob?
    var id: Int { runner.id }
    var state: RunnerState { runner.state }
}

@MainActor
final class RunnerStore: ObservableObject {
    @Published private(set) var rows: [RunnerRow] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var error: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var rateLimitRemaining: Int?

    var org: String {
        get { UserDefaults.standard.string(forKey: "org") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "org") }
    }

    private static let repoCacheTTL: TimeInterval = 600
    private static let fullScanCooldown: TimeInterval = 300
    private static let throttledScanLimit = 50
    private static let scanBatchSize = 8

    private var client = GitHubClient(token: Keychain.readToken())
    private var repoCache: (org: String, names: [String], fetched: Date)?
    /// Checked first on the next refresh.
    private var lastSeenRepo: [Int: String] = [:]
    /// Throttles exhaustive repo scans when a busy runner's job can't be located
    /// (e.g. it's running for a repo the token can't see).
    private var lastFullScan: Date?

    func reconfigure() {
        client = GitHubClient(token: Keychain.readToken())
        rows = []
        error = nil
        repoCache = nil
        lastSeenRepo = [:]
        lastFullScan = nil
        Task { await refresh() }
    }

    func refresh() async {
        let org = org
        guard !org.isEmpty, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let runners = try await client.runners(org: org)
            let busyIDs = Set(runners.filter { $0.state == .busy }.map(\.id))
            let jobs = busyIDs.isEmpty ? [:] : try await findJobs(org: org, busy: busyIDs)

            rows = runners
                .map { RunnerRow(runner: $0, job: jobs[$0.id]) }
                .sorted { ($0.state.rawValue, $0.runner.name) < ($1.state.rawValue, $1.runner.name) }
            error = nil
            lastUpdated = Date()
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        rateLimitRemaining = await client.rateLimitRemaining
    }

    /// There's no API linking a runner to its current job, so scan in-progress runs repo by repo,
    /// most likely repos first, and stop once every busy runner is accounted for.
    private func findJobs(org: String, busy: Set<Int>) async throws -> [Int: ActiveJob] {
        let repos = try await repoNames(org: org)
        var ordered: [String] = []
        for repo in busy.compactMap({ lastSeenRepo[$0] }) + repos where !ordered.contains(repo) {
            ordered.append(repo)
        }

        let fullScanAllowed = lastFullScan.map { Date().timeIntervalSince($0) > Self.fullScanCooldown } ?? true
        let candidates = fullScanAllowed ? ordered : Array(ordered.prefix(Self.throttledScanLimit))

        var pending = busy
        var found: [Int: ActiveJob] = [:]
        let client = client
        for start in stride(from: 0, to: candidates.count, by: Self.scanBatchSize) {
            let batch = candidates[start..<min(start + Self.scanBatchSize, candidates.count)]
            let results = await withTaskGroup(of: [ActiveJob].self) { group in
                for repo in batch {
                    group.addTask { (try? await client.inProgressJobs(org: org, repo: repo)) ?? [] }
                }
                return await group.reduce(into: []) { $0 += $1 }
            }
            for active in results {
                guard let id = active.job.runnerId, pending.remove(id) != nil else { continue }
                found[id] = active
                lastSeenRepo[id] = active.repo
            }
            if pending.isEmpty { break }
        }

        if !pending.isEmpty && fullScanAllowed { lastFullScan = Date() }
        return found
    }

    private func repoNames(org: String) async throws -> [String] {
        if let cache = repoCache, cache.org == org, Date().timeIntervalSince(cache.fetched) < Self.repoCacheTTL {
            return cache.names
        }
        let names = try await client.repos(org: org)
        repoCache = (org, names, Date())
        return names
    }
}
