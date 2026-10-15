import Foundation

/// What one diff window shows and remembers: the files, which are collapsed, and how much
/// unchanged context each gap between hunks has revealed.
final class DiffPreview: ObservableObject {
    enum Phase {
        case loading
        case loaded(DiffVersion)
        case failed(String)
    }

    enum Source {
        case loading
        case loaded([String])
        case failed(String)
    }

    enum Direction {
        case belowPrevious
        case aboveNext
        case all
    }

    struct Gap {
        let index: Int
        /// Nil for the stretch after the last hunk until the file is fetched, since only the file knows its length.
        let hiddenLines: Int?
        let section: String
        let hasPrevious: Bool
        let hasNext: Bool
        let source: Source?
    }

    struct Row: Identifiable {
        enum Content {
            case line(DiffLine)
            case gap(Gap)
            case note(String)
        }

        let id: String
        let content: Content
    }

    static let revealStep = 20

    @Published private(set) var phase = Phase.loading
    @Published private(set) var collapsed: Set<String> = []
    @Published private(set) var reveals: [String: [Int: Reveal]] = [:]
    @Published private(set) var sources: [String: Source] = [:]

    let collapsedFilePatterns: [String]
    private let mergeRequest: MergeRequest
    private let client: GitLabClient

    struct Reveal {
        var belowPrevious = 0
        var aboveNext = 0
        var isAll = false
    }

    init(of mergeRequest: MergeRequest, client: GitLabClient, collapsedFilePatterns: [String]) {
        self.mergeRequest = mergeRequest
        self.client = client
        self.collapsedFilePatterns = collapsedFilePatterns
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let version = Result { try client.latestDiff(of: mergeRequest) }
            DispatchQueue.main.async { self?.show(version) }
        }
    }

    var files: [FileDiff] {
        guard case .loaded(let version) = phase else { return [] }
        return version.files
    }

    func isCollapsed(_ file: FileDiff) -> Bool {
        collapsed.contains(file.id)
    }

    func toggle(_ file: FileDiff) {
        if collapsed.remove(file.id) == nil {
            collapsed.insert(file.id)
        }
    }

    func collapseAll() {
        collapsed = Set(files.map(\.id))
    }

    func expandAll() {
        collapsed = []
    }

    func reveal(_ direction: Direction, at gap: Int, in file: FileDiff) {
        var reveal = reveals[file.id]?[gap] ?? Reveal()
        switch direction {
        case .belowPrevious: reveal.belowPrevious += Self.revealStep
        case .aboveNext: reveal.aboveNext += Self.revealStep
        case .all: reveal.isAll = true
        }
        reveals[file.id, default: [:]][gap] = reveal
        fetchSource(of: file)
    }

    func rows(for file: FileDiff) -> [Row] {
        if file.isOmitted { return [note("Too large to show here — open it in GitLab.")] }
        if file.hunks.isEmpty { return [note("No text changes.")] }
        let hunkRows = { (hunk: Hunk) in hunk.lines.map { Row(id: $0.id, content: .line($0)) } }
        guard file.hasHiddenContext else { return file.hunks.flatMap(hunkRows) }

        var rows: [Row] = []
        for index in file.hunks.indices {
            rows += gapRows(at: index, in: file)
            rows += hunkRows(file.hunks[index])
        }
        return rows + gapRows(at: file.hunks.count, in: file)
    }

    private func show(_ version: Result<DiffVersion, Error>) {
        switch version {
        case .success(let version):
            let folded = version.files.filter { $0.isGenerated || $0.firstMatch(in: collapsedFilePatterns) != nil }
            collapsed = Set(folded.map(\.id))
            phase = .loaded(version)
        case .failure(let error):
            phase = .failed(error.localizedDescription)
        }
    }

    /// Context lines read the file at the version's head commit, the same commit its hunks were cut from.
    private func fetchSource(of file: FileDiff) {
        switch sources[file.id] {
        case .loading, .loaded: return
        case .failed, nil: break
        }
        guard case .loaded(let version) = phase else { return }
        sources[file.id] = .loading
        let projectID = mergeRequest.projectID
        DispatchQueue.global(qos: .userInitiated).async { [weak self, client] in
            let lines = Result { try client.fileLines(projectID: projectID, path: file.newPath, at: version.headSHA) }
            DispatchQueue.main.async {
                switch lines {
                case .success(let lines): self?.sources[file.id] = .loaded(lines)
                case .failure(let error): self?.sources[file.id] = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Gap `index` is the unchanged stretch before hunk `index`; the one past the last hunk runs to the end of the file.
    private func gapRows(at index: Int, in file: FileDiff) -> [Row] {
        let previous = index > 0 ? file.hunks[index - 1] : nil
        let next = index < file.hunks.count ? file.hunks[index] : nil
        let first = previous?.newLineAfter ?? 1
        let source = sources[file.id]
        var fileLines: [String]?
        if case .loaded(let loaded) = source { fileLines = loaded }

        let gapRow = { (hidden: Int?) in
            Row(id: "gap\(index)", content: .gap(Gap(index: index, hiddenLines: hidden, section: next?.section ?? "",
                                                     hasPrevious: previous != nil, hasNext: next != nil, source: source)))
        }
        guard let fileLines else {
            guard let last = next?.newLineBefore else { return [gapRow(nil)] }
            return last < first ? [] : [gapRow(last - first + 1)]
        }

        let last = min(next?.newLineBefore ?? fileLines.count, fileLines.count)
        guard last >= first else { return [] }
        let size = last - first + 1
        let reveal = reveals[file.id]?[index] ?? Reveal()
        let shownBelowPrevious = reveal.isAll ? size : min(reveal.belowPrevious, size)
        let shownAboveNext = min(reveal.aboveNext, size - shownBelowPrevious)
        let hidden = size - shownBelowPrevious - shownAboveNext

        let oldOffset = next.map { $0.oldLineBefore - $0.newLineBefore }
            ?? previous.map { $0.oldLineAfter - $0.newLineAfter } ?? 0
        let contextRow = { (number: Int) -> Row in
            let line = DiffLine.context(old: number + oldOffset, new: number, text: fileLines[number - 1])
            return Row(id: line.id, content: .line(line))
        }
        var rows = (first ..< first + shownBelowPrevious).map(contextRow)
        if hidden > 0 { rows.append(gapRow(hidden)) }
        rows += (last - shownAboveNext + 1 ..< last + 1).map(contextRow)
        return rows
    }

    private func note(_ text: String) -> Row {
        Row(id: "note", content: .note(text))
    }
}
