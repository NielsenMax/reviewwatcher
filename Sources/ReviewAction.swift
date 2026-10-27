import Foundation

/// The one-click paths for merge requests that need nothing beyond the reviewer's sign-off.
enum ReviewAction {
    case approve
    case unapprove
    case merge
    case approveAndMerge

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

    func run(on mergeRequest: MergeRequest, client: GitLabClient) throws -> String {
        switch self {
        case .approve:
            try client.approve(mergeRequest)
            return "Approved"
        case .unapprove:
            try client.unapprove(mergeRequest)
            return "Unapproved"
        case .merge:
            switch try client.merge(mergeRequest) {
            case .merged: return "Merged"
            case .mergesWhenChecksPass: return "Merges when checks pass"
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
            case .merged: return "Approved and merged"
            case .mergesWhenChecksPass: return "Approved, merges when checks pass"
            }
        }
    }
}
