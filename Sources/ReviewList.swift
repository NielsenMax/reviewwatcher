import Foundation

/// What the menu bar popover and the diff windows show. Owned by the main queue; the poller feeds it from its own.
final class ReviewList: ObservableObject {
    enum PollState {
        case waiting
        case updated(Date)
        case failed(String)
    }

    enum Progress {
        case working
        case done(String)
        case failed(String)
    }

    @Published private(set) var mergeRequests: [MergeRequest] = []
    @Published private(set) var pollState = PollState.waiting
    @Published private(set) var progress: [String: Progress] = [:]
    @Published private(set) var armedKey: String?

    let username: String
    private let client: GitLabClient
    private var disarm: DispatchWorkItem?

    private static let armedSeconds = 4.0

    /// Assigned once the poller exists, since the poller is built around this list.
    var refresh: () -> Void = {}

    init(username: String, client: GitLabClient) {
        self.username = username
        self.client = client
    }

    func show(_ open: [MergeRequest]) {
        DispatchQueue.main.async {
            let openKeys = Set(open.map(\.key))
            self.mergeRequests = open
            self.progress = self.progress.filter { key, progress in
                guard openKeys.contains(key) else { return false }
                if case .done = progress { return false }
                return true
            }
            self.pollState = .updated(Date())
        }
    }

    func showFailure(_ error: Error) {
        DispatchQueue.main.async {
            self.pollState = .failed(error.localizedDescription)
        }
    }

    func mergeRequest(withKey key: String) -> MergeRequest? {
        mergeRequests.first { $0.key == key }
    }

    func actions(for mergeRequest: MergeRequest) -> [ReviewAction] {
        [ReviewAction.approve, .unapprove, .merge, .approveAndMerge]
            .filter { $0.isAvailable(on: mergeRequest, reviewer: username) }
    }

    /// Merging is armed by the first click and fired by the second, so a list reshuffled by a refresh cannot merge the wrong row.
    func trigger(_ action: ReviewAction, on mergeRequest: MergeRequest) {
        disarm?.cancel()
        if action.isMerge, armedKey != mergeRequest.key {
            armedKey = mergeRequest.key
            let disarm = DispatchWorkItem { [weak self] in self?.armedKey = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.armedSeconds, execute: disarm)
            self.disarm = disarm
            return
        }
        armedKey = nil
        perform(action, on: mergeRequest)
    }

    private func perform(_ action: ReviewAction, on mergeRequest: MergeRequest) {
        progress[mergeRequest.key] = .working
        DispatchQueue.global(qos: .userInitiated).async { [client] in
            let outcome = Result { try action.run(on: mergeRequest, client: client) }
            DispatchQueue.main.async {
                switch outcome {
                case .success(let summary):
                    Log.write("\(summary): \(mergeRequest.label)")
                    self.progress[mergeRequest.key] = .done(summary)
                case .failure(let error):
                    Log.write("\(action.title) failed for \(mergeRequest.label): \(error.localizedDescription)")
                    self.progress[mergeRequest.key] = .failed(error.localizedDescription)
                }
                self.refresh()
            }
        }
    }
}
