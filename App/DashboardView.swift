import SwiftData
import SwiftUI

struct DashboardView: View {
    let car: Car
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(filter: #Predicate<Reminder> { !$0.done }) private var reminders: [Reminder]
    @State private var trigger: AddTrigger?
    @State private var editing: Expense?

    private var stats: Stats { Stats(car: car, expenses: expenses) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthCard
                    addButtons
                    if !KeyVault.hasKey { keyHint }
                    statsGrid
                    remindersBlock
                    categoriesBlock
                    recentBlock
                }
                .padding()
            }
            .defaultScrollAnchor(UserDefaults.standard.string(forKey: "scroll") == "bottom" ? .bottom : .top)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(car.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { AddExpenseMenu(trigger: $trigger) }
            }
            .addExpenseFlow(trigger: $trigger, currentOdometer: stats.currentOdometer)
            .sheet(item: $editing) { e in
                ExpenseEditor(source: .manual, currentOdometer: stats.currentOdometer, existing: e)
            }
            .onAppear {
                // для скриншотов: `-sheet editor` сразу открывает карточку расхода
                if UserDefaults.standard.string(forKey: "sheet") == "editor" { editing = expenses.first }
            }
        }
    }

    // MARK: Блоки

    private var monthCard: some View {
        let s = stats
        let month = Date.now.formatted(.dateTime.month(.wide).locale(Locale(identifier: "ru_RU")))
        return VStack(alignment: .leading, spacing: 6) {
            Text("Расходы за \(month)")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.85))
            Text(Fmt.money(s.monthTotal))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .contentTransition(.numericText())
            if s.lastMonthTotal > 0 {
                Text("В прошлом месяце: \(Fmt.money(s.lastMonthTotal, decimals: 0))")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            HStack {
                Label(Fmt.km(s.currentOdometer), systemImage: "speedometer")
                Spacer()
                Text("Your car — your price")
                    .italic()
            }
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.75))
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: [Color(red: 0.05, green: 0.45, blue: 0.42), Color(red: 0.06, green: 0.24, blue: 0.36)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private var addButtons: some View {
        HStack(spacing: 10) {
            bigButton("Чек", icon: "camera.fill") { trigger = .camera }
            bigButton("Голосом", icon: "mic.fill") { trigger = .voice }
            bigButton("Вручную", icon: "square.and.pencil") { trigger = .manual }
        }
    }

    private func bigButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.footnote.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    private var keyHint: some View {
        Label("Чтобы чеки и голос заполнялись сами, добавь ключ Gemini в Настройках.", systemImage: "key.fill")
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    private var statsGrid: some View {
        let s = stats
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            tile("Цена километра", s.costPerKm.map { Fmt.money($0, decimals: 2) } ?? "—",
                 hint: s.costPerKm == nil ? "после 100 км" : "все расходы / км", icon: "eurosign.circle")
            tile("Расход топлива", s.fuelConsumption.map { Fmt.number($0) + " л" } ?? "—",
                 hint: s.fuelConsumption == nil ? "нужно 2 заправки с пробегом" : "на 100 км", icon: "fuelpump")
            tile("В среднем в месяц", s.monthlyAverage.map { Fmt.money($0, decimals: 0) } ?? "—",
                 hint: "с начала учёта", icon: "calendar")
            tile("Проехал", Fmt.km(s.kmDriven), hint: "с начала учёта", icon: "flag.checkered")
        }
    }

    private func tile(_ title: String, _ value: String, hint: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var remindersBlock: some View {
        let odo = stats.currentOdometer
        let upcoming = reminders.sorted { $0.urgency(odometer: odo) < $1.urgency(odometer: odo) }.prefix(3)
        if !upcoming.isEmpty {
            card("Скоро") {
                ForEach(Array(upcoming)) { r in
                    ReminderRow(reminder: r, odometer: odo)
                    if r.id != upcoming.last?.id { Divider() }
                }
            }
        }
    }

    @ViewBuilder
    private var categoriesBlock: some View {
        let cats = stats.byCategory(in: stats.thisMonth)
        let maxV = cats.first?.1 ?? 1
        if !cats.isEmpty {
            card("На что ушло в этом месяце") {
                ForEach(cats, id: \.0) { item in
                    CategoryBar(category: item.0, value: item.1, maxValue: maxV)
                }
            }
        }
    }

    @ViewBuilder
    private var recentBlock: some View {
        if expenses.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "receipt").font(.largeTitle).foregroundStyle(.tertiary)
                Text("Пока нет записей").font(.headline)
                Text("Заправился или заехал на мойку? Сфоткай чек — остальное приложение сделает само.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        } else {
            card("Последние") {
                ForEach(expenses.prefix(5)) { e in
                    Button { editing = e } label: { ExpenseRow(expense: e) }
                        .buttonStyle(.plain)
                    if e.id != expenses.prefix(5).last?.id { Divider() }
                }
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

// Строка расхода — общая для главной и истории
struct ExpenseRow: View {
    let expense: Expense

    private var details: String {
        var parts = [Fmt.shortDate(expense.date)]
        if let l = expense.liters { parts.append("\(Fmt.number(l)) л") }
        if let o = expense.odometer { parts.append(Fmt.km(o)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: expense.category.icon)
                .foregroundStyle(expense.category.color)
                .frame(width: 36, height: 36)
                .background(expense.category.color.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.note.isEmpty ? expense.category.title : expense.note)
                    .lineLimit(1)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(Fmt.money(expense.amount))
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}

struct CategoryBar: View {
    let category: ExpenseCategory
    let value: Double
    let maxValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label {
                    Text(category.title)
                } icon: {
                    Image(systemName: category.icon).foregroundStyle(category.color)
                }
                Spacer()
                Text(Fmt.money(value)).monospacedDigit()
            }
            .font(.subheadline)
            GeometryReader { g in
                Capsule().fill(category.color.opacity(0.8))
                    .frame(width: max(6, g.size.width * CGFloat(value / max(maxValue, 0.01))))
            }
            .frame(height: 6)
        }
    }
}