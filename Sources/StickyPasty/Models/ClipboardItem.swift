import Foundation

enum ClipboardContent: Codable {
    case text(String)
    case image(Data)   // PNG data

    private enum CodingKeys: String, CodingKey {
        case type, text, imageData
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let s):
            try c.encode("text", forKey: .type)
            try c.encode(s, forKey: .text)
        case .image(let d):
            try c.encode("image", forKey: .type)
            try c.encode(d, forKey: .imageData)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try c.decode(String.self, forKey: .text))
        case "image":
            self = .image(try c.decode(Data.self, forKey: .imageData))
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Unknown content type: \(type)")
            )
        }
    }
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let content: ClipboardContent
    let timestamp: Date
    var spaceID: UUID?   // nil = clipboard history; non-nil = saved to a Space

    var textPreview: String? {
        if case .text(let s) = content { return String(s.prefix(300)) }
        return nil
    }

    var isImage: Bool {
        if case .image = content { return true }
        return false
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}
