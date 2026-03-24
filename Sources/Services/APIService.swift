import Foundation
import GoogleGenerativeAI

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case networkError(Error)
}

class APIService {
    static let shared = APIService()
    private let baseURL = Constants.cloudflareApiUrl
    private let geminiApiKey = Constants.geminiApiKey
    private let session = URLSession.shared
    
    private init() {}
    
    // MARK: - Audits
    
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
        
        struct AuditSummaryListResponse: Codable {
            let audits: [AuditSummary]
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
                "answers": answers.reduce(into: [String: Any]()) { dict, pair in
                    dict[pair.key] = [
                        "status": pair.value.status?.rawValue,
                        "value": pair.value.value,
                        "photos": pair.value.photos ?? []
                    ]
                }
            ]
        ]
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.invalidResponse
        }
    }
    
    func submitAudit(auditId: String, userId: String, reportData: [SectionSnapshot], pdfUrl: String) async throws {
        let payload: [String: Any] = [
            "action": "submit",
            "auditId": auditId,
            "userId": userId,
            "reportData": try JSONSerialization.jsonObject(with: JSONEncoder().encode(reportData)),
            "pdfUrl": pdfUrl
        ]
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.invalidResponse
        }
    }
    
    // MARK: - PDF Generation (Google Apps Script)
    
    func generatePDF(auditId: String, userId: String, metadata: AuditMetadata, answers: [String: Answer], reportData: [SectionSnapshot]) async throws -> String {
        let gasURL = Constants.gasScriptUrl
        let payload: [String: Any] = [
            "auditId": auditId,
            "userId": userId,
            "metadata": ["its": metadata.its, "mauze": metadata.mauze],
            "answers": answers.reduce(into: [String: Any]()) { dict, pair in
                dict[pair.key] = ["status": pair.value.status?.rawValue, "value": pair.value.value]
            },
            "reportData": try JSONSerialization.jsonObject(with: JSONEncoder().encode(reportData))
        ]
        
        var request = URLRequest(url: URL(string: gasURL)!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        struct GASResponse: Codable {
            let pdfUrl: String
        }
        let result = try JSONDecoder().decode(GASResponse.self, from: data)
        return result.pdfUrl
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
                .map { ($0.value.value ?? "").isEmpty ? $0.key : ($0.value.value ?? "") }
                .prefix(10) ?? []
            return """
            ID: \(r.id ?? "N/A")
            Kitchen: \(r.metadata?.mauze ?? "Unknown")
            Date: \(r.createdAt ?? "N/A")
            Status: \(r.status ?? "N/A")
            PDF Link: \(r.pdfUrl ?? "N/A")
            Key Failures/Issues: \(failures.joined(separator: ", "))
            """
        }.joined(separator: "\n---\n")
        
        let systemPrompt = "You are the FMB Audit Assistant. Use the following audit context to answer questions: \n\n\(contextData)\n\nPlease keep responses professional and concise."
        
        let chatHistory = messages.map { m in
            ModelContent(role: m.role == "user" ? "user" : "model", parts: [TextPart(m.text)])
        }
        
        let response = try await model.generateContent([ModelContent(role: "user", parts: [TextPart(systemPrompt)])] + chatHistory)
        return response.text ?? "I'm sorry, I couldn't generate a response."
    }
}
