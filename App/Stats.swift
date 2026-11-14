import Foundation

// Все цифры для главного экрана считаются тут, из записей.
struct Stats {
    let car: Car?
    let expenses: [Expense]

    var currentOdometer: Int {
        max(car?.startOdometer ?? 0, expenses.compactMap(\.odometer).max() ?? 0)
    }

    var total: Double { expenses.reduce(0) { $0 + $1.amount } }

    func total(in interval: DateInterval) -> Double {
        expenses.filter { interval.contains($0.date) }.reduce(0) { $0 + $1.amount }
    }

    var thisMonth: DateInterval {
        Calendar.current.dateInterval(of: .month, for: .now) ?? DateInterval(start: .now, duration: 0)
    }

    var lastMonth: DateInterval {
        let prev = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        return Calendar.current.dateInterval(of: .month, for: prev) ?? DateInterval(start: prev, duration: 0)
    }

    var monthTotal: Double { total(in: thisMonth) }
    var lastMonthTotal: Double { total(in: lastMonth) }

    // Сколько км проехали с начала учёта
    var kmDriven: Int { max(0, currentOdometer - (car?.startOdometer ?? currentOdometer)) }

    // € на километр — показываем, только когда проехали хотя бы 100 км
    var costPerKm: Double? {
        kmDriven >= 100 ? total / Double(kmDriven) : nil
    }

    // Средний расход в месяц с первой записи
    var monthlyAverage: Double? {
        guard let first = expenses.map(\.date).min() else { return nil }
        let months = max(1, (Calendar.current.dateComponents([.month], from: first, to: .now).month ?? 0) + 1)
        return total / Double(months)
    }

    // Расход топлива л/100 км: между первой и последней заправкой с пробегом.
    // Литры первой заправки не считаем — они ушли на км до неё.
    var fuelConsumption: Double? {
        let fills = expenses
            .filter { $0.category == .fuel && ($0.liters ?? 0) > 0 && $0.odometer != nil }
            .sorted { $0.odometer! < $1.odometer! }
        guard fills.count >= 2, let a = fills.first?.odometer, let b = fills.last?.odometer, b - a >= 50 else { return nil }
        let liters = fills.dropFirst().reduce(0) { $0 + ($1.liters ?? 0) }
        return liters / Double(b - a) * 100
    }

    // Разбивка по категориям за период, от большей к меньшей
    func byCategory(in interval: DateInterval?) -> [(ExpenseCategory, Double)] {
        let list = interval.map { iv in expenses.filter { iv.contains($0.date) } } ?? expenses
        var sums: [ExpenseCategory: Double] = [:]
        for e in list { sums[e.category, default: 0] += e.amount }
        return sums.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
}

// Форматирование: всегда евро, по-русски
enum Fmt {
    static func money(_ v: Double, decimals: Int = 2) -> String {
        v.formatted(.currency(code: "EUR").precision(.fractionLength(decimals)).locale(Locale(identifier: "ru_RU")))
    }

    static func km(_ v: Int) -> String {
        v.formatted(.number.locale(Locale(identifier: "ru_RU"))) + " км"
    }

    static func number(_ v: Double, decimals: Int = 1) -> String {
        v.formatted(.number.precision(.fractionLength(decimals)).locale(Locale(identifier: "ru_RU")))
    }

    static func date(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "ru_RU")))
    }

    static func shortDate(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "ru_RU")))
    }
}
