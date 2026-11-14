import PhotosUI
import SwiftData
import SwiftUI

// Фото своей машины: снять / из галереи / найти в интернете → вырезать фон и спрятать номера
struct CarPhotoSheet: View {
    @Bindable var car: Car
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case choose
        case search
        case processing
        case preview(UIImage, Int)
        case failed(UIImage, String)
    }

    @State private var stage: Stage = .choose
    @State private var showCamera = false
    @State private var pendingImage: UIImage?
    @State private var galleryItem: PhotosPickerItem?
    @State private var query = ""
    @State private var candidates: [CarImageSearch.Candidate] = []
    @State private var searching = false
    @State private var searchError: String?

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .choose: chooseView
                case .search: searchView
                case .processing: processingView
                case .preview(let img, let plates): previewView(img, plates: plates)
                case .failed(let img, let msg): failedView(img, message: msg)
                }
            }
            .navigationTitle("Фото машины")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            if let img = pendingImage { pendingImage = nil; run(img) }
        }) {
            CameraPicker { pendingImage = $0 }.ignoresSafeArea()
        }
        .onChange(of: galleryItem) { _, item in
            guard let item else { return }
            galleryItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    run(img)
                }
            }
        }
        .onAppear { if query.isEmpty { query = "\(car.make) \(car.modelName)".trimmed } }
    }

    // MARK: Экраны

    private var chooseView: some View {
        ScrollView {
            VStack(spacing: 16) {
                CarImageView(car: car, height: 180)
                    .padding(.top, 8)

                Text("Лучше всего смотрится фото **сбоку**, как в каталоге. Фон вырежется, а номер закрасится — прямо на телефоне.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 10) {
                    optionButton("Сфоткать машину", icon: "camera.fill") { showCamera = true }
                    PhotosPicker(selection: $galleryItem, matching: .images) {
                        optionLabel("Выбрать из галереи", icon: "photo.on.rectangle")
                    }
                    .buttonStyle(.plain)
                    optionButton("Найти фото модели в интернете", icon: "magnifyingglass") {
                        stage = .search
                        Task { await runSearch() }
                    }
                    if car.photo != nil {
                        Button(role: .destructive) {
                            car.photo = nil
                        } label: {
                            Text("Убрать фото").frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var searchView: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Например, Audi A3", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { Task { await runSearch() } }
                Button("Найти") { Task { await runSearch() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            if searching {
                Spacer()
                ProgressView("Ищу фото…")
                Spacer()
            } else if let searchError {
                Spacer()
                Text(searchError).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                Spacer()
            } else {
                ScrollView {
                    Text("Выбери фото, где машина видна сбоку целиком и стоит одна")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(candidates) { c in
                            Button {
                                stage = .processing
                                Task {
                                    do { run(try await CarImageSearch.download(c)) }
                                    catch { stage = .search; searchError = "Не получилось скачать это фото — выбери другое." }
                                }
                            } label: {
                                AsyncImage(url: c.thumb) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    Color.secondary.opacity(0.15)
                                }
                                .frame(height: 120)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    Text("Фото: Wikimedia Commons")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Назад") { stage = .choose } }
        }
    }

    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Вырезаю фон и прячу номера…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func previewView(_ img: UIImage, plates: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 10)
                .padding(.horizontal)
            Label(plates > 0 ? "Номер закрашен" : "Номеров на фото не нашёл",
                  systemImage: plates > 0 ? "checkmark.shield.fill" : "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            VStack(spacing: 10) {
                Button {
                    car.photo = img.pngData()
                    dismiss()
                } label: {
                    Text("Поставить на главную").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                Button("Выбрать другое фото") { stage = .choose }
            }
            .padding()
        }
    }

    private func failedView(_ original: UIImage, message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(uiImage: original)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            VStack(spacing: 10) {
                Button {
                    car.photo = original.downscaled(maxSide: 1400).jpegData(compressionQuality: 0.8)
                    dismiss()
                } label: {
                    Text("Оставить как есть").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                Button("Выбрать другое фото") { stage = .choose }
            }
            .padding()
        }
    }

    // MARK: Кнопки и действия

    private func optionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { optionLabel(title, icon: icon) }.buttonStyle(.plain)
    }

    private func optionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func run(_ image: UIImage) {
        stage = .processing
        Task {
            do {
                let r = try await CarPhotoProcessor.process(image)
                stage = .preview(r.image, r.platesHidden)
            } catch {
                stage = .failed(image, (error as? LocalizedError)?.errorDescription ?? "Не получилось обработать фото.")
            }
        }
    }

    private func runSearch() async {
        let q = query.trimmed
        guard !q.isEmpty else { return }
        searching = true
        searchError = nil
        defer { searching = false }
        do {
            candidates = try await CarImageSearch.search(q)
            if candidates.isEmpty { searchError = "Ничего не нашёл. Попробуй написать по-другому, например «Audi A3 8V»." }
        } catch {
            searchError = "Нет связи с интернетом."
        }
    }
}

// Картинка машины для главной и для экрана выбора; без фото — аккуратная заглушка
struct CarImageView: View {
    let car: Car
    var height: CGFloat = 170

    var body: some View {
        if let data = car.photo, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 12)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                Label("Добавь фото своей машины", systemImage: "plus.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
            )
        }
    }
}
