import SwiftUI
import UIKit

// Тип кузова — от него зависит рисованный силуэт машины
enum BodyType: String, CaseIterable, Identifiable {
    case hatchback, sedan, wagon, suv, coupe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hatchback: "Хэтчбек"
        case .sedan: "Седан"
        case .wagon: "Универсал"
        case .suv: "Внедорожник"
        case .coupe: "Купе"
        }
    }

    // Угадываем кузов по названию модели; не угадали — хэтчбек (поменять можно в меню)
    static func guess(model: String) -> BodyType {
        let m = model.lowercased()
        let words = m.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        func has(_ list: [String]) -> Bool { list.contains { m.contains($0) } }

        if has(["avant", "variant", "kombi", "touring", "estate", "wagon", "tourer", "combi", "allroad"]) { return .wagon }
        let suvCode = words.contains { w in
            w.count == 2 && (w.hasPrefix("q") || w.hasPrefix("x")) && (w.last?.isNumber ?? false)
        }
        if suvCode || has(["tiguan", "touareg", "t-roc", "rav4", "cr-v", "kuga", "sportage", "tucson", "qashqai",
                           "x-trail", "duster", "kodiaq", "karoq", "glc", "gle", "gls", "cayenne", "macan",
                           "range", "evoque", "outlander", "cx-", "santa", "land cruiser", "wrangler", "suv"]) {
            return .suv
        }
        if has(["coupe", "coupé", "mustang", "camaro", "911", "z4"]) || words.contains("tt") { return .coupe }
        if has(["sedan", "limousine", "passat", "jetta", "camry", "c-klasse", "e-klasse", "s-klasse"])
            || words.contains(where: { ["a4", "a6", "a8", "3er", "5er", "7er"].contains($0) }) {
            return .sedan
        }
        return .hatchback
    }
}

// Аккуратная рисованная машина сбоку — в цвете и кузове твоей машины.
// Рисуется в системе координат 100 × 40, нос машины смотрит вправо.
struct CarSilhouette: View {
    let kind: BodyType
    let color: CarColor

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / 100, size.height / 40)
            let ox = (size.width - 100 * s) / 2, oy = (size.height - 40 * s) / 2
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
            let g = CarShape.of(kind)
            let base = UIColor(color.swatch)

            // тень под машиной
            ctx.fill(Path(ellipseIn: CGRect(x: ox + 7 * s, y: oy + 37.6 * s, width: 86 * s, height: 2.4 * s)),
                     with: .color(.black.opacity(0.3)))

            // кузов: верх — плавная линия, низ — с арками колёс
            var shell = smoothPath(g.outline.map { P($0.x, $0.y) }, closed: false)
            let ar = g.wheelR + 1.5
            func arch(_ cx: CGFloat) {
                shell.addLine(to: P(cx + ar, g.bottomY))
                shell.addCurve(to: P(cx - ar, g.bottomY),
                              control1: P(cx + ar, g.bottomY - ar * 4 / 3),
                              control2: P(cx - ar, g.bottomY - ar * 4 / 3))
            }
            arch(78)
            arch(22)
            shell.closeSubpath()
            ctx.fill(shell, with: .linearGradient(
                Gradient(colors: [Color(base.shaded(1.3, plus: 0.1)), Color(base), Color(base.shaded(0.62))]),
                startPoint: P(50, g.outline.map(\.y).min() ?? 8), endPoint: P(50, 33)))
            ctx.stroke(shell, with: .color(Color.primary.opacity(0.16)), lineWidth: 0.35 * s)

            // блик по линии плеча
            var shoulder = Path()
            shoulder.move(to: P(g.window.first!.x - 2, g.beltY + 2.4))
            shoulder.addLine(to: P(88, g.beltY + 3.6))
            ctx.stroke(shoulder, with: .color(.white.opacity(0.22)), lineWidth: 0.45 * s)

            // стёкла и стойка между дверями
            let glass = smoothPath(g.window.map { P($0.x, $0.y) }, closed: true, k: 0.55)
            ctx.fill(glass, with: .linearGradient(
                Gradient(colors: [Color(red: 0.30, green: 0.36, blue: 0.42), Color(red: 0.10, green: 0.13, blue: 0.17)]),
                startPoint: P(50, g.beltY - 8), endPoint: P(50, g.beltY)))
            var pillar = Path()
            pillar.move(to: P(g.pillarX + 1.2, g.beltY - 9))
            pillar.addLine(to: P(g.pillarX, g.beltY + 0.5))
            ctx.stroke(pillar, with: .color(Color(base)), lineWidth: 1.7 * s)

            // линии дверей и ручки
            var doors = Path()
            doors.move(to: P(g.pillarX, g.beltY)); doors.addLine(to: P(g.pillarX - 0.6, 30.5))
            doors.move(to: P(g.frontDoorX, g.beltY)); doors.addLine(to: P(g.frontDoorX + 1.2, 25))
            doors.addLine(to: P(g.frontDoorX - 0.4, 30.5))
            ctx.stroke(doors, with: .color(.black.opacity(0.25)), lineWidth: 0.35 * s)
            for hx in [g.pillarX - 8, g.pillarX + 12] {
                ctx.fill(Path(roundedRect: CGRect(x: ox + hx * s, y: oy + (g.beltY + 2.6) * s, width: 3.4 * s, height: 0.9 * s),
                              cornerRadius: 0.45 * s), with: .color(.black.opacity(0.3)))
            }

            // зеркало, фары, фонари
            ctx.fill(Path(ellipseIn: CGRect(x: ox + (g.frontDoorX - 1.6) * s, y: oy + (g.beltY - 1.6) * s,
                                            width: 3 * s, height: 1.8 * s)),
                     with: .color(Color(base.shaded(0.75))))
            ctx.fill(Path(roundedRect: CGRect(x: ox + g.head.x * s, y: oy + g.head.y * s, width: 6 * s, height: 1.9 * s),
                          cornerRadius: 0.9 * s), with: .color(Color(white: 0.93)))
            ctx.fill(Path(roundedRect: CGRect(x: ox + g.tail.x * s, y: oy + g.tail.y * s, width: 3.4 * s, height: 2.2 * s),
                          cornerRadius: 0.8 * s), with: .color(Color(red: 0.85, green: 0.12, blue: 0.12)))

            // колёса
            let wheelXs: [CGFloat] = [22, 78]
            for cx in wheelXs {
                let c = P(cx, g.wheelY), r = g.wheelR * s
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(Color(white: 0.09)))
                let rr = r * 0.63
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr)),
                         with: .linearGradient(Gradient(colors: [Color(white: 0.88), Color(white: 0.52)]),
                                               startPoint: CGPoint(x: c.x, y: c.y - rr), endPoint: CGPoint(x: c.x, y: c.y + rr)))
                var spokes = Path()
                for i in 0..<5 {
                    let a = Double(i) * 2 * .pi / 5 - .pi / 2
                    spokes.move(to: c)
                    spokes.addLine(to: CGPoint(x: c.x + rr * 0.92 * cos(a), y: c.y + rr * 0.92 * sin(a)))
                }
                ctx.stroke(spokes, with: .color(Color(white: 0.32)), lineWidth: 0.55 * s)
                let hub = r * 0.14
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - hub, y: c.y - hub, width: 2 * hub, height: 2 * hub)),
                         with: .color(Color(white: 0.25)))
            }
        }
        .aspectRatio(100 / 40, contentMode: .fit)
        .accessibilityLabel("\(color.title) \(kind.title.lowercased())")
    }
}

// Форма кузова: точки контура в системе 100 × 40
private struct CarShape {
    let outline: [CGPoint]   // верх кузова: от заднего низа к переднему низу
    let window: [CGPoint]
    let beltY: CGFloat       // нижний край стёкол
    let pillarX: CGFloat     // стойка между дверями
    let frontDoorX: CGFloat  // передний край передней двери
    let head: CGPoint        // фара (левый верхний угол)
    let tail: CGPoint        // фонарь
    var wheelR: CGFloat = 6.3
    var wheelY: CGFloat = 32.6
    var bottomY: CGFloat = 32

    static func of(_ kind: BodyType) -> CarShape {
        func pts(_ a: [(CGFloat, CGFloat)]) -> [CGPoint] { a.map { CGPoint(x: $0.0, y: $0.1) } }
        // общий «нос»: капот и бампер
        let nose: [(CGFloat, CGFloat)] = [(66, 17.5), (80, 19), (92, 21), (97, 25), (97, 30), (95, 32)]
        switch kind {
        case .hatchback:
            return CarShape(outline: pts([(4, 31), (3, 25), (5, 17), (9, 12), (16, 9), (34, 8), (50, 8.5), (58, 12)] + nose),
                            window: pts([(11, 16.8), (15, 11.2), (34, 10), (50, 10.5), (57, 13.5), (62, 16.8)]),
                            beltY: 16.8, pillarX: 36, frontDoorX: 61.5,
                            head: CGPoint(x: 87, y: 22), tail: CGPoint(x: 5.4, y: 17.6))
        case .sedan:
            return CarShape(outline: pts([(3, 31), (2, 25), (3, 20), (14, 18.5), (22, 16), (30, 9.5), (48, 8.5), (57, 11)] + nose),
                            window: pts([(24, 16.8), (31, 11), (48, 10.3), (55.5, 12.8), (62, 16.8)]),
                            beltY: 16.8, pillarX: 40, frontDoorX: 61.5,
                            head: CGPoint(x: 87, y: 22), tail: CGPoint(x: 3.2, y: 20.4))
        case .wagon:
            return CarShape(outline: pts([(3, 31), (2, 25), (3, 15), (6, 10), (14, 8), (50, 8), (58, 11.5)] + nose),
                            window: pts([(6, 16.8), (8, 11.5), (15, 10), (50, 10), (57, 13.5), (62, 16.8)]),
                            beltY: 16.8, pillarX: 37, frontDoorX: 61.5,
                            head: CGPoint(x: 87, y: 22), tail: CGPoint(x: 3.2, y: 16.6))
        case .suv:
            return CarShape(outline: pts([(3, 31), (2, 22), (3, 12), (7, 6), (14, 5), (52, 5), (60, 8.5), (67, 14),
                                          (82, 15.5), (93, 17), (97, 21), (97, 30), (95, 31)]),
                            window: pts([(6, 13.5), (9, 8), (15, 7), (52, 7), (59.5, 10.5), (64, 13.5)]),
                            beltY: 13.5, pillarX: 37, frontDoorX: 63,
                            head: CGPoint(x: 88, y: 17.6), tail: CGPoint(x: 3, y: 13.6),
                            wheelR: 7, wheelY: 31.8, bottomY: 31)
        case .coupe:
            return CarShape(outline: pts([(4, 31), (3, 24), (5, 18.5), (14, 15.5), (26, 9.5), (44, 8.5), (56, 12)] + nose),
                            window: pts([(20, 16.8), (28, 11.2), (44, 10.4), (54.5, 13), (61, 16.8)]),
                            beltY: 16.8, pillarX: 34, frontDoorX: 61,
                            head: CGPoint(x: 87, y: 22), tail: CGPoint(x: 4.2, y: 18.8))
        }
    }
}

// Плавная кривая через точки (Catmull-Rom → кривые Безье)
private func smoothPath(_ pts: [CGPoint], closed: Bool, k: CGFloat = 0.85) -> Path {
    var p = Path()
    guard pts.count > 1 else { return p }
    let n = pts.count
    func pt(_ i: Int) -> CGPoint { closed ? pts[(i % n + n) % n] : pts[min(max(i, 0), n - 1)] }
    p.move(to: pts[0])
    for i in 0..<(closed ? n : n - 1) {
        let p0 = pt(i - 1), p1 = pt(i), p2 = pt(i + 1), p3 = pt(i + 2)
        let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6 * k, y: p1.y + (p2.y - p0.y) / 6 * k)
        let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6 * k, y: p2.y - (p3.y - p1.y) / 6 * k)
        p.addCurve(to: p2, control1: c1, control2: c2)
    }
    if closed { p.closeSubpath() }
    return p
}

private extension UIColor {
    // светлее/темнее того же оттенка
    func shaded(_ k: CGFloat, plus: CGFloat = 0) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
            return UIColor(hue: h, saturation: s, brightness: min(1, b * k + plus), alpha: a)
        }
        var w: CGFloat = 0
        if getWhite(&w, alpha: &a) { return UIColor(white: min(1, w * k + plus), alpha: a) }
        return self
    }
}
