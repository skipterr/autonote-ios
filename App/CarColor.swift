import SwiftUI

// Цвет машины — чтобы картинка в гараже была похожа на твою
enum CarColor: String, CaseIterable, Identifiable {
    case black, white, silver, graphite, blue, red, green, beige, brown, yellow, orange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: "Чёрный"
        case .white: "Белый"
        case .silver: "Серебристый"
        case .graphite: "Тёмно-серый"
        case .blue: "Синий"
        case .red: "Красный"
        case .green: "Зелёный"
        case .beige: "Бежевый"
        case .brown: "Коричневый"
        case .yellow: "Жёлтый"
        case .orange: "Оранжевый"
        }
    }

    // как назвать цвет для ИИ
    var prompt: String {
        switch self {
        case .black: "glossy black"
        case .white: "pure white"
        case .silver: "metallic silver"
        case .graphite: "dark graphite grey metallic"
        case .blue: "deep blue metallic"
        case .red: "bright red"
        case .green: "dark green metallic"
        case .beige: "beige"
        case .brown: "brown metallic"
        case .yellow: "yellow"
        case .orange: "orange"
        }
    }

    var swatch: Color {
        switch self {
        case .black: Color(white: 0.08)
        case .white: Color(white: 0.97)
        case .silver: Color(white: 0.75)
        case .graphite: Color(white: 0.33)
        case .blue: Color(red: 0.10, green: 0.25, blue: 0.60)
        case .red: Color(red: 0.80, green: 0.10, blue: 0.12)
        case .green: Color(red: 0.10, green: 0.35, blue: 0.22)
        case .beige: Color(red: 0.85, green: 0.78, blue: 0.64)
        case .brown: Color(red: 0.40, green: 0.26, blue: 0.16)
        case .yellow: Color(red: 0.98, green: 0.82, blue: 0.10)
        case .orange: Color(red: 0.95, green: 0.50, blue: 0.10)
        }
    }
}
