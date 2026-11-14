import Foundation
import SwiftData
import SwiftUI

// MARK: - Машина

@Model
final class Car {
    var name: String          // как человек зовёт машину, например «Гольф»
    var make: String          // марка
    var modelName: String     // модель
    var year: Int
    var startOdometer: Int    // пробег, когда начали вести учёт
    var createdAt: Date

    init(name: String, make: String, modelName: String, year: Int, startOdometer: Int) {
        self.name = name
        self.make = make
        self.modelName = modelName
        self.year = year
        self.startOdometer = startOdometer
        self.createdAt = .now
    }

    var title: String {
        let full = [make, modelName].filter { !$0.isEmpty }.joined(separator: " ")
        if name.isEmpty { return full.isEmpty ? "Моя машина" : full }
        return name
    }
}

// MARK: - Расход

enum ExpenseCategory: String, CaseIterable, Identifiable, Codable {
    case fuel, service, repair, tires, wash, insurance, tax, parking, fines, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fuel: "Топливо"
        case .service: "ТО"
        case .repair: "Ремонт"
        case .tires: "Шины"
        case .wash: "Мойка"
        case .insurance: "Страховка"
        case .tax: "Налог"
        case .parking: "Парковка"
        case .fines: "Штрафы"
        case .other: "Другое"
        }
    }

    var icon: String {
        switch self {
        case .fuel: "fuelpump.fill"
        case .service: "wrench.and.screwdriver.fill"
        case .repair: "hammer.fill"
        case .tires: "circle.circle.fill"
        case .wash: "drop.fill"
        case .insurance: "shield.fill"
        case .tax: "building.columns.fill"
        case .parking: "parkingsign.circle.fill"
        case .fines: "exclamationmark.triangle.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .fuel: .orange
        case .service: .blue
        case .repair: .red
        case .tires: .gray
        case .wash: .cyan
        case .insurance: .indigo
        case .tax: .brown
        case .parking: .purple
        case .fines: .pink
        case .other: .secondary
        }
    }
}

@Model
final class Expense {
    var date: Date
    var categoryRaw: String
    var amount: Double
    var liters: Double?
    var odometer: Int?
    var note: String
    @Attribute(.externalStorage) var photo: Data?
    var createdAt: Date

    init(date: Date, category: ExpenseCategory, amount: Double, liters: Double? = nil,
         odometer: Int? = nil, note: String = "", photo: Data? = nil) {
        self.date = date
        self.categoryRaw = category.rawValue
        self.amount = amount
        self.liters = liters
        self.odometer = odometer
        self.note = note
        self.photo = photo
        self.createdAt = .now
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

// MARK: - Напоминание

enum ReminderKind: String, CaseIterable, Identifiable {
    case service, tuv, insurance, tires, oil, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .service: "ТО"
        case .tuv: "TÜV / техосмотр"
        case .insurance: "Страховка"
        case .tires: "Смена шин"
        case .oil: "Замена масла"
        case .other: "Другое"
        }
    }

    var icon: String {
        switch self {
        case .service: "wrench.and.screwdriver.fill"
        case .tuv: "checkmark.seal.fill"
        case .insurance: "shield.fill"
        case .tires: "snowflake"
        case .oil: "drop.halffull"
        case .other: "bell.fill"
        }
    }
}

@Model
final class Reminder {
    var title: String
    var kindRaw: String
    var dueDate: Date?
    var dueOdometer: Int?
    var done: Bool
    var notificationID: String
    var createdAt: Date

    init(title: String, kind: ReminderKind, dueDate: Date?, dueOdometer: Int?) {
        self.title = title
        self.kindRaw = kind.rawValue
        self.dueDate = dueDate
        self.dueOdometer = dueOdometer
        self.done = false
        self.notificationID = UUID().uuidString
        self.createdAt = .now
    }

    var kind: ReminderKind { ReminderKind(rawValue: kindRaw) ?? .other }
}
