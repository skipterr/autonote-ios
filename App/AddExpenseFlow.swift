import PhotosUI
import SwiftUI

// Как человек хочет добавить расход
enum AddTrigger: Identifiable {
    case camera, gallery, voice, manual
    var id: Self { self }
}

enum ExpenseSource {
    case manual
    case photo(UIImage)
    case voice(String)
}

struct EditorRequest: Identifiable {
    let id = UUID()
    let source: ExpenseSource
}

// Подключает к любому экрану всю цепочку: камера/галерея/голос → редактор с заполненными полями.
struct AddExpenseFlow: ViewModifier {
    @Binding var trigger: AddTrigger?
    let currentOdometer: Int

    @State private var showCamera = false
    @State private var showGallery = false
    @State private var showVoice = false
    @State private var galleryItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var pendingText: String?
    @State private var editor: EditorRequest?

    func body(content: Content) -> some View {
        content
            .onChange(of: trigger) { _, t in
                guard let t else { return }
                trigger = nil
                switch t {
                case .camera: showCamera = true
                case .gallery: showGallery = true
                case .voice: showVoice = true
                case .manual: editor = EditorRequest(source: .manual)
                }
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                if let img = pendingImage {
                    pendingImage = nil
                    editor = EditorRequest(source: .photo(img))
                }
            }) {
                CameraPicker { pendingImage = $0 }
                    .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showGallery, selection: $galleryItem, matching: .images)
            .onChange(of: galleryItem) { _, item in
                guard let item else { return }
                galleryItem = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        editor = EditorRequest(source: .photo(img))
                    }
                }
            }
            .sheet(isPresented: $showVoice, onDismiss: {
                if let text = pendingText {
                    pendingText = nil
                    editor = EditorRequest(source: .voice(text))
                }
            }) {
                VoiceInputView { pendingText = $0 }
            }
            .sheet(item: $editor) { req in
                ExpenseEditor(source: req.source, currentOdometer: currentOdometer)
            }
    }
}

extension View {
    func addExpenseFlow(trigger: Binding<AddTrigger?>, currentOdometer: Int) -> some View {
        modifier(AddExpenseFlow(trigger: trigger, currentOdometer: currentOdometer))
    }
}

// Меню «+» для панели сверху
struct AddExpenseMenu: View {
    @Binding var trigger: AddTrigger?

    var body: some View {
        Menu {
            Button { trigger = .camera } label: { Label("Сфоткать чек", systemImage: "camera") }
            Button { trigger = .gallery } label: { Label("Чек из галереи", systemImage: "photo") }
            Button { trigger = .voice } label: { Label("Сказать голосом", systemImage: "mic") }
            Button { trigger = .manual } label: { Label("Вручную", systemImage: "square.and.pencil") }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
        }
    }
}

// Экран голосового ввода
struct VoiceInputView: View {
    var onDone: (String) -> Void
    @StateObject private var speech = SpeechRecognizer()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Скажи, например:\n«Заправился на 62 евро, 45 литров, пробег 84 300»")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                ScrollView {
                    Text(speech.text.isEmpty ? (speech.isRecording ? "Слушаю…" : " ") : speech.text)
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(speech.text.isEmpty ? Color.secondary : Color.primary)
                }
                .frame(maxHeight: 200)
                .padding()
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))

                if let err = speech.error {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                Button {
                    if speech.isRecording {
                        speech.stop()
                    } else {
                        Task { await speech.start() }
                    }
                } label: {
                    Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 84))
                        .symbolEffect(.pulse, isActive: speech.isRecording)
                        .foregroundStyle(speech.isRecording ? .red : Color.accentColor)
                }
                Text(speech.isRecording ? "Нажми, когда закончишь" : "Нажми и говори")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Голосом")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { speech.stop(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        speech.stop()
                        let t = speech.text.trimmed
                        if !t.isEmpty { onDone(t) }
                        dismiss()
                    }
                    .disabled(speech.text.trimmed.isEmpty)
                }
            }
            .task { await speech.start() }
            .onDisappear { speech.stop() }
        }
        .presentationDetents([.medium, .large])
    }
}
