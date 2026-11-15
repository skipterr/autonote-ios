import Foundation
import SwiftData

// Тестовые данные для скриншотов: запуск с аргументами `-demo YES`.
// В обычном запуске не используется.
enum DemoData {
    @MainActor
    static func seed(_ ctx: ModelContext) {
        let car = Car(name: "", make: "Volkswagen", modelName: "Golf", year: 2017, startOdometer: 84_000)
        car.plate = "M AN 2017"
        // для скриншотов: `-body suv -color red`
        car.bodyRaw = UserDefaults.standard.string(forKey: "body")
        car.colorRaw = UserDefaults.standard.string(forKey: "color")
        ctx.insert(car)

        let cal = Calendar.current
        func day(_ ago: Int) -> Date { cal.date(byAdding: .day, value: -ago, to: .now) ?? .now }

        let items: [(Int, ExpenseCategory, Double, Double?, Int?, String)] = [
            (2, .fuel, 64.30, 38.2, 86_950, "Aral, дизель"),
            (5, .wash, 12.00, nil, nil, "Мойка"),
            (9, .parking, 6.50, nil, nil, "Парковка у вокзала"),
            (13, .fuel, 58.10, 35.0, 86_320, "Shell, дизель"),
            (20, .service, 189.00, nil, 86_100, "Замена масла и фильтров"),
            (27, .fuel, 61.75, 37.1, 85_690, "Aral, дизель"),
            (35, .fuel, 55.40, 33.9, 85_080, "Esso, дизель"),
            (41, .tires, 80.00, nil, nil, "Смена шин"),
            (48, .fuel, 60.20, 36.5, 84_470, "Shell, дизель"),
            (52, .insurance, 342.00, nil, nil, "Страховка HUK, полгода"),
            (63, .fuel, 57.90, 35.2, 84_010, "Aral, дизель"),
        ]
        for (ago, cat, amount, liters, odo, note) in items {
            ctx.insert(Expense(date: day(ago), category: cat, amount: amount, liters: liters, odometer: odo, note: note))
        }

        ctx.insert(Reminder(title: "Смена на летние шины", kind: .tires,
                            dueDate: cal.date(byAdding: .day, value: 5, to: .now), dueOdometer: nil))
        ctx.insert(Reminder(title: "TÜV", kind: .tuv,
                            dueDate: cal.date(byAdding: .day, value: 24, to: .now), dueOdometer: nil))
        ctx.insert(Reminder(title: "ТО", kind: .service, dueDate: nil, dueOdometer: 100_000))
        ctx.insert(Reminder(title: "Страховка", kind: .insurance,
                            dueDate: cal.date(byAdding: .month, value: 4, to: .now), dueOdometer: nil))
        let firstOfNext = cal.date(from: cal.dateComponents([.year, .month], from: cal.date(byAdding: .month, value: 1, to: .now) ?? .now)) ?? .now
        ctx.insert(RecurringPayment(title: "Страховка HUK", category: .insurance, amount: 57,
                                    period: .monthly, startDate: firstOfNext))
        ctx.insert(RecurringPayment(title: "Налог на авто", category: .tax, amount: 146,
                                    period: .yearly, startDate: cal.date(byAdding: .month, value: 3, to: .now) ?? .now))
        try? ctx.save()
    }
}
