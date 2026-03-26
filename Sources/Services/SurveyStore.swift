import Foundation
import Combine

class SurveyStore: ObservableObject {
    @Published var userId: String = UserDefaults.standard.string(forKey: "fmb_audit_user") ?? "" {
        didSet { UserDefaults.standard.set(userId, forKey: "fmb_audit_user") }
    }
    @Published var authToken: String = UserDefaults.standard.string(forKey: "fmb_audit_token") ?? "" {
        didSet { UserDefaults.standard.set(authToken, forKey: "fmb_audit_token") }
    }
    
    @Published var audits: [AuditSummary] = []
    @Published var currentAudit: Audit?
    @Published var isLoading: Bool = false
    @Published var error: Error?
    
    // Pagination for User Audits
    @Published var auditPage: Int = 1
    @Published var hasMoreAudits: Bool = false
    @Published var isLoadingMoreAudits: Bool = false
    
    // Auto-save state
    @Published var isSaving: Bool = false
    @Published var activeUploads: Int = 0
    
    // Validation
    @Published var validationError: String? = nil
    @Published var isSubmitting: Bool = false
    
    // Admin state
    @Published var isAdmin: Bool = UserDefaults.standard.bool(forKey: "fmb_audit_isAdmin") {
        didSet { UserDefaults.standard.set(isAdmin, forKey: "fmb_audit_isAdmin") }
    }
    @Published var adminReports: [AuditSummary] = []
    @Published var adminPage: Int = 1
    @Published var adminHasMore: Bool = false
    @Published var adminIsLoadingMore: Bool = false
    
    // Admin detail
    @Published var selectedAdminReport: Audit? = nil
    @Published var isLoadingDetails: Bool = false
    
    // Checklist Data
    let checklist: [SurveySection] = ChecklistData.allSections
    
    // Auto-save debounce
    private var autoSaveCancellable: AnyCancellable?
    private var lastSavedAnswers: [String: Answer]? = nil
    
    init() {
        if authToken.isEmpty {
            userId = ""
            isAdmin = false
        }
        
        // Load cached audits for "Instant-On" startup
        loadCachedAudits()
        
        setupAutoSave()
    }
    
    // MARK: - Local Caching (Instant-On Startup)
    
    private let auditsCacheKey = "fmb_cached_audits"
    
    private func saveAuditsToCache(_ audits: [AuditSummary]) {
        if let data = try? JSONEncoder().encode(audits) {
            UserDefaults.standard.set(data, forKey: auditsCacheKey)
        }
    }
    
    private func loadCachedAudits() {
        if let data = UserDefaults.standard.data(forKey: auditsCacheKey),
           let cached = try? JSONDecoder().decode([AuditSummary].self, from: data) {
            self.audits = cached
        }
    }
    
    // MARK: - Auto-Save (matches web's 2-second debounce)
    
    private func setupAutoSave() {
        autoSaveCancellable = $currentAudit
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] audit in
                guard let self = self,
                      let audit = audit,
                      let auditId = audit.id,
                      let metadata = audit.metadata,
                      !self.isLoading else { return }
                
                // Only save if answers actually changed
                let currentAnswers = audit.answers ?? [:]
                if currentAnswers.isEmpty { return }
                
                Task {
                    await self.saveProgress(auditId: auditId, metadata: metadata, answers: currentAnswers)
                }
            }
    }
    
    private func saveProgress(auditId: String, metadata: AuditMetadata, answers: [String: Answer]) async {
        await MainActor.run { self.isSaving = true }
        let progress = calculateProgress()
        
        // Build V14: Increment version for optimistic concurrency
        let nextVersion = (currentAudit?.version ?? 0) + 1
        
        do {
            try await APIService.shared.saveAudit(
                auditId: auditId,
                metadata: metadata,
                answers: answers,
                progress: progress,
                version: nextVersion
            )
            // Update local version on success
            await MainActor.run { self.currentAudit?.version = nextVersion }
        } catch {
            print("Auto-save failed: \(error)")
        }
        await MainActor.run { self.isSaving = false }
    }
    
    // MARK: - Progress Calculation (matches web app exactly)
    
    func calculateProgress() -> Int {
        guard let answers = currentAudit?.answers else { return 0 }
        var total = 0
        var completed = 0
        
        for section in ChecklistData.allSections {
            for (idx, item) in section.items.enumerated() {
                total += 1
                let key = "\(section.id)-\(idx)"
                let ans = answers[key]
                
                if item.type == .text {
                    if let value = ans?.value, value.trimmingCharacters(in: .whitespaces).count > 0 {
                        completed += 1
                    }
                } else {
                    if ans?.status != nil {
                        completed += 1
                    }
                }
            }
        }
        
        return total == 0 ? 0 : Int((Double(completed) / Double(total)) * 100)
    }
    
    // MARK: - Validation (matches web app: finds first missing item)
    
    func validateSurvey() -> Bool {
        guard let answers = currentAudit?.answers else { return false }
        
        for section in ChecklistData.allSections {
            for (idx, item) in section.items.enumerated() {
                let key = "\(section.id)-\(idx)"
                let ans = answers[key]
                
                if item.type == .text {
                    if ans?.value == nil || (ans?.value ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                        return false
                    }
                } else {
                    if ans?.status == nil {
                        return false
                    }
                }
            }
        }
        return true
    }
    
    func findFirstMissingItem() -> (section: SurveySection, question: SurveyItem)? {
        guard let answers = currentAudit?.answers else {
            if let s = ChecklistData.allSections.first, let i = s.items.first {
                return (s, i)
            }
            return nil
        }
        
        for section in ChecklistData.allSections {
            for (idx, item) in section.items.enumerated() {
                let key = "\(section.id)-\(idx)"
                let ans = answers[key]
                
                let isFilled: Bool
                if item.type == .text {
                    isFilled = (ans?.value != nil && !(ans?.value ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    isFilled = (ans?.status != nil)
                }
                
                if !isFilled {
                    return (section, item)
                }
            }
        }
        return nil
    }
    
    // MARK: - Upload tracking (matches web's activeUploads counter)
    
    func registerUploadStart() {
        activeUploads += 1
    }
    
    func registerUploadEnd() {
        activeUploads = max(0, activeUploads - 1)
    }
    
    func dismissValidationError() {
        validationError = nil
    }
    
    // MARK: - Audits
    
    func refreshAudits() async {
        guard !userId.isEmpty else { return }
        await MainActor.run { 
            isLoading = true
            auditPage = 1
        }
        do {
            let (fetched, more) = try await APIService.shared.fetchAudits(userId: userId, page: 1)
            await MainActor.run { 
                self.audits = fetched
                self.hasMoreAudits = more
                self.saveAuditsToCache(fetched)
            }
        } catch {
            await MainActor.run { self.error = error }
        }
        await MainActor.run { isLoading = false }
    }
    
    func fetchMoreAudits() async {
        guard !userId.isEmpty && !isLoadingMoreAudits && hasMoreAudits else { return }
        await MainActor.run { isLoadingMoreAudits = true }
        
        let nextPage = auditPage + 1
        do {
            let (fetched, more) = try await APIService.shared.fetchAudits(userId: userId, page: nextPage)
            await MainActor.run {
                self.audits.append(contentsOf: fetched)
                self.auditPage = nextPage
                self.hasMoreAudits = more
            }
        } catch {
            print("Failed to fetch more audits: \(error)")
        }
        
        await MainActor.run { isLoadingMoreAudits = false }
    }
    
    func createAudit(location: String) async -> String? {
        await MainActor.run { isLoading = true }
        do {
            let auditId = try await APIService.shared.createAudit(
                userId: userId,
                location: location,
                metadata: AuditMetadata(its: userId, mauze: location)
            )
            await MainActor.run { isLoading = false }
            return auditId
        } catch {
            print("Create audit error: \(error)")
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
            return nil
        }
    }
    
    func updateAnswer(sectionId: String, itemIndex: Int, answer: Answer) {
        let key = "\(sectionId)-\(itemIndex)"
        if currentAudit?.answers == nil {
            currentAudit?.answers = [:]
        }
        currentAudit?.answers?[key] = answer
    }
    
    func loadAudit(id: String) async {
        await MainActor.run { isLoading = true }
        do {
            let detail = try await APIService.shared.fetchAuditDetails(auditId: id)
            await MainActor.run { self.currentAudit = detail }
        } catch {
            await MainActor.run { self.error = error }
        }
        await MainActor.run { isLoading = false }
    }
    
    func clearCurrentAudit() {
        currentAudit = nil
    }
    
    // MARK: - Submit (matches web: GAS PDF → Cloudflare save)
    
    func submitAudit() async {
        guard let audit = currentAudit,
              let auditId = audit.id,
              let metadata = audit.metadata else { return }
        
        let answers = audit.answers ?? [:]
        
        // Validation check
        let total = ChecklistData.allSections.flatMap { $0.items }.count
        var completed = 0
        for section in ChecklistData.allSections {
            for (idx, item) in section.items.enumerated() {
                let key = "\(section.id)-\(idx)"
                let ans = answers[key]
                if item.type == .text {
                    if let v = ans?.value, !v.trimmingCharacters(in: .whitespaces).isEmpty { completed += 1 }
                } else {
                    if ans?.status != nil { completed += 1 }
                }
            }
        }
        
        if completed < total {
            let missing = findFirstMissingItem()
            let missingText = missing != nil
                ? "\n\nFirst missing item:\nSection: \(missing!.section.title)\nQuestion: \(missing!.question.q)"
                : ""
            
            let finalCompleted = completed
            let finalTotal = total
            await MainActor.run {
                validationError = "Please complete all questions before submitting.\nAnswered: \(finalCompleted) / \(finalTotal)\(missingText)"
            }
            return
        }
        
        if activeUploads > 0 {
            await MainActor.run {
                validationError = "Please wait for \(activeUploads) image(s) to finish uploading before submitting."
            }
            return
        }
        
        await MainActor.run { isSubmitting = true }
        
        do {
            // Build report data snapshots (matches web's reportData structure)
            let snapshots = ChecklistData.allSections.map { section in
                SectionSnapshot(title: section.title, items: section.items.enumerated().map { (idx, item) in
                    ItemSnapshot(
                        question: item.q,
                        type: item.type.rawValue,
                        answer: answers["\(section.id)-\(idx)"] ?? Answer(status: nil, value: "", photos: [])
                    )
                })
            }
            
            // 1. Generate PDF via GAS
            var pdfUrl: String = ""
            do {
                pdfUrl = try await APIService.shared.generatePDF(
                    auditId: auditId,
                    userId: userId,
                    metadata: metadata,
                    answers: answers,
                    reportData: snapshots
                )
            } catch {
                print("GAS PDF generation failed: \(error)")
                // Continue even if PDF fails, matching web behavior
            }
            
            // 2. Submit to Cloudflare/NeonDB
            try await APIService.shared.submitAudit(
                auditId: auditId,
                userId: userId,
                reportData: snapshots,
                pdfUrl: pdfUrl
            )
            
            await MainActor.run {
                isSubmitting = false
                clearCurrentAudit()
            }
        } catch {
            print("Submit error: \(error)")
            await MainActor.run { isSubmitting = false }
        }
    }
    
    func loginUser(userId: String) async -> Bool {
        await MainActor.run { isLoading = true }
        do {
            let session = try await APIService.shared.login(userId: userId)
            await MainActor.run {
                self.authToken = session.token
                self.userId = session.userId ?? userId
                self.isAdmin = false
                self.error = nil
                self.isLoading = false
            }
            return true
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
            return false
        }
    }

    // MARK: - Admin Functions
    
    func loginAdmin(password: String) async -> Bool {
        await MainActor.run { isLoading = true }
        do {
            let session = try await APIService.shared.loginAdmin(password: password)
            await MainActor.run {
                self.authToken = session.token
                self.userId = session.userId ?? ""
                self.isAdmin = true
                self.error = nil
                self.isLoading = false
            }
            return true
        } catch {
            await MainActor.run {
                self.error = error
                self.isAdmin = false
                self.isLoading = false
            }
            return false
        }
    }
    
    func fetchAdminReports() async {
        await MainActor.run {
            isLoading = true
            adminPage = 1
        }
        do {
            let (reports, hasMore) = try await APIService.shared.fetchAllReports(page: 1)
            await MainActor.run {
                self.adminReports = reports
                self.adminHasMore = hasMore
                self.isLoading = false
            }
        } catch {
            print("Admin fetch error: \(error)")
            await MainActor.run { self.isLoading = false }
        }
    }
    
    func fetchMoreAdminReports() async {
        guard adminHasMore, !adminIsLoadingMore else { return }
        let nextPage = adminPage + 1
        await MainActor.run { adminIsLoadingMore = true }
        do {
            let (reports, hasMore) = try await APIService.shared.fetchAllReports(page: nextPage)
            await MainActor.run {
                self.adminReports.append(contentsOf: reports)
                self.adminPage = nextPage
                self.adminHasMore = hasMore
                self.adminIsLoadingMore = false
            }
        } catch {
            print("Admin fetch more error: \(error)")
            await MainActor.run { self.adminIsLoadingMore = false }
        }
    }
    
    func fetchAdminReportDetails(auditId: String, attempt: Int = 0) async {
        guard !isLoadingDetails else { return }
        await MainActor.run {
            isLoadingDetails = true
            selectedAdminReport = Audit(
                id: auditId,
                userId: nil,
                metadata: nil,
                answers: nil,
                progress: nil,
                status: nil,
                createdAt: nil,
                updatedAt: nil,
                pdfUrl: nil
            )
        }
        do {
            let detail = try await APIService.shared.fetchAuditDetails(auditId: auditId)
            await MainActor.run {
                self.selectedAdminReport = detail
                self.isLoadingDetails = false
            }
        } catch {
            if attempt == 0 {
                print("Admin detail fetch retry after error: \(error)")
                await MainActor.run { self.isLoadingDetails = false }
                await fetchAdminReportDetails(auditId: auditId, attempt: 1)
                return
            }
            print("Admin detail fetch error: \(error)")
            await MainActor.run {
                self.selectedAdminReport = nil
                self.isLoadingDetails = false
            }
        }
    }
    
    func logout() {
        self.userId = ""
        self.authToken = ""
        self.isAdmin = false
        self.audits = []
        self.adminReports = []
        self.selectedAdminReport = nil
        self.currentAudit = nil
    }
}
