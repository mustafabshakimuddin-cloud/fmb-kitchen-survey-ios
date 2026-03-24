import SwiftUI

struct SurveyWizardView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: SurveyStore
    @State private var currentSectionIndex = 0
    @State private var isSubmitting = false
    
    var body: some View {
        NavigationView {
            VStack {
                // Progress Bar
                ProgressView(value: Double(currentSectionIndex + 1), total: Double(ChecklistData.allSections.count))
                    .padding()
                
                // Section Title
                Text(ChecklistData.allSections[currentSectionIndex].title)
                    .font(.title2.bold())
                    .padding(.horizontal)
                
                // Questions
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(ChecklistData.allSections[currentSectionIndex].items.indices, id: \.self) { idx in
                            QuestionView(
                                sectionId: ChecklistData.allSections[currentSectionIndex].id,
                                itemIndex: idx,
                                item: ChecklistData.allSections[currentSectionIndex].items[idx]
                            )
                        }
                    }
                    .padding()
                }
                
                Spacer()
                
                // Navigation Buttons
                HStack {
                    if currentSectionIndex > 0 {
                        Button("Back") {
                            withAnimation { currentSectionIndex -= 1 }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Spacer()
                    
                    if currentSectionIndex < ChecklistData.allSections.count - 1 {
                        Button("Next") {
                            withAnimation { currentSectionIndex += 1 }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Submit Audit") {
                            submitAudit()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(isSubmitting)
                    }
                }
                .padding()
                .background(Color.white)
                .shadow(radius: 2)
            }
            .navigationTitle("Survey")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Save & Exit") {
                        saveAndExit()
                    }
                }
            }
        }
    }
    
    func saveAndExit() {
        Task {
            if let audit = store.currentAudit {
                try? await APIService.shared.saveAudit(
                    auditId: audit.id,
                    metadata: audit.metadata,
                    answers: audit.answers ?? [:],
                    progress: calculateProgress()
                )
            }
            dismiss()
        }
    }
    
    func submitAudit() {
        isSubmitting = true
        Task {
            do {
                guard let audit = store.currentAudit else { return }
                
                // 1. Generate Snapshots
                let snapshots = ChecklistData.allSections.map { section in
                    SectionSnapshot(title: section.title, items: section.items.enumerated().map { (idx, item) in
                        ItemSnapshot(question: item.q, type: item.type.rawValue, answer: audit.answers?["\(section.id)-\(idx)"] ?? Answer(status: nil, value: "", photos: []))
                    })
                }
                
                // 2. Generate PDF via GAS
                let pdfUrl = try await APIService.shared.generatePDF(
                    auditId: audit.id,
                    userId: store.userId,
                    metadata: audit.metadata,
                    answers: audit.answers ?? [:],
                    reportData: snapshots
                )
                
                // 3. Submit to Cloudflare/NeonDB
                try await APIService.shared.submitAudit(
                    auditId: audit.id,
                    userId: store.userId,
                    reportData: snapshots,
                    pdfUrl: pdfUrl
                )
                
                await MainActor.run {
                    isSubmitting = false
                    dismiss()
                }
            } catch {
                print("Submit error: \(error)")
                await MainActor.run { isSubmitting = false }
            }
        }
    }
    
    func calculateProgress() -> Int {
        // Simple progress calculation based on answered questions
        let total = ChecklistData.allSections.flatMap { $0.items }.count
        let answered = store.currentAudit?.answers?.count ?? 0
        return Int((Double(answered) / Double(total)) * 100)
    }
}

struct QuestionView: View {
    @EnvironmentObject var store: SurveyStore
    let sectionId: String
    let itemIndex: Int
    let item: SurveyItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.q)
                .font(.body.bold())
            
            if item.type == .status {
                HStack(spacing: 20) {
                    StatusButton(title: "Pass", color: .green, isSelected: getAnswer().status?.isPass == true) {
                        setAnswer(status: .bool(true))
                    }
                    StatusButton(title: "Fail", color: .red, isSelected: getAnswer().status?.isFail == true) {
                        setAnswer(status: .bool(false))
                    }
                    StatusButton(title: "N/A", color: .gray, isSelected: getAnswer().status?.isNA == true) {
                        setAnswer(status: .string("N/A"))
                    }
                }
            } else {
                TextEditor(text: Binding(get: { getAnswer().value }, set: { setAnswer(value: $0) }))
                    .frame(height: 80)
                    .padding(4)
                    .background(Color.slate50)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.slate200, lineWidth: 1))
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
    
    func getAnswer() -> Answer {
        store.currentAudit?.answers?["\(sectionId)-\(itemIndex)"] ?? Answer(status: nil, value: "", photos: [])
    }
    
    func setAnswer(status: Answer.AnswerStatus? = nil, value: String? = nil) {
        var ans = getAnswer()
        if let status = status { ans.status = status }
        if let value = value { ans.value = value }
        store.updateAnswer(sectionId: sectionId, itemIndex: itemIndex, answer: ans)
    }
}

struct StatusButton: View {
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? color : Color.white)
                .foregroundColor(isSelected ? .white : color)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 1))
        }
    }
}

extension Answer.AnswerStatus {
    var isPass: Bool {
        if case .bool(let b) = self { return b }
        return false
    }
    var isFail: Bool {
        if case .bool(let b) = self { return !b }
        return false
    }
    var isNA: Bool {
        if case .string(let s) = self { return s == "N/A" }
        return false
    }
}

