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
        isLoading = true
        do {
            audits = try await APIService.shared.fetchAudits(userId: userId)
        } catch {
            self.error = error
        }
        isLoading = false
    }
    
    func startNewAudit(metadata: AuditMetadata) {
        // In a real app, we'd call a 'create' endpoint. 
        // For now, let's assume we create a local draft and 'save' it.
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
        currentAudit?.answers?[key] = answer
    }
    
    func loadAudit(id: String) async {
        isLoading = true
        do {
            currentAudit = try await APIService.shared.fetchAuditDetails(auditId: id)
        } catch {
            self.error = error
        }
        isLoading = false
    }
}
