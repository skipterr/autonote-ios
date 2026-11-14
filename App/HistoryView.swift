import SwiftData
import SwiftUI

struct HistoryView: View {
    let car: Car
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var trigger: AddTrigger?
    @State private var editing: Expense?
    @State private var filter: ExpenseCategory?

    private var shown: [Expense] {
        guard let filter else { return expenses }
        return expenses.filter { $0.category == filter }
    }

    // Записи по месяцам, свежие сверху
    private var months: [(key: Date, items: [Expense])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: shown) { cal.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                if expenses.isEmpty {
                    ContentUnavailableView("Пока пусто", systemImage: "list.bullet.rectangle",
                                           description: Text("Нажми «+» сверху, чтобы добавить первый расход."))
                        .listRowBackground(Color.clear)
                }
                ForEach(months, id: \.key) { month in
                    Section {
                        ForEach(month.items) { e in
                            Button { editing = e } label: { ExpenseRow(expense: e) }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button("Удалить", role: .destructive) {
                                        context.delete(e)
                                        try? context.save()
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text(month.key.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "ru_RU"))).capitalized)
                            Spacer()
                            Text(Fmt.money(month.items.reduce(0) { $0 + $1.amount }))
                        }
                    }
                }
            }
            .navigationTitle("История")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { filter = nil } label: {
                            Label("Все", systemImage: filter == nil ? "checkmark" : "")
                        }
                        ForEach(ExpenseCategory.allCases) { c in
                            Button { filter = c } label: {
                                Label(c.title, systemImage: filter == c ? "checkmark" : c.icon)
                            }
                        }
                    } label: {
                        Image(systemName: filter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { AddExpenseMenu(trigger: $trigger) }
            }
            .addExpenseFlow(trigger: $trigger, currentOdometer: Stats(car: car, expenses: expenses).currentOdometer)
            .sheet(item: $editing) { e in
                ExpenseEditor(source: .manual, currentOdometer: Stats(car: car, expenses: expenses).currentOdometer, existing: e)
            }
        }
    }
}
