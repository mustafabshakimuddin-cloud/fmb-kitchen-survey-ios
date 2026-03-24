import Foundation

struct Audit: Codable, Identifiable {
    var id: String?
    var userId: String?
    var metadata: AuditMetadata?
    var answers: [String: Answer]?
    var progress: Int?
    var status: String?
    var createdAt: String?
    var updatedAt: String?
    var pdfUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case metadata
        case answers
        case progress
        case status
        case createdAt = "timestamp"
        case updatedAt
        case pdfUrl
    }
}

struct AuditSummary: Codable, Identifiable {
    let id: String
    let location: String
    let lastUpdated: String
    let progress: Int
    let status: String
    let reportUrl: String?
}

struct AuditMetadata: Codable {
    var its: String?
    var mauze: String?
}

struct Answer: Codable {
    var status: AnswerStatus?
    var value: String?
    var photos: [String]?
    
    enum AnswerStatus: Codable, RawRepresentable {
        case bool(Bool)
        case string(String)
        
        init?(rawValue: String) {
            if let boolValue = Bool(rawValue) {
                self = .bool(boolValue)
            } else {
                self = .string(rawValue)
            }
        }
        
        var rawValue: String {
            switch self {
            case .bool(let b): return String(b)
            case .string(let s): return s
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let b = try? container.decode(Bool.self) {
                self = .bool(b)
            } else if let s = try? container.decode(String.self) {
                self = .string(s)
            } else {
                throw DecodingError.typeMismatch(AnswerStatus.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected Bool or String"))
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .bool(let b): try container.encode(b)
            case .string(let s): try container.encode(s)
            }
        }
    }
}

struct SurveySection: Codable, Identifiable {
    let id: String
    let title: String
    let items: [SurveyItem]
}

struct SurveyItem: Codable, Identifiable {
    var id: String { q }
    let q: String
    let type: ItemType
    
    enum ItemType: String, Codable {
        case text
        case status
    }
}

// For submission report snapshot
struct SectionSnapshot: Codable {
    let title: String
    let items: [ItemSnapshot]
}

struct ItemSnapshot: Codable {
    let question: String
    let type: String
    let answer: Answer
}
