import CoreImage
import UIKit
import Vision

// Картинка машины для гаража: рисует Gemini (вид сбоку, студия), фон вырезается на телефоне.
enum CarArtwork {
    private static let ciContext = CIContext()

    // Gemini рисует машину сбоку в студийном стиле, потом вырезаем фон
    static func draw(make: String, model: String, year: Int, color: CarColor) async throws -> UIImage {
        let raw = try await Gemini.drawCar(make: make, model: model, year: year, color: color)
        return (try? await cutOut(raw)) ?? raw
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
