import SwiftUI

struct ReviewListView: View {
    @ObservedObject var list: ReviewList
    let openDiff: (MergeRequest) -> Void
    let openSettings: () -> Void

    private static let maxRowsHeight: CGFloat = 520

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if list.mergeRequests.isEmpty {
                placeholder
            } else {
                // The popover takes the ideal size, and a scroll view's ideal height is its content's.
                ScrollView { rows }
                    .frame(maxHeight: Self.maxRowsHeight)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 480)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Reviews").font(.headline)
            pollSummary.font(.caption).lineLimit(1).truncationMode(.tail)
            Spacer()
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
        case .waiting:
            Text("Loading…").foregroundStyle(.secondary)
        case .updated(let date):
            Text("\(list.mergeRequests.count) open · updated \(date.formatted(date: .omitted, time: .shortened))")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).foregroundStyle(.red).help(message)
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        Group {
            if case .waiting = list.pollState {
                ProgressView().controlSize(.small)
            } else {
                Text("Nothing waiting for your review.").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(list.mergeRequests) { mergeRequest in
                ReviewRow(mergeRequest: mergeRequest, list: list, openDiff: openDiff)
                if mergeRequest.id != list.mergeRequests.last?.id {
                    Divider().padding(.leading, 14)
                }
            }
        }
    }
}

private struct ReviewRow: View {
    let mergeRequest: MergeRequest
    @ObservedObject var list: ReviewList
    let openDiff: (MergeRequest) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                PipelineDot(status: mergeRequest.pipeline).padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mergeRequest.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                    Text("\(mergeRequest.label) · @\(mergeRequest.author.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            HStack(spacing: 8) {
                DiffStatsLabel(stats: mergeRequest.diffStats)
                if let status = mergeRequest.mergeStatusSummary {
                    StatusChip(text: status)
                }
                Spacer(minLength: 4)
                Button { openDiff(mergeRequest) } label: { Image(systemName: "text.magnifyingglass") }
                    .buttonStyle(.borderless)
                    .disabled(!mergeRequest.isPreviewable)
                    .help(mergeRequest.isPreviewable ? "Preview diff" : "Too large to preview here")
                Button { openInBrowser() } label: { Image(systemName: "safari") }
                    .buttonStyle(.borderless)
                    .help("Open in GitLab")
                ReviewActionButtons(mergeRequest: mergeRequest, list: list)
            }
            .padding(.leading, 16)
            ActionFailure(key: mergeRequest.key, list: list).padding(.leading, 16)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func openInBrowser() {
        if let url = URL(string: mergeRequest.webURL) { openURL(url) }
    }
}

struct ReviewActionButtons: View {
    let mergeRequest: MergeRequest
    @ObservedObject var list: ReviewList

    var body: some View {
        switch list.progress[mergeRequest.key] {
        case .working:
            ProgressView().controlSize(.small)
        case .done(let summary):
            Text(summary).font(.caption).foregroundStyle(.secondary)
        case .failed, nil:
            HStack(spacing: 6) {
                ForEach(list.actions(for: mergeRequest), id: \.self) { action in
                    button(for: action)
                }
            }
        }
    }

    @ViewBuilder
    private func button(for action: ReviewAction) -> some View {
        switch action {
        case .approve, .unapprove:
            Button(action.title) { list.trigger(action, on: mergeRequest) }
                .controlSize(.small)
        case .merge:
            let isArmed = list.armedKey == mergeRequest.key
            Button(isArmed ? "Confirm merge" : action.title) { list.trigger(action, on: mergeRequest) }
                .buttonStyle(.borderedProminent)
                .tint(isArmed ? .red : .accentColor)
                .controlSize(.small)
        }
    }
}

struct ActionFailure: View {
    let key: String
    @ObservedObject var list: ReviewList

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

struct DiffStatsLabel: View {
    let stats: MergeRequest.DiffStats?

    var body: some View {
        if let stats {
            HStack(spacing: 4) {
                Text("+\(stats.additions)").foregroundStyle(.green)
                Text("−\(stats.deletions)").foregroundStyle(.red)
                Text("· \(stats.fileCount) \(stats.fileCount == 1 ? "file" : "files")").foregroundStyle(.secondary)
            }
            .font(.caption.monospacedDigit())
        } else {
            Text("diff pending").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct StatusChip: View {
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

private struct PipelineDot: View {
    let status: PipelineStatus?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .help(status?.summary ?? "no pipeline")
    }

    private var color: Color {
        switch status {
        case .success: return .green
        case .failed: return .red
        case .pending: return .yellow
        case nil: return .secondary.opacity(0.4)
        }
    }
}
