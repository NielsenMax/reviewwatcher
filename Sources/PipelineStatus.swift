import Foundation

/// GitLab reports eleven pipeline states; only the two terminal ones change what a reviewer can do.
enum PipelineStatus: String {
    case success
    case failed
    case pending

    /// GraphQL spells states in uppercase; raw values stay lowercase because the state file already stores them so.
    init(gitlabStatus: String) {
        switch gitlabStatus.lowercased() {
        case "success": self = .success
        case "failed": self = .failed
        default: self = .pending
        }
    }

    var emoji: String {
        switch self {
        case .success: return "🟢"
        case .failed: return "🔴"
        case .pending: return "🟡"
        }
    }

    var summary: String {
        switch self {
        case .success: return "pipeline passed"
        case .failed: return "pipeline failed"
        case .pending: return "pipeline running"
        }
    }

    var imageName: String { "status-\(rawValue)" }
}
