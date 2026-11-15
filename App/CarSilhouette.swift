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
            CarPainter(ctx: ctx, size: size, shape: CarShape.of(kind), base: UIColor(color.swatch)).draw()
        }
        .aspectRatio(100 / 40, contentMode: .fit)
        .accessibilityLabel("\(color.title) \(kind.title.lowercased())")
    }
}

// Рисование разбито на маленькие шаги — так компилятору проще
private struct CarPainter {
    var ctx: GraphicsContext
    let shape: CarShape
    let base: UIColor
    let s: CGFloat
    let ox: CGFloat
    let oy: CGFloat

    init(ctx: GraphicsContext, size: CGSize, shape: CarShape, base: UIColor) {
        self.ctx = ctx
        self.shape = shape
        self.base = base
        let scale: CGFloat = min(size.width / 100, size.height / 40)
        s = scale
        ox = (size.width - 100 * scale) / 2
        oy = (size.height - 40 * scale) / 2
    }

    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s)
    }

    func draw() {
        drawShadow()
        drawShell()
        drawGlass()
        drawDetails()
        drawWheel(22)
        drawWheel(78)
    }

    func drawShadow() {
        ctx.fill(Path(ellipseIn: R(7, 37.6, 86, 2.4)), with: .color(Color.black.opacity(0.3)))
    }

    func shellPath() -> Path {
        let pts: [CGPoint] = shape.outline.map { P($0.x, $0.y) }
        var path: Path = smoothPath(pts, closed: false)
        let ar: CGFloat = shape.wheelR + 1.5
        let by: CGFloat = shape.bottomY
        let lift: CGFloat = by - ar * 4 / 3
        for cx in [CGFloat(78), CGFloat(22)] {
            path.addLine(to: P(cx + ar, by))
            path.addCurve(to: P(cx - ar, by), control1: P(cx + ar, lift), control2: P(cx - ar, lift))
        }
        path.closeSubpath()
        return path
    }

    func drawShell() {
        let path = shellPath()
        let top: CGFloat = shape.outline.map(\.y).min() ?? 8
        let light = Color(base.shaded(1.3, plus: 0.1))
        let dark = Color(base.shaded(0.62))
        let gradient = Gradient(colors: [light, Color(base), dark])
        ctx.fill(path, with: .linearGradient(gradient, startPoint: P(50, top), endPoint: P(50, 33)))
        ctx.stroke(path, with: .color(Color.primary.opacity(0.16)), lineWidth: 0.35 * s)

        var shoulder = Path()
        let startX: CGFloat = (shape.window.first?.x ?? 10) - 2
        shoulder.move(to: P(startX, shape.beltY + 2.4))
        shoulder.addLine(to: P(88, shape.beltY + 3.6))
        ctx.stroke(shoulder, with: .color(Color.white.opacity(0.22)), lineWidth: 0.45 * s)
    }

    func drawGlass() {
        let pts: [CGPoint] = shape.window.map { P($0.x, $0.y) }
        let glass: Path = smoothPath(pts, closed: true, k: 0.55)
        let top = Color(red: 0.30, green: 0.36, blue: 0.42)
        let bottom = Color(red: 0.10, green: 0.13, blue: 0.17)
        ctx.fill(glass, with: .linearGradient(Gradient(colors: [top, bottom]),
                                              startPoint: P(50, shape.beltY - 8), endPoint: P(50, shape.beltY)))
        var pillar = Path()
        pillar.move(to: P(shape.pillarX + 1.2, shape.beltY - 9))
        pillar.addLine(to: P(shape.pillarX, shape.beltY + 0.5))
        ctx.stroke(pillar, with: .color(Color(base)), lineWidth: 1.7 * s)
    }

    func drawDetails() {
        let belt: CGFloat = shape.beltY
        let pillarX: CGFloat = shape.pillarX
        let doorX: CGFloat = shape.frontDoorX

        var doors = Path()
        doors.move(to: P(pillarX, belt))
        doors.addLine(to: P(pillarX - 0.6, 30.5))
        doors.move(to: P(doorX, belt))
        doors.addLine(to: P(doorX + 1.2, 25))
        doors.addLine(to: P(doorX - 0.4, 30.5))
        ctx.stroke(doors, with: .color(Color.black.opacity(0.25)), lineWidth: 0.35 * s)

        for hx in [pillarX - 8, pillarX + 12] {
            let handle = Path(roundedRect: R(hx, belt + 2.6, 3.4, 0.9), cornerRadius: 0.45 * s)
            ctx.fill(handle, with: .color(Color.black.opacity(0.3)))
        }

        ctx.fill(Path(ellipseIn: R(doorX - 1.6, belt - 1.6, 3, 1.8)), with: .color(Color(base.shaded(0.75))))
        let head = Path(roundedRect: R(shape.head.x, shape.head.y, 6, 1.9), cornerRadius: 0.9 * s)
        ctx.fill(head, with: .color(Color(white: 0.93)))
        let tail = Path(roundedRect: R(shape.tail.x, shape.tail.y, 3.4, 2.2), cornerRadius: 0.8 * s)
        ctx.fill(tail, with: .color(Color(red: 0.85, green: 0.12, blue: 0.12)))
    }

    func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    func drawWheel(_ cx: CGFloat) {
        let c: CGPoint = P(cx, shape.wheelY)
        let r: CGFloat = shape.wheelR * s
        let rr: CGFloat = r * 0.63
        ctx.fill(circle(c, r), with: .color(Color(white: 0.09)))
        let rim = Gradient(colors: [Color(white: 0.88), Color(white: 0.52)])
        ctx.fill(circle(c, rr), with: .linearGradient(rim, startPoint: CGPoint(x: c.x, y: c.y - rr),
                                                      endPoint: CGPoint(x: c.x, y: c.y + rr)))
        var spokes = Path()
        for i in 0..<5 {
            let a: CGFloat = CGFloat(i) * 2 * .pi / 5 - .pi / 2
            spokes.move(to: c)
            spokes.addLine(to: CGPoint(x: c.x + rr * 0.92 * cos(a), y: c.y + rr * 0.92 * sin(a)))
        }
        ctx.stroke(spokes, with: .color(Color(white: 0.32)), lineWidth: 0.55 * s)
        ctx.fill(circle(c, r * 0.14), with: .color(Color(white: 0.25)))
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
