import Foundation

enum RunnerState: Int, CaseIterable {
    case busy, idle, offline
}

struct Runner: Decodable {
    struct Label: Decodable { let name: String }
    let id: Int
    let name: String
    let status: String
    let busy: Bool
    let labels: [Label]

    var state: RunnerState {
        if status != "online" { return .offline }
        return busy ? .busy : .idle
    }
}

struct Repo: Decodable {
    let name: String
    let archived: Bool
}

struct Job: Decodable {
    let name: String
    let status: String
    let htmlUrl: String?
    let startedAt: Date?
    let runnerId: Int?
    let workflowName: String?
    let headBranch: String?
}

struct ActiveJob {
    let repo: String
    let job: Job
}

private struct ErrorBody: Decodable { let message: String }

enum GitHubError: LocalizedError {
    case noToken
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "No GitHub token. Run `gh auth login` or paste a token in Settings."
        case let .http(code, message):
            return "GitHub API \(code): \(message)"
        }
    }
}

actor GitHubClient {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let tokenOverride: String?
    private var cachedToken: String?
    private(set) var rateLimitRemaining: Int?

    init(token: String?) {
        tokenOverride = token
    }

    func runners(org: String) async throws -> [Runner] {
        struct Page: Decodable { let totalCount: Int; let runners: [Runner] }
        var all: [Runner] = []
        for page in 1... {
            let p: Page = try await get("/orgs/\(org)/actions/runners?per_page=100&page=\(page)")
            all += p.runners
            if p.runners.isEmpty || all.count >= p.totalCount { break }
        }
        return all
    }

    func repos(org: String) async throws -> [String] {
        var all: [Repo] = []
        for page in 1... {
            let p: [Repo] = try await get("/orgs/\(org)/repos?sort=pushed&direction=desc&per_page=100&page=\(page)")
            all += p
            if p.count < 100 { break }
        }
        return all.filter { !$0.archived }.map(\.name)
    }

    func inProgressJobs(org: String, repo: String) async throws -> [ActiveJob] {
        struct Run: Decodable { let id: Int }
        struct RunsPage: Decodable { let workflowRuns: [Run] }
        struct JobsPage: Decodable { let jobs: [Job] }

        let runs: RunsPage = try await get("/repos/\(org)/\(repo)/actions/runs?status=in_progress&per_page=100")
        var result: [ActiveJob] = []
        for run in runs.workflowRuns {
            let jobs: JobsPage = try await get("/repos/\(org)/\(repo)/actions/runs/\(run.id)/jobs?filter=latest&per_page=100")
            result += jobs.jobs
                .filter { $0.status == "in_progress" && $0.runnerId != nil }
                .map { ActiveJob(repo: repo, job: $0) }
        }
        return result
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: URL(string: "https://api.github.com" + path)!)
        request.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        let http = response as! HTTPURLResponse
        if let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining") {
            rateLimitRemaining = Int(remaining)
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { cachedToken = nil }
            let message = (try? decoder.decode(ErrorBody.self, from: data))?.message ?? ""
            throw GitHubError.http(http.statusCode, message)
        }
        return try decoder.decode(T.self, from: data)
    }

    private func token() throws -> String {
        if let tokenOverride { return tokenOverride }
        if let cachedToken { return cachedToken }
        guard let t = Self.ghCLIToken() else { throw GitHubError.noToken }
        cachedToken = t
        return t
    }

    /// GUI apps don't inherit the shell PATH, so look for `gh` in the usual install locations.
    private static func ghCLIToken() -> String? {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        guard let gh = candidates.first(where: FileManager.default.isExecutableFile) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gh)
        process.arguments = ["auth", "token"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return process.terminationStatus == 0 && !token.isEmpty ? token : nil
    }
}
