import Foundation

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case networkError(Error)
    case serverError(String)
}

class APIService {
    static let shared = APIService()
    private let baseURL = Constants.cloudflareApiUrl
    private let session = URLSession.shared
    private let authTokenKey = "fmb_audit_token"
    
    private init() {}

    private var authToken: String? {
        UserDefaults.standard.string(forKey: authTokenKey)
    }

    private func makeRequest(
        url: URL,
        method: String = "GET",
        contentType: String? = nil,
        body: Data? = nil,
        includeAuth: Bool = true
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if includeAuth, let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        return request
    }

    private func decodeAPIError(from data: Data, fallback: String = "Request failed") -> APIError {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? String {
            return .serverError(error)
        }
        return .serverError(fallback)
    }

    func login(userId: String) async throws -> AuthSession {
        let payload = ["action": "login", "userId": userId]
        let request = makeRequest(
            url: URL(string: baseURL)!,
            method: "POST",
            contentType: "application/json",
            body: try JSONSerialization.data(withJSONObject: payload),
            includeAuth: false
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw decodeAPIError(from: data, fallback: "Login failed")
        }

        return try JSONDecoder().decode(AuthSession.self, from: data)
    }

    func loginAdmin(password: String) async throws -> AuthSession {
        let payload = ["action": "adminLogin", "password": password]
        let request = makeRequest(
            url: URL(string: baseURL)!,
            method: "POST",
            contentType: "application/json",
            body: try JSONSerialization.data(withJSONObject: payload),
            includeAuth: false
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw decodeAPIError(from: data, fallback: "Admin login failed")
        }

        return try JSONDecoder().decode(AuthSession.self, from: data)
    }
    
    // MARK: - Audits
    
    func fetchAudits(userId: String) async throws -> [AuditSummary] {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "list"),
            URLQueryItem(name: "userId", value: userId)
        ]

        let request = makeRequest(url: components.url!)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw decodeAPIError(from: data, fallback: "Failed to fetch audits")
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
        
        let request = makeRequest(url: components.url!)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw decodeAPIError(from: data, fallback: "Failed to fetch audit")
        }
        
        // First try strict decoding
        struct AuditResponse: Codable {
            let audit: AuditContainer
        }
        struct AuditContainer: Codable {
            let data: Audit
        }
        
        do {
            let result = try JSONDecoder().decode(AuditResponse.self, from: data)
            var audit = result.audit.data
            if audit.id == nil { audit.id = auditId }
            return audit
        } catch {
            print("⚠️ Strict decode failed: \(error). Falling back to manual parsing.")
        }
        
        // Fallback: manual JSON parsing for resilience
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auditWrapper = json["audit"] as? [String: Any],
              let auditData = auditWrapper["data"] as? [String: Any] else {
            throw APIError.invalidResponse
        }
        
        // Extract critical fields manually
        var audit = Audit(
            id: auditData["id"] as? String ?? auditId,
            userId: auditData["userId"] as? String,
            metadata: nil,
            answers: nil,
            progress: auditData["progress"] as? Int,
            status: auditData["status"] as? String,
            createdAt: auditData["timestamp"] as? String,
            updatedAt: auditData["updatedAt"] as? String,
            pdfUrl: auditData["pdfUrl"] as? String
        )
        
        // Try to decode metadata
        if let metaDict = auditData["metadata"] as? [String: Any] {
            let its: String?
            if let s = metaDict["its"] as? String { its = s }
            else if let i = metaDict["its"] as? Int { its = String(i) }
            else { its = nil }
            audit.metadata = AuditMetadata(its: its, mauze: metaDict["mauze"] as? String)
        }
        
        // Try to decode answers one-by-one (skip any that fail)
        if let answersDict = auditData["answers"] as? [String: Any] {
            var parsed: [String: Answer] = [:]
            for (key, val) in answersDict {
                guard let ansDict = val as? [String: Any] else { continue }
                
                var status: Answer.AnswerStatus? = nil
                if let s = ansDict["status"] as? String {
                    status = .string(s)
                } else if let b = ansDict["status"] as? Bool {
                    status = .bool(b)
                }
                
                let value = ansDict["value"] as? String
                let photos = ansDict["photos"] as? [String]
                
                parsed[key] = Answer(status: status, value: value, photos: photos)
            }
            audit.answers = parsed
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
        
        let request = makeRequest(
            url: URL(string: baseURL)!,
            method: "POST",
            contentType: "application/json",
            body: try JSONSerialization.data(withJSONObject: payload)
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw decodeAPIError(from: data, fallback: "Failed to create audit")
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
        
        let request = makeRequest(
            url: URL(string: baseURL)!,
            method: "POST",
            contentType: "application/json",
            body: try JSONSerialization.data(withJSONObject: payload)
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw decodeAPIError(from: data, fallback: "Failed to save audit")
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
        
        let request = makeRequest(
            url: URL(string: baseURL)!,
            method: "POST",
            contentType: "application/json",
            body: try JSONSerialization.data(withJSONObject: payload)
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw decodeAPIError(from: data, fallback: "Failed to submit audit")
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
                dict[pair.key] = ["status": pair.value.status?.rawValue as Any, "value": pair.value.value as Any, "photos": pair.value.photos ?? []]
            },
            "reportData": try JSONSerialization.jsonObject(with: JSONEncoder().encode(reportData))
        ]
        
        let request = makeRequest(
            url: URL(string: gasURL)!,
            method: "POST",
            contentType: "text/plain;charset=utf-8",
            body: try JSONSerialization.data(withJSONObject: payload),
            includeAuth: false
        )
        
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
        
        let request = makeRequest(
            url: url,
            method: "POST",
            contentType: "text/plain;charset=utf-8",
            body: try JSONSerialization.data(withJSONObject: payload),
            includeAuth: false
        )
        
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
        
        let request = makeRequest(
            url: url,
            method: "POST",
            contentType: "text/plain;charset=utf-8",
            body: try? JSONSerialization.data(withJSONObject: payload),
            includeAuth: false
        )
        
        do {
            let _ = try await session.data(for: request)
        } catch {
            print("Failed to delete file from Drive: \(error)")
        }
    }
    
    // MARK: - Gemini AI (via Cloudflare proxy — API key stays server-side)
    
    func chatWithGemini(messages: [ChatMessage], reports: [AuditSummary]) async throws -> String {
        guard let url = URL(string: baseURL) else { throw APIError.invalidURL }
        
        // Build conversation messages (skip initial greeting, same as web)
        var conversationMessages: [[String: String]] = []
        for (index, msg) in messages.enumerated() {
            if index == 0 && msg.role == "model" { continue } // skip greeting
            conversationMessages.append(["role": msg.role, "text": msg.text])
        }
        
        // Build request body
        let requestBody: [String: Any] = [
            "action": "chat",
            "messages": conversationMessages,
            "reportIds": reports.map { $0.id }
        ]
        
        let request = makeRequest(
            url: url,
            method: "POST",
            contentType: "application/json",
            body: try JSONSerialization.data(withJSONObject: requestBody)
        )
        
        print("🤖 Calling chat proxy with \(conversationMessages.count) messages, \(reports.count) reports")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("🤖 Chat proxy error (\(httpResponse.statusCode)): \(errorText)")
            throw APIError.serverError("Chat failed: \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        
        if let error = json["error"] as? String {
            throw APIError.serverError(error)
        }
        
        return json["response"] as? String ?? "I'm sorry, I couldn't generate a response."
    }

    
    // MARK: - Admin: Fetch All Reports with Pagination (matches web's lazy loading)
    
    func fetchAllReports(page: Int) async throws -> ([AuditSummary], Bool) {
        let urlString = "\(baseURL)?action=getAllReports&page=\(page)"
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }

        let request = makeRequest(url: url)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw decodeAPIError(from: data, fallback: "Failed to fetch admin reports")
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
