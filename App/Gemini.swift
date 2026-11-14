import Foundation
import UIKit

// Что Gemini вытащил из чека или фразы. Всё необязательное — человек проверит и поправит.
struct ParsedExpense {
    var category: ExpenseCategory?
    var amount: Double?
    var liters: Double?
    var odometer: Int?
    var date: Date?
    var note: String?
}

enum GeminiError: LocalizedError {
    case noKey, failed(String)
    var errorDescription: String? {
        switch self {
        case .noKey: "Нет ключа Gemini. Добавь его в Настройках — или заполни вручную."
        case .failed(let m): m
        }
    }
}

enum Gemini {
    // Как в Бульке: быстрые модели по очереди; если одна молчит или её нет — пробуем следующую.
    static let models = ["gemini-3.1-flash-lite", "gemini-3-flash-preview", "gemini-3.5-flash-lite", "gemini-3.5-flash"]

    static func parse(text: String, currentOdometer: Int) async throws -> ParsedExpense {
        try await run(parts: [["text": prompt(currentOdometer) + "\n\nФраза пользователя: «\(text)»"]])
    }

    static func parse(image: UIImage, currentOdometer: Int) async throws -> ParsedExpense {
        guard let jpeg = image.downscaled(maxSide: 1600).jpegData(compressionQuality: 0.7) else {
            throw GeminiError.failed("Не получилось прочитать фото")
        }
        return try await run(parts: [
            ["text": prompt(currentOdometer) + "\n\nНа фото — чек или квитанция. Прочитай его."],
            ["inlineData": ["mimeType": "image/jpeg", "data": jpeg.base64EncodedString()]],
        ])
    }

    private static func prompt(_ odo: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let cats = ExpenseCategory.allCases.map { "\($0.rawValue) (\($0.title))" }.joined(separator: ", ")
        return """
        Ты помогаешь вести учёт расходов на машину. Сегодня \(f.string(from: .now)). \
        Текущий пробег машины примерно \(odo) км.
        Определи один расход и верни ТОЛЬКО JSON такого вида:
        {"category": "...", "amount": 0.0, "liters": null, "odometer": null, "date": "YYYY-MM-DD", "note": "..."}
        category — одно из: \(cats).
        amount — итоговая сумма в евро (число). liters — литры топлива, если это заправка, иначе null.
        odometer — пробег в км, только если он явно указан, иначе null. \
        Если сказано «проехал 375» — верни 375 (приложение само прибавит к прошлому пробегу).
        date — дата расхода; если не указана — сегодня; «вчера» = вчерашняя дата.
        note — очень коротко по-русски, например «Shell, дизель» или «замена колодок».
        Если чего-то не знаешь — ставь null. Ничего не выдумывай.
        """
    }

    private static func run(parts: [[String: Any]]) async throws -> ParsedExpense {
        guard let key = KeyVault.load() else { throw GeminiError.noKey }
        let body: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": ["responseMimeType": "application/json", "temperature": 0.1],
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        var queue = models
        var tried = Set<String>()
        var lastErr = "Gemini не ответил"

        while !queue.isEmpty {
            let model = queue.removeFirst()
            if tried.contains(model) { continue }
            tried.insert(model)

            var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
            req.httpMethod = "POST"
            req.timeoutInterval = 30
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            req.httpBody = payload

            let data: Data, status: Int
            do {
                let (d, resp) = try await URLSession.shared.data(for: req)
                data = d
                status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            } catch {
                lastErr = "Нет связи с Gemini (\(model))"
                continue
            }

            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? ""

            if status == 404 {
                lastErr = "Нет модели \(model)"
                // Google иногда подсказывает, какую модель взять вместо этой
                if let r = message.range(of: #"use models/([\w.-]+)"#, options: .regularExpression) {
                    queue.insert(String(message[r].dropFirst("use models/".count)), at: 0)
                }
                continue
            }
            if status == 0 || status == 429 || status >= 500 {
                lastErr = message.isEmpty ? "Модель \(model) занята" : message
                continue
            }
            if status != 200 {
                throw GeminiError.failed(message.isEmpty ? "Ошибка Gemini \(status)" : message)
            }

            let text = (((json?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]])?
                .compactMap { $0["text"] as? String }.joined() ?? ""
            return decode(text)
        }
        throw GeminiError.failed(lastErr)
    }

    // MARK: Рисование машины для гаража

    // Модели, которые умеют рисовать; если какой-то нет — пробуем следующую
    static let imageModels = ["gemini-3.1-flash-image-preview", "gemini-3-pro-image-preview",
                              "gemini-2.5-flash-image", "gemini-2.5-flash-image-preview"]

    static func drawCar(make: String, model: String, year: Int, color: CarColor) async throws -> UIImage {
        guard let key = KeyVault.load() else { throw GeminiError.noKey }
        let yearText = year > 0 ? "\(year) " : ""
        let prompt = """
        Photorealistic studio catalog render of a \(yearText)\(make) \(model) car, \(color.prompt) paint. \
        Exact side profile view, perfectly from the side, front of the car pointing to the right. \
        The whole car is visible and centered with some margin. No license plate numbers, no text, no watermark, \
        no people. Plain seamless light grey studio background, soft even lighting, subtle soft shadow under the wheels. \
        Accurate body shape and generation for that model year.
        """
        var withAspect = true
        var queue = imageModels
        var tried = Set<String>()
        var lastErr = "Gemini не смог нарисовать машину"
        var sawQuota = false

        while !queue.isEmpty {
            let m = queue.removeFirst()
            if tried.contains(m) { continue }
            tried.insert(m)

            var config: [String: Any] = ["responseModalities": ["IMAGE"]]
            if withAspect { config["imageConfig"] = ["aspectRatio": "16:9"] }
            let body: [String: Any] = ["contents": [["parts": [["text": prompt]]]], "generationConfig": config]

            var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(m):generateContent")!)
            req.httpMethod = "POST"
            req.timeoutInterval = 90
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            guard let result = try? await URLSession.shared.data(for: req) else {
                lastErr = "Нет связи с Gemini"
                continue
            }
            let data = result.0
            let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? ""

            // модель не знает настройку пропорций — повторяем без неё
            if status == 400 && withAspect && (message.contains("imageConfig") || message.contains("aspect")) {
                withAspect = false
                tried.remove(m)
                queue.insert(m, at: 0)
                continue
            }
            if status == 404 || (status == 400 && message.lowercased().contains("not supported")) {
                lastErr = "Нет модели \(m)"
                continue
            }
            if status == 429 {
                sawQuota = true
                lastErr = message
                continue
            }
            if status != 200 {
                lastErr = message.isEmpty ? "Ошибка Gemini \(status)" : message
                continue
            }

            let parts = (((json?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
            for p in parts {
                let inline = (p["inlineData"] ?? p["inline_data"]) as? [String: Any]
                if let b64 = inline?["data"] as? String, let d = Data(base64Encoded: b64), let img = UIImage(data: d) {
                    return img
                }
            }
            lastErr = "Gemini ответил без картинки"
        }
        if sawQuota {
            throw GeminiError.failed("Google не дал нарисовать картинку — похоже, на бесплатном ключе рисование ограничено. Попробуй позже.")
        }
        throw GeminiError.failed(lastErr)
    }

    // Разбираем ответ «мягко»: числа могут прийти строкой, с запятой, с «€».
    private static func decode(_ raw: String) -> ParsedExpense {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let a = s.firstIndex(of: "{"), let b = s.lastIndex(of: "}") { s = String(s[a...b]) }
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] else {
            return ParsedExpense()
        }
        func num(_ k: String) -> Double? {
            if let n = obj[k] as? NSNumber { return n.doubleValue }
            if let t = obj[k] as? String { return Double.parseLoose(t) }
            return nil
        }
        var p = ParsedExpense()
        if let c = obj["category"] as? String { p.category = ExpenseCategory(rawValue: c.lowercased()) }
        p.amount = num("amount")
        p.liters = num("liters")
        p.odometer = num("odometer").map { Int($0) }
        if let d = obj["date"] as? String {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            p.date = f.date(from: d)
        }
        if let n = obj["note"] as? String, !n.isEmpty { p.note = n }
        return p
    }
}

extension Double {
    // «12,50 €» → 12.5
    static func parseLoose(_ s: String) -> Double? {
        let cleaned = s.replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(cleaned)
    }
}

extension UIImage {
    func downscaled(maxSide: CGFloat) -> UIImage {
        let side = max(size.width, size.height)
        guard side > maxSide else { return self }
        let k = maxSide / side
        let newSize = CGSize(width: size.width * k, height: size.height * k)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
