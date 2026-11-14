import SwiftUI

// Карточка «гаража» сверху главной: название, номер в плашке и машина сбоку.
struct GarageCard: View {
    @Bindable var car: Car
    var onPhoto: () -> Void

    @State private var editingPlate = false
    @State private var plateText = ""

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

            Button(action: onPhoto) {
                if let data = car.photo, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 8)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "car.side.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.secondary.opacity(0.45))
                        Text("Добавить фото машины")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(.secondarySystemGroupedBackground), Color(.tertiarySystemGroupedBackground)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .alert("Госномер", isPresented: $editingPlate) {
            TextField("Например, M AB 1234", text: $plateText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Сохранить") {
                let p = plateText.trimmed.uppercased()
                car.plate = p.isEmpty ? nil : p
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Номер видно только тебе — на фото он всё равно закрашивается.")
        }
    }
}
