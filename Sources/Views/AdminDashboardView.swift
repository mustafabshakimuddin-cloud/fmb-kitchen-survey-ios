import SwiftUI

struct AdminDashboardView: View {
    @EnvironmentObject var store: SurveyStore
    @State private var searchText = ""
    
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
            VStack {
                if store.isLoading && store.adminReports.isEmpty {
                    Spacer()
                    ProgressView("Loading Reports...")
                    Spacer()
                } else {
                    List {
                        ForEach(filteredReports) { report in
                            AuditRow(audit: report) {
                                store.loadAudit(id: report.id)
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search by Mauze or ID")
                    .refreshable {
                        await store.fetchAdminReports()
                    }
                }
            }
            .navigationTitle("Admin Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { store.logout() }) {
                        Label("Logout", systemImage: "logout")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await store.fetchAdminReports() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .onAppear {
            Task {
                await store.fetchAdminReports()
            }
        }
    }
}
