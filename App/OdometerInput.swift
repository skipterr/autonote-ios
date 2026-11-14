import SwiftUI

// Пробег можно вводить целиком (87 325) или «сколько проехал» (+375) —
// тогда он прибавится к последнему записанному пробегу.
enum OdometerMode: String, CaseIterable, Identifiable {
    case delta, total
    var id: String { rawValue }
    var title: String { self == .delta ? "+ проехал" : "Весь пробег" }
}

struct OdometerField: View {
    @Binding var text: String
    @Binding var mode: OdometerMode
    let current: Int

    private var entered: Int? { Int(text.filter(\.isNumber)) }

    // Итоговый пробег, который запишется
    static func result(text: String, mode: OdometerMode, current: Int) -> Int? {
        guard let v = Int(text.filter(\.isNumber)) else { return nil }
        return mode == .delta ? current + v : v
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Как вводить пробег", selection: $mode) {
                ForEach(OdometerMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack {
                Text(mode == .delta ? "Проехал" : "Пробег")
                TextField(mode == .delta ? "например 375" : (current > 0 ? "сейчас ~\(current)" : "необязательно"),
                          text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                Text("км").foregroundStyle(.secondary)
            }

            if let v = entered {
                let total = mode == .delta ? current + v : v
                Group {
                    if mode == .delta {
                        Text("\(Fmt.km(current)) + \(Fmt.km(v)) = \(Fmt.km(total))")
                    } else if total < current {
                        Text("Меньше, чем последний записанный пробег (\(Fmt.km(current))) — проверь цифры.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Это +\(Fmt.km(total - current)) с прошлой записи")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// Быстро обновить пробег без расхода — например, в конце недели
struct OdometerSheet: View {
    let car: Car
    let current: Int
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var mode: OdometerMode = .delta

    private var result: Int? { OdometerField.result(text: text, mode: mode, current: current) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    OdometerField(text: $text, mode: $mode, current: current)
                } footer: {
                    Text("Сейчас записано \(Fmt.km(current)). Можно ввести, сколько проехал с прошлого раза, — приложение само прибавит.")
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Обновить пробег")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if let r = result { car.lastKnownOdometer = r }
                        dismiss()
                    }
                    .bold()
                    .disabled(result == nil || (result ?? 0) < current)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
