import CoreImage
import UIKit
import Vision

// Картинка машины для гаража подбирается сама, как в банковских приложениях:
// ищем фото модели сбоку в бесплатной фотобазе Wikimedia Commons,
// вырезаем фон прямо на телефоне и берём ту, где машина стоит в профиль.
enum CarArtwork {
    private static let ciContext = CIContext()

    // Подбирает картинку; `skip` — сколько удачных вариантов пропустить (для «покажи другую»)
    static func find(make: String, model: String, skip: Int = 0) async -> UIImage? {
        let base = "\(make) \(model)".trimmed
        guard !base.isEmpty else { return nil }
        var seen = Set<URL>()
        var found = 0
        for query in ["\(base) Seitenansicht", "\(base) side view", base] {
            guard let list = try? await CarImageSearch.search(query) else { continue }
            for c in list where !seen.contains(c.original) {
                if Task.isCancelled { return nil }
                seen.insert(c.original)
                guard let img = try? await CarImageSearch.download(c),
                      let cut = try? await cutOut(img) else { continue }
                // машина сбоку заметно шире своей высоты
                let ratio = cut.size.width / max(cut.size.height, 1)
                guard ratio >= 1.9, ratio <= 3.6, cut.size.width >= 500 else { continue }
                if found == skip { return cut }
                found += 1
                if seen.count > 40 { return nil }
            }
        }
        return nil
    }

    // Вырезает главный объект (самый крупный) из фона
    static func cutOut(_ input: UIImage) async throws -> UIImage {
        try await Task.detached(priority: .userInitiated) {
            let image = input.downscaled(maxSide: 1600).normalizedUp()
            guard let cg = image.cgImage else { throw CarPhotoError.unreadable }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg)
            try handler.perform([request])
            guard let obs = request.results?.first, !obs.allInstances.isEmpty else { throw CarPhotoError.noSubject }
            let buffer = try obs.generateMaskedImage(ofInstances: largestInstance(obs), from: handler,
                                                     croppedToInstancesExtent: true)
            let out = CIImage(cvPixelBuffer: buffer)
            guard let outCG = ciContext.createCGImage(out, from: out.extent) else { throw CarPhotoError.unreadable }
            return UIImage(cgImage: outCG).downscaled(maxSide: 1200)
        }.value
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

enum CarPhotoError: LocalizedError {
    case unreadable, noSubject
    var errorDescription: String? {
        switch self {
        case .unreadable: "Не получилось прочитать фото."
        case .noSubject: "Не нашёл на фото машину."
        }
    }
}

// Поиск фото в Wikimedia Commons
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
            .init(name: "gsrlimit", value: "15"),
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
                ? URL(string: thumbS.replacingOccurrences(of: "/500px-", with: "/1400px-")) : nil
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
