import SwiftData
import SwiftUI

// Первый запуск: знакомимся с машиной.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var make = ""
    @State private var modelName = ""
    @State private var year = ""
    @State private var odometer = ""

    private var odoValue: Int? { Int(odometer.filter(\.isNumber)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "car.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Color(red: 0.05, green: 0.45, blue: 0.42))
                            .frame(width: 64, height: 64)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        Text("AutoNote")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .padding(.top, 6)
                        Text("Your car — your price.")
                            .font(.headline)
                            .italic()
                            .foregroundStyle(Color.white.opacity(0.85))
                        VStack(alignment: .leading, spacing: 8) {
                            feature("camera.fill", "Сфоткал чек — расход записан")
                            feature("mic.fill", "Или просто скажи голосом")
                            feature("eurosign.circle.fill", "Сколько стоит каждый километр")
                            feature("bell.fill", "Напомнит про ТО, TÜV и страховку")
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                    .background(
                        LinearGradient(colors: [Color(red: 0.07, green: 0.55, blue: 0.50), Color(red: 0.05, green: 0.20, blue: 0.33)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .listRowInsets(EdgeInsets())
                }

                Section("Машина") {
                    TextField("Марка, например Volkswagen", text: $make)
                    TextField("Модель, например Golf", text: $modelName)
                    TextField("Год выпуска", text: $year)
                        .keyboardType(.numberPad)
                    TextField("Как зовёшь машину (необязательно)", text: $name)
                }

                Section {
                    TextField("Пробег сейчас, км", text: $odometer)
                        .keyboardType(.numberPad)
                } footer: {
                    Text("От этого пробега начнём считать километры и цену за км.")
                }

                Section {
                    Button {
                        let car = Car(name: name.trimmed, make: make.trimmed, modelName: modelName.trimmed,
                                      year: Int(year.filter(\.isNumber)) ?? 0, startOdometer: odoValue ?? 0)
                        context.insert(car)
                        try? context.save()
                    } label: {
                        Text("Начать")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(odoValue == nil)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).foregroundStyle(Color.white)
        } icon: {
            Image(systemName: icon).foregroundStyle(Color.white.opacity(0.8))
        }
        .font(.subheadline)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
