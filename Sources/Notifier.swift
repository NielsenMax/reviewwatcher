import UserNotifications

enum ReviewEvent {
    case reviewRequested(PipelineStatus?)
    case approvalRemoved(PipelineStatus?)
    case activity(PipelineStatus?)
    case pipelineFixed
    case autoApproved(AutoApproval, PipelineStatus?)

    init(_ announcement: SeenStore.Announcement, pipeline: PipelineStatus?) {
        switch announcement {
        case .reviewRequested: self = .reviewRequested(pipeline)
        case .approvalRemoved: self = .approvalRemoved(pipeline)
        }
    }

    var pipeline: PipelineStatus? {
        switch self {
        case .reviewRequested(let status), .approvalRemoved(let status), .activity(let status),
             .autoApproved(_, let status): return status
        case .pipelineFixed: return .success
        }
    }

    var headline: String {
        let badge = pipeline.map { "\($0.emoji) " } ?? ""
        switch self {
        case .reviewRequested: return badge + "Review requested"
        case .approvalRemoved: return badge + "Your approval was removed"
        case .activity: return badge + "Merge request updated"
        case .pipelineFixed: return badge + "Pipeline fixed"
        case .autoApproved(let reason, _): return badge + "Auto-approved \(reason.summary)"
        }
    }
}

struct Notifier {
    static let urlKey = "mergeRequestURL"

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Log.write("notification authorization failed: \(error.localizedDescription)")
            } else if granted {
                Log.write("notifications authorized")
            } else {
                Log.write("notifications denied — enable ReviewWatcher in System Settings > Notifications")
            }
        }
    }

    func post(_ mergeRequest: MergeRequest, event: ReviewEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.headline
        content.subtitle = [mergeRequest.label, event.pipeline?.summary].compactMap { $0 }.joined(separator: " · ")
        content.body = "\(mergeRequest.title) — @\(mergeRequest.author.username)"
        content.sound = .default
        content.userInfo = [Self.urlKey: mergeRequest.webURL]
        content.threadIdentifier = mergeRequest.key
        if let imageName = event.pipeline?.imageName, let attachment = attachment(named: imageName) {
            content.attachments = [attachment]
        }

        // Reusing the key as identifier collapses repeat pings into one entry per merge request.
        let request = UNNotificationRequest(identifier: mergeRequest.key, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.write("could not post notification for \(mergeRequest.label): \(error.localizedDescription)")
            }
        }
    }

    /// One notification per ticket and poll, carrying every change it went through since the last one.
    func post(_ ticket: Ticket, changes: [TicketChange], jira: JiraConfig) {
        let content = UNMutableNotificationContent()
        let headlines = changes.map { $0.headline(for: ticket, epic: jira.epic, me: jira.email) }
        content.title = "\(ticket.status.category.emoji) " + headlines.joined(separator: " · ")
        content.subtitle = "\(ticket.key) · \(ticket.summary)"
        content.body = body(for: ticket, changes: changes)
        content.sound = .default
        content.threadIdentifier = ticket.key
        if let url = jira.browseURL(for: ticket.key) {
            content.userInfo = [Self.urlKey: url.absoluteString]
        }
        if let attachment = attachment(named: ticket.status.category.imageName) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.write("could not post notification for \(ticket.key): \(error.localizedDescription)")
            }
        }
    }

    private func body(for ticket: Ticket, changes: [TicketChange]) -> String {
        for case .commented(let comments) in changes {
            if let latest = comments.max(by: { $0.id < $1.id }) {
                return "\(latest.author.displayName): \(latest.text)"
            }
        }
        return [ticket.type, ticket.status.name, ticket.assignee?.displayName ?? "Unassigned"].joined(separator: " · ")
    }

    private func attachment(named imageName: String) -> UNNotificationAttachment? {
        guard let bundled = Bundle.main.url(forResource: imageName, withExtension: "png") else {
            return nil
        }
        // The notification store takes ownership of the file, so the bundled original is never handed over.
        let handover = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(imageName)-\(UUID().uuidString).png")
        do {
            try FileManager.default.copyItem(at: bundled, to: handover)
            return try UNNotificationAttachment(identifier: "", url: handover, options: nil)
        } catch {
            Log.write("could not attach \(imageName): \(error.localizedDescription)")
            return nil
        }
    }
}
