import SwiftUI

// Знакомство с приложением: слайды с живыми иллюстрациями, листаются свайпом или кнопкой.
struct WelcomeView: View {
    var onDone: () -> Void

    @State private var page = min(max(UserDefaults.standard.integer(forKey: "welcomePage"), 0), WelcomePage.all.count - 1)
    private let pages = WelcomePage.all

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    WelcomeSlide(page: pages[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 18) {
                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: i == page ? 20 : 7, height: 7)
                    }
                }
                .animation(.spring(duration: 0.3), value: page)

                Button {
                    if page < pages.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onDone()
                    }
                } label: {
                    Text(page < pages.count - 1 ? "Далее" : "Начать")
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(WelcomePage.gradient, in: Capsule())
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .padding(.top, 4)
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .topTrailing) {
            if page < pages.count - 1 {
                Button("Пропустить") { onDone() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.18), in: Capsule())
                    .padding(.trailing, 16)
                    .padding(.top, 8)
            }
        }
    }
}

struct WelcomePage {
    let title: String
    let text: String
    let symbol: String          // значки, которые плавают на фоне
    let demo: Demo

    enum Demo { case intro, receipt, voice, stats, payments, reminders }

    static let gradient = LinearGradient(
        colors: [Color(red: 0.07, green: 0.58, blue: 0.52), Color(red: 0.06, green: 0.27, blue: 0.40)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let all: [WelcomePage] = [
        .init(title: "AutoNote — твой помощник",
              text: "Все расходы на машину в одном месте: заправки, ремонт, страховка, мойка. Your car — your price.",
              symbol: "car.fill", demo: .intro),
        .init(title: "Сфоткал чек — готово",
              text: "Наведи камеру на чек с заправки или из сервиса. Сумму, литры и дату приложение заполнит само.",
              symbol: "camera.fill", demo: .receipt),
        .init(title: "Или просто скажи",
              text: "«Заправился на 60 евро, 40 литров» — и запись готова. Никаких форм и таблиц.",
              symbol: "mic.fill", demo: .voice),
        .init(title: "Сколько стоит машина на самом деле",
              text: "Цена каждого километра, расход топлива и траты за месяц — посчитано автоматически.",
              symbol: "eurosign.circle.fill", demo: .stats),
        .init(title: "Постоянные платежи",
              text: "Страховка, налог, кредит — добавь один раз, и они будут записываться сами в нужный день.",
              symbol: "repeat", demo: .payments),
        .init(title: "Ничего не забудешь",
              text: "Напомню про ТО, TÜV, страховку и смену шин заранее — по дате или по пробегу.",
              symbol: "bell.fill", demo: .reminders),
    ]
}

// MARK: - Слайд

private struct WelcomeSlide: View {
    let page: WelcomePage

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                WelcomePage.gradient
                FloatingSymbols(symbol: page.symbol)
                PhoneMock { DemoScreen(demo: page.demo) }
                    .padding(.top, 50)
            }
            .frame(maxHeight: .infinity)
            .clipped()

            VStack(spacing: 10) {
                Text(page.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(page.text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 8)
            .frame(height: 170, alignment: .top)
        }
    }
}

// Значки, которые медленно покачиваются на фоне
private struct FloatingSymbols: View {
    let symbol: String
    private let spots: [(CGFloat, CGFloat, CGFloat, Double)] = [
        (0.08, 0.22, 26, 0.0), (0.90, 0.18, 22, 1.3), (0.15, 0.55, 18, 2.1), (0.86, 0.48, 28, 0.7),
        (0.06, 0.85, 24, 1.8), (0.93, 0.80, 18, 2.6), (0.25, 0.10, 16, 3.1), (0.75, 0.92, 20, 0.4),
    ]

    var body: some View {
        GeometryReader { g in
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(spots.indices, id: \.self) { i in
                        let s = spots[i]
                        Image(systemName: symbol)
                            .font(.system(size: s.2, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.22))
                            .rotationEffect(.degrees(sin(t * 0.6 + s.3) * 12))
                            .position(x: g.size.width * s.0,
                                      y: g.size.height * s.1 + CGFloat(sin(t * 0.8 + s.3) * 8))
                    }
                }
            }
        }
    }
}

// Рамка «телефона», обрезанная снизу — как витрина
private struct PhoneMock<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: 230, height: 420, alignment: .top)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Color.black.opacity(0.85), lineWidth: 7)
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Живые экраны внутри «телефона»

private struct DemoScreen: View {
    let demo: WelcomePage.Demo

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let p = t.truncatingRemainder(dividingBy: 4) / 4        // 0…1 за 4 секунды, по кругу
            VStack(spacing: 10) {
                Capsule().fill(Color.black.opacity(0.85)).frame(width: 70, height: 20).padding(.top, 10)
                switch demo {
                case .intro: intro(p)
                case .receipt: receipt(p)
                case .voice: voice(p)
                case .stats: stats(p)
                case .payments: payments(p)
                case .reminders: reminders(p)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func ease(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }

    // 1. Мини-главная: сумма месяца набегает
    @ViewBuilder private func intro(_ p: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Расходы за месяц").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.85))
            Text(Fmt.money(386.15 * ease(p * 2))).font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(WelcomePage.gradient, in: RoundedRectangle(cornerRadius: 14))
        ForEach(Array(sample.enumerated()), id: \.offset) { i, row in
            miniRow(row.0, row.1, row.2, row.3)
                .opacity(ease((p - 0.15 * Double(i)) * 4))
                .offset(y: (1 - ease((p - 0.15 * Double(i)) * 4)) * 12)
        }
    }

    private var sample: [(String, String, String, Color)] {
        [("fuelpump.fill", "Aral, дизель", "64,30 €", .orange),
         ("drop.fill", "Мойка", "12,00 €", .cyan),
         ("wrench.and.screwdriver.fill", "Замена масла", "189,00 €", .blue),
         ("shield.fill", "Страховка", "57,00 €", .indigo)]
    }

    private func miniRow(_ icon: String, _ title: String, _ sum: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(color)
                .frame(width: 24, height: 24).background(color.opacity(0.15), in: Circle())
            Text(title).font(.system(size: 11))
            Spacer()
            Text(sum).font(.system(size: 11, weight: .semibold))
        }
        .padding(8)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    // 2. Чек сканируется, потом появляется готовая запись
    @ViewBuilder private func receipt(_ p: Double) -> some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ARAL").font(.system(size: 13, weight: .heavy))
                ForEach(0..<6, id: \.self) { i in
                    HStack {
                        RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.35)).frame(width: CGFloat(60 + i * 9 % 40), height: 5)
                        Spacer()
                        RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.35)).frame(width: 26, height: 5)
                    }
                }
                Divider()
                HStack { Text("SUMME").font(.system(size: 10, weight: .bold)); Spacer(); Text("64,30 €").font(.system(size: 10, weight: .bold)) }
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(Color.black)

            Rectangle()
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0), Color.accentColor.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                .frame(height: 24)
                .offset(y: CGFloat(ease(p * 2)) * 150)
                .opacity(p < 0.5 ? 1 : 0)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 2).padding(-6))
        .padding(.top, 6)

        VStack(spacing: 6) {
            chip("fuelpump.fill", "Топливо", .orange)
            chip("eurosign", "64,30 €", .accentColor)
            chip("drop.halffull", "38,2 л", .blue)
        }
        .opacity(ease((p - 0.5) * 5))
        .offset(y: (1 - ease((p - 0.5) * 5)) * 16)
    }

    private func chip(_ icon: String, _ text: String, _ color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    // 3. Голос: пульсирующий микрофон и текст, который «печатается»
    @ViewBuilder private func voice(_ p: Double) -> some View {
        let phrase = "Заправился на 60 евро, 40 литров"
        let shown = String(phrase.prefix(Int(Double(phrase.count) * min(1, p * 1.6))))
        Spacer().frame(height: 30)
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 2)
                    .frame(width: 70, height: 70)
                    .scaleEffect(1 + CGFloat((p * 3 + Double(i) / 3).truncatingRemainder(dividingBy: 1)) * 0.9)
                    .opacity(1 - (p * 3 + Double(i) / 3).truncatingRemainder(dividingBy: 1))
            }
            Image(systemName: "mic.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.white)
                .frame(width: 70, height: 70)
                .background(WelcomePage.gradient, in: Circle())
        }
        .frame(height: 140)
        Text("«\(shown)»")
            .font(.system(size: 14, weight: .medium))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(10)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        chip("checkmark.circle.fill", "Записано: топливо, 60 €", .green)
            .opacity(ease((p - 0.7) * 6))
    }

    // 4. Цифры: цена км и расход
    @ViewBuilder private func stats(_ p: Double) -> some View {
        let k = ease(p * 1.6)
        HStack(spacing: 8) {
            tile("Цена км", Fmt.money(0.33 * k), "eurosign.circle")
            tile("Расход", Fmt.number(6.1 * k) + " л", "fuelpump")
        }
        HStack(spacing: 8) {
            tile("В месяц", Fmt.money(329 * k, decimals: 0), "calendar")
            tile("Проехал", Fmt.km(Int(2950 * k)), "flag.checkered")
        }
        VStack(alignment: .leading, spacing: 6) {
            bar("Топливо", 0.8 * k, .orange)
            bar("ТО", 0.45 * k, .blue)
            bar("Мойка", 0.15 * k, .cyan)
        }
        .padding(10)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func tile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func bar(_ title: String, _ v: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            GeometryReader { g in
                Capsule().fill(color).frame(width: max(4, g.size.width * CGFloat(v)))
            }
            .frame(height: 5)
        }
    }

    // 5. Постоянные платежи появляются по очереди
    @ViewBuilder private func payments(_ p: Double) -> some View {
        let rows: [(String, String, String, String, Color)] = [
            ("shield.fill", "Страховка", "57 €", "в месяц", .indigo),
            ("building.columns.fill", "Налог на авто", "146 €", "в год", .brown),
            ("creditcard.fill", "Кредит", "210 €", "в месяц", .teal),
        ]
        Text("Постоянные платежи").font(.system(size: 13, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        ForEach(rows.indices, id: \.self) { i in
            let r = rows[i]
            HStack(spacing: 8) {
                Image(systemName: r.0).font(.system(size: 11)).foregroundStyle(r.4)
                    .frame(width: 26, height: 26).background(r.4.opacity(0.15), in: Circle())
                Text(r.1).font(.system(size: 11))
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(r.2).font(.system(size: 11, weight: .semibold))
                    Text(r.3).font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
            .opacity(ease((p - 0.18 * Double(i)) * 4))
            .offset(x: (1 - ease((p - 0.18 * Double(i)) * 4)) * 40)
        }
        HStack {
            Text("В среднем в месяц").font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Text("279,17 €").font(.system(size: 12, weight: .bold))
        }
        .padding(.horizontal, 6)
        .opacity(ease((p - 0.6) * 5))
    }

    // 6. Уведомления «падают» сверху
    @ViewBuilder private func reminders(_ p: Double) -> some View {
        let items: [(String, String)] = [
            ("Через неделю: TÜV", "8 декабря"),
            ("Сегодня платёж: Страховка, 57 €", "10:00"),
            ("Скоро ТО: осталось 950 км", "по пробегу"),
        ]
        Spacer().frame(height: 10)
        ForEach(items.indices, id: \.self) { i in
            let k = ease((p - 0.2 * Double(i)) * 4)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "car.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 26, height: 26)
                    .background(WelcomePage.gradient, in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text("AutoNote").font(.system(size: 10, weight: .semibold))
                        Spacer()
                        Text(items[i].1).font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                    Text(items[i].0).font(.system(size: 11))
                }
            }
            .padding(9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .opacity(k)
            .offset(y: (1 - k) * -30)
            .scaleEffect(0.9 + 0.1 * k)
        }
    }
}
