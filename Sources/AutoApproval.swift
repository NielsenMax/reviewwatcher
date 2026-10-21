import Foundation

/// The merge requests approved without being read: a release of develop, or a diff whose every change moves
/// an image tag to a release version.
enum AutoApproval {
    case release
    case versionBump

    var summary: String {
        switch self {
        case .release: return "release"
        case .versionBump: return "version bump"
        }
    }

    static let releaseSource = "develop"
    static let releaseTargets: Set<String> = ["main", "master"]

    /// A fork's branch named develop is not this project's develop.
    static func isRelease(_ mergeRequest: MergeRequest) -> Bool {
        mergeRequest.sourceBranch == releaseSource && releaseTargets.contains(mergeRequest.targetBranch)
            && mergeRequest.sourceProjectID == mergeRequest.projectID
    }

    static func isVersionBump(_ files: [FileDiff]) -> Bool {
        !files.isEmpty && files.allSatisfy { isEditedManifest($0) && $0.hunks.allSatisfy(onlyMovesTags) }
    }

    private static func isEditedManifest(_ file: FileDiff) -> Bool {
        let isYAML = file.newPath.hasSuffix(".yaml") || file.newPath.hasSuffix(".yml")
        return isYAML && !file.isNew && !file.isDeleted && !file.isRenamed && !file.isOmitted && !file.hunks.isEmpty
    }

    /// The n-th removed line of a hunk is replaced by its n-th added line, so the two are compared as a pair.
    private static func onlyMovesTags(_ hunk: Hunk) -> Bool {
        let removed = hunk.lines.filter { $0.kind == .removed }.map { TagLine($0.text) }
        let added = hunk.lines.filter { $0.kind == .added }.map { TagLine($0.text) }
        guard !added.isEmpty, removed.count == added.count else { return false }
        return zip(removed, added).allSatisfy { old, new in
            guard let old, let new else { return false }
            return old.indentation == new.indentation && old.key == new.key && old.repository == new.repository
                && (try? releaseVersion.wholeMatch(in: new.tag)) != nil
        }
    }

    private static let releaseVersion = try! Regex(#"v?\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?"#)
}

/// A kustomize `newTag:` or a container `image:` line, as far as a version bump may touch it.
private struct TagLine {
    let indentation: String
    let key: String
    /// Image lines only: everything before the tag, registry included.
    let repository: String?
    let tag: String

    private static let pattern = try! Regex(
        #"(?<indentation>\s*(?:-\s+)?)(?<key>newTag|image):\s+(?<value>"[^"]*"|'[^']*'|[^\s"'#]+)\s*(?:#.*)?"#
    )

    /// A digest pins content rather than a version, and an image without a tag floats on latest.
    init?(_ text: String) {
        guard let match = try? Self.pattern.wholeMatch(in: text),
              let indentation = match["indentation"]?.substring,
              let key = match["key"]?.substring,
              let value = match["value"]?.substring?.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) else {
            return nil
        }
        self.indentation = String(indentation)
        self.key = String(key)
        guard key == "image" else {
            repository = nil
            tag = value
            return
        }
        guard !value.contains("@"), let colon = value.lastIndex(of: ":"), !value[colon...].contains("/") else {
            return nil
        }
        repository = String(value[..<colon])
        tag = String(value[value.index(after: colon)...])
    }
}
