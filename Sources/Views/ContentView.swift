import SwiftUI
import SafariServices

struct ContentView: View {
    @EnvironmentObject var store: SurveyStore
    
    var body: some View {
        Group {
            if store.userId.isEmpty {
                LoginView()
            } else if let audit = store.currentAudit {
                if (audit.status == "submitted" || audit.status == "Completed"), let pdfUrl = audit.pdfUrl, let url = URL(string: pdfUrl) {
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
