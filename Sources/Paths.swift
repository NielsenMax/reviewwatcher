import Foundation

enum Paths {
    private static let configDirectory = home(".config/reviewwatcher")
    static let configFile = configDirectory.appendingPathComponent("config.json")
    static let tokenFile = configDirectory.appendingPathComponent("token")
    static let stateFile = home(".local/state/reviewwatcher/seen.json")
    static let epicStateFile = home(".local/state/reviewwatcher/epic.json")
    static let rouletteStateFile = home(".local/state/reviewwatcher/ruleta.json")

    private static func home(_ relative: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relative)
    }
}
