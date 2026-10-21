import Foundation

/// The one-click paths for merge requests that need nothing beyond the reviewer's sign-off.
enum ReviewAction {
    case approve
    case unapprove
    case merge

    var title: String {
        switch self {
        case .approve: return "Approve"
        case .unapprove: return "Unapprove"
        case .merge: return "Merge"
        }
    }

    func isAvailable(on mergeRequest: MergeRequest, reviewer username: String) -> Bool {
        switch self {
        case .approve: return mergeRequest.canApprove && !mergeRequest.isApproved(by: username)
        case .unapprove: return mergeRequest.isApproved(by: username)
        case .merge: return mergeRequest.canMerge && mergeRequest.isQuickMergeable
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
        }
    }
}
