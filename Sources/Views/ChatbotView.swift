import SwiftUI

struct ChatbotView: View {
    @Environment(\.dismiss) var dismiss
    let selectedAudits: [AuditSummary]
    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var isLoading = false
    
    init(selectedAudits: [AuditSummary]) {
        self.selectedAudits = selectedAudits
        // Correcting initial message in init
        _messages = State(initialValue: [
            ChatMessage(role: "model", text: "Hello! I am the FMB Audit Assistant. I am analyzing the \(selectedAudits.count) selected reports. What would you like to know?")
        ])
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Background Header
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.blue)
                        Text("FMB AI")
                            .font(.headline)
                        Spacer()
                        Capsule()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 140, height: 24)
                            .overlay(
                                Text("Manual Selection Mode")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.blue)
                            )
                    }
                    .padding(.horizontal)
                    
                    Text(selectedAudits.count > 0 ? "Analyzing \(selectedAudits.count) selected reports" : "No reports selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
                .padding(.vertical, 12)
                .background(Theme.card)
                .shadow(color: .black.opacity(0.05), radius: 5, y: 5)
                
                // Chat Area
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(messages) { msg in
                                ChatBubble(message: msg)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _ in
                        withAnimation { proxy.scrollTo(messages.last?.id) }
                    }
                }
                
                // Input Area
                HStack(spacing: 12) {
                    TextField("Ask about these reports...", text: $input)
                        .padding(10)
                        .background(Theme.secondaryBackground)
                        .cornerRadius(20)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border, lineWidth: 1))
                        .disabled(isLoading || selectedAudits.isEmpty)
                    
                    Button(action: sendMessage) {
                        ZStack {
                            Circle()
                                .fill(input.isEmpty || isLoading || selectedAudits.isEmpty ? Theme.textMuted : Color.blue)
                                .frame(width: 40, height: 40)
                            
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .disabled(input.isEmpty || isLoading || selectedAudits.isEmpty)
                }
                .padding()
                .background(Theme.card)
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
    
    func sendMessage() {
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let userMsg = ChatMessage(role: "user", text: input)
        messages.append(userMsg)
        let query = input
        input = ""
        isLoading = true
        
        Task {
            do {
                let response = try await APIService.shared.chatWithGemini(messages: messages, reports: selectedAudits)
                await MainActor.run {
                    messages.append(ChatMessage(role: "model", text: response))
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    messages.append(ChatMessage(role: "model", text: "Error: \(error.localizedDescription)"))
                    isLoading = false
                }
            }
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == "user" { Spacer() }
            
            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                HStack {
                    if message.role == "model" {
                        Image(systemName: "robot")
                            .foregroundColor(.blue)
                    }
                    Text(message.role == "user" ? "You" : "FMB AI")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    if message.role == "user" {
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                    }
                }
                
                Text(message.text)
                    .padding(12)
                    .background(message.role == "user" ? Color.blue : Theme.card)
                    .foregroundColor(message.role == "user" ? .white : Theme.textPrimary)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 2)
            }
            
            if message.role == "model" { Spacer() }
        }
    }
}
