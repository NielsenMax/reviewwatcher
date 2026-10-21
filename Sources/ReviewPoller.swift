import Foundation

/// Owns the timer, the config and the seen store; every touch of them happens on `queue`.
final class ReviewPoller {
    private var config: Config
    private let client: GitLabClient
    private let notifier: Notifier
    private let list: ReviewList
    private var store: SeenStore
    private let queue = DispatchQueue(label: "app.reviewwatcher.poll")
    private var timer: DispatchSourceTimer?
    private var isPaused = false

    init(config: Config, client: GitLabClient, notifier: Notifier, list: ReviewList) {
        self.config = config
        self.client = client
        self.notifier = notifier
        self.list = list
        self.store = SeenStore.load()
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.setEventHandler { [weak self] in self?.poll() }
            timer.schedule(deadline: .now(), repeating: config.pollInterval)
            self.timer = timer
            timer.resume()
            Log.write("watching reviews for @\(config.username) on \(config.host) every \(Int(config.pollInterval))s")
        }
    }

    /// A sleeping machine freezes the timer anyway; suspending also covers a dark screen on battery.
    func pause() {
        queue.async { [weak self] in
            guard let self, let timer, !isPaused else { return }
            isPaused = true
            timer.suspend()
            Log.write("paused: machine asleep")
        }
    }

    func resume() {
        queue.async { [weak self] in
            guard let self, let timer, isPaused else { return }
            isPaused = false
            timer.schedule(deadline: .now(), repeating: config.pollInterval)
            timer.resume()
            Log.write("resumed: polling now")
        }
    }

    func apply(_ newConfig: Config) {
        queue.async { [weak self] in
            guard let self else { return }
            let isNewInterval = newConfig.pollInterval != config.pollInterval
            config = newConfig
            guard isNewInterval, let timer, !isPaused else { return }
            timer.schedule(deadline: .now() + newConfig.pollInterval, repeating: newConfig.pollInterval)
            Log.write("polling every \(Int(newConfig.pollInterval))s")
        }
    }

    func refresh() {
        queue.async { [weak self] in self?.poll() }
    }

    private func poll() {
        do {
            let open = try client.openReviewRequests(username: config.username)
            list.show(open)
            for (mergeRequest, event) in reconcile(open) {
                Log.write("\(event.headline): \(mergeRequest.label)")
                notifier.post(mergeRequest, event: event)
            }
        } catch {
            Log.write("poll failed: \(error.localizedDescription)")
            list.showFailure(error)
        }
    }

    private func reconcile(_ open: [MergeRequest]) -> [(MergeRequest, ReviewEvent)] {
        var events: [(MergeRequest, ReviewEvent)] = []
        var current: [String: SeenStore.ReviewState] = [:]
        for mergeRequest in open {
            let decision = decide(mergeRequest, previous: store.reviews[mergeRequest.key])
            if let event = decision.event {
                events.append((mergeRequest, event))
            }
            current[mergeRequest.key] = SeenStore.ReviewState(
                updatedAt: mergeRequest.updatedAt,
                headSHA: mergeRequest.headSHA,
                pipeline: mergeRequest.pipeline?.rawValue,
                isApprovedByReviewer: mergeRequest.isApproved(by: config.username),
                held: decision.held
            )
        }

        // Rebuilding the map rather than merging drops merged and closed merge requests.
        store = SeenStore(seeded: true, reviews: current)
        do {
            try store.save()
        } catch {
            Log.write("could not persist state to \(Paths.stateFile.path): \(error.localizedDescription)")
        }
        return events
    }

    /// A review request, or a review whose approval GitLab removed, owes one announcement. It is made once
    /// the merge request passes the gate and dropped if the reviewer approves first. Otherwise a review speaks
    /// up again only for a fixed pipeline or fresh activity.
    private func decide(_ mergeRequest: MergeRequest,
                        previous: SeenStore.ReviewState?) -> (event: ReviewEvent?, held: SeenStore.Announcement?) {
        let isAdmitted = config.notifyOnlyWhen.admits(mergeRequest)
        if let owed = owedAnnouncement(mergeRequest, previous: previous) {
            guard !mergeRequest.isApproved(by: config.username) else { return (nil, nil) }
            return isAdmitted ? (ReviewEvent(owed, pipeline: mergeRequest.pipeline), nil) : (nil, owed)
        }
        guard isAdmitted, let previous else { return (nil, nil) }
        if config.notifyOnPipelineFixed,
           previous.pipeline == PipelineStatus.failed.rawValue, mergeRequest.pipeline == .success {
            return (.pipelineFixed, nil)
        }
        if config.notifyOnActivity, previous.updatedAt != mergeRequest.updatedAt {
            return (.activity(mergeRequest.pipeline), nil)
        }
        return (nil, nil)
    }

    private func owedAnnouncement(_ mergeRequest: MergeRequest,
                                  previous: SeenStore.ReviewState?) -> SeenStore.Announcement? {
        let owed: SeenStore.Announcement?
        if let previous {
            // GitLab drops approvals on push; an approval lost on an unmoved head is the reviewer's own revocation.
            let hasNewCommits = previous.headSHA.map { $0 != mergeRequest.headSHA } ?? true
            let lostApproval = previous.isApprovedByReviewer && !mergeRequest.isApproved(by: config.username) && hasNewCommits
            owed = previous.held ?? (lostApproval ? .approvalRemoved : nil)
        } else {
            owed = store.seeded || config.notifyBacklogOnFirstRun ? .reviewRequested : nil
        }
        switch owed {
        case .reviewRequested: return config.notifyOnNewReviewRequest ? owed : nil
        case .approvalRemoved: return config.notifyOnApprovalRemoved ? owed : nil
        case nil: return nil
        }
    }
}
