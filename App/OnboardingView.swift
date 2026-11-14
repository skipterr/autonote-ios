import SwiftData
import SwiftUI

// Первый запуск: знакомимся с машиной.
struct OnboardingView: View {
    private enum Field: Hashable, CaseIterable { case make, model, year, name, odometer }

    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var make = ""
    @State private var modelName = ""
    @State private var year = ""
    @State private var odometer = ""
    @FocusState private var focus: Field?

    private var odoValue: Int? { Int(odometer.filter(\.isNumber)) }
    private var typing: Bool { focus != nil }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        hero
                            .listRowInsets(EdgeInsets())
                    }

                    Section("Машина") {
                        TextField("Марка, например Volkswagen", text: $make)
                            .focused($focus, equals: .make)
                            .submitLabel(.next)
                            .id(Field.make)
                        TextField("Модель, например Golf", text: $modelName)
                            .focused($focus, equals: .model)
                            .submitLabel(.next)
                            .id(Field.model)
                        TextField("Год выпуска", text: $year)
                            .keyboardType(.numberPad)
                            .focused($focus, equals: .year)
                            .id(Field.year)
                        TextField("Как зовёшь машину (необязательно)", text: $name)
                            .focused($focus, equals: .name)
                            .submitLabel(.next)
                            .id(Field.name)
                    }
                    .onSubmit { next() }

                    Section {
                        TextField("Пробег сейчас, км", text: $odometer)
                            .keyboardType(.numberPad)
                            .focused($focus, equals: .odometer)
                            .id(Field.odometer)
                    } footer: {
                        Text("От этого пробега начнём считать километры и цену за км.")
                    }

                    Section {
                        Button {
                            focus = nil
                            let car = Car(name: name.trimmed, make: make.trimmed, modelName: modelName.trimmed,
                                          year: Int(year.filter(\.isNumber)) ?? 0, startOdometer: odoValue ?? 0)
                            context.insert(car)
                            try? context.save()
                        } label: {
                            Text(odoValue == nil ? "Укажи пробег, чтобы начать" : "Начать")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(odoValue == nil)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }
                .onChange(of: focus) { _, f in
                    guard let f else { return }
                    // поле, в котором печатаешь, всегда остаётся над клавиатурой
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation { proxy.scrollTo(f, anchor: .center) }
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        if focus != .odometer {
                            Button("Далее") { next() }
                        }
                        Spacer()
                        Button("Готово") { focus = nil }.bold()
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: typing)
            .onAppear {
                // для скриншотов: `-focus year` — сразу ставит курсор в поле года
                if UserDefaults.standard.string(forKey: "focus") == "year" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { focus = .year }
                }
            }
        }
    }

    private func next() {
        let all = Field.allCases
        guard let f = focus, let i = all.firstIndex(of: f), i + 1 < all.count else { focus = nil; return }
        focus = all[i + 1]
    }

    // Фирменная шапка; пока печатаешь — сворачивается в узкую полосу, чтобы не мешать
    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "car.fill")
                    .font(.system(size: typing ? 18 : 30, weight: .bold))
                    .foregroundStyle(Color(red: 0.05, green: 0.45, blue: 0.42))
                    .frame(width: typing ? 40 : 64, height: typing ? 40 : 64)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: typing ? 10 : 16))
                if typing {
                    Text("AutoNote")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                }
            }
            if !typing {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(typing ? 14 : 22)
        .background(
            LinearGradient(colors: [Color(red: 0.07, green: 0.55, blue: 0.50), Color(red: 0.05, green: 0.20, blue: 0.33)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
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

// Кнопка «Готово» над любой клавиатурой — у цифровой своей кнопки закрытия нет
struct KeyboardDoneButton: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .bold()
            }
        }
    }
}

extension View {
    func keyboardDoneButton() -> some View { modifier(KeyboardDoneButton()) }
}
