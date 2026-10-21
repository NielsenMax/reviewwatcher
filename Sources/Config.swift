import Foundation

struct Config {
    var host: String
    var username: String
    var pollInterval: TimeInterval
    var notifyOnNewReviewRequest: Bool
    var notifyOnApprovalRemoved: Bool
    var notifyOnPipelineFixed: Bool
    var notifyOnActivity: Bool
    var notifyBacklogOnFirstRun: Bool
    var notifyOnlyWhen: NotificationGate
    var autoApproveReleases: Bool
    var autoApproveVersionBumps: Bool
    var collapsedFilePatterns: [String]
}

extension Config: Codable {
    private enum CodingKeys: String, CodingKey {
        case host, username, pollIntervalSeconds
        case notifyOnNewReviewRequest, notifyOnApprovalRemoved, notifyOnPipelineFixed, notifyOnActivity
        case notifyBacklogOnFirstRun
        case notifyOnlyWhen, autoApproveReleases, autoApproveVersionBumps, collapsedFilePatterns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? "gitlab.com"
        username = try container.decode(String.self, forKey: .username)
        // GitLab's REST quota is per-token; 30s keeps a day of polling well inside it.
        let seconds = try container.decodeIfPresent(Int.self, forKey: .pollIntervalSeconds) ?? 60
        pollInterval = TimeInterval(max(30, seconds))
        notifyOnNewReviewRequest = try container.decodeIfPresent(Bool.self, forKey: .notifyOnNewReviewRequest) ?? true
        notifyOnApprovalRemoved = try container.decodeIfPresent(Bool.self, forKey: .notifyOnApprovalRemoved) ?? true
        notifyOnPipelineFixed = try container.decodeIfPresent(Bool.self, forKey: .notifyOnPipelineFixed) ?? true
        notifyOnActivity = try container.decodeIfPresent(Bool.self, forKey: .notifyOnActivity) ?? false
        notifyBacklogOnFirstRun = try container.decodeIfPresent(Bool.self, forKey: .notifyBacklogOnFirstRun) ?? false
        notifyOnlyWhen = try container.decodeIfPresent(NotificationGate.self, forKey: .notifyOnlyWhen) ?? NotificationGate()
        autoApproveReleases = try container.decodeIfPresent(Bool.self, forKey: .autoApproveReleases) ?? false
        autoApproveVersionBumps = try container.decodeIfPresent(Bool.self, forKey: .autoApproveVersionBumps) ?? false
        collapsedFilePatterns = try container.decodeIfPresent([String].self, forKey: .collapsedFilePatterns) ?? ["*test*", "*spec/*"]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(username, forKey: .username)
        try container.encode(Int(pollInterval), forKey: .pollIntervalSeconds)
        try container.encode(notifyOnNewReviewRequest, forKey: .notifyOnNewReviewRequest)
        try container.encode(notifyOnApprovalRemoved, forKey: .notifyOnApprovalRemoved)
        try container.encode(notifyOnPipelineFixed, forKey: .notifyOnPipelineFixed)
        try container.encode(notifyOnActivity, forKey: .notifyOnActivity)
        try container.encode(notifyBacklogOnFirstRun, forKey: .notifyBacklogOnFirstRun)
        try container.encode(notifyOnlyWhen, forKey: .notifyOnlyWhen)
        try container.encode(autoApproveReleases, forKey: .autoApproveReleases)
        try container.encode(autoApproveVersionBumps, forKey: .autoApproveVersionBumps)
        try container.encode(collapsedFilePatterns, forKey: .collapsedFilePatterns)
    }

    static func load() throws -> Config {
        let data: Data
        do {
            data = try Data(contentsOf: Paths.configFile)
        } catch {
            throw WatcherError.setup("no config at \(Paths.configFile.path) — run install.sh to create one")
        }
        return try JSONDecoder().decode(Config.self, from: data)
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: Paths.configFile, options: .atomic)
    }
}

enum WatcherError: LocalizedError {
    case setup(String)
    case glab(String)

    var errorDescription: String? {
        switch self {
        case .setup(let detail): return detail
        case .glab(let detail): return "glab failed: \(detail)"
        }
    }
}
