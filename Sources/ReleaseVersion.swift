import Foundation

/// A release as the repository tags it, `v1.2.3`.
struct ReleaseVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    var description: String { "\(major).\(minor).\(patch)" }

    var tag: String { "v\(description)" }

    init?(tag: String) {
        guard tag.first == "v" else { return nil }
        self.init(numbers: tag.dropFirst())
    }

    /// The bundle carries `git describe` output, which runs on past the tag when the build is not the tag itself:
    /// `1.2.3-4-gabc1234-dirty`.
    init?(bundleVersion: String) {
        self.init(numbers: bundleVersion.prefix { $0 != "-" })
    }

    private init?(numbers: Substring) {
        let parts = numbers.split(separator: ".", omittingEmptySubsequences: false)
            .map { $0.allSatisfy { ("0"..."9").contains($0) } ? Int($0) : nil }
        guard parts.count == 3, let major = parts[0], let minor = parts[1], let patch = parts[2] else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
