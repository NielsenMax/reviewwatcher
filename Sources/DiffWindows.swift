import AppKit
import SwiftUI

/// One preview window per merge request; asking again brings the open one forward.
final class DiffWindows: NSObject, NSWindowDelegate {
    private let list: ReviewList
    private let client: GitLabClient
    private let settings: Settings
    private var windows: [String: NSWindow] = [:]

    init(list: ReviewList, client: GitLabClient, settings: Settings) {
        self.list = list
        self.client = client
        self.settings = settings
    }

    func show(_ mergeRequest: MergeRequest) {
        let window = windows[mergeRequest.key] ?? makeWindow(for: mergeRequest)
        windows[mergeRequest.key] = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value !== closing }
    }

    private func makeWindow(for mergeRequest: MergeRequest) -> NSWindow {
        let preview = DiffPreview(of: mergeRequest, client: client,
                                  collapsedFilePatterns: settings.config.collapsedFilePatterns)
        let view = DiffView(initial: mergeRequest, list: list, preview: preview)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = mergeRequest.label
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 960, height: 720))
        window.center()
        return window
    }
}

private struct DiffView: View {
    let initial: MergeRequest
    @ObservedObject var list: ReviewList
    @ObservedObject var preview: DiffPreview
    @Environment(\.openURL) private var openURL

    /// Nil once the merge request leaves the review list: merged, closed, or the reviewer removed.
    private var current: MergeRequest? { list.mergeRequest(withKey: initial.key) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 620, minHeight: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(initial.title).font(.headline).lineLimit(2)
                    HStack(spacing: 8) {
                        Text("@\(initial.author.username)").font(.caption).foregroundStyle(.secondary)
                        DiffStatsLabel(stats: initial.diffStats)
                    }
                }
                Spacer()
                Button("Open in GitLab") {
                    if let url = URL(string: initial.webURL) { openURL(url) }
                }
                .controlSize(.small)
                if let current {
                    ReviewActionButtons(mergeRequest: current, list: list)
                } else {
                    Text("No longer open").font(.caption).foregroundStyle(.secondary)
                }
            }
            ActionFailure(key: initial.key, list: list)
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        switch preview.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let version):
            VStack(spacing: 0) {
                FilesToolbar(preview: preview, files: version.files)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(version.files) { file in
                            fileSection(file)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    /// Built here rather than in its own view so the lazy stack sees each `Section` and pins its header.
    @ViewBuilder
    private func fileSection(_ file: FileDiff) -> some View {
        let isCollapsed = preview.isCollapsed(file)
        Section {
            if isCollapsed {
                Color.clear.frame(height: 10)
            } else {
                let rows = preview.rows(for: file)
                let gutterWidth = Self.gutterWidth(for: rows)
                ForEach(rows) { row in
                    switch row.content {
                    case .line(let line): DiffLineRow(line: line, gutterWidth: gutterWidth)
                    case .gap(let gap): GapRow(gap: gap, gutterWidth: gutterWidth) { preview.reveal($0, at: gap.index, in: file) }
                    case .note(let text): NoteRow(text: text)
                    }
                }
                CardFooter().padding(.bottom, 14)
            }
        } header: {
            FileHeader(file: file,
                       isCollapsed: isCollapsed,
                       matchedPattern: file.firstMatch(in: preview.collapsedFilePatterns)) {
                preview.toggle(file)
            }
        }
    }

    /// One line-number column, wide enough for the file's longest number at the gutter's monospaced digit width.
    private static func gutterWidth(for rows: [DiffPreview.Row]) -> CGFloat {
        let highest = rows.reduce(0) { highest, row in
            guard case .line(let line) = row.content else { return highest }
            return max(highest, line.oldNumber ?? 0, line.newNumber ?? 0)
        }
        return CGFloat(String(highest).count) * 7 + 14
    }
}

private struct FilesToolbar: View {
    @ObservedObject var preview: DiffPreview
    let files: [FileDiff]

    var body: some View {
        HStack(spacing: 10) {
            Text(summary).font(.caption).foregroundStyle(.secondary)
            if !preview.collapsedFilePatterns.isEmpty {
                Text("Auto-collapses \(preview.collapsedFilePatterns.joined(separator: "  "))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help("Set by collapsedFilePatterns in ~/.config/reviewwatcher/config.json, along with generated files")
            }
            Spacer()
            Button("Expand all") { preview.expandAll() }
                .disabled(preview.collapsed.isEmpty)
            Button("Collapse all") { preview.collapseAll() }
                .disabled(preview.collapsed.count == files.count)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var summary: String {
        let fileCount = "\(files.count) \(files.count == 1 ? "file" : "files")"
        return preview.collapsed.isEmpty ? fileCount : "\(fileCount) · \(preview.collapsed.count) collapsed"
    }
}

private struct FileHeader: View {
    let file: FileDiff
    let isCollapsed: Bool
    let matchedPattern: String?
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                .frame(width: 12)
            path
            badges
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Text("+\(file.additions)").foregroundStyle(.green)
                Text("−\(file.deletions)").foregroundStyle(.red)
            }
            .font(.system(size: 11, design: .monospaced))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CardShape(part: shapePart).fill(Color.primary.opacity(0.05)))
        .background(CardShape(part: shapePart).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(CardShape(part: shapePart).stroke(Color(nsColor: .separatorColor)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .help(isCollapsed ? "Show this file's changes" : "Hide this file's changes")
    }

    private var shapePart: CardShape.Part { isCollapsed ? .whole : .top }

    private var path: some View {
        let shown = file.isDeleted ? file.oldPath : file.newPath
        let slash = shown.lastIndex(of: "/").map { shown.index(after: $0) } ?? shown.startIndex
        return (Text(verbatim: String(shown[..<slash])).foregroundColor(.secondary)
            + Text(verbatim: String(shown[slash...])).fontWeight(.semibold))
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.head)
            .help(file.isRenamed ? "\(file.oldPath) → \(file.newPath)" : shown)
    }

    @ViewBuilder
    private var badges: some View {
        if file.isNew { Badge(text: "new", tint: .green) }
        if file.isDeleted { Badge(text: "deleted", tint: .red) }
        if file.isRenamed { Badge(text: "renamed", tint: .blue) }
        if file.isGenerated { Badge(text: "generated", tint: .secondary) }
        if let matchedPattern { Badge(text: matchedPattern, tint: .secondary) }
    }
}

private struct Badge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

private struct DiffLineRow: View {
    let line: DiffLine
    let gutterWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            gutter(line.oldNumber)
            gutter(line.newNumber)
            Text(verbatim: marker)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            // An empty Text collapses to zero height, which would swallow blank lines.
            Text(verbatim: line.text.isEmpty ? " " : line.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 10)
        }
        .font(.system(size: 12, design: .monospaced))
        .background(alignment: .leading) { gutterTint.frame(width: gutterWidth * 2) }
        .background(tint.opacity(0.12))
        .modifier(CardSides())
    }

    private func gutter(_ number: Int?) -> some View {
        Text(verbatim: number.map(String.init) ?? "")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(width: gutterWidth, alignment: .trailing)
    }

    private var gutterTint: Color {
        line.kind == .context ? Color.primary.opacity(0.035) : tint.opacity(0.12)
    }

    private var marker: String {
        switch line.kind {
        case .added: return "+"
        case .removed: return "−"
        case .context: return ""
        }
    }

    private var tint: Color {
        switch line.kind {
        case .added: return .green
        case .removed: return .red
        case .context: return .clear
        }
    }
}

private struct GapRow: View {
    let gap: DiffPreview.Gap
    let gutterWidth: CGFloat
    let reveal: (DiffPreview.Direction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                if gap.hasNext {
                    revealButton("arrow.up", .aboveNext, help: "Show \(DiffPreview.revealStep) lines above the next change")
                }
                if gap.hasPrevious {
                    revealButton("arrow.down", .belowPrevious, help: "Show \(DiffPreview.revealStep) lines below the previous change")
                }
            }
            .frame(width: gutterWidth * 2, alignment: .center)
            Button(allLabel) { reveal(.all) }
                .buttonStyle(.link)
                .font(.caption)
            status
            Text(verbatim: gap.section)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.07))
        .modifier(CardSides())
    }

    private var allLabel: String {
        switch gap.hiddenLines {
        case nil: return "Show the rest of the file"
        case 1?: return "Show 1 hidden line"
        case let count?: return "Show \(count) hidden lines"
        }
    }

    @ViewBuilder
    private var status: some View {
        switch gap.source {
        case .loading:
            ProgressView().controlSize(.mini)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red).lineLimit(1).help(message)
        case .loaded, nil:
            EmptyView()
        }
    }

    private func revealButton(_ symbol: String, _ direction: DiffPreview.Direction, help: String) -> some View {
        Button { reveal(direction) } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

private struct NoteRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .modifier(CardSides())
    }
}

private struct CardFooter: View {
    var body: some View {
        Color.clear
            .frame(height: CardShape.radius)
            .background(CardShape(part: .bottom).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(CardShape(part: .bottom).stroke(Color(nsColor: .separatorColor)))
    }
}

/// The card around a file is drawn in strips so its rows can stay lazy: a top piece for the header,
/// side edges on every row, and a bottom piece to close it.
private struct CardSides: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(SideEdges().stroke(Color(nsColor: .separatorColor)))
    }

    private struct SideEdges: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            return path
        }
    }
}

private struct CardShape: Shape {
    enum Part {
        case top, bottom, whole
    }

    static let radius: CGFloat = 8

    let part: Part

    func path(in rect: CGRect) -> Path {
        let radius = min(Self.radius, rect.height / 2)
        var path = Path()
        switch part {
        case .whole:
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius))
        case .top:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                        tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: radius)
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                        tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: radius)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        case .bottom:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                        tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: radius)
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                        tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: radius)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        return path
    }
}
