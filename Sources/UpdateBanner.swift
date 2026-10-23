import SwiftUI

/// Sits above the popover's tabs while a release waits, installs or failed to install, and takes no room otherwise.
struct UpdateBanner: View {
    @ObservedObject var updater: Updater

    var body: some View {
        switch updater.state {
        case .available(let release):
            banner {
                Text("Version \(release.version.description) is available")
                Spacer()
                Link("What changed", destination: updater.changes(in: release)).font(.caption)
                Button("Update") { updater.install(release) }
                    .help("Build \(release.version.tag) on this Mac and restart into it")
            }
        case .installing(_, let step):
            banner {
                ProgressView().controlSize(.small)
                Text(step).foregroundStyle(.secondary)
                Spacer()
            }
        case .installFailed(let release, let message):
            banner {
                Text(message).foregroundStyle(.red).lineLimit(2).help(message)
                Spacer()
                Button("Retry") { updater.install(release) }
            }
        case .unchecked, .upToDate, .checkFailed:
            EmptyView()
        }
    }

    private func banner<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8, content: content)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.12))
    }
}
