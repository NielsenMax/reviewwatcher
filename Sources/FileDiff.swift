import Foundation

/// The newest diff of a merge request, with the commit its files can be read at.
struct DiffVersion: Decodable {
    let headSHA: String
    let files: [FileDiff]

    private enum CodingKeys: String, CodingKey {
        case headSHA = "head_commit_sha"
        case files = "diffs"
    }
}

struct FileDiff: Identifiable {
    static let previewLineLimit = 2000

    let oldPath: String
    let newPath: String
    let isNew: Bool
    let isRenamed: Bool
    let isDeleted: Bool
    let isGenerated: Bool
    let isOmitted: Bool
    let hunks: [Hunk]

    var id: String { newPath }

    var additions: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .added }.count } }

    var deletions: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .removed }.count } }

    /// A new or deleted file is already shown whole; only a modified one has unchanged lines left out.
    var hasHiddenContext: Bool { !isNew && !isDeleted && !isOmitted && !hunks.isEmpty }

    /// Patterns are `fnmatch` globs over the whole path, so `*` also crosses `/`.
    func firstMatch(in patterns: [String]) -> String? {
        patterns.first { pattern in
            [newPath, oldPath].contains { fnmatch(pattern, $0, FNM_CASEFOLD) == 0 }
        }
    }
}

struct Hunk {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let section: String
    let lines: [DiffLine]

    /// Unified diff writes an empty range as the line it follows, so the unchanged neighbours
    /// of a hunk sit one line further out when its count is zero.
    var newLineBefore: Int { newCount == 0 ? newStart : newStart - 1 }
    var newLineAfter: Int { newCount == 0 ? newStart + 1 : newStart + newCount }
    var oldLineBefore: Int { oldCount == 0 ? oldStart : oldStart - 1 }
    var oldLineAfter: Int { oldCount == 0 ? oldStart + 1 : oldStart + oldCount }
}

struct DiffLine: Identifiable {
    enum Kind {
        case added, removed, context
    }

    let kind: Kind
    let oldNumber: Int?
    let newNumber: Int?
    let text: String

    /// Unique within a file: every new-side line is either context or added, and removals have only an old side.
    var id: String {
        if let newNumber { return "n\(newNumber)" }
        return "o\(oldNumber ?? 0)"
    }

    static func context(old: Int, new: Int, text: String) -> DiffLine {
        DiffLine(kind: .context, oldNumber: old, newNumber: new, text: text)
    }
}

extension FileDiff: Decodable {
    private enum CodingKeys: String, CodingKey {
        case diff
        case oldPath = "old_path"
        case newPath = "new_path"
        case isNew = "new_file"
        case isRenamed = "renamed_file"
        case isDeleted = "deleted_file"
        case isGenerated = "generated_file"
        case isTooLarge = "too_large"
        case isCollapsed = "collapsed"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        oldPath = try container.decode(String.self, forKey: .oldPath)
        newPath = try container.decode(String.self, forKey: .newPath)
        isNew = try container.decode(Bool.self, forKey: .isNew)
        isRenamed = try container.decode(Bool.self, forKey: .isRenamed)
        isDeleted = try container.decode(Bool.self, forKey: .isDeleted)
        isGenerated = try container.decodeIfPresent(Bool.self, forKey: .isGenerated) ?? false
        let isTooLarge = try container.decodeIfPresent(Bool.self, forKey: .isTooLarge) ?? false
        let isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        isOmitted = isTooLarge || isCollapsed
        let diff = try container.decode(String.self, forKey: .diff)
        guard let hunks = HunkParser.parse(diff) else {
            throw DecodingError.dataCorruptedError(forKey: .diff, in: container,
                                                   debugDescription: "unreadable hunk header in the diff of \(newPath)")
        }
        self.hunks = hunks
    }
}

private enum HunkParser {
    static func parse(_ diff: String) -> [Hunk]? {
        var hunks: [Hunk] = []
        var header: Header?
        var lines: [DiffLine] = []
        var old = 0
        var new = 0

        func close() {
            guard let header else { return }
            hunks.append(Hunk(oldStart: header.oldStart, oldCount: header.oldCount,
                              newStart: header.newStart, newCount: header.newCount,
                              section: header.section, lines: lines))
        }

        for row in diff.components(separatedBy: "\n") {
            let marker = row.first
            let text = String(row.dropFirst())
            switch marker {
            case "@":
                close()
                guard let next = Header(row) else { return nil }
                header = next
                lines = []
                old = next.oldStart
                new = next.newStart
            case "+":
                lines.append(DiffLine(kind: .added, oldNumber: nil, newNumber: new, text: text))
                new += 1
            case "-":
                lines.append(DiffLine(kind: .removed, oldNumber: old, newNumber: nil, text: text))
                old += 1
            case " ":
                lines.append(.context(old: old, new: new, text: text))
                old += 1
                new += 1
            default:
                // "\ No newline at end of file" and the empty tail after the final newline.
                continue
            }
        }
        close()
        return hunks
    }

    /// `@@ -oldStart[,oldCount] +newStart[,newCount] @@ section`, where an omitted count means one line.
    private struct Header {
        let oldStart: Int
        let oldCount: Int
        let newStart: Int
        let newCount: Int
        let section: String

        init?(_ row: String) {
            let parts = row.components(separatedBy: " @@")
            guard parts.count >= 2, parts[0].hasPrefix("@@ ") else { return nil }
            let ranges = parts[0].dropFirst(3).split(separator: " ")
            guard ranges.count == 2,
                  let old = Self.range(ranges[0], sign: "-"),
                  let new = Self.range(ranges[1], sign: "+") else { return nil }
            (oldStart, oldCount) = old
            (newStart, newCount) = new
            section = parts.dropFirst().joined(separator: " @@").trimmingCharacters(in: .whitespaces)
        }

        private static func range(_ text: Substring, sign: Character) -> (Int, Int)? {
            guard text.first == sign else { return nil }
            let bounds = text.dropFirst().split(separator: ",")
            guard let start = bounds.first.flatMap({ Int($0) }) else { return nil }
            guard bounds.count == 2 else { return (start, 1) }
            return Int(bounds[1]).map { (start, $0) }
        }
    }
}
