import SwiftData
import SwiftUI

// Постоянные платежи: страховка, налог, кредит/лизинг, абонемент на парковку…
// В день платежа сам появляется расход в истории, за 3 дня приходит напоминание.

enum PaymentPeriod: String, CaseIterable, Identifiable {
    case monthly, quarterly, halfYear, yearly

    var id: String { rawValue }

    var months: Int {
        switch self {
        case .monthly: 1
        case .quarterly: 3
        case .halfYear: 6
        case .yearly: 12
        }
    }

    var title: String {
        switch self {
        case .monthly: "Каждый месяц"
        case .quarterly: "Раз в квартал"
        case .halfYear: "Раз в полгода"
        case .yearly: "Раз в год"
        }
    }

    var short: String {
        switch self {
        case .monthly: "в месяц"
        case .quarterly: "в квартал"
        case .halfYear: "в полгода"
        case .yearly: "в год"
        }
    }
}

@Model
final class RecurringPayment {
    var title: String
    var categoryRaw: String
    var amount: Double
    var periodRaw: String
    var startDate: Date       // первый платёж
    var paidCount: Int        // сколько платежей уже записано в историю
    var notificationID: String
    var createdAt: Date

    init(title: String, category: ExpenseCategory, amount: Double, period: PaymentPeriod, startDate: Date) {
        self.title = title
        self.categoryRaw = category.rawValue
        self.amount = amount
        self.periodRaw = period.rawValue
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.paidCount = 0
        self.notificationID = UUID().uuidString
        self.createdAt = .now
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var period: PaymentPeriod {
        get { PaymentPeriod(rawValue: periodRaw) ?? .monthly }
        set { periodRaw = newValue.rawValue }
    }

    // Считаем от первой даты, чтобы 31-е число не «уползало» на 28-е
    func dueDate(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: period.months * n, to: startDate) ?? startDate
    }

    var nextDate: Date { dueDate(paidCount) }

    var monthlyEquivalent: Double { amount / Double(period.months) }
}

enum Recurring {
    // Записывает в историю все платежи, день которых уже наступил
    @MainActor
    static func catchUp(_ ctx: ModelContext) {
        guard let list = try? ctx.fetch(FetchDescriptor<RecurringPayment>()), !list.isEmpty else { return }
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
        var changed = false
        for p in list {
            var n = 0
            while p.nextDate < tomorrow && n < 240 {
                ctx.insert(Expense(date: p.nextDate, category: p.category, amount: p.amount, note: p.title))
                p.paidCount += 1
                n += 1
                changed = true
            }
        }
        if changed { try? ctx.save() }
        guard !UserDefaults.standard.bool(forKey: "demo") else { return }
        for p in list {
            let id = p.notificationID, title = p.title, amount = p.amount, next = p.nextDate
            Task { await Notifications.schedulePayment(id: id, title: title, amount: amount, date: next) }
        }
    }
}

// MARK: - Блок на главной

struct RecurringCard: View {
    @Query(sort: \RecurringPayment.createdAt) private var payments: [RecurringPayment]
    @State private var editing: RecurringPayment?
    @State private var creating = false

    private var perMonth: Double { payments.reduce(0) { $0 + $1.monthlyEquivalent } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Постоянные платежи").font(.headline)
                Spacer()
                Button { creating = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }

            if payments.isEmpty {
                Button { creating = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "repeat.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        Text("Страховка, налог, кредит — добавь один раз, и они будут записываться сами.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)
            } else {
                ForEach(payments) { p in
                    Button { editing = p } label: { PaymentRow(payment: p) }
                        .buttonStyle(.plain)
                    if p.id != payments.last?.id { Divider() }
                }
                Divider()
                HStack {
                    Text("В среднем в месяц")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Fmt.money(perMonth)).bold().monospacedDigit()
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .sheet(isPresented: $creating) { PaymentEditor(payment: nil) }
        .sheet(item: $editing) { p in PaymentEditor(payment: p) }
        .onAppear {
            if UserDefaults.standard.string(forKey: "sheet") == "payment" { creating = true }
        }
    }
}

struct PaymentRow: View {
    let payment: RecurringPayment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: payment.category.icon)
                .foregroundStyle(payment.category.color)
                .frame(width: 36, height: 36)
                .background(payment.category.color.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(payment.title).lineLimit(1)
                Text("следующий \(Fmt.shortDate(payment.nextDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.money(payment.amount)).font(.body.weight(.semibold)).monospacedDigit()
                Text(payment.period.short).font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Редактор

struct PaymentEditor: View {
    let payment: RecurringPayment?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ExpenseCategory.insurance.title
    @State private var category: ExpenseCategory = .insurance
    @State private var amountText = ""
    @State private var period: PaymentPeriod = .monthly
    @State private var date = Date()
    @State private var loaded = false

    private let choices: [ExpenseCategory] = [.insurance, .tax, .loan, .parking, .service, .other]
    private var amount: Double? { Double.parseLoose(amountText) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Что") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(choices) { c in
                                Button {
                                    if title.isEmpty || title == category.title { title = c.title }
                                    category = c
                                } label: {
                                    Label(c.title, systemImage: c.icon)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(category == c ? c.color.opacity(0.2) : Color.secondary.opacity(0.1),
                                                    in: Capsule())
                                        .foregroundStyle(category == c ? c.color : Color.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    HStack {
                        Text("Название")
                        TextField("Например, HUK страховка", text: $title)
                            .multilineTextAlignment(.trailing)
                    }
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
                    Picker("Как часто", selection: $period) {
                        ForEach(PaymentPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker(payment == nil ? "Ближайший платёж" : "Следующий платёж",
                               selection: $date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "ru_RU"))
                } footer: {
                    if let a = amount, period != .monthly {
                        Text("Это \(Fmt.money(a / Double(period.months))) в месяц. В день платежа расход сам появится в истории, а за 3 дня придёт напоминание.")
                    } else {
                        Text("В день платежа расход сам появится в истории, а за 3 дня придёт напоминание.")
                    }
                }

                if let payment {
                    Section {
                        Button("Удалить платёж", role: .destructive) {
                            Notifications.cancelPayment(id: payment.notificationID)
                            context.delete(payment)
                            try? context.save()
                            dismiss()
                        }
                    } footer: {
                        Text("Уже записанные платежи останутся в истории.")
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle(payment == nil ? "Новый платёж" : "Платёж")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .bold()
                        .disabled(amount == nil || title.trimmed.isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let p = payment {
                    title = p.title
                    category = p.category
                    amountText = Fmt.number(p.amount, decimals: 2)
                    period = p.period
                    date = p.nextDate
                }
            }
        }
    }

    private func save() {
        guard let amount else { return }
        if let p = payment {
            p.title = title.trimmed
            p.category = category
            p.amount = amount
            if p.period != period || !Calendar.current.isDate(p.nextDate, inSameDayAs: date) {
                // новый график начинается с выбранной даты
                p.period = period
                p.startDate = Calendar.current.startOfDay(for: date)
                p.paidCount = 0
            }
        } else {
            context.insert(RecurringPayment(title: title.trimmed, category: category, amount: amount,
                                            period: period, startDate: date))
        }
        try? context.save()
        Recurring.catchUp(context)
        dismiss()
    }
}
