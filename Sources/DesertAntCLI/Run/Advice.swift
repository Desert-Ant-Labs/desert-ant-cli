import Foundation
import Tongue

enum Advice {
    static func notes(for id: String, text: String) -> [String] {
        var notes: [String] = []
        let words = text.split(whereSeparator: \.isWhitespace).count
        switch id {
        case "gist" where words < 3 && text.count < 15:
            notes.append("Gist reads a title or a post best, so a word or two gives a weak topic.")
        case "emo" where words > 20 || text.count > 120:
            notes.append("Emo is tuned for a short intent, like a to-do, so a long text gets noisier emoji.")
        default:
            break
        }
        if let language = unread(by: id, text: text) {
            notes.append("\(Manifest.shared.model(id)?.name ?? id) does not read \(language), so the result may not mean anything.")
        }
        return notes
    }

    static func tongue(_ detection: Detection, text: String) -> [String] {
        guard detection.reliability == .tentative, !detection.isTooCloseToCall else { return [] }
        return text.split(whereSeparator: \.isWhitespace).count < 3
            ? ["Tongue is surest from three words, so this is a guess."]
            : ["Tongue is unsure of this text, so this is a guess."]
    }

    private static func unread(by id: String, text: String) -> String? {
        guard let codes = Manifest.shared.model(id)?.languages?.codes, !codes.isEmpty,
              let detection = try? Tongue().detect(text, topK: 1),
              detection.reliability == .confident, !detection.isTooCloseToCall,
              let code = detection.language else { return nil }
        let read = code == "no" ? codes.contains { ["nb", "nn", "no"].contains($0) } : codes.contains(code)
        guard !read else { return nil }
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }
}
