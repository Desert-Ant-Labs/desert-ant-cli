import Foundation
import Transcript

// Captions cut the way broadcasters cut them: at most two lines of 42 characters,
// at most 7s on screen and at least 1s, breaking at the end of a sentence first, then
// at a comma or clause, then at the widest pause between words.

struct Caption: Encodable, Sendable, Equatable {
    let start: Double
    let end: Double
    let text: String
}

enum Captions {
    static let lineLength = 42
    static let maxLines = 2
    static let maxDuration = 7.0
    static let minDuration = 1.0
    static let closeGap = 0.3

    static func captions(from words: [TimedWord], sentences: [Sentence]) -> [Caption] {
        var cues: [Caption] = []
        for sentence in sentences {
            let inSentence = words.filter { $0.start >= sentence.start - 0.001 && $0.end <= sentence.end + 0.001 }
            guard !inSentence.isEmpty else {
                cues.append(Caption(start: sentence.start, end: sentence.end, text: sentence.text))
                continue
            }
            for chunk in split(inSentence) {
                cues.append(Caption(start: chunk.first!.start, end: chunk.last!.end, text: layout(chunk)))
            }
        }
        return settle(cues)
    }

    /// Words as a caption: one line, or two balanced lines.
    static func layout(_ words: [TimedWord]) -> String {
        let text = join(words)
        guard text.count > lineLength else { return text }
        let ws = words.map { $0.text.trimmingCharacters(in: .whitespaces) }
        var best = 0, bestScore = Int.max
        for i in 1..<ws.count {
            let a = ws[..<i].joined(separator: " "), b = ws[i...].joined(separator: " ")
            guard a.count <= lineLength, b.count <= lineLength else { continue }
            let score = abs(a.count - b.count) - (ws[i - 1].last.map { ",;:".contains($0) } == true ? 8 : 0)
            if score < bestScore { bestScore = score; best = i }
        }
        guard best > 0 else { return text }
        return ws[..<best].joined(separator: " ") + "\n" + ws[best...].joined(separator: " ")
    }

    /// A sentence's words in runs that fit a caption, split at the best pause.
    private static func split(_ words: [TimedWord]) -> [[TimedWord]] {
        if fits(words) { return [words] }
        guard words.count > 1 else { return [words] }
        var best = words.count / 2, bestScore = -Double.infinity
        for i in 1..<words.count {
            let gap = words[i].start - words[i - 1].end
            let punctuation = words[i - 1].text.trimmingCharacters(in: .whitespaces).last.map { ",;:".contains($0) } == true ? 1.0 : 0
            let balance = 1 - abs(Double(i) / Double(words.count) - 0.5)
            let score = gap * 2 + punctuation + balance * 0.5
            if score > bestScore { bestScore = score; best = i }
        }
        return split(Array(words[..<best])) + split(Array(words[best...]))
    }

    private static func fits(_ words: [TimedWord]) -> Bool {
        guard let first = words.first, let last = words.last else { return true }
        if last.end - first.start > maxDuration { return false }
        let text = join(words)
        return text.count <= lineLength || layout(words).contains("\n") && layout(words).split(separator: "\n").allSatisfy { $0.count <= lineLength }
    }

    private static func join(_ words: [TimedWord]) -> String {
        words.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }

    /// No overlaps, short cues held for at least a second, tiny gaps closed.
    private static func settle(_ cues: [Caption]) -> [Caption] {
        var out: [Caption] = []
        for (i, cue) in cues.enumerated() {
            var start = cue.start, end = max(cue.end, cue.start + minDuration)
            if let previous = out.last, start < previous.end { start = previous.end }
            let next = i + 1 < cues.count ? cues[i + 1].start : Double.infinity
            if next - end < closeGap { end = next }
            end = min(end, next)
            if end <= start { end = start + 0.5 }
            out.append(Caption(start: start, end: end, text: cue.text))
        }
        return out
    }
}
