import Combine
import Foundation

/// The Epic tab's search box: what is typed, and what Jira finds for it once typing pauses.
final class EpicSearch: ObservableObject {
    enum State {
        case idle
        case searching
        case found([Ticket])
        case failed(String)
    }

    @Published var query = ""
    @Published private(set) var state = State.idle

    private let client: JiraClient
    private var typing: AnyCancellable?
    /// The text the newest search ran for; an answer to any older one arrives stale and is dropped.
    private var latestText = ""

    private static let resultLimit = 8

    init(client: JiraClient) {
        self.client = client
        typing = $query
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] in self?.search(for: $0) }
    }

    func clear() {
        query = ""
        latestText = ""
        state = .idle
    }

    private func search(for typed: String) {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        latestText = text
        guard let jql = Self.jql(for: text) else {
            state = .idle
            return
        }
        state = .searching
        DispatchQueue.global(qos: .userInitiated).async { [client] in
            let outcome = Result { try client.search(jql, limit: Self.resultLimit) }
            DispatchQueue.main.async {
                guard self.latestText == text else { return }
                switch outcome {
                case .success(let tickets): self.state = .found(tickets)
                case .failure(let error): self.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// A ticket key finds that ticket whatever its type; words find open epics whose summary has all of them.
    static func jql(for text: String) -> String? {
        if text.range(of: #"^[A-Za-z][A-Za-z0-9_]*-[0-9]+$"#, options: .regularExpression) != nil {
            return "key = \(text.uppercased())"
        }
        // Jira's text index does not lowercase wildcard terms, so AIS* misses what ais* finds.
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        let clauses = ["issuetype = Epic", "statusCategory != Done"] + words.map { "summary ~ \"\($0)*\"" }
        return clauses.joined(separator: " AND ") + " ORDER BY updated DESC"
    }
}
