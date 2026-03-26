import SwiftUI
import SafariServices

struct DashboardView: View {
    @EnvironmentObject var store: SurveyStore
    @State private var selectedAuditIds: Set<String> = []
    @State private var showChatbot = false
    @State private var showNewAuditModal = false
    @State private var newLocation: String = ""
    @State private var isCreating = false
    
    // Detail modal state (same pattern as admin dashboard which works)
    @State private var selectedCompletedAudit: Audit? = nil
    @State private var isLoadingDetails = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if store.isLoading && store.audits.isEmpty {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                        Spacer()
                    } else if store.audits.isEmpty {
                        emptyState
                    } else {
                        auditList
                    }
                }
                
                // Detail Modal for completed audits (same pattern as admin dashboard)
                if let report = selectedCompletedAudit {
                    auditDetailModal(report: report)
                }
                
                // Loading overlay
                if isLoadingDetails {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    ProgressView("Loading report...")
                        .padding(24)
                        .background(Theme.secondaryBackground)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.1), radius: 10)
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
    
    // MARK: - Create Audit
    
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
                            if selectedAuditIds.count >= 20 { return }
                            selectedAuditIds.insert(audit.id)
                        }
                    },
                    onTap: {
                        if audit.status == "Completed" || audit.status == "submitted" {
                            Task { await fetchAndShowDetails(auditId: audit.id) }
                        } else {
                            Task { await store.loadAudit(id: audit.id) }
                        }
                    }
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            
            if store.hasMoreAudits {
                Button(action: {
                    Task { await store.fetchMoreAudits() }
                }) {
                    HStack {
                        Spacer()
                        if store.isLoadingMoreAudits {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text(store.isLoadingMoreAudits ? "Loading..." : "Load More Audits")
                            .font(.subheadline.bold())
                            .foregroundColor(.blue)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(Theme.secondaryBackground)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .disabled(store.isLoadingMoreAudits)
                .padding(.vertical, 8)
            }
        }
        .listStyle(PlainListStyle())
        .refreshable {
            await store.refreshAudits()
        }
    }
    
    // MARK: - Fetch and Show Detail (identical pattern to admin dashboard)
    
    func fetchAndShowDetails(auditId: String) async {
        await MainActor.run { isLoadingDetails = true }
        do {
            let detail = try await APIService.shared.fetchAuditDetails(auditId: auditId)
            await MainActor.run {
                selectedCompletedAudit = detail
                isLoadingDetails = false
            }
        } catch {
            print("Detail fetch error: \(error)")
            await MainActor.run { isLoadingDetails = false }
        }
    }
    
    // MARK: - Detail Modal (replicated from working admin dashboard)
    
    func auditDetailModal(report: Audit) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { selectedCompletedAudit = nil }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.metadata?.mauze ?? "Unknown Kitchen")
                            .font(.title3.bold())
                            .foregroundColor(Theme.textPrimary)
                        Text("ITS: \(report.metadata?.its ?? "N/A") • \(report.createdAt ?? "")")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                    
                    Spacer()
                    
                    if let pdfUrl = report.pdfUrl, let url = URL(string: pdfUrl) {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text.fill")
                                Text("View PDF")
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                    }
                    
                    Button(action: { selectedCompletedAudit = nil }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(Theme.textSecondary)
                            .padding(8)
                            .background(Theme.border.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding()
                .background(Theme.secondaryBackground)
                
                Divider()
                    .background(Theme.border)
                
                // Report Content
                ScrollView {
                    if let answers = report.answers, !answers.isEmpty {
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
                                                .foregroundColor(Theme.textSecondary)
                                                .textCase(.uppercase)
                                            
                                            if section.items[idx].type == .text {
                                                if let s = ans?.status, s.isNA {
                                                    Text("N/A")
                                                        .font(.subheadline.weight(.medium))
                                                        .foregroundColor(Theme.textMuted)
                                                } else {
                                                    let val = ans?.value?.trimmingCharacters(in: .whitespaces) ?? ""
                                                    Text(val.isEmpty ? "Not Filled" : val)
                                                        .font(.subheadline.weight(.medium))
                                                        .foregroundColor(val.isEmpty ? Theme.textMuted : Theme.textPrimary)
                                                        .italic(val.isEmpty)
                                                }
                                            } else {
                                                userStatusDisplay(status: ans?.status)
                                            }
                                            
                                            if let photos = ans?.photos, !photos.isEmpty {
                                                ScrollView(.horizontal, showsIndicators: false) {
                                                    HStack(spacing: 8) {
                                                        ForEach(photos, id: \.self) { photoUrl in
                                                            AsyncImage(url: URL(string: photoUrl)) { image in
                                                                image.resizable().aspectRatio(contentMode: .fill)
                                                            } placeholder: {
                                                                Theme.border.opacity(0.1)
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
                                        if idx < section.items.count - 1 { Divider() }
                                    }
                                }
                                .padding()
                                .background(Theme.card)
                                .cornerRadius(12)
                                .shadow(color: .black.opacity(0.05), radius: 4)
                            }
                        }
                        .padding()
                    } else {
                        // Fallback: still show PDF link even without structured data
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.green)
                            Text("Audit Submitted")
                                .font(.headline)
                            if let pdfUrl = report.pdfUrl, let url = URL(string: pdfUrl) {
                                Link("Open PDF Report →", destination: url)
                                    .font(.body.bold())
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(32)
                    }
                }
            }
            .background(Theme.background)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.2), radius: 20)
            .padding()
        }
    }
    
    @ViewBuilder
    func userStatusDisplay(status: Answer.AnswerStatus?) -> some View {
        if let s = status {
            if s.isPass {
                Text("✓ Attributes Met")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.green)
            } else if s.isNA {
                Text("N/A")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Theme.textMuted)
            } else {
                Text("No Answer")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Theme.textMuted)
                    .italic()
            }
        } else {
            Text("No Answer")
                .font(.subheadline.weight(.medium))
                .foregroundColor(Theme.textMuted)
                .italic()
        }
    }
    
    // MARK: - Empty State
    
    var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(Theme.textMuted)
            Text("No audits found")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
            Text("Start one above!")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
            Button("Start New Audit") {
                showNewAuditModal = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Audit Row (matches web's audit card)

struct AuditRow: View {
    let audit: AuditSummary
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleSelection) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Theme.card)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(isSelected ? Color.blue : Theme.border, lineWidth: 1.5))
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(audit.location)
                            .font(.subheadline.bold())
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        StatusBadge(status: audit.status)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(formatDate(audit.lastUpdated))
                            .font(.caption)
                    }
                    .foregroundColor(Theme.textSecondary)
                    
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.border.opacity(0.3))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(audit.progress == 100 ? Color.green : Color.blue)
                                    .frame(width: geo.size.width * CGFloat(audit.progress) / 100.0, height: 6)
                            }
                        }
                        .frame(height: 6)
                        
                        Text("\(audit.progress)%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                    
                    if audit.reportUrl != nil {
                        HStack(spacing: 2) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10))
                            Text("PDF Available")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Theme.cardSelected : Theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 2 : 1)
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

struct StatusBadge: View {
    let status: String
    
    var badgeColor: Color {
        switch status {
        case "Completed", "submitted": return .green
        case "In Progress": return .blue
        default: return Theme.textMuted
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
                        adminEmptyState
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
                    isLoading: store.isLoadingDetails,
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
            
            // Lazy Loading: "Load More" button
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
                    .background(Theme.secondaryBackground)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
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
    
    var adminEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(Theme.textMuted)
            Text("No reports found.")
                .font(.headline)
                .foregroundColor(Theme.textSecondary)
        }
        .padding()
    }
    
    // MARK: - Admin Detail Modal
    
    func adminDetailModal(report: Audit) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { store.selectedAdminReport = nil }
            
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.metadata?.mauze ?? "Unknown Kitchen")
                            .font(.title3.bold())
                            .foregroundColor(Theme.textPrimary)
                        Text("ITS: \(report.metadata?.its ?? "N/A") • \(report.createdAt ?? "")")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
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
                            .background(Theme.textPrimary)
                            .foregroundColor(Theme.card)
                            .cornerRadius(8)
                        }
                    }
                    
                    Button(action: { store.selectedAdminReport = nil }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(Theme.textSecondary)
                            .padding(8)
                            .background(Theme.border.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding()
                .background(Theme.background)
                
                Divider()
                
                if store.isLoadingDetails {
                    Spacer()
                    ProgressView("Loading details...")
                    Spacer()
                } else {
                    ScrollView {
                        if let answers = report.answers, !answers.isEmpty {
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
                                                    .foregroundColor(Theme.textSecondary)
                                                    .textCase(.uppercase)
                                                
                                                if section.items[idx].type == .text {
                                                    if let s = ans?.status, s.isNA {
                                                        Text("N/A")
                                                            .font(.subheadline.weight(.medium))
                                                            .foregroundColor(Theme.textMuted)
                                                    } else {
                                                        let val = ans?.value?.trimmingCharacters(in: .whitespaces) ?? ""
                                                        Text(val.isEmpty ? "Not Filled" : val)
                                                            .font(.subheadline.weight(.medium))
                                                            .foregroundColor(val.isEmpty ? Theme.textMuted : Theme.textPrimary)
                                                            .italic(val.isEmpty)
                                                    }
                                                } else {
                                                    adminStatusDisplay(status: ans?.status)
                                                }
                                                
                                                if let photos = ans?.photos, !photos.isEmpty {
                                                    ScrollView(.horizontal, showsIndicators: false) {
                                                        HStack(spacing: 8) {
                                                            ForEach(photos, id: \.self) { photoUrl in
                                                                AsyncImage(url: URL(string: photoUrl)) { image in
                                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                                } placeholder: {
                                                                    Theme.border.opacity(0.1)
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
                                            if idx < section.items.count - 1 { Divider() }
                                        }
                                    }
                                    .padding()
                                    .background(Theme.card)
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
                                    .foregroundColor(Theme.textMuted)
                                if let pdfUrl = report.pdfUrl, let url = URL(string: pdfUrl) {
                                    Link("Open PDF Report →", destination: url)
                                        .font(.body.bold())
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(32)
                        }
                    }
                }
            }
            .background(Theme.background)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.2), radius: 20)
            .padding()
        }
    }
    
    @ViewBuilder
    func adminStatusDisplay(status: Answer.AnswerStatus?) -> some View {
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
                    .foregroundColor(Theme.textMuted)
            } else {
                Text("No Answer")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Theme.textMuted)
                    .italic()
            }
        } else {
            Text("No Answer")
                .font(.subheadline.weight(.medium))
                .foregroundColor(Theme.textMuted)
                .italic()
        }
    }
}

// MARK: - Admin Report Row

struct AdminReportRow: View {
    let report: AuditSummary
    let isSelected: Bool
    let isLoading: Bool
    let onToggle: () -> Void
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Theme.card)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(isSelected ? Color.blue : Theme.border, lineWidth: 1.5))
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isLoading)
            
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(report.location)
                            .font(.subheadline.bold())
                            .foregroundColor(Theme.textPrimary)
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
                        .foregroundColor(Theme.textSecondary)
                    
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.border.opacity(0.3))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(report.progress == 100 ? Color.green : Color.blue)
                                    .frame(width: geo.size.width * CGFloat(report.progress) / 100.0, height: 6)
                            }
                        }
                        .frame(height: 6)
                        
                        Text("\(report.progress)%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isLoading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Theme.cardSelected : Theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 2 : 1)
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
