import Foundation

/// Remembers which merge requests have already been announced, so a restart is silent.
struct SeenStore: Codable {
    var seeded: Bool
    var reviews: [String: ReviewState]

    struct ReviewState: Codable {
        let updatedAt: String
        /// Nil in state written before the head was tracked.
        let headSHA: String?
        let pipeline: String?
        let isApprovedByReviewer: Bool
        /// A notification still owed, waiting for the merge request to meet the notification gate.
        let held: Announcement?
    }

    enum Announcement: String, Codable {
        case reviewRequested
        case approvalRemoved
    }

    static func load() -> SeenStore {
        guard let data = try? Data(contentsOf: Paths.stateFile),
              let store = try? JSONDecoder().decode(SeenStore.self, from: data) else {
            return SeenStore(seeded: false, reviews: [:])
        }
        return store
    }

    func save() throws {
        let directory = Paths.stateFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Paths.stateFile, options: .atomic)
    }
}
