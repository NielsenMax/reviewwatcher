import SwiftUI

struct TicketListView: View {
    @ObservedObject var list: TicketList
    @ObservedObject var settings: Settings
    @ObservedObject var search: EpicSearch
    let openSettings: () -> Void
    @Environment(\.openURL) private var openURL

    private static let maxSectionsHeight: CGFloat = 480

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if case .notSetUp = list.pollState {
                placeholder("Log in with acli jira auth login, then run install.sh again.")
            } else {
                searchBox
                Divider()
                sections
            }
        }
        .frame(width: 480)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Epics").font(.headline)
                pollSummary.font(.caption).lineLimit(1).truncationMode(.tail)
            }
            Spacer()
            Toggle(isOn: $settings.config.jira.showsDoneTickets) { Image(systemName: "checkmark.circle") }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help(settings.config.jira.showsDoneTickets ? "Hide finished tickets" : "Show finished tickets")
            Button { list.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Refresh now")
            Button(action: openSettings) { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var pollSummary: some View {
        switch list.pollState {
        case .notSetUp:
            Text("Jira not set up").foregroundStyle(.secondary)
        case .waiting:
            Text("Loading…").foregroundStyle(.secondary)
        case .updated(let date):
            let count = settings.config.jira.epics.count
            Text("\(count) followed · updated \(date.formatted(date: .omitted, time: .shortened))")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).foregroundStyle(.red).help(message)
        }
    }

    private var searchBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Follow an epic: search its title or type a key", text: $search.query)
                    .textFieldStyle(.plain)
                if case .searching = search.state {
                    ProgressView().controlSize(.small)
                }
                if !search.query.isEmpty {
                    Button { search.clear() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            searchResults
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        switch search.state {
        case .idle, .searching:
            EmptyView()
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        case .found(let epics) where epics.isEmpty:
            Text("No open epic matches.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        case .found(let epics):
            VStack(spacing: 0) {
                ForEach(epics) { epic in
                    SearchResultRow(epic: epic, isFollowed: settings.config.jira.epics.contains(epic.key)) {
                        settings.follow(epic.key)
                        search.clear()
                    }
                }
            }
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var sections: some View {
        if settings.config.jira.epics.isEmpty {
            placeholder("Search above to follow an epic.")
        } else {
            // The popover takes the ideal size, and a scroll view's ideal height is its content's.
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(settings.config.jira.epics, id: \.self) { key in
                        EpicSectionView(key: key,
                                        section: list.sections[key],
                                        showsDone: settings.config.jira.showsDoneTickets,
                                        list: list,
                                        open: open,
                                        unfollow: settings.unfollow)
                        if key != settings.config.jira.epics.last {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: Self.maxSectionsHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func placeholder(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(24)
    }

    private func open(_ key: String) {
        if let url = settings.config.jira.browseURL(for: key) { openURL(url) }
    }
}

private struct SearchResultRow: View {
    let epic: Ticket
    let isFollowed: Bool
    let follow: () -> Void

    var body: some View {
        Button(action: follow) {
            HStack(spacing: 8) {
                TicketStatusDot(category: epic.status.category)
                Text(epic.key)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(epic.summary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if isFollowed {
                    Text("Following").font(.caption).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "plus.circle")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFollowed)
        .help(isFollowed ? "Already following \(epic.key)" : "Follow \(epic.key)")
    }
}

private struct EpicSectionView: View {
    let key: String
    let section: EpicSection?
    let showsDone: Bool
    @ObservedObject var list: TicketList
    let open: (String) -> Void
    let unfollow: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let failure = section?.failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            if let branch = section?.branch {
                let rows = branch.rows(includingDone: showsDone)
                if rows.isEmpty {
                    Text(branch.workItems.isEmpty ? "Nothing filed under it yet." : "Everything is done.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                ForEach(rows) { row in
                    Divider().padding(.leading, 14)
                    TicketRow(row: row, list: list, open: open)
                }
            } else if section?.failure == nil {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 12)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let epic = section?.branch?.epic {
                TicketStatusDot(category: epic.status.category)
            }
            Button { open(key) } label: {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.tail)
            }
            .buttonStyle(.plain)
            .help("Open \(key) in Jira")
            Spacer(minLength: 4)
            if let branch = section?.branch {
                Text("\(branch.workItems.count - branch.openCount) of \(branch.workItems.count) done")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button { unfollow(key) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Stop following \(key)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
    }

    private var title: String {
        guard let epic = section?.branch?.epic else { return key }
        return "\(epic.key) · \(epic.summary)"
    }
}

private struct TicketRow: View {
    let row: EpicBranch.Row
    @ObservedObject var list: TicketList
    let open: (String) -> Void

    private var ticket: Ticket { row.ticket }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                TicketStatusDot(category: ticket.status.category).padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ticket.summary)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            HStack(spacing: 8) {
                TicketStatusChip(text: ticket.status.name)
                Spacer(minLength: 4)
                Button { open(ticket.key) } label: { Image(systemName: "safari") }
                    .buttonStyle(.borderless)
                    .help("Open in Jira")
                TicketActionButtons(ticket: ticket, list: list)
            }
            .padding(.leading, 16)
            TicketActionFailure(key: ticket.key, list: list).padding(.leading, 16)
        }
        .padding(.leading, row.isSubtask ? 34 : 14)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
    }

    private var details: String {
        [ticket.key, ticket.type, ticket.assignee?.displayName ?? "Unassigned", ticket.priority]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private struct TicketActionButtons: View {
    let ticket: Ticket
    @ObservedObject var list: TicketList

    var body: some View {
        switch list.progress[ticket.key] {
        case .working:
            ProgressView().controlSize(.small)
        case .done(let summary):
            Text(summary).font(.caption).foregroundStyle(.secondary)
        case .failed, nil:
            HStack(spacing: 6) {
                let targets = list.moveTargets(for: ticket)
                Menu("Move") {
                    ForEach(targets, id: \.self) { status in
                        Button("\(status.category.emoji) \(status.name)") {
                            list.trigger(.move(to: status.name), on: ticket)
                        }
                    }
                }
                .fixedSize()
                .controlSize(.small)
                .disabled(targets.isEmpty)
                let assignment = list.assignment(for: ticket)
                Button(assignment.title) { list.trigger(assignment, on: ticket) }
                    .controlSize(.small)
            }
        }
    }
}

private struct TicketActionFailure: View {
    let key: String
    @ObservedObject var list: TicketList

    var body: some View {
        if case .failed(let message) = list.progress[key] {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TicketStatusChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

private struct TicketStatusDot: View {
    let category: TicketStatus.Category

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch category {
        case .toDo: return .secondary.opacity(0.5)
        case .inProgress: return .blue
        case .done: return .green
        }
    }
}
