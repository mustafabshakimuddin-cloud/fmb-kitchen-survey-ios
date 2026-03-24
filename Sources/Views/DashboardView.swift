import SwiftUI
import SafariServices


struct DashboardView: View {
    @EnvironmentObject var store: SurveyStore
    @State private var selectedAuditIds: Set<String> = []
    @State private var showChatbot = false
    @State private var showNewAuditModal = false
    @State private var newLocation: String = ""
    @State private var isCreating = false
    @State private var safariURLString: String? = nil
    @State private var showSafari = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if store.isLoading && store.audits.isEmpty {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Spacer()
                } else if let error = store.error {
                    errorView(error: error)
                } else if store.audits.isEmpty {
                    emptyState
                } else {
                    auditList
                }
            }
            .navigationTitle("Audits")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        if !selectedAuditIds.isEmpty {
                            Button(action: { showChatbot = true }) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Button(action: { showNewAuditModal = true }) {
                            Image(systemName: "plus")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { store.logout() }) {
                        Text("Logout")
                            .foregroundColor(.red)
                    }
                }
            }
            .onAppear {
                Task { await store.refreshAudits() }
            }
            .sheet(isPresented: $showChatbot) {
                ChatbotView(selectedAudits: store.audits.filter { selectedAuditIds.contains($0.id) })
            }
            .fullScreenCover(isPresented: $showSafari) {
                if let str = safariURLString, let url = URL(string: str) {
                    SafariViewWrapper(url: url) {
                        showSafari = false
                        safariURLString = nil
                    }
                    .ignoresSafeArea()
                }
            }
            // New Audit Modal (matches web's modal exactly)
            .alert("Start New Audit", isPresented: $showNewAuditModal) {
                TextField("Kitchen Name / Mauze", text: $newLocation)
                Button("Cancel", role: .cancel) { newLocation = "" }
                Button("Start Audit") {
                    handleCreateAudit()
                }
                .disabled(newLocation.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("Enter the Location / Kitchen Name")
            }
        }
    }
    
    // MARK: - Create Audit (matches web's handleCreateAudit via API)
    
    func handleCreateAudit() {
        let location = newLocation.trimmingCharacters(in: .whitespaces)
        guard !location.isEmpty else { return }
        newLocation = ""
        isCreating = true
        
        Task {
            if let auditId = await store.createAudit(location: location) {
                await store.loadAudit(id: auditId)
            }
            await MainActor.run { isCreating = false }
        }
    }
    
    // MARK: - Audit List
    
    var auditList: some View {
        List {
            ForEach(store.audits) { audit in
                AuditRow(
                    audit: audit,
                    isSelected: selectedAuditIds.contains(audit.id),
                    onToggleSelection: {
                        if selectedAuditIds.contains(audit.id) {
                            selectedAuditIds.remove(audit.id)
                        } else {
                            if selectedAuditIds.count >= 20 {
                                return // Max 20 like web
                            }
                            selectedAuditIds.insert(audit.id)
                        }
                    },
                    onTap: {
                        // Matches web: completed → open PDF, in-progress → open wizard
                        if audit.status == "Completed" || audit.status == "submitted" {
                            if let urlStr = audit.reportUrl {
                                safariURLString = urlStr
                                showSafari = true
                            }
                            // If no PDF URL, do nothing (matching web's alert behavior)
                        } else {
                            Task { await store.loadAudit(id: audit.id) }
                        }
                    }
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(PlainListStyle())
        .refreshable {
            await store.refreshAudits()
        }
    }
    
    // MARK: - Empty State
    
    var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.slate400)
            
            Text("No audits found")
                .font(.headline)
            
            Text("Start one above!")
                .font(.subheadline)
                .foregroundColor(.slate500)
            
            Button("Start New Audit") {
                showNewAuditModal = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    // MARK: - Error View
    
    func errorView(error: Error) -> some View {
        VStack(spacing: 16) {
            Text("Error: \(error.localizedDescription)")
                .font(.subheadline)
                .foregroundColor(.red)
                .padding()
                .background(Color.red.opacity(0.05))
                .cornerRadius(8)
            
            Button("Retry") {
                Task { await store.refreshAudits() }
            }
            .font(.body.bold())
            .foregroundColor(.red)
        }
        .padding()
    }
}

// MARK: - Audit Row (matches web's audit card with progress bar, status badge, report link)

struct AuditRow: View {
    let audit: AuditSummary
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onTap: () -> Void
    
    func parseDate(_ dateString: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateString) ?? Date()
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Selection Toggle
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .slate400)
                    .font(.title3)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Main Content Area (Tappable)
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(audit.location)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        StatusBadge(status: audit.status)
                    }
                    
                    HStack {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(parseDate(audit.lastUpdated), style: .date)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    
                    // Progress Bar (matches web)
                    VStack(spacing: 4) {
                        HStack {
                            Text("Progress")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.slate600)
                            Spacer()
                            Text("\(audit.progress)%")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.slate600)
                        }
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.slate100)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.blue)
                                    .frame(width: geo.size.width * CGFloat(audit.progress) / 100.0, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                    
                    // Report link (matches web)
                    if audit.status == "Completed" && audit.reportUrl != nil {
                        HStack {
                            Spacer()
                            Text("View Report →")
                                .font(.caption.bold())
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue : Color.slate100, lineWidth: isSelected ? 2 : 1)
                )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct StatusBadge: View {
    let status: String
    
    var badgeColor: Color {
        switch status {
        case "Completed", "submitted": return .green
        case "In Progress": return .blue
        default: return .slate400
        }
    }
    
    var body: some View {
        Text(status.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.1))
            .foregroundColor(badgeColor)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(badgeColor.opacity(0.2), lineWidth: 1))
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
                        Task {
                            if let auditId = await store.createAudit(location: mauze) {
                                await store.loadAudit(id: auditId)
                            }
                        }
                        dismiss()
                    }
                    .disabled(mauze.isEmpty)
                }
            }
        }
    }
}


// MARK: - Admin Dashboard (matches web's AdminDashboard.jsx with detail modal + lazy loading)

struct AdminDashboardView: View {
    @EnvironmentObject var store: SurveyStore
    @State private var searchText = ""
    @State private var selectedIds: Set<String> = []
    @State private var showChat = false
    
    var filteredReports: [AuditSummary] {
        if searchText.isEmpty {
            return store.adminReports
        } else {
            return store.adminReports.filter { 
                $0.location.localizedCaseInsensitiveContains(searchText) || 
                $0.id.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack {
                    if store.isLoading && store.adminReports.isEmpty {
                        Spacer()
                        ProgressView("Loading Reports...")
                        Spacer()
                    } else if store.adminReports.isEmpty {
                        emptyState
                    } else {
                        reportList
                    }
                }
                
                // Detail Modal
                if let report = store.selectedAdminReport {
                    adminDetailModal(report: report)
                }
            }
            .navigationTitle("Admin Dashboard")
            .searchable(text: $searchText, prompt: "Search by Mauze or ID")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { store.logout() }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Logout")
                        }
                        .foregroundColor(.red)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        if !selectedIds.isEmpty {
                            Button("Deselect") {
                                selectedIds.removeAll()
                            }
                            .font(.caption)
                        }
                        
                        if selectedIds.count > 0 {
                            Button(action: { showChat = true }) {
                                Image(systemName: "sparkles")
                            }
                        }
                        
                        Button(action: {
                            Task { await store.fetchAdminReports() }
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .onAppear {
            Task { await store.fetchAdminReports() }
        }
        .sheet(isPresented: $showChat) {
            ChatbotView(selectedAudits: store.adminReports.filter { selectedIds.contains($0.id) })
        }
    }
    
    // MARK: - Report List with Lazy Loading
    
    var reportList: some View {
        List {
            ForEach(filteredReports) { report in
                AdminReportRow(
                    report: report,
                    isSelected: selectedIds.contains(report.id),
                    onToggle: {
                        if selectedIds.contains(report.id) {
                            selectedIds.remove(report.id)
                        } else {
                            if selectedIds.count >= 20 { return }
                            selectedIds.insert(report.id)
                        }
                    },
                    onTap: {
                        Task { await store.fetchAdminReportDetails(auditId: report.id) }
                    }
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            
            // Lazy Loading: "Load More" button (matches web)
            if store.adminHasMore {
                Button(action: {
                    Task { await store.fetchMoreAdminReports() }
                }) {
                    HStack {
                        if store.adminIsLoadingMore {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(store.adminIsLoadingMore ? "Loading..." : "Load More Reports")
                            .font(.subheadline.bold())
                        if !store.adminIsLoadingMore {
                            Image(systemName: "chevron.down")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.slate50)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.slate200, lineWidth: 1))
                }
                .disabled(store.adminIsLoadingMore)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(PlainListStyle())
        .refreshable {
            await store.fetchAdminReports()
        }
    }
    
    // MARK: - Empty State
    
    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.slate400)
            Text("No reports found.")
                .font(.headline)
                .foregroundColor(.slate500)
        }
        .padding()
    }
    
    // MARK: - Admin Detail Modal (matches web's report detail popup)
    
    func adminDetailModal(report: Audit) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { store.selectedAdminReport = nil }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.metadata?.mauze ?? "Unknown Kitchen")
                            .font(.title3.bold())
                            .foregroundColor(.slate800)
                        Text("ITS: \(report.metadata?.its ?? "N/A") • \(report.createdAt ?? "")")
                            .font(.caption)
                            .foregroundColor(.slate500)
                    }
                    
                    Spacer()
                    
                    if let pdfUrl = report.pdfUrl, let url = URL(string: pdfUrl) {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text.fill")
                                Text("PDF")
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.slate800)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                    }
                    
                    Button(action: { store.selectedAdminReport = nil }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(.slate500)
                            .padding(8)
                            .background(Color.slate100)
                            .clipShape(Circle())
                    }
                }
                .padding()
                .background(Color.slate50)
                
                Divider()
                
                // Detail Content
                if store.isLoadingDetails {
                    Spacer()
                    ProgressView("Loading details...")
                    Spacer()
                } else {
                    ScrollView {
                        if let answers = report.answers, !answers.isEmpty {
                            // Structured view: group by checklist sections
                            VStack(spacing: 16) {
                                ForEach(ChecklistData.allSections) { section in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(section.title)
                                            .font(.headline)
                                            .foregroundColor(.blue)
                                            .padding(.bottom, 4)
                                        
                                        ForEach(section.items.indices, id: \.self) { idx in
                                            let key = "\(section.id)-\(idx)"
                                            let ans = answers[key]
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(section.items[idx].q)
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.slate500)
                                                    .textCase(.uppercase)
                                                
                                                if section.items[idx].type == .text {
                                                    Text(ans?.value ?? "Not Filled")
                                                        .font(.subheadline.weight(.medium))
                                                        .foregroundColor(ans?.value != nil ? .slate800 : .slate300)
                                                        .italic(ans?.value == nil)
                                                } else {
                                                    statusDisplay(status: ans?.status)
                                                }
                                                
                                                // Show photos if any
                                                if let photos = ans?.photos, !photos.isEmpty {
                                                    ScrollView(.horizontal, showsIndicators: false) {
                                                        HStack(spacing: 8) {
                                                            ForEach(photos, id: \.self) { url in
                                                                AsyncImage(url: URL(string: url)) { image in
                                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                                } placeholder: {
                                                                    Color.slate100
                                                                }
                                                                .frame(width: 80, height: 80)
                                                                .cornerRadius(8)
                                                                .clipped()
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            .padding(.vertical, 4)
                                            
                                            if idx < section.items.count - 1 {
                                                Divider()
                                            }
                                        }
                                    }
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .shadow(color: .black.opacity(0.05), radius: 4)
                                }
                            }
                            .padding()
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.title)
                                    .foregroundColor(.orange)
                                Text("No structured data available")
                                    .font(.headline)
                                    .foregroundColor(.slate600)
                                Text("This report may have been created with an older version.")
                                    .font(.caption)
                                    .foregroundColor(.slate400)
                            }
                            .padding(32)
                        }
                    }
                }
            }
            .background(Color.white)
            .cornerRadius(16)
            .shadow(radius: 20)
            .padding()
        }
    }
    
    @ViewBuilder
    func statusDisplay(status: Answer.AnswerStatus?) -> some View {
        if let s = status {
            if s.isPass {
                Text("Attributes Met")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.green)
            } else if s.isFail {
                Text("Attributes NOT Met")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.red)
            } else if s.isNA {
                Text("N/A")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.slate400)
            } else {
                Text("No Answer")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.slate300)
                    .italic()
            }
        } else {
            Text("No Answer")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.slate300)
                .italic()
        }
    }
}

// MARK: - Admin Report Row

struct AdminReportRow: View {
    let report: AuditSummary
    let isSelected: Bool
    let onToggle: () -> Void
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color.white)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle().stroke(isSelected ? Color.blue : Color.slate300, lineWidth: 1.5)
                        )
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Report content
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(report.location)
                            .font(.subheadline.bold())
                            .foregroundColor(.slate800)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if report.reportUrl != nil {
                            HStack(spacing: 2) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 10))
                                Text("PDF")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                        }
                    }
                    
                    Text(report.lastUpdated.isEmpty ? "N/A" : formatDate(report.lastUpdated))
                        .font(.caption)
                        .foregroundColor(.slate500)
                    
                    // Progress bar
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.slate100)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(report.progress == 100 ? Color.green : Color.blue)
                                    .frame(width: geo.size.width * CGFloat(report.progress) / 100.0, height: 6)
                            }
                        }
                        .frame(height: 6)
                        
                        Text("\(report.progress)%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.slate600)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.blue : Color.slate200, lineWidth: isSelected ? 2 : 1)
                )
        )
    }
    
    func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
        return dateString
    }
}
