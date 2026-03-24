import SwiftUI

struct AdminLoginView: View {
    @EnvironmentObject var store: SurveyStore
    @Environment(\.dismiss) var dismiss
    @State private var password = ""
    @State private var error = ""
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.slate800)
                
                Text("Admin Access")
                    .font(.title.bold())
                    .foregroundColor(.slate900)
                
                Text("Please enter the admin password")
                    .font(.subheadline)
                    .foregroundColor(.slate500)
            }
            .padding(.top, 40)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.caption.bold())
                    .foregroundColor(.slate700)
                
                SecureField("••••••••", text: $password)
                    .padding()
                    .background(Color.slate100)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.slate200, lineWidth: 1)
                    )
            }
            
            if !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            
            Button(action: handleLogin) {
                HStack {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Login as Admin")
                            .fontWeight(.bold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.slate900)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isLoading || password.isEmpty)
            
            Button("Back to User Login") {
                dismiss()
            }
            .font(.footnote)
            .foregroundColor(.slate500)
            
            Spacer()
        }
        .padding(30)
    }
    
    func handleLogin() {
        error = ""
        isLoading = true
        
        Task {
            let success = await store.loginAdmin(password: password)
            await MainActor.run {
                isLoading = false
                if success {
                    dismiss()
                } else {
                    error = "Invalid admin password"
                }
            }
        }
    }
}
