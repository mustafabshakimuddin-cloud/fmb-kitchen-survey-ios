import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: SurveyStore
    
    var body: some View {
        Group {
            if store.userId.isEmpty {
                LoginView()
            } else if let audit = store.currentAudit {
                if audit.status == "submitted", let pdfUrl = audit.pdfUrl, let url = URL(string: pdfUrl) {
                    SafariViewWrapper(url: url) {
                        store.clearCurrentAudit()
                    }
                    .ignoresSafeArea()
                } else {
                    SurveyWizardView()
                }
            } else {
                DashboardView()
            }
        }
        .animation(.easeInOut, value: store.userId)
        .animation(.easeInOut, value: store.currentAudit != nil)
    }
}
