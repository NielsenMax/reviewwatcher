import Foundation

/// The one-click paths for merge requests that need nothing beyond the reviewer's sign-off.
enum ReviewAction {
    case approve
    case merge

    var title: String {
        switch self {
        case .approve: return "Approve"
        case .merge: return "Merge"
        }
    }

    func isAvailable(on mergeRequest: MergeRequest, reviewer username: String) -> Bool {
        switch self {
        case .approve: return mergeRequest.canApprove && !mergeRequest.isApproved(by: username)
        case .merge: return mergeRequest.canMerge && mergeRequest.isQuickMergeable
        }
    }

    func run(on mergeRequest: MergeRequest, client: GitLabClient) throws -> String {
        switch self {
        case .approve:
            try client.approve(mergeRequest)
            return "Approved"
        case .merge:
            switch try client.merge(mergeRequest) {
            case .merged: return "Merged"
            case .mergesWhenChecksPass: return "Merges when checks pass"
            }
        }
    }
}
