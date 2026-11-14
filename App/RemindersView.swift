import SwiftData
import SwiftUI

extension Reminder {
    // Чем меньше — тем срочнее. Дата и пробег сводятся к «дням»: ~40 км в день.
    func urgency(odometer: Int) -> Double {
        var u = Double.greatestFiniteMagnitude
        if let d = dueDate { u = min(u, d.timeIntervalSinceNow / 86400) }
        if let km = dueOdometer { u = min(u, Double(km - odometer) / 40) }
        return u
    }

    func isOverdue(odometer: Int) -> Bool { urgency(odometer: odometer) < 0 }

    func statusText(odometer: Int) -> String {
        var parts: [String] = []
        if let d = dueDate {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                                       to: Calendar.current.startOfDay(for: d)).day ?? 0
            if days < 0 { parts.append("просрочено на \(-days) дн.") }
            else if days == 0 { parts.append("сегодня") }
            else { parts.append("через \(days) дн. · \(Fmt.shortDate(d))") }
        }
        if let km = dueOdometer {
            let left = km - odometer
            parts.append(left < 0 ? "пробег превышен на \(Fmt.km(-left))" : "через \(Fmt.km(left))")
        }
        return parts.joined(separator: " · ")
    }
}

struct ReminderRow: View {
    let reminder: Reminder
    let odometer: Int

    var body: some View {
        let overdue = reminder.isOverdue(odometer: odometer)
        let soon = reminder.urgency(odometer: odometer) < 14
        HStack(spacing: 12) {
            Image(systemName: reminder.kind.icon)
                .foregroundStyle(overdue ? Color.red : (soon ? Color.orange : Color.accentColor))
                .frame(width: 36, height: 36)
                .background((overdue ? Color.red : (soon ? Color.orange : Color.accentColor)).opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .strikethrough(reminder.done)
                Text(reminder.statusText(odometer: odometer))
                    .font(.caption)
                    .foregroundStyle(overdue ? Color.red : Color.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

struct RemindersView: View {
    let car: Car
    @Environment(\.modelContext) private var context
    @Query private var reminders: [Reminder]
    @Query private var expenses: [Expense]
    @State private var editing: Reminder?
    @State private var creating = false

    private var odometer: Int { Stats(car: car, expenses: expenses).currentOdometer }

    var body: some View {
        let odo = odometer
        let active = reminders.filter { !$0.done }.sorted { $0.urgency(odometer: odo) < $1.urgency(odometer: odo) }
        let done = reminders.filter(\.done).sorted { $0.createdAt > $1.createdAt }

        NavigationStack {
            List {
                if reminders.isEmpty {
                    ContentUnavailableView("Нет напоминаний", systemImage: "bell",
                                           description: Text("Добавь ТО, TÜV, страховку или смену шин — приложение напомнит заранее."))
                        .listRowBackground(Color.clear)
                }
                if !active.isEmpty {
                    Section("Впереди") {
                        ForEach(active) { r in
                            Button { editing = r } label: { ReminderRow(reminder: r, odometer: odo) }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading) {
                                    Button("Сделано") {
                                        r.done = true
                                        Notifications.cancel(r)
                                        try? context.save()
                                    }
                                    .tint(.green)
                                }
                                .swipeActions {
                                    Button("Удалить", role: .destructive) { delete(r) }
                                }
                        }
                    }
                }
                if !done.isEmpty {
                    Section("Сделано") {
                        ForEach(done) { r in
                            ReminderRow(reminder: r, odometer: odo)
                                .opacity(0.6)
                                .swipeActions {
                                    Button("Удалить", role: .destructive) { delete(r) }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Напоминания")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                }
            }
            .sheet(isPresented: $creating) { ReminderEditor(reminder: nil, odometer: odo) }
            .sheet(item: $editing) { r in ReminderEditor(reminder: r, odometer: odo) }
        }
    }

    private func delete(_ r: Reminder) {
        Notifications.cancel(r)
        context.delete(r)
        try? context.save()
    }
}

struct ReminderEditor: View {
    let reminder: Reminder?
    let odometer: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var kind: ReminderKind = .service
    @State private var title = ReminderKind.service.title
    @State private var byDate = true
    @State private var date = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var byKm = false
    @State private var kmText = ""
    @State private var loaded = false

    private var km: Int? { Int(kmText.filter(\.isNumber)) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Что") {
                    Picker("Тип", selection: $kind) {
                        ForEach(ReminderKind.allCases) { k in
                            Label(k.title, systemImage: k.icon).tag(k)
                        }
                    }
                    .onChange(of: kind) { old, new in
                        // название меняем, только если человек его не трогал
                        if title.isEmpty || title == old.title { title = new.title }
                    }
                    TextField("Название", text: $title)
                }

                Section {
                    Toggle("По дате", isOn: $byDate)
                    if byDate {
                        DatePicker("Когда", selection: $date, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "ru_RU"))
                    }
                } footer: {
                    if byDate { Text("Пришлю уведомление за неделю и в сам день, в 10:00.") }
                }

                Section {
                    Toggle("По пробегу", isOn: $byKm)
                    if byKm {
                        HStack {
                            Text("На пробеге")
                            TextField(String(odometer + 15000), text: $kmText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                            Text("км").foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    if byKm { Text("Сейчас пробег ~\(Fmt.km(odometer)). Покажу на главной, когда останется мало.") }
                }

                if let reminder {
                    Section {
                        if !reminder.done {
                            Button("Отметить как сделанное") {
                                reminder.done = true
                                Notifications.cancel(reminder)
                                try? context.save()
                                dismiss()
                            }
                        }
                        Button("Удалить", role: .destructive) {
                            Notifications.cancel(reminder)
                            context.delete(reminder)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(reminder == nil ? "Новое напоминание" : "Напоминание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .bold()
                        .disabled(title.trimmed.isEmpty || (!byDate && !(byKm && km != nil)))
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let r = reminder {
                    kind = r.kind
                    title = r.title
                    byDate = r.dueDate != nil
                    if let d = r.dueDate { date = d }
                    byKm = r.dueOdometer != nil
                    kmText = r.dueOdometer.map(String.init) ?? ""
                }
            }
        }
    }

    private func save() {
        let r: Reminder
        if let existing = reminder {
            r = existing
            r.title = title.trimmed
            r.kindRaw = kind.rawValue
        } else {
            r = Reminder(title: title.trimmed, kind: kind, dueDate: nil, dueOdometer: nil)
            context.insert(r)
        }
        r.dueDate = byDate ? date : nil
        r.dueOdometer = byKm ? km : nil
        r.done = false
        try? context.save()
        Task { await Notifications.schedule(r) }
        dismiss()
    }
}
