import Foundation

/// What each ticket under the watched epic looked like at the last poll, so a restart is silent and only changes speak.
struct EpicSeenStore: Codable {
    let epic: String
    /// When the last successful poll started; nil until the first one for `epic`.
    var polledAt: Date?
    var tickets: [String: TicketState]

    struct TicketState: Codable {
        let status: String
        let assigneeAccountID: String?
        let parentKey: String?
        /// Jira numbers comments site-wide in creation order, so any higher id is a newer comment.
        let latestCommentID: Int?
    }

    static func fresh(for epic: String) -> EpicSeenStore {
        EpicSeenStore(epic: epic, polledAt: nil, tickets: [:])
    }

    static func load(for epic: String) -> EpicSeenStore {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: Paths.epicStateFile),
              let store = try? decoder.decode(EpicSeenStore.self, from: data),
              store.epic == epic else {
            return fresh(for: epic)
        }
        return store
    }

    func save() throws {
        let directory = Paths.epicStateFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: Paths.epicStateFile, options: .atomic)
    }
}
