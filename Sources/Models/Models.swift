import SwiftUI

struct Audit: Codable, Identifiable {
    var id: String? = nil
    var userId: String? = nil
    var metadata: AuditMetadata? = nil
    var answers: [String: Answer]? = nil
    var progress: Int? = nil
    var status: String? = nil
    var createdAt: String? = nil
    var updatedAt: String? = nil
    var pdfUrl: String? = nil
    var version: Int? = nil
    
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
        case version
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
    
    enum CodingKeys: String, CodingKey {
        case its, mauze
    }
    
    init(its: String? = nil, mauze: String? = nil) {
        self.its = its
        self.mauze = mauze
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mauze = try container.decodeIfPresent(String.self, forKey: .mauze)
        
        if let s = try? container.decodeIfPresent(String.self, forKey: .its) {
            its = s
        } else if let i = try? container.decodeIfPresent(Int.self, forKey: .its) {
            its = String(i)
        } else {
            its = nil
        }
    }
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

extension Answer.AnswerStatus {
    var isPass: Bool {
        switch self {
        case .bool(let b): return b
        case .string(let s): return s == "Pass"
        }
    }
    var isFail: Bool {
        switch self {
        case .bool(let b): return !b
        case .string(let s): return s == "Fail"
        }
    }
    var isNA: Bool {
        if case .string(let s) = self {
            let lower = s.lowercased().trimmingCharacters(in: .whitespaces)
            return lower == "na" || lower == "n/a"
        }
        return false
    }
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: String // "user" or "model"
    let text: String
    
    init(id: UUID = UUID(), role: String, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

struct AuthSession: Codable {
    let token: String
    let role: String
    let userId: String?
}


