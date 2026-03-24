import SwiftUI

struct LoginView: View {
    @EnvironmentObject var store: SurveyStore
    @State private var its: String = ""
    @State private var isLoading = false
    
    var body: some View {
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
    
    func handleLogin() {
        isLoading = true
        // Simulate login
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            store.userId = its
            isLoading = false
        }
    }
}

