import Foundation
import Transcript

// Who's turns shaped for a reader. `who --transcript` and `voz --speakers` both write
// through here.

/// One stretch of one speaker, numbered from 0 in order of first appearance.
struct SpeakerTurn: Encodable, Sendable, Equatable {
    let start: Double
    let end: Double
    let speaker: Int

    /// Times to the millisecond, so the JSON reads 10.88 and not float noise.
    init(start: Double, end: Double, speaker: Int) {
        self.start = (start * 1000).rounded() / 1000
        self.end = (end * 1000).rounded() / 1000
        self.speaker = speaker
    }
}

/// One speaker's share of the recording.
struct SpeakerSummary: Encodable, Sendable, Equatable {
    let speaker: Int
    let name: String
    let seconds: Double
    let share: Double
    let turns: Int
}

/// A line of the transcript with the speaker who said it.
struct SpokenLine: Encodable, Sendable, Equatable {
    let start: Double
    let end: Double
    let speaker: Int
    let text: String
}

enum Speakers {
    /// The pause, in seconds, under which a speaker's turns read as one.
    static let defaultJoin = 1.0

    /// "Speaker 1" or the name given for that speaker, in order of first appearance.
    static func name(_ speaker: Int, names: [String]) -> String {
        speaker < names.count ? names[speaker] : "Speaker \(speaker + 1)"
    }

    static func names(_ list: String?) -> [String] {
        (list ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Turns in time order, a speaker's consecutive turns joined when the pause between
    /// them is at most `gap`. Another speaker in between keeps them apart, so a short
    /// "yes" from someone else stays on the page.
    static func join(_ turns: [SpeakerTurn], gap: Double) -> [SpeakerTurn] {
        var out: [SpeakerTurn] = []
        for turn in turns.sorted(by: { ($0.start, $0.speaker) < ($1.start, $1.speaker) }) {
            if let last = out.last, last.speaker == turn.speaker, turn.start - last.end <= gap {
                out[out.count - 1] = SpeakerTurn(start: last.start, end: max(last.end, turn.end), speaker: last.speaker)
            } else {
                out.append(turn)
            }
        }
        return out
    }

    /// Each speaker's time and share of `duration`, most heard first. `turns` counts
    /// the joined turns, the ones a reader sees.
    static func summary(_ turns: [SpeakerTurn], joined: [SpeakerTurn], duration: Double, names: [String]) -> [SpeakerSummary] {
        return Set(turns.map(\.speaker)).map { s in
            let seconds = turns.filter { $0.speaker == s }.reduce(0) { $0 + ($1.end - $1.start) }
            return SpeakerSummary(speaker: s, name: name(s, names: names), seconds: (seconds * 100).rounded() / 100,
                                  share: duration > 0 ? (seconds / duration * 1000).rounded() / 1000 : 0,
                                  turns: joined.filter { $0.speaker == s }.count)
        }.sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.speaker < $1.speaker }
    }

    /// The speaker heard most during `start...end`, summed over their turns, or the
    /// nearest one within a second when nobody overlaps it, else nil.
    static func speaker(at start: Double, _ end: Double, in turns: [SpeakerTurn]) -> Int? {
        var heard: [Int: Double] = [:]
        var nearest: (speaker: Int, distance: Double)?
        for turn in turns {
            let overlap = min(end, turn.end) - max(start, turn.start)
            if overlap > 0 { heard[turn.speaker, default: 0] += overlap }
            let distance = max(turn.start - end, start - turn.end, 0)
            if distance < (nearest?.distance ?? .infinity) { nearest = (turn.speaker, distance) }
        }
        if let most = heard.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }) { return most.key }
        if let nearest, nearest.distance <= 1 { return nearest.speaker }
        return nil
    }

    /// Words split into lines by speaker, then into sentences within each speaker's run.
    /// A run of one or two words under 0.6s between two runs of the same speaker is
    /// boundary jitter, and goes to the speaker around it.
    static func lines(words: [TimedWord], turns: [SpeakerTurn]) -> [SpokenLine] {
        guard !words.isEmpty else { return [] }
        var labels: [Int] = []
        for word in words {
            labels.append(speaker(at: word.start, word.end, in: turns) ?? labels.last ?? 0)
        }
        var runs = runs(of: labels)
        var i = 1
        while i + 1 < runs.count {
            let run = runs[i]
            let span = words[run.range.upperBound - 1].end - words[run.range.lowerBound].start
            if run.range.count <= 2, span < 0.6, runs[i - 1].speaker == runs[i + 1].speaker {
                runs[i - 1] = (runs[i - 1].speaker, runs[i - 1].range.lowerBound..<runs[i + 1].range.upperBound)
                runs.removeSubrange(i...(i + 1))
            } else {
                i += 1
            }
        }
        var out: [SpokenLine] = []
        for run in runs {
            let spoken = Array(words[run.range])
            for sentence in Sentence.sentences(from: spoken) {
                let text = sentence.text.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                out.append(SpokenLine(start: sentence.start, end: sentence.end, speaker: run.speaker, text: text))
            }
        }
        return out
    }

    /// Sentences with no word times, as an SRT carries them: each goes to the speaker
    /// heard most during it.
    static func lines(sentences: [Sentence], turns: [SpeakerTurn]) -> [SpokenLine] {
        var last = 0
        return sentences.map { s in
            let speaker = speaker(at: s.start, s.end, in: turns) ?? last
            last = speaker
            return SpokenLine(start: s.start, end: s.end, speaker: speaker, text: s.text)
        }
    }

    private static func runs(of labels: [Int]) -> [(speaker: Int, range: Range<Int>)] {
        var runs: [(speaker: Int, range: Range<Int>)] = []
        var start = 0
        for i in 1...labels.count where i == labels.count || labels[i] != labels[start] {
            runs.append((labels[start], start..<i))
            start = i
        }
        return runs
    }
}

/// A diarization three ways: the turns as Who numbered them, joined for reading, and
/// summed per speaker.
struct LabeledTurns {
    let raw: [SpeakerTurn]
    let joined: [SpeakerTurn]
    let summary: [SpeakerSummary]

    init(_ turns: [SpeakerTurn], duration: Double, join: Double, names: [String]) {
        raw = turns
        joined = Speakers.join(turns, gap: join)
        summary = Speakers.summary(turns, joined: joined, duration: duration, names: names)
    }
}

extension Output {
    /// "2 speakers in 46 seconds", then each speaker's time and share, most heard first.
    func speakerSummary(_ summary: [SpeakerSummary], duration: Double) {
        let p = palette
        line(p.bold("\(summary.count) speaker\(summary.count == 1 ? "" : "s")") + p.dim(" in \(Format.spoken(duration))"))
        let nameWidth = summary.map(\.name.count).max() ?? 0
        for s in summary {
            let share = String(format: "%3d%%", Int((s.share * 100).rounded()))
            line("\(p.model(s.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)))  "
                 + "\(Format.elapsed(s.seconds).leftPadded(to: 7))  \(p.dim(share))")
        }
    }

    /// A script: the speaker's name when it changes, then each line with its time.
    func script(_ lines: [SpokenLine], names: [String]) {
        let p = palette
        let width = min(Terminal.columns, 100)
        let keyWidth = Format.stamp(lines.last?.start ?? 0).count
        var previous: Int?
        for spoken in lines {
            if spoken.speaker != previous {
                if previous != nil { line() }
                line(p.model(Speakers.name(spoken.speaker, names: names)))
                previous = spoken.speaker
            }
            for row in column(Format.stamp(spoken.start), keyWidth: keyWidth, text: spoken.text, width: width,
                              palette: p, keyStyle: { p.time($0) }) { line(row) }
        }
    }
}

/// The files a speaker-labeled result is written as.
enum SpeakerFile {
    /// RTTM, the diarization exchange format: one `SPEAKER` line per turn.
    static func rttm(_ turns: [SpeakerTurn], input: String, names: [String]) -> String {
        let file = token(URL(fileURLWithPath: input).deletingPathExtension().lastPathComponent)
        return turns.map { t in
            "SPEAKER \(file) 1 \(String(format: "%.3f %.3f", t.start, t.end - t.start)) <NA> <NA> \(token(Speakers.name(t.speaker, names: names))) <NA> <NA>"
        }.joined(separator: "\n") + (turns.isEmpty ? "" : "\n")
    }

    /// The transcript as text: a paragraph per speaker turn, the name in front.
    static func text(_ lines: [SpokenLine], names: [String]) -> String {
        paragraphs(lines).map { "\(Speakers.name($0.speaker, names: names)): \($0.text)" }.joined(separator: "\n\n") + "\n"
    }

    /// Captions with the speaker named when it changes.
    static func srt(_ lines: [SpokenLine], words: [TimedWord]?, names: [String]) -> String {
        var previous: Int?
        let cues = captions(lines, words: words).map { cue, speaker in
            defer { previous = speaker }
            return speaker == previous ? cue : Caption(start: cue.start, end: cue.end, text: "\(Speakers.name(speaker, names: names)): \(cue.text)")
        }
        return TranscriptFile.srt(cues)
    }

    /// WebVTT with a voice span on every cue.
    static func vtt(_ lines: [SpokenLine], words: [TimedWord]?, names: [String]) -> String {
        TranscriptFile.vtt(captions(lines, words: words).map { cue, speaker in
            Caption(start: cue.start, end: cue.end, text: "<v \(Speakers.name(speaker, names: names))>\(cue.text)")
        })
    }

    /// Cues that never straddle two speakers: each speaker's run is cut on its own.
    static func captions(_ lines: [SpokenLine], words: [TimedWord]?) -> [(Caption, Int)] {
        paragraphs(lines).flatMap { p -> [(Caption, Int)] in
            let sentences = p.lines.enumerated().map { Sentence(id: $0.offset, text: $0.element.text, start: $0.element.start, end: $0.element.end) }
            let inside = (words ?? []).filter { $0.start >= p.start - 0.001 && $0.end <= p.end + 0.001 }
            let cues = inside.isEmpty ? sentences.map { Caption(start: $0.start, end: $0.end, text: $0.text) }
                : Captions.captions(from: inside, sentences: sentences)
            return cues.map { ($0, p.speaker) }
        }
    }

    private struct Paragraph {
        let speaker: Int
        var lines: [SpokenLine]
        var start: Double { lines.first?.start ?? 0 }
        var end: Double { lines.last?.end ?? 0 }
        var text: String { lines.map(\.text).joined(separator: " ") }
    }

    private static func paragraphs(_ lines: [SpokenLine]) -> [Paragraph] {
        var out: [Paragraph] = []
        for line in lines {
            if out.last?.speaker == line.speaker { out[out.count - 1].lines.append(line) } else { out.append(Paragraph(speaker: line.speaker, lines: [line])) }
        }
        return out
    }

    /// RTTM fields are separated by spaces, so a name keeps its words with underscores.
    private static func token(_ s: String) -> String {
        let t = s.split(whereSeparator: \.isWhitespace).joined(separator: "_")
        return t.isEmpty ? "audio" : t
    }
}
