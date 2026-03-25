import SwiftUI

struct LoginView: View {
    @EnvironmentObject var store: SurveyStore
    @State private var its: String = ""
    @State private var isLoading = false
    @State private var error = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background Gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "0F172A"), Color(hex: "1E293B")]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ).ignoresSafeArea()
                
                VStack(spacing: 40) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "safari.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.blue)
                            .shadow(color: .blue.opacity(0.5), radius: 10)
                        
                        Text("Kitchen Survey")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Smart Kitchen Certification")
                            .font(.subheadline)
                            .foregroundColor(.slate400)
                    }
                    .padding(.top, 60)
                    
                    // Input Section
                    VStack(alignment: .leading, spacing: 20) {
                        Text("ITS Identification")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        TextField("Enter your ITS", text: $its)
                            .keyboardType(.numberPad)
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .foregroundColor(.white)
                            .accentColor(.blue)
                        
                        Button(action: handleLogin) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Sign In")
                                        .fontWeight(.semibold)
                                    Image(systemName: "arrow.right")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(its.count >= 8 ? Color.blue : Color.slate600)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        .disabled(its.count < 8 || isLoading)

                        if !error.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        
                        NavigationLink(destination: AdminLoginView()) {
                            Text("Login as Admin")
                                .font(.footnote)
                                .foregroundColor(.slate500)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.top, 10)
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                    
                    Text("v1.0.0 Native")
                        .font(.caption)
                        .foregroundColor(.slate500)
                        .padding(.bottom, 20)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    func handleLogin() {
        let normalizedIts = its.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedIts.range(of: #"^\d{8,}$"#, options: .regularExpression) != nil else {
            error = "Enter a valid ITS number with at least 8 digits."
            return
        }

        error = ""
        isLoading = true
        Task {
            let success = await store.loginUser(userId: normalizedIts)
            await MainActor.run {
                isLoading = false
                if !success {
                    error = "Login failed. Please try again."
                }
            }
        }
    }
}

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
                    error = "Admin login failed"
                }
            }
        }
    }
}
