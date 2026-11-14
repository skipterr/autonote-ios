import SwiftUI

// Карточка «гаража» сверху главной: название, номер в плашке и машина сбоку.
// Картинка подбирается сама по марке и модели; нажми на неё — покажет другой вариант.
struct GarageCard: View {
    @Bindable var car: Car

    @State private var editingPlate = false
    @State private var plateText = ""
    @State private var loading = false
    @State private var notFound = false

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

            Button {
                Task { await load(skip: (car.photoVariant ?? 0) + 1) }
            } label: {
                ZStack {
                    if let data = car.photo, let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 8)
                            .opacity(loading ? 0.35 : 1)
                    } else {
                        Image(systemName: "car.side.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(Color.secondary.opacity(0.35))
                    }
                    if loading {
                        VStack(spacing: 6) {
                            ProgressView()
                            Text("Подбираю картинку…").font(.caption2).foregroundStyle(.secondary)
                        }
                    } else if notFound && car.photo == nil {
                        Text("Картинка не нашлась — нажми, чтобы попробовать ещё")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .offset(y: 44)
                    }
                }
                .frame(height: 120)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
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
        // картинка подбирается сама, когда её ещё нет или сменили марку/модель
        .task(id: "\(car.make)|\(car.modelName)") {
            if car.photo == nil && !UserDefaults.standard.bool(forKey: "demo") {
                try? await Task.sleep(for: .seconds(1))   // ждём, пока человек допечатает
                await load(skip: car.photoVariant ?? 0)
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

    private func load(skip: Int) async {
        guard !loading, !Task.isCancelled else { return }
        loading = true
        defer { loading = false }
        var img = await CarArtwork.find(make: car.make, model: car.modelName, skip: skip)
        var used = skip
        if img == nil && skip > 0 {          // варианты кончились — по кругу к первому
            img = await CarArtwork.find(make: car.make, model: car.modelName, skip: 0)
            used = 0
        }
        if let img {
            car.photo = img.pngData()
            car.photoVariant = used
            notFound = false
        } else {
            notFound = true
        }
    }
}
