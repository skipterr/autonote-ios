import CoreImage
import UIKit
import Vision

enum CarPhotoError: LocalizedError {
    case unreadable, noSubject
    var errorDescription: String? {
        switch self {
        case .unreadable: "Не получилось прочитать фото."
        case .noSubject: "Не нашёл на фото машину, чтобы вырезать фон."
        }
    }
}

// Всё делается на телефоне, без интернета:
// 1) ищем на фото номерной знак и размываем его;
// 2) вырезаем главный объект (машину) из фона — та же технология, что «поднять объект» в Фото.
enum CarPhotoProcessor {
    private static let ciContext = CIContext()

    struct Result {
        let image: UIImage
        let platesHidden: Int
    }

    static func process(_ image: UIImage) async throws -> Result {
        try await Task.detached(priority: .userInitiated) { try processSync(image) }.value
    }

    private static func processSync(_ input: UIImage) throws -> Result {
        let image = input.downscaled(maxSide: 2000).normalizedUp()
        guard let cg = image.cgImage else { throw CarPhotoError.unreadable }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)

        // 1. Номера: текст, где есть и буквы, и цифры, в вытянутой рамке
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: cg).perform([text])
        var plates: [[CGPoint]] = []
        for obs in text.results ?? [] {
            guard let s = obs.topCandidates(1).first?.string else { continue }
            let alnum = s.filter { $0.isLetter || $0.isNumber }
            guard alnum.count >= 4, alnum.contains(where: \.isNumber), alnum.contains(where: \.isLetter) else { continue }
            let r = VNImageRectForNormalizedRect(obs.boundingBox, Int(w), Int(h))
            guard r.width / max(r.height, 1) >= 1.8 else { continue }
            plates.append(plateQuad(around: obs.boundingBox, in: cg) ?? fallbackQuad(r))
        }
        let cleaned = plates.isEmpty ? cg : (paintPlates(plates, on: cg) ?? cg)

        // 2. Фон: оставляем самый крупный объект на фото
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cleaned)
        try handler.perform([request])
        guard let obs = request.results?.first, !obs.allInstances.isEmpty else { throw CarPhotoError.noSubject }
        let buffer = try obs.generateMaskedImage(ofInstances: largestInstance(obs), from: handler,
                                                 croppedToInstancesExtent: true)
        let out = CIImage(cvPixelBuffer: buffer)
        guard let outCG = ciContext.createCGImage(out, from: out.extent) else { throw CarPhotoError.unreadable }
        return Result(image: UIImage(cgImage: outCG).downscaled(maxSide: 1400), platesHidden: plates.count)
    }

    // Ищем рамку самой таблички вокруг найденного текста — чтобы закрасить ровно её, с наклоном
    private static func plateQuad(around textBox: CGRect, in cg: CGImage) -> [CGPoint]? {
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let roi = textBox.insetBy(dx: -textBox.width * 0.35, dy: -textBox.height * 1.2)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let req = VNDetectRectanglesRequest()
        req.regionOfInterest = roi
        req.minimumAspectRatio = 0.15
        req.maximumAspectRatio = 0.6          // табличка вытянутая: высота / ширина
        req.minimumSize = 0.2
        req.maximumObservations = 4
        req.minimumConfidence = 0.4
        req.quadratureTolerance = 25
        try? VNImageRequestHandler(cgImage: cg).perform([req])
        // координаты рамки — внутри ROI; переводим в координаты фото
        let center = CGPoint(x: textBox.midX, y: textBox.midY)
        func toImage(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (roi.minX + p.x * roi.width) * w, y: (roi.minY + p.y * roi.height) * h)
        }
        for r in req.results ?? [] {
            let bb = CGRect(x: roi.minX + r.boundingBox.minX * roi.width, y: roi.minY + r.boundingBox.minY * roi.height,
                            width: r.boundingBox.width * roi.width, height: r.boundingBox.height * roi.height)
            // рамка должна содержать текст и быть не сильно больше него
            guard bb.contains(center), bb.width < textBox.width * 2.2, bb.height < textBox.height * 3.5 else { continue }
            return [toImage(r.bottomLeft), toImage(r.bottomRight), toImage(r.topRight), toImage(r.topLeft)]
        }
        return nil
    }

    private static func fallbackQuad(_ r: CGRect) -> [CGPoint] {
        let p = r.insetBy(dx: -r.height * 0.55, dy: -r.height * 0.35)
        return [CGPoint(x: p.minX, y: p.minY), CGPoint(x: p.maxX, y: p.minY),
                CGPoint(x: p.maxX, y: p.maxY), CGPoint(x: p.minX, y: p.maxY)]
    }

    // Закрашиваем номер чистой пустой табличкой: белая, со скруглением и тонкой рамкой
    private static func paintPlates(_ quads: [[CGPoint]], on cg: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        for q in quads where q.count == 4 {
            // CGContext считает от левого нижнего угла — так же, как Vision
            let path = CGMutablePath()
            path.addLines(between: q)
            path.closeSubpath()
            let height = hypot(q[3].x - q[0].x, q[3].y - q[0].y)
            ctx.setLineJoin(.round)
            ctx.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.94, alpha: 1))
            ctx.setStrokeColor(CGColor(red: 0.95, green: 0.95, blue: 0.94, alpha: 1))
            ctx.setLineWidth(max(2, height * 0.18))     // «скругляет» углы
            ctx.addPath(path)
            ctx.drawPath(using: .fillStroke)
            ctx.setStrokeColor(CGColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 0.85))
            ctx.setLineWidth(max(1.5, height * 0.06))
            ctx.addPath(path)
            ctx.strokePath()
        }
        return ctx.makeImage()
    }

    // Если на фото несколько объектов (соседние машины, люди) — берём самый большой
    private static func largestInstance(_ obs: VNInstanceMaskObservation) -> IndexSet {
        let mask = obs.instanceMask
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return obs.allInstances }
        let width = CVPixelBufferGetWidth(mask), height = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let p = base.assumingMemoryBound(to: UInt8.self)
        var counts = [Int](repeating: 0, count: 256)
        for y in 0..<height {
            let row = p + y * bytesPerRow
            for x in 0..<width { counts[Int(row[x])] += 1 }
        }
        counts[0] = 0
        guard let best = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[best] > 0 else {
            return obs.allInstances
        }
        return IndexSet(integer: best)
    }
}

// Поиск фото модели в бесплатной фотобазе Wikimedia Commons
enum CarImageSearch {
    struct Candidate: Identifiable {
        let id = UUID()
        let thumb: URL
        let large: URL?
        let original: URL
    }

    static func search(_ query: String) async throws -> [Candidate] {
        var c = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        c.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "generator", value: "search"),
            .init(name: "gsrnamespace", value: "6"),
            .init(name: "gsrsearch", value: "\(query) filetype:bitmap"),
            .init(name: "gsrlimit", value: "24"),
            .init(name: "prop", value: "imageinfo"),
            .init(name: "iiprop", value: "url"),
            .init(name: "iiurlwidth", value: "500"),
        ]
        var req = URLRequest(url: c.url!)
        req.setValue("AutoNote/1.0 (iOS app)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let pages = ((json?["query"] as? [String: Any])?["pages"] as? [String: Any]) ?? [:]

        let items: [(Int, Candidate)] = pages.values.compactMap { v in
            guard let page = v as? [String: Any],
                  let info = (page["imageinfo"] as? [[String: Any]])?.first,
                  let thumbS = info["thumburl"] as? String, let thumb = URL(string: thumbS),
                  let origS = info["url"] as? String, let orig = URL(string: origS) else { return nil }
            let large = thumbS.contains("/500px-")
                ? URL(string: thumbS.replacingOccurrences(of: "/500px-", with: "/1600px-")) : nil
            return ((page["index"] as? Int) ?? 999, Candidate(thumb: thumb, large: large, original: orig))
        }
        return items.sorted { $0.0 < $1.0 }.map(\.1)
    }

    static func download(_ c: Candidate) async throws -> UIImage {
        for url in [c.large, c.original].compactMap({ $0 }) {
            var req = URLRequest(url: url)
            req.setValue("AutoNote/1.0 (iOS app)", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 30
            if let result = try? await URLSession.shared.data(for: req),
               (result.1 as? HTTPURLResponse)?.statusCode == 200,
               let img = UIImage(data: result.0) {
                return img
            }
        }
        throw CarPhotoError.unreadable
    }
}

extension UIImage {
    // Поворачиваем пиксели «как на экране», чтобы Vision видел фото правильно
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
