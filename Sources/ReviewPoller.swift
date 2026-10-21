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
    /// Heads found not to qualify under the current auto-approve settings, by merge request key.
    private var unqualifiedHeads: [String: String] = [:]

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
            if newConfig.autoApproveReleases != config.autoApproveReleases
                || newConfig.autoApproveVersionBumps != config.autoApproveVersionBumps {
                unqualifiedHeads = [:]
            }
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
            var open = try client.openReviewRequests(username: config.username)
            let autoApproved = autoApprove(open)
            if !autoApproved.isEmpty {
                open = try client.openReviewRequests(username: config.username)
            }
            list.show(open)
            for (mergeRequest, event) in reconcile(open, autoApproved: autoApproved) {
                Log.write("\(event.headline): \(mergeRequest.label)")
                notifier.post(mergeRequest, event: event)
            }
        } catch {
            Log.write("poll failed: \(error.localizedDescription)")
            list.showFailure(error)
        }
    }

    private func reconcile(_ open: [MergeRequest],
                           autoApproved: [String: AutoApprovedHead]) -> [(MergeRequest, ReviewEvent)] {
        var events: [(MergeRequest, ReviewEvent)] = []
        var current: [String: SeenStore.ReviewState] = [:]
        for mergeRequest in open {
            let previous = store.reviews[mergeRequest.key]
            let approval = autoApproved[mergeRequest.key]
            let decision = approval.map { (event: ReviewEvent.autoApproved($0.reason, mergeRequest.pipeline), held: nil) }
                ?? decide(mergeRequest, previous: previous)
            if let event = decision.event {
                events.append((mergeRequest, event))
            }
            current[mergeRequest.key] = SeenStore.ReviewState(
                updatedAt: mergeRequest.updatedAt,
                headSHA: mergeRequest.headSHA,
                pipeline: mergeRequest.pipeline?.rawValue,
                isApprovedByReviewer: mergeRequest.isApproved(by: config.username),
                autoApprovedHead: approval?.head ?? previous?.autoApprovedHead,
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

    /// Each head is judged once: an approval the reviewer revokes stays revoked until new commits arrive.
    private func autoApprove(_ open: [MergeRequest]) -> [String: AutoApprovedHead] {
        guard config.autoApproveReleases || config.autoApproveVersionBumps else { return [:] }
        var approved: [String: AutoApprovedHead] = [:]
        for mergeRequest in open {
            guard let head = mergeRequest.headSHA, !mergeRequest.isDraft,
                  ReviewAction.approve.isAvailable(on: mergeRequest, reviewer: config.username),
                  store.reviews[mergeRequest.key]?.autoApprovedHead != head,
                  unqualifiedHeads[mergeRequest.key] != head else { continue }
            do {
                guard let reason = try qualification(of: mergeRequest, at: head) else {
                    unqualifiedHeads[mergeRequest.key] = head
                    continue
                }
                try client.approve(mergeRequest)
                Log.write("Auto-approved \(reason.summary): \(mergeRequest.label)")
                approved[mergeRequest.key] = AutoApprovedHead(reason: reason, head: head)
            } catch {
                Log.write("could not auto-approve \(mergeRequest.label): \(error.localizedDescription)")
            }
        }
        return approved
    }

    /// A bump replaces each line it touches, so a diff adding more lines than it removes is ruled out unread.
    private func qualification(of mergeRequest: MergeRequest, at head: String) throws -> AutoApproval? {
        if config.autoApproveReleases, AutoApproval.isRelease(mergeRequest) { return .release }
        guard config.autoApproveVersionBumps, let stats = mergeRequest.diffStats, stats.additions == stats.deletions else {
            return nil
        }
        let version = try client.latestDiff(of: mergeRequest)
        guard version.headSHA == head else {
            throw WatcherError.setup("its newest diff is at \(version.headSHA.prefix(8)), its head at \(head.prefix(8))")
        }
        return AutoApproval.isVersionBump(version.files) ? .versionBump : nil
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

private struct AutoApprovedHead {
    let reason: AutoApproval
    let head: String
}
