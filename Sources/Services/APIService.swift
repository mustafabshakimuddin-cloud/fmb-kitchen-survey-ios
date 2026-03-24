import Foundation
import GoogleGenerativeAI

class APIService {
    static let shared = APIService()
    
    let baseURL = Constants.cloudflareApiUrl
    let scriptURL = Constants.gasScriptUrl
    let geminiApiKey = Constants.geminiApiKey
    
    private let session = URLSession.shared
    
    // MARK: - Cloudflare API (NeonDB)
    
    func fetchAudits(userId: String) async throws -> [AuditSummary] {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "list"),
            URLQueryItem(name: "userId", value: userId)
        ]
        
        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        let result = try JSONDecoder().decode(AuditSummaryListResponse.self, from: data)
        return result.audits
    }
    
    func fetchAuditDetails(auditId: String) async throws -> Audit {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "get"),
            URLQueryItem(name: "auditId", value: auditId)
        ]
        
        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        // The API returns { audit: { data: { metadata, answers, ... } } }
        struct AuditResponse: Codable {
            let audit: AuditContainer
        }
        struct AuditContainer: Codable {
            let data: Audit
        }
        
        let result = try JSONDecoder().decode(AuditResponse.self, from: data)
        var audit = result.audit.data
        if audit.id == nil {
            audit.id = auditId
        }
        return audit
    }
    
    func saveAudit(auditId: String, metadata: AuditMetadata, answers: [String: Answer], progress: Int) async throws {
        let payload: [String: Any] = [
            "action": "save",
            "auditId": auditId,
            "progress": progress,
            "data": [
                "metadata": ["its": metadata.its, "mauze": metadata.mauze],
                "answers": try? JSONSerialization.jsonObject(with: JSONEncoder().encode(answers))
            ]
        ]
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.saveFailed
        }
    }
    
    func submitAudit(auditId: String, userId: String, reportData: [SectionSnapshot], pdfUrl: String?) async throws {
        let payload: [String: Any] = [
            "action": "submit",
            "auditId": auditId,
            "userId": userId,
            "reportData": try? JSONSerialization.jsonObject(with: JSONEncoder().encode(reportData)),
            "pdfUrl": pdfUrl as Any
        ]
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.submitFailed
        }
    }
    
    // MARK: - Google Apps Script (PDF Generation)
    
    func generatePDF(auditId: String, userId: String, metadata: AuditMetadata, answers: [String: Answer], reportData: [SectionSnapshot]) async throws -> String? {
        let payload: [String: Any] = [
            "action": "submit",
            "auditId": auditId,
            "userId": userId,
            "metadata": ["its": metadata.its, "mauze": metadata.mauze],
            "answers": try? JSONSerialization.jsonObject(with: JSONEncoder().encode(answers)),
            "reportData": try? JSONSerialization.jsonObject(with: JSONEncoder().encode(reportData))
        ]
        
        var request = URLRequest(url: URL(string: scriptURL)!)
        request.httpMethod = "POST"
        request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.pdfGenerationFailed
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let url = json["url"] as? String ?? json["reportUrl"] as? String {
            return url
        }
        
        return nil
    }
    
    // MARK: - Gemini AI
    
    func chatWithGemini(messages: [ChatMessage], reports: [AuditSummary]) async throws -> String {
        let model = GenerativeModel(name: "gemini-1.5-flash", apiKey: geminiApiKey)
        
        // Fetch full details for context
        var fullAudits: [Audit] = []
        for r in reports {
            if let detail = try? await fetchAuditDetails(auditId: r.id) {
                fullAudits.append(detail)
            }
        }
        
        let contextData = fullAudits.map { r in
            let failures = r.answers?.filter { $0.value.status?.isFailure ?? false }
                .map { $0.value.value.isEmpty ? $0.key : $0.value.value }
                .prefix(10) ?? []
            return """
            ID: \(r.id)
            Kitchen: \(r.metadata?.mauze ?? "Unknown")
            Date: \(r.createdAt ?? "N/A")
            Status: \(r.status ?? "N/A")
            PDF Link: \(r.pdfUrl ?? "N/A")
            Key Failures/Issues: \(failures.joined(separator: ", "))
            """
        }.joined(separator: "\n---\n")
        
        let systemPrompt = """
        You are an FMB Analyst.
        CONTEXT: The user has selected the following \(reports.count) reports for analysis:
        \(contextData)
        
        INSTRUCTIONS:
        Answer the question based ONLY on the selected reports above.
        If the answer is not in these reports, say "I don't see that in the selected reports."
        ALWAYS provide the "PDF Link" formatted as a clickable Markdown link: [Click Here to View PDF](URL).
        """
        
        var history: [ModelContent] = [
            try ModelContent(role: "user", parts: [systemPrompt]),
            try ModelContent(role: "model", parts: ["I am analyzing the \(reports.count) selected reports. What would you like to know?"])
        ]
        
        for msg in messages.dropLast() {
            if let content = try? ModelContent(role: msg.role, parts: [msg.text]) {
                history.append(content)
            }
        }
        
        let chat = model.startChat(history: history)
        let response = try await chat.sendMessage(messages.last!.text)
        return response.text ?? "No response"
    }
}

// Support Structs
struct AuditSummaryListResponse: Codable {
    let audits: [AuditSummary]
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String // "user" or "model"
    let text: String
}

enum APIError: Error {
    case invalidResponse
    case saveFailed
    case submitFailed
    case pdfGenerationFailed
}

extension Answer.AnswerStatus {
    var isFailure: Bool {
        switch self {
        case .bool(let b): return !b
        case .string(let s): return s.lowercased() == "fail"
        }
    }
}
