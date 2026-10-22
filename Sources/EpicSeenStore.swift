import Foundation

/// What each ticket under each followed epic looked like at its last poll, so a restart is silent and only
/// changes speak. An epic without an entry has not been polled yet: its first poll only takes note.
struct EpicSeenStore: Codable {
    var epics: [String: EpicState]

    struct EpicState: Codable {
        /// When this epic's last successful poll started.
        let polledAt: Date
        let tickets: [String: TicketState]
    }

    struct TicketState: Codable {
        let status: String
        let assigneeAccountID: String?
        let parentKey: String?
        /// Jira numbers comments site-wide in creation order, so any higher id is a newer comment.
        let latestCommentID: Int?
    }

    static func load() -> EpicSeenStore {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: Paths.epicStateFile),
              let store = try? decoder.decode(EpicSeenStore.self, from: data) else {
            return EpicSeenStore(epics: [:])
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
