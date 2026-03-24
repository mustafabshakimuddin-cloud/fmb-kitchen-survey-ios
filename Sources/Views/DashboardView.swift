import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: SurveyStore
    @State private var selectedAuditIds: Set<String> = []
    @State private var showChatbot = false
    @State private var showNewAuditSheet = false
    
    var body: some View {
        NavigationView {
            VStack {
                if store.isLoading && store.audits.isEmpty {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                } else if store.audits.isEmpty {
                    emptyState
                } else {
                    auditList
                }
            }
            .navigationTitle("Audits")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        if !selectedAuditIds.isEmpty {
                            Button(action: { showChatbot = true }) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Button(action: { showNewAuditSheet = true }) {
                            Image(systemName: "plus")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { store.userId = "" }) {
                        Text("Logout")
                            .foregroundColor(.red)
                    }
                }
            }
            .onAppear {
                Task {
                    await store.refreshAudits()
                }
            }
            .sheet(isPresented: $showChatbot) {
                ChatbotView(selectedAudits: store.audits.filter { selectedAuditIds.contains($0.id) })
            }
            .sheet(isPresented: $showNewAuditSheet) {
                NewAuditFormView()
            }
        }
    }
    
    var auditList: some View {
        List {
            ForEach(store.audits) { audit in
                AuditRow(audit: audit, isSelected: selectedAuditIds.contains(audit.id)) {
                    if selectedAuditIds.contains(audit.id) {
                        selectedAuditIds.remove(audit.id)
                    } else {
                        selectedAuditIds.insert(audit.id)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(PlainListStyle())
    }
    
    var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.slate400)
            
            Text("No audits found")
                .font(.headline)
            
            Text("Complete your first survey to see it here.")
                .font(.subheadline)
                .foregroundColor(.slate500)
            
            Button("Start New Audit") {
                showNewAuditSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct AuditRow: View {
    let audit: AuditSummary
    let isSelected: Bool
    let onToggleSelection: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Selection Toggle
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .slate400)
                    .font(.title3)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(audit.location)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("ID: \(audit.id.prefix(8))...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    StatusBadge(status: audit.status)
                    Text(audit.lastUpdated)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .onTapGesture {
                onToggleSelection()
            }
            
            Spacer()
            
            // Progress Ring
            ZStack {
                Circle()
                    .stroke(lineWidth: 4)
                    .opacity(0.1)
                    .foregroundColor(.blue)
                
                Circle()
                    .trim(from: 0.0, to: CGFloat(min(Double(audit.progress) / 100.0, 1.0)))
                    .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .foregroundColor(.blue)
                    .rotationEffect(Angle(degrees: 270.0))
                
                Text("\(audit.progress)%")
                    .font(.system(size: 10, weight: .bold))
            }
            .frame(width: 36, height: 36)
            
            Button(action: {
                Task {
                    await store.loadAudit(id: audit.id)
                }
            }) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .padding(8)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct StatusBadge: View {
    let status: String
    
    var body: some View {
        Text(status.capitalized)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(status == "submitted" ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
            .foregroundColor(status == "submitted" ? .green : .orange)
            .cornerRadius(4)
    }
}

struct NewAuditFormView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: SurveyStore
    @State private var mauze: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Kitchen Information")) {
                    TextField("Kitchen Name / Mauze", text: $mauze)
                }
            }
            .navigationTitle("New Audit")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Start") {
                        store.startNewAudit(metadata: AuditMetadata(its: store.userId, mauze: mauze))
                        dismiss()
                    }
                    .disabled(mauze.isEmpty)
                }
            }
        }
    }
}
