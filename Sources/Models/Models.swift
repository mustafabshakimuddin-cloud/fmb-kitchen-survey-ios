import SwiftUI

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
        if case .string(let s) = self { return s == "N/A" }
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

extension Color {
    static let slate50 = Color(hex: "F8FAFC")
    static let slate100 = Color(hex: "F1F5F9")
    static let slate200 = Color(hex: "E2E8F0")
    static let slate300 = Color(hex: "CBD5E1")
    static let slate400 = Color(hex: "94A3B8")
    static let slate500 = Color(hex: "64748B")
    static let slate600 = Color(hex: "475569")
    static let slate700 = Color(hex: "334155")
    static let slate800 = Color(hex: "1E293B")
    static let slate900 = Color(hex: "0F172A")
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
