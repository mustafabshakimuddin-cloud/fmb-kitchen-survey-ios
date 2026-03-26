import SwiftUI
import PhotosUI

struct SurveyWizardView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: SurveyStore
    @State private var currentSectionIndex = 0
    @State private var isSavingAndExiting = false
    
    var sections: [SurveySection] { ChecklistData.allSections }
    var currentSection: SurveySection { sections[currentSectionIndex] }
    var isLastSection: Bool { currentSectionIndex == sections.count - 1 }
    var progress: Int { store.calculateProgress() }
    var isValid: Bool { store.validateSurvey() }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // MARK: - Progress Header (matches web's sticky progress header)
                    progressHeader
                    
                    // MARK: - Questions ScrollView
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                // Section Title
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(currentSection.title)
                                        .font(.title2.bold())
                                        .foregroundColor(Theme.textPrimary)
                                    Text("Please answer all questions below.")
                                        .font(.subheadline)
                                        .foregroundColor(Theme.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .id("sectionTop")
                                
                                // Question Cards
                                LazyVStack(spacing: 16) {
                                    ForEach(currentSection.items.indices, id: \.self) { idx in
                                        QuestionCardView(
                                            sectionId: currentSection.id,
                                            itemIndex: idx,
                                            item: currentSection.items[idx]
                                        )
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.bottom, 120) // Space for nav buttons
                            }
                        }
                        .onChange(of: currentSectionIndex) { _ in
                            withAnimation {
                                proxy.scrollTo("sectionTop", anchor: .top)
                            }
                        }
                    }
                    
                    Spacer(minLength: 0)
                    
                    // MARK: - Navigation Bar (matches web's sticky bottom nav)
                    navigationBar
                }
                
                // MARK: - Submitting Overlay (matches web's submission progress modal)
                if store.isSubmitting {
                    submittingOverlay
                }
                
                // MARK: - Validation Error Modal (matches web's validation error modal)
                if store.validationError != nil {
                    validationErrorModal
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isSavingAndExiting {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Saving...")
                                .font(.subheadline)
                                .foregroundColor(Theme.textMuted)
                        }
                    } else {
                        Button("Save & Exit") {
                            saveAndExit()
                        }
                        .disabled(store.activeUploads > 0 || isSavingAndExiting)
                    }
                }
            }
        }
    }
    
    // MARK: - Progress Header
    
    var progressHeader: some View {
        VStack(spacing: 8) {
            HStack {
                // Section Dropdown (matches web's section picker)
                Menu {
                    ForEach(sections.indices, id: \.self) { idx in
                        Button(action: {
                            withAnimation { currentSectionIndex = idx }
                        }) {
                            HStack {
                                Text("\(idx + 1). \(sections[idx].title)")
                                if idx == currentSectionIndex {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("\(currentSectionIndex + 1). \(currentSection.title)")
                            .font(.subheadline.bold())
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.card)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.05), radius: 2)
                }
                
                Spacer()
                
                // Saving Status & Progress (matches web's saving indicator)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(store.isSaving ? Color.orange : Color.green)
                            .frame(width: 6, height: 6)
                        Text(store.isSaving ? "Saving..." : "Saved")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.textMuted)
                    }
                    Text("\(progress)% Done")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            
            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.border.opacity(0.3))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue)
                        .frame(width: geo.size.width * CGFloat(progress) / 100.0, height: 6)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding()
        .background(Theme.background.opacity(0.95))
    }
    
    
    // MARK: - Navigation Bar
    
    var navigationBar: some View {
        VStack(spacing: 12) {
            // Warning banners (matching web)
            if isLastSection && !isValid {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Please answer **all questions** in all sections to submit.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            }
            
            if store.activeUploads > 0 {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Uploading \(store.activeUploads) image(s)... Please wait.")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Navigation buttons
            HStack(spacing: 16) {
                if currentSectionIndex > 0 {
                    Button(action: {
                        withAnimation { currentSectionIndex -= 1 }
                    }) {
                        HStack {
                            Image(systemName: "arrow.left")
                            Text("Back")
                        }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.card)
                        .foregroundColor(Theme.textPrimary)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                        .shadow(color: .black.opacity(0.05), radius: 4)
                    }
                }
                
                if isLastSection {
                    Button(action: {
                        Task { await store.submitAudit() }
                    }) {
                        HStack {
                            Text("Submit Audit")
                            Image(systemName: "paperplane.fill")
                        }
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(store.isSubmitting || store.activeUploads > 0 ? Color.green.opacity(0.5) : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: .green.opacity(0.3), radius: 6)
                    }
                    .disabled(store.isSubmitting || store.activeUploads > 0)
                } else {
                    Button(action: {
                        withAnimation { currentSectionIndex += 1 }
                    }) {
                        HStack {
                            Text("Next")
                            Image(systemName: "arrow.right")
                        }
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: .blue.opacity(0.3), radius: 6)
                    }
                }
            }
        }
        .padding()
        .background(
            Theme.background
                .shadow(color: .black.opacity(0.1), radius: 8, y: -4)
        )
    }
    
    // MARK: - Submitting Overlay (matches web's submission progress modal)
    
    var submittingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 64, height: 64)
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.green)
                }
                
                Text("Submitting Audit...")
                    .font(.title3.bold())
                    .foregroundColor(Theme.textPrimary)
                
                Text("Please wait while we generate your PDF report and finalize the submission.")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                
                // Animated progress bar
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.border.opacity(0.1))
                        .frame(height: 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green)
                                .frame(width: geo.size.width * 0.33, height: 8)
                                .modifier(IndeterminateProgressModifier(width: geo.size.width))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .frame(height: 8)
            }
            .padding(32)
            .background(Theme.card)
            .cornerRadius(20)
            .shadow(radius: 20)
            .padding(40)
        }
    }
    
    // MARK: - Validation Error Modal (matches web's validation error modal)
    
    var validationErrorModal: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { store.dismissValidationError() }
            
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
                
                Text("Incomplete Audit")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
                
                Text(store.validationError ?? "")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.secondaryBackground)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                
                Button(action: { store.dismissValidationError() }) {
                    Text("OK, I'll fix it")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.textPrimary)
                        .foregroundColor(Theme.card)
                        .cornerRadius(12)
                }
            }
            .padding(24)
            .background(Theme.card)
            .cornerRadius(20)
            .shadow(radius: 20)
            .padding(32)
        }
    }
    
    // MARK: - Actions
    
    func saveAndExit() {
        if store.activeUploads > 0 {
            store.validationError = "Please wait for \(store.activeUploads) image(s) to finish uploading before leaving this audit."
            return
        }

        Task {
            await MainActor.run { isSavingAndExiting = true }
            
            if let audit = store.currentAudit,
               let auditId = audit.id,
               let metadata = audit.metadata {
                try? await APIService.shared.saveAudit(
                    auditId: auditId,
                    metadata: metadata,
                    answers: audit.answers ?? [:],
                    progress: store.calculateProgress()
                )
            }
            
            await MainActor.run {
                isSavingAndExiting = false
                store.clearCurrentAudit()
            }
        }
    }
}

// MARK: - Indeterminate Progress Animation

struct IndeterminateProgressModifier: ViewModifier {
    let width: CGFloat
    @State private var offset: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .offset(x: offset - width * 0.33)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    offset = width
                }
            }
    }
}

// MARK: - Question Card (matches web's QuestionCard.jsx — images on ALL question types)

struct QuestionCardView: View {
    @EnvironmentObject var store: SurveyStore
    let sectionId: String
    let itemIndex: Int
    let item: SurveyItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Question text
            Text(item.q)
                .font(.body.bold())
                .foregroundColor(Theme.textPrimary)
            
            if item.type == .status {
                // Pass / Fail / N/A buttons (matches web's StatusButton)
                HStack(spacing: 12) {
                    StatusButton(title: "Pass", color: .green, isSelected: getAnswer().status?.isPass == true) {
                        setAnswer(status: .string("Pass"))
                    }
                    StatusButton(title: "Fail", color: .red, isSelected: getAnswer().status?.isFail == true) {
                        setAnswer(status: .string("Fail"))
                    }
                    StatusButton(title: "N/A", color: .gray, isSelected: getAnswer().status?.isNA == true) {
                        setAnswer(status: .string("N/A"))
                    }
                }
            } else {
                // Text input
                DebouncedTextEditor(text: Binding(
                    get: { getAnswer().value ?? "" },
                    set: { setAnswer(value: $0) }
                ))
                .frame(minHeight: 80)
                .padding(8)
                .background(Theme.secondaryBackground)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            }
            
            // Image Upload Section — on ALL question types (matches web)
            Divider()
            
            ImageUploadView(photos: Binding(
                get: { getAnswer().photos ?? [] },
                set: { setAnswer(photos: $0) }
            ))
        }
        .padding(16)
        .background(Theme.card)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
    
    func getAnswer() -> Answer {
        store.currentAudit?.answers?["\(sectionId)-\(itemIndex)"] ?? Answer(status: nil, value: "", photos: [])
    }
    
    func setAnswer(status: Answer.AnswerStatus? = nil, value: String? = nil, photos: [String]? = nil) {
        var ans = getAnswer()
        if let status = status { ans.status = status }
        if let value = value { ans.value = value }
        if let photos = photos { ans.photos = photos }
        store.updateAnswer(sectionId: sectionId, itemIndex: itemIndex, answer: ans)
    }
}

// MARK: - Image Upload (matches web's ImageInput.jsx exactly — upload + delete)

struct ImageUploadView: View {
    @EnvironmentObject var store: SurveyStore
    @Binding var photos: [String]
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isShowingCamera = false
    @State private var isUploading = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "photo.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
                Text("Photos")
                    .font(.caption.bold())
                    .foregroundColor(Theme.textPrimary)
                Text("(\(photos.count) attached)")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Existing photos
                    ForEach(photos.indices, id: \.self) { idx in
                        ZStack(alignment: .topTrailing) {
                            AsyncImage(url: URL(string: photos[idx])) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().aspectRatio(contentMode: .fill)
                                case .failure:
                                    Theme.border.opacity(0.1)
                                        .overlay(Image(systemName: "photo").foregroundColor(Theme.textMuted))
                                default:
                                    Theme.border.opacity(0.1).overlay(ProgressView())
                                }
                            }
                            .frame(width: 64, height: 64)
                            .cornerRadius(10)
                            .clipped()
                            
                            // Delete button (matches web's X button with Drive delete)
                            Button(action: {
                                if idx < photos.count {
                                    let photoUrl = photos[idx]
                                    photos.remove(at: idx) // Optimistic removal (matches web)
                                    Task { await APIService.shared.deletePhoto(photoUrl: photoUrl) }
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                            }
                            .padding(2)
                        }
                    }
                    
                    if isUploading {
                        VStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        .frame(width: 64, height: 64)
                        .background(Theme.secondaryBackground)
                        .cornerRadius(10)
                    } else {
                        // Camera Button (Only show if available — prevents Simulator crashes)
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button(action: { isShowingCamera = true }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .padding(8)
                                        .background(Color.blue.opacity(0.1))
                                        .clipShape(Circle())
                                    Text("Camera")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .frame(width: 64, height: 64)
                                .background(Theme.card)
                                .foregroundColor(.blue)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(style: StrokeStyle(lineWidth: 1))
                                        .foregroundColor(.blue.opacity(0.3))
                                )
                            }
                        }
                        
                        // Gallery Button (PhotosPicker)
                        PhotosPicker(selection: $selectedItems, maxSelectionCount: 5, matching: .images) {
                            VStack(spacing: 4) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 16, weight: .medium))
                                    .padding(8)
                                    .background(Theme.secondaryBackground)
                                    .clipShape(Circle())
                                Text("Library")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .frame(width: 64, height: 64)
                            .background(Theme.secondaryBackground)
                            .foregroundColor(Theme.textMuted)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                    .foregroundColor(Theme.textMuted)
                            )
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in
                Task.detached {
                    let scaled = image.size.width > 1200 ? (image.resized(toWidth: 1200) ?? image) : image
                    if let data = scaled.jpegData(compressionQuality: 0.7) {
                        await MainActor.run { uploadImageData(data) }
                    }
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: selectedItems) { items in
            uploadImagesFromPicker(items: items)
        }
    }
    
    private func uploadImagesFromPicker(items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    uploadImageData(data)
                }
            }
            await MainActor.run {
                selectedItems = []
            }
        }
    }
    
    private func uploadImageData(_ data: Data) {
        isUploading = true
        store.registerUploadStart()
        
        Task.detached {
            let base64 = data.base64EncodedString()
            let fileName = "ios_upload_\(UUID().uuidString).jpg"
            
            do {
                let url = try await APIService.shared.uploadPhoto(
                    fileName: fileName,
                    mimeType: "image/jpeg",
                    base64Data: base64
                )
                await MainActor.run {
                    if !photos.contains(url) {
                        photos.append(url)
                    }
                    isUploading = false
                }
            } catch {
                print("Upload failed: \(error)")
                await MainActor.run {
                    isUploading = false
                }
            }
            await MainActor.run { store.registerUploadEnd() }
        }
    }
}

// MARK: - Status Button

struct StatusButton: View {
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: isSelected ? .bold : .regular))
                Text(title)
                    .font(.system(size: 11, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? color.opacity(0.1) : Theme.card)
            .foregroundColor(isSelected ? color : Theme.textMuted)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? color : Theme.border, lineWidth: isSelected ? 2 : 1)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .shadow(color: isSelected ? color.opacity(0.2) : .clear, radius: 4)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
    }
    
    var iconName: String {
        switch title {
        case "Pass": return "checkmark"
        case "Fail": return "xmark"
        default: return "minus"
        }
    }
}

// MARK: - Camera Picker (Native UIKit Wrapper)

struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss
    var onImagePicked: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        
        init(parent: CameraPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.onImagePicked(uiImage)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Image Resizing Extension
extension UIImage {
    func resized(toWidth width: CGFloat) -> UIImage? {
        let canvasSize = CGSize(width: width, height: CGFloat(ceil(width/size.width * size.height)))
        UIGraphicsBeginImageContextWithOptions(canvasSize, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: canvasSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
import SwiftUI
import Combine

class TextDebouncer: ObservableObject {
    @Published var input: String = ""
    @Published var debouncedOutput: String = ""
    private var cancellable: AnyCancellable?

    init(initialValue: String, delay: TimeInterval = 0.15) {
        self.input = initialValue
        self.debouncedOutput = initialValue
        
        cancellable = $input
            .dropFirst()
            .debounce(for: .seconds(delay), scheduler: RunLoop.main)
            .sink { [weak self] val in
                self?.debouncedOutput = val
            }
    }
}

struct DebouncedTextEditor: View {
    @Binding var text: String
    @StateObject private var debouncer: TextDebouncer

    init(text: Binding<String>) {
        self._text = text
        self._debouncer = StateObject(wrappedValue: TextDebouncer(initialValue: text.wrappedValue))
    }

    var body: some View {
        TextEditor(text: $debouncer.input)
            .onChange(of: debouncer.debouncedOutput) { newValue in
                text = newValue
            }
            // Add iOS 17 onChange backwards compatibility fallback
            .onAppear {
                if debouncer.input != text {
                    debouncer.input = text
                }
            }
    }
}
