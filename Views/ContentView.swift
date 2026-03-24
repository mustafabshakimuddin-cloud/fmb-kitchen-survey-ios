import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: SurveyStore
    
    var body: some View {
        Group {
            if store.userId.isEmpty {
                LoginView()
            } else if let _ = store.currentAudit {
                SurveyWizardView()
            } else {
                DashboardView()
            }
        }
        .animation(.easeInOut, value: store.userId)
        .animation(.easeInOut, value: store.currentAudit != nil)
    }
}
