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

    @Published private(set) var saveFailure: String?

    private let onChange: (Config) -> Void

    init(config: Config, onChange: @escaping (Config) -> Void) {
        self.config = config
        self.collapsedPatternsText = config.collapsedFilePatterns.joined(separator: "\n")
        self.onChange = onChange
    }

    func follow(_ epic: String) {
        guard !config.jira.epics.contains(epic) else { return }
        config.jira.epics.append(epic)
    }

    func unfollow(_ epic: String) {
        config.jira.epics.removeAll { $0 == epic }
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
