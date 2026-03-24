import Foundation
import Combine

class SurveyStore: ObservableObject {
    @Published var userId: String = UserDefaults.standard.string(forKey: "fmb_audit_user") ?? "" {
        didSet { UserDefaults.standard.set(userId, forKey: "fmb_audit_user") }
    }
    
    @Published var audits: [AuditSummary] = []
    @Published var currentAudit: Audit?
    @Published var isLoading: Bool = false
    @Published var error: Error?
    
    // Checklist Data
    let checklist: [SurveySection] = ChecklistData.allSections
    
    func refreshAudits() async {
        guard !userId.isEmpty else { return }
        await MainActor.run { isLoading = true }
        do {
            let fetched = try await APIService.shared.fetchAudits(userId: userId)
            await MainActor.run { self.audits = fetched }
        } catch {
            await MainActor.run { self.error = error }
        }
        await MainActor.run { isLoading = false }
    }
    
    func startNewAudit(metadata: AuditMetadata) {
        let now = ISO8601DateFormatter().string(from: Date())
        let newAudit = Audit(
            id: UUID().uuidString,
            userId: userId,
            metadata: metadata,
            answers: [:],
            progress: 0,
            status: "draft",
            createdAt: now,
            updatedAt: now,
            pdfUrl: nil
        )
        currentAudit = newAudit
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
}
