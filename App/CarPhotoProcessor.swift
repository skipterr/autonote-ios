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
        var ci = CIImage(cgImage: cg)

        // 1. Номера: текст, где есть и буквы, и цифры, в вытянутой рамке
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: cg).perform([text])
        var hidden = 0
        for obs in text.results ?? [] {
            guard let s = obs.topCandidates(1).first?.string else { continue }
            let alnum = s.filter { $0.isLetter || $0.isNumber }
            guard alnum.count >= 4, alnum.contains(where: \.isNumber), alnum.contains(where: \.isLetter) else { continue }
            var r = VNImageRectForNormalizedRect(obs.boundingBox, Int(w), Int(h))
            guard r.width / max(r.height, 1) >= 1.8 else { continue }
            r = r.insetBy(dx: -r.height * 0.6, dy: -r.height * 0.45)
            let scale = max(6, r.height / 2.5)
            let blurred = ci.clampedToExtent()
                .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: scale,
                                                            kCIInputCenterKey: CIVector(x: r.midX, y: r.midY)])
                .applyingGaussianBlur(sigma: Double(scale) / 2)
                .cropped(to: r)
            ci = blurred.composited(over: ci)
            hidden += 1
        }
        guard let cleaned = ciContext.createCGImage(ci, from: CGRect(x: 0, y: 0, width: w, height: h)) else {
            throw CarPhotoError.unreadable
        }

        // 2. Фон: оставляем самый крупный объект на фото
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cleaned)
        try handler.perform([request])
        guard let obs = request.results?.first, !obs.allInstances.isEmpty else { throw CarPhotoError.noSubject }
        let buffer = try obs.generateMaskedImage(ofInstances: largestInstance(obs), from: handler,
                                                 croppedToInstancesExtent: true)
        let out = CIImage(cvPixelBuffer: buffer)
        guard let outCG = ciContext.createCGImage(out, from: out.extent) else { throw CarPhotoError.unreadable }
        return Result(image: UIImage(cgImage: outCG).downscaled(maxSide: 1400), platesHidden: hidden)
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
