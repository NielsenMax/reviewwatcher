import Foundation

/// The editable side of config.json. Every change is written straight back and handed on, so
/// nothing waits for a restart.
final class Settings: ObservableObject {
    @Published var config: Config {
        didSet { persist() }
    }

    /// The diff window patterns as typed, one per line. Kept apart from `config` so a blank line
    /// being typed is not trimmed away under the cursor.
    @Published var collapsedPatternsText: String {
        didSet {
            config.collapsedFilePatterns = collapsedPatternsText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }

    /// The epic key as typed. It reaches `config` only through `watchEpicDraft`, so a half-typed key never polls.
    @Published var epicDraft: String

    @Published private(set) var saveFailure: String?

    private let onChange: (Config) -> Void

    init(config: Config, onChange: @escaping (Config) -> Void) {
        self.config = config
        self.collapsedPatternsText = config.collapsedFilePatterns.joined(separator: "\n")
        self.epicDraft = config.jira.epic
        self.onChange = onChange
    }

    var isEpicDraftWatchable: Bool {
        normalizedEpicDraft != config.jira.epic
            && normalizedEpicDraft.range(of: #"^[A-Z][A-Z0-9_]*-[0-9]+$"#, options: .regularExpression) != nil
    }

    func watchEpicDraft() {
        guard isEpicDraftWatchable else { return }
        epicDraft = normalizedEpicDraft
        config.jira.epic = epicDraft
    }

    private var normalizedEpicDraft: String {
        epicDraft.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func persist() {
        do {
            try config.save()
            saveFailure = nil
        } catch {
            let failure = "could not save \(Paths.configFile.path): \(error.localizedDescription)"
            Log.write(failure)
            saveFailure = failure
        }
        onChange(config)
    }
}
