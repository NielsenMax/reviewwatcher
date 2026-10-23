import SwiftUI

struct ArgoListView: View {
    @ObservedObject var list: ArgoList
    let openSettings: () -> Void

    private static let maxRowsHeight: CGFloat = 520

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            controls
            Divider()
            content
        }
        .frame(width: 480)
        .onAppear { list.refresh() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Argo CD").font(.headline)
            summary.font(.caption).lineLimit(1).truncationMode(.tail)
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
    private var summary: some View {
        switch list.loadState {
        case .idle, .loading:
            Text("Loading…").foregroundStyle(.secondary)
        case .loaded(let date):
            Text("\(list.outOfSyncCount) out of sync · updated \(date.formatted(date: .omitted, time: .shortened))")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).foregroundStyle(.red).help(message)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter by app, project or namespace", text: $list.query)
                .textFieldStyle(.plain)
            Picker("", selection: $list.filter) {
                Text("Out of sync").tag(ArgoList.Filter.outOfSync)
                Text("All").tag(ArgoList.Filter.all)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        let apps = list.visibleApps
        if list.apps.isEmpty {
            if case .failed(let message) = list.loadState {
                placeholder(message, isError: true)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        } else if apps.isEmpty {
            placeholder(list.query.isEmpty && list.filter == .outOfSync ? "Everything is in sync." : "No app matches.")
        } else {
            // The popover takes the ideal size, and a scroll view's ideal height is its content's.
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(apps) { app in
                        ArgoRow(app: app, list: list)
                        if app.id != apps.last?.id {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
            .frame(maxHeight: Self.maxRowsHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func placeholder(_ message: String, isError: Bool = false) -> some View {
        Text(message)
            .foregroundStyle(isError ? Color.red : Color.secondary)
            .multilineTextAlignment(.center)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity)
            .padding(24)
    }
}

private struct ArgoRow: View {
    let app: ArgoApp
    @ObservedObject var list: ArgoList
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                HealthDot(health: app.health).padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text("\(app.project) · \(app.destination)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            HStack(spacing: 6) {
                ArgoChip(text: app.sync, isWarning: app.isOutOfSync)
                ArgoChip(text: app.health, isWarning: app.health != "Healthy")
                if app.isAutoSynced {
                    ArgoChip(text: "auto-sync", isWarning: false)
                }
                Spacer(minLength: 4)
                Button { list.browseURL(for: app).map { openURL($0) } } label: { Image(systemName: "safari") }
                    .buttonStyle(.borderless)
                    .disabled(list.browseURL(for: app) == nil)
                    .help("Open in Argo CD")
                ArgoSyncButton(app: app, list: list)
            }
            .padding(.leading, 16)
            if let failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// A sync started here speaks for itself; otherwise the last operation's error, while it still matters.
    private var failure: String? {
        switch list.progress[app.id] {
        case .failed(let message): return message
        case .done, .starting, .syncing: return nil
        case nil:
            guard app.isOutOfSync, let operation = app.operation, operation.hasFailed else { return nil }
            return "Last sync \(operation.phase.lowercased()): \(operation.message ?? "no message")"
        }
    }
}

private struct ArgoSyncButton: View {
    let app: ArgoApp
    @ObservedObject var list: ArgoList

    var body: some View {
        switch list.progress[app.id] {
        case .starting, .syncing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Syncing…").font(.caption).foregroundStyle(.secondary)
            }
        case .done(let summary):
            Text(summary).font(.caption).foregroundStyle(.secondary)
        case .failed, nil:
            if app.operation?.isRunning == true {
                Text("Operation running").font(.caption).foregroundStyle(.secondary)
            } else {
                let isArmed = list.armedID == app.id
                Button(isArmed ? "Confirm sync" : "Sync") { list.triggerSync(of: app) }
                    .buttonStyle(.borderedProminent)
                    .tint(isArmed ? .red : .accentColor)
                    .controlSize(.small)
            }
        }
    }
}

private struct ArgoChip: View {
    let text: String
    let isWarning: Bool

    var body: some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .foregroundStyle(isWarning ? Color.orange : Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill((isWarning ? Color.orange : Color.secondary).opacity(0.15)))
    }
}

private struct HealthDot: View {
    let health: String

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .help(health)
    }

    private var color: Color {
        switch health {
        case "Healthy": return .green
        case "Progressing": return .blue
        case "Degraded": return .red
        case "Missing": return .orange
        default: return .secondary.opacity(0.5)
        }
    }
}
