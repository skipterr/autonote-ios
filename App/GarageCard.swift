import SwiftUI

// Карточка «гаража» сверху главной: название, номер в плашке и машина сбоку.
// Машина рисуется сама — в цвете и кузове твоей; нажми на неё — меню.
struct GarageCard: View {
    @Bindable var car: Car

    @State private var editingPlate = false
    @State private var plateText = ""
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 6) {
            Text(car.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 16)

            Button {
                plateText = car.plate ?? ""
                editingPlate = true
            } label: {
                HStack(spacing: 4) {
                    if let plate = car.plate, !plate.isEmpty {
                        Text(plate)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    } else {
                        Text(car.year > 0 ? "\(String(car.year)) · добавить номер" : "Добавить номер")
                            .font(.system(size: 12, weight: .medium))
                    }
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            Menu {
                Picker(selection: Binding(get: { car.bodyType }, set: { car.bodyType = $0; dropAI() })) {
                    ForEach(BodyType.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label("Кузов: \(car.bodyType.title)", systemImage: "car.side")
                }
                .pickerStyle(.menu)
                Picker(selection: Binding(get: { car.color }, set: { car.color = $0; dropAI() })) {
                    ForEach(CarColor.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label("Цвет: \(car.color.title)", systemImage: "paintpalette")
                }
                .pickerStyle(.menu)
                Divider()
                if car.photo != nil {
                    Button { dropAI() } label: {
                        Label("Вернуть рисованную", systemImage: "arrow.uturn.backward")
                    }
                }
                Button { Task { await drawAI() } } label: {
                    Label("Нарисовать через ИИ", systemImage: "sparkles")
                }
            } label: {
                artwork
            }
            .disabled(loading)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            .alert("Не получилось нарисовать",
                   isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("Понятно", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(.secondarySystemGroupedBackground), Color(.tertiarySystemGroupedBackground)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .onAppear {
            // фото из прошлых версий (свои или из интернета) больше не показываем
            if car.photo != nil && car.photoIsAI != true {
                car.photo = nil
                car.photoVariant = nil
            }
        }
        .alert("Госномер", isPresented: $editingPlate) {
            TextField("Например, M AB 1234", text: $plateText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Сохранить") {
                let p = plateText.trimmed.uppercased()
                car.plate = p.isEmpty ? nil : p
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var artwork: some View {
        ZStack {
            if let data = car.photo, car.photoIsAI == true, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 8)
            } else {
                CarSilhouette(kind: car.bodyType, color: car.color)
            }
            if loading {
                ProgressView()
                    .padding(10)
                    .background(.regularMaterial, in: Circle())
            }
        }
        .opacity(loading ? 0.5 : 1)
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func dropAI() {
        car.photo = nil
        car.photoIsAI = nil
    }

    private func drawAI() async {
        guard !loading, !car.make.trimmed.isEmpty else { return }
        guard KeyVault.hasKey else {
            errorText = "Для этого нужен ключ Gemini в Настройках."
            return
        }
        loading = true
        defer { loading = false }
        do {
            let img = try await CarArtwork.draw(make: car.make, model: car.modelName, year: car.year, color: car.color)
            car.photo = img.pngData()
            car.photoIsAI = true
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Попробуй позже."
        }
    }
}
