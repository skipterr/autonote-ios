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
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "car.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                        Text("AutoNote")
                            .font(.largeTitle.bold())
                        Text("Your car — your price.")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Фоткай чеки или говори голосом — приложение само всё запишет и посчитает, сколько тебе стоит машина.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
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
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
