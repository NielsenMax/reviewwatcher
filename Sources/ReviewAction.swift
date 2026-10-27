import Foundation

/// The one-click paths for merge requests that need nothing beyond the reviewer's sign-off.
enum ReviewAction {
    case approve
    case unapprove
    case merge
    case approveAndMerge

    struct Outcome {
        let summary: String
        let isMerged: Bool
    }

    var title: String {
        switch self {
        case .approve: return "Approve"
        case .unapprove: return "Unapprove"
        case .merge: return "Merge"
        case .approveAndMerge: return "Approve & merge"
        }
    }

    var isMerge: Bool {
        self == .merge || self == .approveAndMerge
    }

    /// GitLab's auto-merge waits on approvals too, so a merge the reviewer has not approved would sit until they do.
    func isAvailable(on mergeRequest: MergeRequest, reviewer username: String) -> Bool {
        let awaitsApproval = mergeRequest.canApprove && !mergeRequest.isApproved(by: username)
        let isMergeable = mergeRequest.canMerge && mergeRequest.isQuickMergeable
        switch self {
        case .approve: return awaitsApproval
        case .unapprove: return mergeRequest.isApproved(by: username)
        case .merge: return isMergeable && !awaitsApproval
        case .approveAndMerge: return isMergeable && awaitsApproval
        }
    }

    func run(on mergeRequest: MergeRequest, client: GitLabClient) throws -> Outcome {
        switch self {
        case .approve:
            try client.approve(mergeRequest)
            return Outcome(summary: "Approved", isMerged: false)
        case .unapprove:
            try client.unapprove(mergeRequest)
            return Outcome(summary: "Unapproved", isMerged: false)
        case .merge:
            switch try client.merge(mergeRequest) {
            case .merged: return Outcome(summary: "Merged", isMerged: true)
            case .mergesWhenChecksPass: return Outcome(summary: "Merges when checks pass", isMerged: false)
            }
        case .approveAndMerge:
            try client.approve(mergeRequest)
            let outcome: MergeOutcome
            do {
                outcome = try client.merge(mergeRequest)
            } catch {
                throw WatcherError.setup("Approved, but the merge failed: \(error.localizedDescription)")
            }
            switch outcome {
            case .merged: return Outcome(summary: "Approved and merged", isMerged: true)
            case .mergesWhenChecksPass: return Outcome(summary: "Approved, merges when checks pass", isMerged: false)
            }
        }
    }
}
