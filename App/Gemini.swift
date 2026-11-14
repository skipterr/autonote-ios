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
        odometer — пробег в км, только если он явно указан, иначе null.
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
