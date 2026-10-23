import Foundation

/// Jira Cloud stores rich text as Atlassian Document Format: a tree of block and inline nodes.
struct AtlassianDocument: Decodable {
    let type: String
    let text: String?
    let attrs: Attributes?
    let content: [AtlassianDocument]?

    struct Attributes: Decodable {
        let text: String?
        let url: String?
    }

    var plainText: String {
        switch type {
        case "text": return text ?? ""
        case "mention", "emoji", "status": return attrs?.text ?? ""
        case "inlineCard": return attrs?.url ?? ""
        case "hardBreak": return " "
        case "paragraph", "heading": return (content ?? []).map(\.plainText).joined()
        default: return (content ?? []).map(\.plainText).filter { !$0.isEmpty }.joined(separator: " ")
        }
    }
}
