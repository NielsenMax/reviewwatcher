import Foundation

/// The roulette's side of config.json. Both values name the organisation, so they live in the local config
/// and never in the code.
struct RouletteConfig: Equatable {
    /// GitLab group whose subgroups are the teams, such as `acme/teams`.
    var teamsGroup = ""
    /// Counts each player's open tickets for weighted odds; left empty, everyone holds none and the odds stay even.
    var loadJQL = ""
}

extension RouletteConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case teamsGroup, loadJQL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teamsGroup = try container.decodeIfPresent(String.self, forKey: .teamsGroup) ?? ""
        loadJQL = try container.decodeIfPresent(String.self, forKey: .loadJQL) ?? ""
    }
}
