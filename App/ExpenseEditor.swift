import SwiftData
import SwiftUI

// Карточка расхода: новая (с автозаполнением из фото/голоса) или редактирование старой.
struct ExpenseEditor: View {
    let source: ExpenseSource
    let currentOdometer: Int
    var existing: Expense?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var category: ExpenseCategory = .fuel
    @State private var amountText = ""
    @State private var litersText = ""
    @State private var odoText = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var photo: UIImage?
    @State private var parsing = false
    @State private var parseError: String?
    @State private var filledByAI = false
    @State private var loaded = false

    private var amount: Double? { Double.parseLoose(amountText) }
    private var liters: Double? { Double.parseLoose(litersText) }
    private var odometer: Int? { Int(odoText.filter(\.isNumber)) }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        NavigationStack {
            Form {
                if parsing {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(isPhoto ? "Читаю чек…" : "Разбираю, что ты сказал…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let parseError {
                    Section {
                        Label(parseError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }
                if filledByAI {
                    Section {
                        Label("Заполнено автоматически — проверь цифры", systemImage: "sparkles")
                            .font(.footnote)
                            .foregroundStyle(.tint)
                    }
                }
                if case .voice(let text) = source {
                    Section("Ты сказал") { Text("«\(text)»").foregroundStyle(.secondary) }
                }

                Section("Категория") {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(ExpenseCategory.allCases) { c in
                            Button { category = c } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: c.icon)
                                        .font(.title3)
                                        .frame(width: 44, height: 44)
                                        .background(category == c ? c.color.opacity(0.25) : Color.secondary.opacity(0.1),
                                                    in: Circle())
                                        .foregroundStyle(category == c ? c.color : Color.secondary)
                                    Text(c.title)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .foregroundStyle(category == c ? Color.primary : Color.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    HStack {
                        Text("Сумма")
                        TextField("0,00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.title3.bold())
                        Text("€").foregroundStyle(.secondary)
                    }
                    DatePicker("Дата", selection: $date, in: ...Date.now.addingTimeInterval(86400), displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "ru_RU"))
                }

                Section {
                    if category == .fuel {
                        HStack {
                            Text("Литры")
                            TextField("необязательно", text: $litersText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        if let a = amount, let l = liters, l > 0 {
                            LabeledContent("Цена литра", value: Fmt.money(a / l, decimals: 3))
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Пробег")
                        TextField(currentOdometer > 0 ? "сейчас ~\(currentOdometer)" : "необязательно", text: $odoText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("км").foregroundStyle(.secondary)
                    }
                    TextField("Заметка, например «Shell» или «колодки»", text: $note)
                } footer: {
                    if category == .fuel {
                        Text("Укажи литры и пробег — и приложение посчитает расход топлива на 100 км.")
                    }
                }

                if let photo {
                    Section("Чек") {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                if let existing {
                    Section {
                        Button("Удалить запись", role: .destructive) {
                            context.delete(existing)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existing == nil ? "Новый расход" : "Расход")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .bold()
                        .disabled(amount == nil || parsing)
                }
            }
            .task {
                guard !loaded else { return }
                loaded = true
                await load()
            }
        }
        .interactiveDismissDisabled(parsing)
    }

    private var isPhoto: Bool {
        if case .photo = source { return true }
        return false
    }

    private func load() async {
        if let e = existing {
            category = e.category
            amountText = Fmt.number(e.amount, decimals: 2)
            litersText = e.liters.map { Fmt.number($0, decimals: 2) } ?? ""
            odoText = e.odometer.map(String.init) ?? ""
            note = e.note
            date = e.date
            photo = e.photo.flatMap(UIImage.init(data:))
            return
        }

        parsing = true
        defer { parsing = false }
        do {
            let parsed: ParsedExpense
            switch source {
            case .manual:
                parsing = false
                return
            case .photo(let img):
                photo = img.downscaled(maxSide: 1600)
                parsed = try await Gemini.parse(image: img, currentOdometer: currentOdometer)
            case .voice(let text):
                parsed = try await Gemini.parse(text: text, currentOdometer: currentOdometer)
            }
            apply(parsed)
        } catch {
            parseError = error.localizedDescription
        }
    }

    private func apply(_ p: ParsedExpense) {
        if let c = p.category { category = c }
        if let a = p.amount { amountText = Fmt.number(a, decimals: 2) }
        if let l = p.liters { litersText = Fmt.number(l, decimals: 2) }
        if let o = p.odometer { odoText = String(o) }
        if let d = p.date { date = d }
        if let n = p.note { note = n }
        filledByAI = p.amount != nil || p.category != nil
        if !filledByAI { parseError = "Не получилось ничего разобрать — заполни вручную." }
    }

    private func save() {
        guard let amount else { return }
        let photoData = photo?.jpegData(compressionQuality: 0.6)
        let l = category == .fuel ? liters : nil
        if let e = existing {
            e.category = category
            e.amount = amount
            e.liters = l
            e.odometer = odometer
            e.note = note.trimmed
            e.date = date
        } else {
            context.insert(Expense(date: date, category: category, amount: amount, liters: l,
                                   odometer: odometer, note: note.trimmed, photo: photoData))
        }
        try? context.save()
        dismiss()
    }
}
