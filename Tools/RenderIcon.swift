import AppKit

// Рисует иконку приложения 1024×1024 (запускается на сборке в GitHub Actions).
@main
struct RenderIcon {
    static func main() {
        let size = 1024
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let full = NSRect(x: 0, y: 0, width: size, height: size)

        // Фон: глубокий бирюзовый → тёмно-синий
        NSGradient(starting: NSColor(red: 0.07, green: 0.55, blue: 0.50, alpha: 1),
                   ending: NSColor(red: 0.05, green: 0.20, blue: 0.33, alpha: 1))?
            .draw(in: full, angle: -60)

        // Карточка-заметка
        let card = NSRect(x: 212, y: 170, width: 600, height: 690)
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 70, yRadius: 70)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 40
        shadow.shadowOffset = NSSize(width: 0, height: -16)
        shadow.set()
        NSColor.white.setFill()
        cardPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Машина сверху карточки
        let teal = NSColor(red: 0.05, green: 0.45, blue: 0.42, alpha: 1)
        let cfg = NSImage.SymbolConfiguration(pointSize: 250, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [teal]))
        if let car = NSImage(systemSymbolName: "car.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
            let s = car.size
            car.draw(in: NSRect(x: (CGFloat(size) - s.width) / 2, y: 520, width: s.width, height: s.height))
        }

        // Строчки «заметки»
        let lineColor = NSColor(red: 0.80, green: 0.86, blue: 0.88, alpha: 1)
        let accent = NSColor(red: 0.98, green: 0.62, blue: 0.20, alpha: 1)
        for (i, w) in [CGFloat(420), 340, 260].enumerated() {
            let y = CGFloat(430 - i * 85)
            (i == 0 ? accent : lineColor).setFill()
            NSBezierPath(roundedRect: NSRect(x: 302, y: y, width: w, height: 38), xRadius: 19, yRadius: 19).fill()
        }

        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        do { try png.write(to: URL(fileURLWithPath: out)) } catch { print(error); exit(1) }
        print("icon -> \(out)")
    }
}
