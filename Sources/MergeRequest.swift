import Foundation

struct MergeRequest: Identifiable {
    let iid: String
    let projectID: Int
    let projectPath: String
    let title: String
    let webURL: String
    let updatedAt: String
    let author: Author
    let headSHA: String?
    let pipeline: PipelineStatus?
    let diffStats: DiffStats?
    let approvers: [String]
    let mergeStatus: String?
    let isAutoMergeEnabled: Bool
    let hasConflicts: Bool
    let isDraft: Bool
    let canMerge: Bool
    let canApprove: Bool

    struct Author: Decodable {
        let username: String
    }

    struct DiffStats: Decodable {
        let additions: Int
        let deletions: Int
        let fileCount: Int

        var changedLines: Int { additions + deletions }
    }

    /// Stable across retitles and rebases, unlike `webURL` on transferred projects.
    var key: String { "\(projectID)!\(iid)" }

    var id: String { key }

    var label: String { "\(projectPath)!\(iid)" }

    var apiPath: String { "projects/\(projectID)/merge_requests/\(iid)" }

    var isPreviewable: Bool {
        guard let diffStats else { return false }
        return diffStats.changedLines <= FileDiff.previewLineLimit
    }

    func isApproved(by username: String) -> Bool {
        approvers.contains(username)
    }

    /// Only approvals or a pipeline that may still pass stand in the way; auto-merge waits those out.
    var isQuickMergeable: Bool {
        guard !isAutoMergeEnabled, pipeline != .failed, let mergeStatus else { return false }
        return ["MERGEABLE", "NOT_APPROVED", "CI_STILL_RUNNING", "CI_MUST_PASS",
                "CHECKING", "UNCHECKED", "APPROVALS_SYNCING"].contains(mergeStatus)
    }

    var mergeStatusSummary: String? {
        if isAutoMergeEnabled { return "Auto-merge on" }
        switch mergeStatus {
        case nil: return nil
        case "MERGEABLE": return "Ready to merge"
        case "NOT_APPROVED": return "Needs approval"
        case "CI_STILL_RUNNING": return "Waiting on pipeline"
        case "CI_MUST_PASS": return pipeline == .failed ? "Pipeline failed" : "Waiting on pipeline"
        case "DISCUSSIONS_NOT_RESOLVED": return "Unresolved threads"
        case "DRAFT_STATUS": return "Draft"
        case "CONFLICT": return "Conflicts"
        case "NEED_REBASE": return "Needs rebase"
        case "CHECKING", "UNCHECKED", "APPROVALS_SYNCING": return "Checking…"
        case let other?: return other.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

extension MergeRequest: Decodable {
    private enum CodingKeys: String, CodingKey {
        case iid, title, author, project, approvedBy, userPermissions, autoMergeEnabled
        case hasConflicts = "conflicts"
        case isDraft = "draft"
        case webURL = "webUrl"
        case projectID = "projectId"
        case updatedAt
        case headSHA = "diffHeadSha"
        case headPipeline
        case diffStats = "diffStatsSummary"
        case mergeStatus = "detailedMergeStatus"
    }

    private struct Project: Decodable {
        let fullPath: String
    }

    private struct Pipeline: Decodable {
        let status: String
    }

    private struct Approvers: Decodable {
        let nodes: [Author]
    }

    private struct Permissions: Decodable {
        let canMerge: Bool
        let canApprove: Bool
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        iid = try container.decode(String.self, forKey: .iid)
        projectID = try container.decode(Int.self, forKey: .projectID)
        projectPath = try container.decode(Project.self, forKey: .project).fullPath
        title = try container.decode(String.self, forKey: .title)
        webURL = try container.decode(String.self, forKey: .webURL)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        author = try container.decode(Author.self, forKey: .author)
        headSHA = try container.decodeIfPresent(String.self, forKey: .headSHA)
        pipeline = try container.decodeIfPresent(Pipeline.self, forKey: .headPipeline)
            .map { PipelineStatus(gitlabStatus: $0.status) }
        diffStats = try container.decodeIfPresent(DiffStats.self, forKey: .diffStats)
        approvers = try container.decode(Approvers.self, forKey: .approvedBy).nodes.map(\.username)
        mergeStatus = try container.decodeIfPresent(String.self, forKey: .mergeStatus)
        isAutoMergeEnabled = try container.decode(Bool.self, forKey: .autoMergeEnabled)
        hasConflicts = try container.decode(Bool.self, forKey: .hasConflicts)
        isDraft = try container.decode(Bool.self, forKey: .isDraft)
        let permissions = try container.decode(Permissions.self, forKey: .userPermissions)
        canMerge = permissions.canMerge
        canApprove = permissions.canApprove
    }
}
