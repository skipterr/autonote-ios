import SwiftUI

// Карточка «гаража» сверху главной: название, номер в плашке и машина сбоку.
// Машину рисует Gemini по марке, модели, году и цвету; нажми на неё — меню.
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
                Button {
                    Task { await draw() }
                } label: {
                    Label("Нарисовать заново", systemImage: "arrow.clockwise")
                }
                Picker(selection: Binding(get: { car.color }, set: { c in
                    car.color = c
                    Task { await draw() }
                })) {
                    ForEach(CarColor.allCases) { c in
                        Text(c.title).tag(c)
                    }
                } label: {
                    Label("Цвет: \(car.color.title)", systemImage: "paintpalette")
                }
                .pickerStyle(.menu)
            } label: {
                artwork
            }
            .disabled(loading)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(.secondarySystemGroupedBackground), Color(.tertiarySystemGroupedBackground)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 22)
        )
        // рисуем сами, когда картинки ещё нет или сменили марку/модель/цвет
        .task(id: "\(car.make)|\(car.modelName)|\(car.year)") {
            if car.photo == nil && KeyVault.hasKey && !UserDefaults.standard.bool(forKey: "demo") {
                try? await Task.sleep(for: .seconds(1))   // ждём, пока человек допечатает
                if !Task.isCancelled { await draw() }
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
            if let data = car.photo, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 8)
                    .opacity(loading ? 0.3 : 1)
            } else {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(car.color.swatch.opacity(0.55))
                    .opacity(loading ? 0.3 : 1)
            }
            if loading {
                VStack(spacing: 6) {
                    ProgressView()
                    Text("Рисую твою машину…").font(.caption2).foregroundStyle(.secondary)
                }
            } else if car.photo == nil || errorText != nil {
                Text(errorText ?? (KeyVault.hasKey ? "Нажми, чтобы нарисовать свою машину"
                                                   : "Добавь ключ Gemini в Настройках — и я нарисую твою машину"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .offset(y: 46)
            }
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func draw() async {
        guard !loading, !car.make.trimmed.isEmpty else { return }
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            let img = try await CarArtwork.draw(make: car.make, model: car.modelName, year: car.year, color: car.color)
            car.photo = img.pngData()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Не получилось нарисовать машину"
        }
    }
}
