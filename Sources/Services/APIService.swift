import Foundation
import GoogleGenerativeAI

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case networkError(Error)
    case serverError(String)
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
    
    // MARK: - Create Audit (matches web's Dashboard.jsx handleCreateAudit)
    
    func createAudit(userId: String, location: String, metadata: AuditMetadata) async throws -> String {
        let payload: [String: Any] = [
            "action": "create",
            "userId": userId,
            "location": location,
            "metadata": [
                "its": metadata.its ?? "",
                "mauze": metadata.mauze ?? ""
            ]
        ]
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        struct CreateResponse: Codable {
            let auditId: String?
            let error: String?
        }
        
        let result = try JSONDecoder().decode(CreateResponse.self, from: data)
        if let auditId = result.auditId {
            return auditId
        } else {
            throw APIError.serverError(result.error ?? "No audit ID returned")
        }
    }
    
    // MARK: - Save Progress
    
    func saveAudit(auditId: String, metadata: AuditMetadata, answers: [String: Answer], progress: Int) async throws {
        let payload: [String: Any] = [
            "action": "save",
            "auditId": auditId,
            "progress": progress,
            "data": [
                "metadata": ["its": metadata.its ?? "", "mauze": metadata.mauze ?? ""],
                "answers": answers.reduce(into: [String: Any]()) { dict, pair in
                    dict[pair.key] = [
                        "status": pair.value.status?.rawValue as Any,
                        "value": pair.value.value as Any,
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
    
    // MARK: - Submit Audit
    
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
        
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        // Check for server-side error
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? String {
            throw APIError.serverError(error)
        }
    }
    
    // MARK: - PDF Generation (Google Apps Script) - matches web's useSurvey submitSurvey
    
    func generatePDF(auditId: String, userId: String, metadata: AuditMetadata, answers: [String: Answer], reportData: [SectionSnapshot]) async throws -> String {
        let gasURL = Constants.gasScriptUrl
        let payload: [String: Any] = [
            "action": "submit",
            "auditId": auditId,
            "userId": userId,
            "metadata": ["its": metadata.its ?? "", "mauze": metadata.mauze ?? ""],
            "answers": answers.reduce(into: [String: Any]()) { dict, pair in
                dict[pair.key] = ["status": pair.value.status?.rawValue as Any, "value": pair.value.value as Any]
            },
            "reportData": try JSONSerialization.jsonObject(with: JSONEncoder().encode(reportData))
        ]
        
        var request = URLRequest(url: URL(string: gasURL)!)
        request.httpMethod = "POST"
        // Match web: text/plain to avoid CORS preflight
        request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        // Handle GAS redirects
        let config = URLSessionConfiguration.default
        let redirectSession = URLSession(configuration: config)
        
        let (data, response) = try await redirectSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        // GAS can return either { url: "..." } or { reportUrl: "..." }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let url = json["url"] as? String { return url }
            if let reportUrl = json["reportUrl"] as? String { return reportUrl }
            if let pdfUrl = json["pdfUrl"] as? String { return pdfUrl }
        }
        
        throw APIError.serverError("No PDF URL in GAS response")
    }
    
    // MARK: - Photo Upload (matches web's ImageInput.jsx)
    
    struct UploadResponse: Codable {
        let url: String?
        let error: String?
    }
    
    func uploadPhoto(fileName: String, mimeType: String, base64Data: String) async throws -> String {
        let payload: [String: Any] = [
            "action": "upload",
            "fileName": fileName,
            "mimeType": mimeType,
            "fileData": base64Data
        ]
        
        guard let url = URL(string: Constants.gasScriptUrl) else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        let decoded = try JSONDecoder().decode(UploadResponse.self, from: data)
        if let photoUrl = decoded.url {
            return photoUrl
        } else {
            throw NSError(domain: "UploadError", code: 0, userInfo: [NSLocalizedDescriptionKey: decoded.error ?? "Upload failed"])
        }
    }
    
    // MARK: - Photo Delete (matches web's ImageInput.jsx handleRemove)
    
    func deletePhoto(photoUrl: String) async {
        // Extract fileId from various Drive URL formats (matching web logic exactly)
        var fileId: String? = nil
        
        // id=FILE_ID pattern
        if let match = photoUrl.range(of: "id=([^&]+)", options: .regularExpression) {
            let idStart = photoUrl.index(match.lowerBound, offsetBy: 3)
            fileId = String(photoUrl[idStart..<match.upperBound])
        }
        
        // /d/FILE_ID pattern
        if fileId == nil, let match = photoUrl.range(of: "/d/([^/]+)", options: .regularExpression) {
            let idStart = photoUrl.index(match.lowerBound, offsetBy: 3)
            fileId = String(photoUrl[idStart..<match.upperBound])
        }
        
        guard let id = fileId else { return }
        
        let payload: [String: Any] = [
            "action": "delete",
            "fileId": id
        ]
        
        guard let url = URL(string: Constants.gasScriptUrl) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        do {
            let _ = try await session.data(for: request)
        } catch {
            print("Failed to delete file from Drive: \(error)")
        }
    }
    
    // MARK: - Gemini AI
    
    func chatWithGemini(messages: [ChatMessage], reports: [AuditSummary]) async throws -> String {
        let model = GenerativeModel(name: "gemini-1.5-flash", apiKey: geminiApiKey)
        
        var fullAudits: [Audit] = []
        for r in reports {
            if let detail = try? await fetchAuditDetails(auditId: r.id) {
                fullAudits.append(detail)
            }
        }
        
        let contextData = fullAudits.map { r in
            let failures = r.answers?.filter { ($0.value.status?.isFail ?? false) }
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
        
        let chatHistory = try messages.map { m in
            try ModelContent(role: m.role == "user" ? "user" : "model", parts: [m.text])
        }
        
        let response = try await model.generateContent([try ModelContent(role: "user", parts: [systemPrompt])] + chatHistory)
        return response.text ?? "I'm sorry, I couldn't generate a response."
    }
    
    // MARK: - Admin: Fetch All Reports with Pagination (matches web's lazy loading)
    
    func fetchAllReports(page: Int) async throws -> ([AuditSummary], Bool) {
        let urlString = "\(baseURL)?action=getAllReports&page=\(page)"
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        struct AdminReport: Codable {
            let auditId: String?
            let userId: String?
            let timestamp: String?
            let pdfUrl: String?
            let progress: Int?
            let status: String?
            let data: AdminData?
            struct AdminData: Codable {
                let metadata: AuditMetadata?
            }
        }
        
        struct AllReportsResponse: Codable {
            let reports: [AdminReport]
            let hasMore: Bool
        }
        
        let decoded = try JSONDecoder().decode(AllReportsResponse.self, from: data)
        let summaries = decoded.reports.compactMap { r -> AuditSummary? in
            guard let id = r.auditId else { return nil }
            return AuditSummary(
                id: id,
                location: r.data?.metadata?.mauze ?? "Unknown Location",
                lastUpdated: r.timestamp ?? "",
                progress: r.progress ?? 0,
                status: (r.status == "submitted" || r.status == "Completed") ? "Completed" : "In Progress",
                reportUrl: r.pdfUrl
            )
        }
        return (summaries, decoded.hasMore)
    }
}
