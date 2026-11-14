import SwiftData
import SwiftUI

struct SettingsView: View {
    @Bindable var car: Car
    @State private var keyText = ""
    @State private var hasKey = KeyVault.hasKey
    @State private var odoText = ""
    @State private var yearText = ""
    @State private var showWelcome = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Машина") {
                    TextField("Как зовёшь машину", text: $car.name)
                    TextField("Марка", text: $car.make)
                    TextField("Модель", text: $car.modelName)
                    HStack {
                        Text("Год")
                        TextField("—", text: $yearText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: yearText) { _, v in car.year = Int(v.filter(\.isNumber)) ?? 0 }
                    }
                    HStack {
                        Text("Пробег на старте учёта")
                        TextField("0", text: $odoText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: odoText) { _, v in
                                if let n = Int(v.filter(\.isNumber)) { car.startOdometer = n }
                            }
                        Text("км").foregroundStyle(.secondary)
                    }
                }

                Section {
                    if hasKey {
                        Label("Ключ сохранён", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Button("Удалить ключ", role: .destructive) {
                            KeyVault.save("")
                            hasKey = false
                        }
                    } else {
                        SecureField("Вставь ключ Gemini", text: $keyText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Сохранить ключ") {
                            KeyVault.save(keyText)
                            keyText = ""
                            hasKey = KeyVault.hasKey
                        }
                        .disabled(keyText.trimmed.isEmpty)
                        Link("Получить бесплатный ключ", destination: URL(string: "https://aistudio.google.com/apikey")!)
                    }
                } header: {
                    Text("Умный ввод (Gemini)")
                } footer: {
                    Text("Ключ нужен, чтобы приложение само читало чеки и понимало голос. Он хранится только на этом телефоне.")
                }

                Section {
                    Button { showWelcome = true } label: {
                        Label("Как пользоваться", systemImage: "sparkles.rectangle.stack")
                    }
                    LabeledContent("Версия", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                } footer: {
                    Text("AutoNote · Your car — your price")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .navigationTitle("Настройки")
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .fullScreenCover(isPresented: $showWelcome) { WelcomeView { showWelcome = false } }
            .onAppear {
                odoText = String(car.startOdometer)
                yearText = car.year > 0 ? String(car.year) : ""
                hasKey = KeyVault.hasKey
            }
        }
    }
}
