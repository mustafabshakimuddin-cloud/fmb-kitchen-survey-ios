import SwiftUI
import SafariServices

struct ContentView: View {
    @EnvironmentObject var store: SurveyStore
    
    var body: some View {
        Group {
            if store.isAdmin {
                if let audit = store.currentAudit, let pdfUrl = audit.pdfUrl, let url = URL(string: pdfUrl) {
                    SafariViewWrapper(url: url) {
                        store.clearCurrentAudit()
                    }
                } else {
                    AdminDashboardView()
                }
            } else if store.userId.isEmpty {
                LoginView()
            } else if store.currentAudit != nil {
                // currentAudit is only set for in-progress audits now
                // (completed audits are handled by DashboardView's detail modal)
                SurveyWizardView()
            } else {
                DashboardView()
            }
        }
        .animation(.easeInOut, value: store.userId)
        .animation(.easeInOut, value: store.currentAudit != nil)
    }
}


struct SafariViewWrapper: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onDismiss()
        }
    }
}
