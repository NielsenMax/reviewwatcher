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
            current[mergeRequest.key] = SeenStore.ReviewState(updatedAt: mergeRequest.updatedAt,
                                                              pipeline: mergeRequest.pipeline?.rawValue,
                                                              isHeld: decision.isHeld)
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

    /// A new or held review request is announced once it passes the gate, unless the reviewer approved it
    /// meanwhile; one already announced speaks up again only for a fixed pipeline or fresh activity.
    private func decide(_ mergeRequest: MergeRequest,
                        previous: SeenStore.ReviewState?) -> (event: ReviewEvent?, isHeld: Bool) {
        let isAdmitted = config.notifyOnlyWhen.admits(mergeRequest)
        guard let previous, !previous.isHeld else {
            let isOwed = config.notifyOnNewReviewRequest
                && (previous != nil || store.seeded || config.notifyBacklogOnFirstRun)
                && !mergeRequest.isApproved(by: config.username)
            return (isOwed && isAdmitted ? .reviewRequested(mergeRequest.pipeline) : nil, isOwed && !isAdmitted)
        }
        guard isAdmitted else { return (nil, false) }
        if config.notifyOnPipelineFixed,
           previous.pipeline == PipelineStatus.failed.rawValue, mergeRequest.pipeline == .success {
            return (.pipelineFixed, false)
        }
        if config.notifyOnActivity, previous.updatedAt != mergeRequest.updatedAt {
            return (.activity(mergeRequest.pipeline), false)
        }
        return (nil, false)
    }
}
