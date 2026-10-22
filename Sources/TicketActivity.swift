import Foundation

/// The fields `acli jira workitem search` refuses to return, read one ticket at a time through `view`.
struct TicketActivity: Decodable {
    let parentKey: String?
    let comments: [Comment]

    struct Comment: Decodable {
        let id: Int
        let author: Person
        let text: String

        private enum CodingKeys: String, CodingKey {
            case id, author, body
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let rawID = try container.decode(String.self, forKey: .id)
            guard let id = Int(rawID) else {
                throw DecodingError.dataCorruptedError(forKey: .id, in: container,
                                                       debugDescription: "expected a numeric comment id, got \(rawID)")
            }
            self.id = id
            author = try container.decode(Person.self, forKey: .author)
            text = try container.decode(AtlassianDocument.self, forKey: .body).plainText
        }
    }

    private enum CodingKeys: String, CodingKey {
        case fields
    }

    private struct Fields: Decodable {
        let parent: Parent?
        let comment: CommentPage
    }

    private struct Parent: Decodable {
        let key: String
    }

    private struct CommentPage: Decodable {
        let comments: [Comment]
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self).decode(Fields.self, forKey: .fields)
        parentKey = fields.parent?.key
        comments = fields.comment.comments
    }
}
