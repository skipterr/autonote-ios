import SwiftData
import SwiftUI

@main
struct AutoNoteApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Car.self, Expense.self, Reminder.self])
    }
}

struct RootView: View {
    @Query(sort: \Car.createdAt) private var cars: [Car]

    var body: some View {
        if let car = cars.first {
            TabView {
                DashboardView(car: car)
                    .tabItem { Label("Главная", systemImage: "gauge.with.dots.needle.33percent") }
                HistoryView(car: car)
                    .tabItem { Label("История", systemImage: "list.bullet.rectangle") }
                RemindersView(car: car)
                    .tabItem { Label("Напоминания", systemImage: "bell") }
                SettingsView(car: car)
                    .tabItem { Label("Настройки", systemImage: "gearshape") }
            }
        } else {
            OnboardingView()
        }
    }
}
