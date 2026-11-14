import SwiftData
import SwiftUI

@main
struct AutoNoteApp: App {
    let container: ModelContainer

    init() {
        // `-demo YES` — тестовые данные в памяти (для скриншотов), настоящие записи не трогаются
        let demo = UserDefaults.standard.bool(forKey: "demo")
        let config = ModelConfiguration(isStoredInMemoryOnly: demo)
        do {
            container = try ModelContainer(for: Car.self, Expense.self, Reminder.self, RecurringPayment.self,
                                           configurations: config)
        } catch {
            fatalError("Не получилось открыть базу: \(error)")
        }
        if demo && !UserDefaults.standard.bool(forKey: "onboarding") {
            DemoData.seed(container.mainContext)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Car.createdAt) private var cars: [Car]
    @State private var tab = UserDefaults.standard.integer(forKey: "tab")
    @AppStorage("welcomeSeen") private var welcomeSeen = false

    var body: some View {
        if let car = cars.first {
            TabView(selection: $tab) {
                DashboardView(car: car)
                    .tabItem { Label("Главная", systemImage: "gauge.with.dots.needle.33percent") }
                    .tag(0)
                HistoryView(car: car)
                    .tabItem { Label("История", systemImage: "list.bullet.rectangle") }
                    .tag(1)
                RemindersView(car: car)
                    .tabItem { Label("Напоминания", systemImage: "bell") }
                    .tag(2)
                SettingsView(car: car)
                    .tabItem { Label("Настройки", systemImage: "gearshape") }
                    .tag(3)
            }
            // постоянные платежи, день которых наступил, сами попадают в историю
            .onAppear { Recurring.catchUp(context) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Recurring.catchUp(context) }
            }
        } else if welcomeSeen {
            OnboardingView()
        } else {
            WelcomeView { withAnimation { welcomeSeen = true } }
        }
    }
}
