import Clear
import Ear
import Emo
import Foundation
import Gist
import Redact
import Tongue
import Transcript
import Who
#if canImport(CoreML)
import Uhm
#endif

enum ModelSteps {
    static var all: [StepDef] {
        var steps = [who, clear, ear, tongue, redact, gist, emo, uhm, captions, clips]
        #if canImport(Voz)
        steps.insert(voz, at: 0)
        #endif
        return steps
    }

    #if canImport(Voz)
    static let voz = StepDef(
        type: "voz", summary: "Transcribes speech, with a time on every word.", category: .model, model: "voz",
        inputs: [Port(id: "audio", type: .audio)],
        outputs: [Port(id: "text", type: .text), Port(id: "sentences", type: .text, each: true), Port(id: "words", type: .any)]
    ) { run in
        let media = try audio(run)
        let voz = await run.context.run.models.model("voz") { VozTranscriber() }
        run.context.progress("loading voz")
        try await voz.prepare { _ in }
        let t = try await voz.transcription(of: URL(fileURLWithPath: media)) { run.context.progress("transcribing", $0) }
        return [
            "text": .text(t.text),
            "sentences": .list(t.sentences.map { .text($0.text.trimmingCharacters(in: .whitespaces)) }),
            "words": .list(t.words.map {
                .record([("text", .text($0.text.trimmingCharacters(in: .whitespaces))), ("start", .number($0.start)), ("end", .number($0.end))])
            }),
        ]
    }
    #endif

    static let who = StepDef(
        type: "who", summary: "Tells the speakers apart. With words from voz, labels each line with who said it.",
        category: .model, model: "who",
        inputs: [Port(id: "audio", type: .audio), Port(id: "words", type: .any, list: true, optional: true)],
        outputs: [Port(id: "text", type: .text), Port(id: "turns", type: .any, each: true), Port(id: "speakers", type: .any),
                  Port(id: "lines", type: .any), Port(id: "paragraphs", type: .text, each: true), Port(id: "speaker", type: .text, each: true)],
        defaults: ["names": ""]
    ) { run in
        let media = try audio(run)
        let model = await run.context.run.models.model("who") { Who() }
        run.context.progress("listening for speakers")
        let result = try await model.labels(of: media)
        let names = Speakers.names(run.params["names"]?.string)
        let turns = LabeledTurns(result.turns.map { SpeakerTurn(start: $0.start, end: $0.end, speaker: $0.speaker) },
                                 duration: result.duration, join: Speakers.defaultJoin, names: names)
        let words = timedWords(run.inputs["words"])
        let lines = words.isEmpty ? [] : Speakers.lines(words: words, turns: turns.raw)
        let text = words.isEmpty
            ? turns.joined.map { "\(Speakers.name($0.speaker, names: names)): \(Format.stamp($0.start)) to \(Format.stamp($0.end))" }.joined(separator: "\n")
            : SpeakerFile.text(lines, names: names).trimmingCharacters(in: .newlines)
        var out: [String: Value] = [
            "text": .text(text),
            "turns": .list(turns.joined.map {
                .record([("speaker", .text(Speakers.name($0.speaker, names: names))), ("start", .number($0.start)), ("end", .number($0.end))])
            }),
            "speakers": .number(Double(turns.summary.count)),
        ]
        if !lines.isEmpty {
            let paragraphs = SpeakerFile.paragraphs(lines)
            out["paragraphs"] = .list(paragraphs.map { .text($0.text) })
            out["speaker"] = .list(paragraphs.map { .text(Speakers.name($0.speaker, names: names)) })
            out["lines"] = .list(lines.map {
                .record([("speaker", .text(Speakers.name($0.speaker, names: names))), ("start", .number($0.start)),
                         ("end", .number($0.end)), ("text", .text($0.text))])
            })
        }
        return out
    }

    static let clear = StepDef(
        type: "clear", summary: "Takes the noise and echo out of a recording and levels the voice. A video keeps its picture.",
        category: .model, model: "clear",
        inputs: [Port(id: "audio", type: .audio)],
        outputs: [Port(id: "audio", type: .audio)],
        defaults: ["loudness": "podcast"]
    ) { run in
        let media = try audio(run)
        let loudness = run.params["loudness"]?.string ?? "podcast"
        let mastering: Clear.Mastering
        switch loudness {
        case "podcast": mastering = .applePodcasts
        case "spotify": mastering = .spotify
        case "youtube": mastering = .youtube
        case "broadcast": mastering = .broadcast
        case "off": mastering = .bypass
        default: throw StepError("loudness is podcast, spotify, youtube, broadcast, or off, not \(loudness).")
        }
        let model = await run.context.run.models.model("clear") { Clear() }
        let video = RunInputKind.isVideo(media)
        let stem = URL(fileURLWithPath: media).deletingPathExtension().lastPathComponent + "_clear"
        #if canImport(AVFoundation)
        let audioExt = video ? "m4a" : MediaFormat.outputExtension(for: media, hasVideo: false)
        #else
        if video || !Media.isWAV(media) { _ = try FFmpeg.require(for: media) }
        let audioExt = video ? "wav" : MediaFormat.outputExtension(for: media, hasVideo: false)
        #endif
        let audioOut = try run.context.scratch(stem + "." + audioExt)
        let progress: Clear.ProgressHandler = { p in
            switch p.phase {
            case .loadingModel: run.context.progress("loading clear")
            case .analyzing: run.context.progress("analyzing", p.fraction)
            case .enhancing: run.context.progress("enhancing", p.fraction)
            }
        }
        let options = Clear.Options(mastering: mastering)
        #if canImport(AVFoundation)
        try await model.enhance(path: media, to: audioOut.path, options: options, progress: progress)
        #else
        run.context.progress("reading audio")
        let channels = try await Media.decodeChannels(media, sampleRate: 48_000)
        let result = try await model.enhance(channels: channels, sampleRate: 48_000, options: options, progress: progress)
        try Media.write(result.channels, sampleRate: result.sampleRate, to: audioOut.path)
        #endif
        guard video else { return ["audio": .audio(audioOut.path)] }
        let muxed = try run.context.scratch(stem + "." + MediaFormat.outputExtension(for: media, hasVideo: true))
        guard let cutter = ClipPipeline().cutter else {
            throw StepError("putting the clean audio back into \((media as NSString).lastPathComponent) needs ffmpeg, which is not installed. Install ffmpeg with \(FFmpeg.installHint).")
        }
        try await cutter.replaceAudio(of: URL(fileURLWithPath: media), with: audioOut, to: muxed)
        return ["audio": .video(muxed.path)]
    }

    static let ear = StepDef(
        type: "ear", summary: "Names the language spoken in a recording.", category: .model, model: "ear",
        inputs: [Port(id: "audio", type: .audio)],
        outputs: [Port(id: "language", type: .text), Port(id: "reliable", type: .any), Port(id: "candidates", type: .any)]
    ) { run in
        let media = try audio(run)
        let model = await run.context.run.models.model("ear") { Ear() }
        run.context.progress("listening")
        let samples = try await Media.decodeMono(media, sampleRate: 16_000)
        let d = try await model.identify(samples: samples, sampleRate: 16_000)
        return [
            "language": .text(d.language ?? ""),
            "reliable": .bool(d.isReliable),
            "candidates": .list(d.candidates.prefix(3).map { .record([("language", .text($0.language)), ("probability", .number($0.probability))]) }),
        ]
    }

    static let tongue = StepDef(
        type: "tongue", summary: "Names the language of a short text.", category: .model, model: "tongue",
        inputs: [Port(id: "text", type: .text)],
        outputs: [Port(id: "language", type: .text), Port(id: "reliable", type: .any), Port(id: "candidates", type: .any)]
    ) { run in
        let d = try Tongue().detect(run.inputs["text"].asText, topK: 3)
        return [
            "language": .text(d.candidates.first?.language ?? ""),
            "reliable": .bool(d.reliability == .confident),
            "candidates": .list(d.candidates.map { .record([("language", .text($0.language)), ("probability", .number($0.probability))]) }),
        ]
    }

    /// On a list, each item is redacted on its own and the placeholders are numbered
    /// across the whole list, so a name keeps one placeholder everywhere.
    static let redact = StepDef(
        type: "redact", summary: "Replaces personal data in a text with placeholders. The same data gets the same placeholder.",
        category: .model, model: "redact",
        inputs: [Port(id: "text", type: .text)],
        outputs: [Port(id: "text", type: .text), Port(id: "found", type: .any), Port(id: "count", type: .any)],
        defaults: ["confidence": 0.6],
        noMap: true
    ) { run in
        let model = await run.context.run.models.model("redact") { Redact() }
        var options = Options()
        if let min = run.params["confidence"]?.number { options.minimumConfidence = min }
        if RedactRunner.offNeuralEngine {
            run.context.note = "Redact runs without the Neural Engine on this Mac, so it does not detect names, addresses, or cities."
        }
        var tags = Placeholders.Numbering()
        var found: [Value] = []
        func one(_ text: String) async throws -> String {
            let r = try await model.redaction(of: text, options: options)
            var local: [String: String] = [:]
            for item in r.items {
                local[item.placeholder] = tags.tag(item.label.rawValue, item.original)
                found.append(.record([("label", .text(item.label.rawValue.lowercased().replacingOccurrences(of: "_", with: " "))),
                                      ("text", .text(item.original)), ("confidence", .number(item.confidence))]))
            }
            return r.redactedText.replacing(#/\[[A-Z_]+_\d+\]/#) { local[String($0.output)] ?? String($0.output) }
        }
        let text: Value
        if case .stream(let items) = run.inputs["text"] {
            var out: [Value?] = []
            for (i, item) in items.enumerated() {
                run.context.progress("\(i + 1) of \(items.count)", Double(i) / Double(max(items.count, 1)))
                if let item { out.append(.text(try await one(item.asText))) } else { out.append(nil) }
            }
            text = .stream(out)
        } else {
            text = .text(try await one(run.inputs["text"].asText))
        }
        return ["text": text, "found": .list(found), "count": .number(Double(found.count))]
    }

    static let gist = StepDef(
        type: "gist", summary: "Tags what a text is about, from 36 topics.", category: .model, model: "gist",
        inputs: [Port(id: "text", type: .text)],
        outputs: [Port(id: "top", type: .text), Port(id: "topics", type: .any)],
        defaults: ["limit": 3]
    ) { run in
        let model = await run.context.run.models.model("gist") { Gist() }
        let topics = try await model.classify(run.inputs["text"].asText, topK: max(1, run.params["limit"]?.int ?? 3))
        return [
            "top": .text(topics.first?.name ?? ""),
            "topics": .list(topics.map { .record([("name", .text($0.name)), ("score", .number($0.score))]) }),
        ]
    }

    static let emo = StepDef(
        type: "emo", summary: "Suggests the emoji that fit a text.", category: .model, model: "emo",
        inputs: [Port(id: "text", type: .text)],
        outputs: [Port(id: "emoji", type: .text), Port(id: "list", type: .any)],
        defaults: ["limit": 3]
    ) { run in
        let model = await run.context.run.models.model("emo") { Emo() }
        let list = try await model.suggestions(for: run.inputs["text"].asText, limit: max(1, run.params["limit"]?.int ?? 3))
        return [
            "emoji": .text(list.map(\.emoji).joined()),
            "list": .list(list.map { .record([("emoji", .text($0.emoji)), ("confidence", .number($0.confidence))]) }),
        ]
    }

    #if canImport(CoreML)
    static let uhm = StepDef(
        type: "uhm", summary: "Finds the uh, um, and hmm in a recording, with times.", category: .model, model: "uhm",
        inputs: [Port(id: "audio", type: .audio)],
        outputs: [Port(id: "fillers", type: .any, each: true), Port(id: "count", type: .any)]
    ) { run in
        let media = try audio(run)
        let model = await run.context.run.models.model("uhm") { Uhm() }
        run.context.progress("reading audio")
        let samples = try await Media.decodeMono(media, sampleRate: 16_000)
        let result = try await model.analyze(samples: samples, sampleRate: 16_000) { run.context.progress("listening", $0) }
        return [
            "fillers": .list(result.fillers.map {
                .record([("type", .text($0.type?.rawValue ?? "filler")), ("start", .number($0.start)),
                         ("end", .number($0.end)), ("confidence", .number($0.confidence))])
            }),
            "count": .number(Double(result.fillers.count)),
        ]
    }
    #else
    static let uhm = StepDef(
        type: "uhm", summary: "Finds the uh, um, and hmm in a recording, with times.", category: .model,
        inputs: [Port(id: "audio", type: .audio)],
        outputs: [Port(id: "fillers", type: .any, each: true), Port(id: "count", type: .any)],
        unavailable: "uhm runs on macOS only"
    ) { _ in throw StepError("uhm runs on macOS only.") }
    #endif

    static let captions = StepDef(
        type: "captions", summary: "Writes captions as SRT and WebVTT from words with times. With turns from who, names each speaker.",
        category: .logic,
        inputs: [Port(id: "words", type: .any, list: true), Port(id: "turns", type: .any, list: true, optional: true)],
        outputs: [Port(id: "srt", type: .text), Port(id: "vtt", type: .text)]
    ) { run in
        let words = timedWords(run.inputs["words"])
        guard !words.isEmpty else { throw StepError("captions needs words with times, as voz gives them.") }
        let records = run.inputs["turns"]?.present ?? []
        var names: [String] = []
        let turns: [SpeakerTurn] = records.compactMap { t in
            guard let start = t["start"]?.asNumber, let end = t["end"]?.asNumber else { return nil }
            let name = t["speaker"].asText
            if !names.contains(name) { names.append(name) }
            return SpeakerTurn(start: start, end: end, speaker: names.firstIndex(of: name)!)
        }
        if !turns.isEmpty {
            let lines = Speakers.lines(words: words, turns: turns)
            return ["srt": .text(SpeakerFile.srt(lines, words: words, names: names)),
                    "vtt": .text(SpeakerFile.vtt(lines, words: words, names: names))]
        }
        let cues = Captions.captions(from: words, sentences: Sentence.sentences(from: words))
        return ["srt": .text(TranscriptFile.srt(cues)), "vtt": .text(TranscriptFile.vtt(cues))]
    }

    static let clips = StepDef(
        type: "clips", summary: "Cuts the moments worth sharing out of a recording, with captions burned in or written beside each clip.",
        category: .model, model: "clips",
        inputs: [Port(id: "audio", type: .audio), Port(id: "words", type: .any, list: true)],
        outputs: [Port(id: "clips", type: .any, each: true), Port(id: "files", type: .any)],
        defaults: ["count": .null, "captions": "off", "position": "bottom", "align": "center", "font": .null, "size": .null,
                   "weight": "bold", "color": "white", "style": "outline", "quality": "high"],
        primary: "files"
    ) { run in
        let media = try audio(run)
        let p = run.params
        var request = ClipPipeline.Request(media: URL(fileURLWithPath: media))
        request.words = timedWords(run.inputs["words"])
        request.count = p["count"]?.int
        let mode = p["captions"]?.string ?? "off"
        guard let captions = CaptionMode(rawValue: mode) else { throw StepError("captions is burn, srt, or off, not \(mode).") }
        request.captions = captions
        request.style = try CaptionStyle.parse(
            position: p["position"]?.string, align: p["align"]?.string, font: p["font"]?.string, size: p["size"]?.string,
            weight: p["weight"]?.string, color: p["color"]?.string, look: p["style"]?.string, quality: p["quality"]?.string)
        request.outputDirectory = try run.context.scratch("clips")
        let pipeline = await run.context.run.models.model("clips") { ClipPipeline() }
        let report = try await pipeline.run(request) { phase in
            switch phase {
            case .downloading(let model, let f): run.context.progress("downloading \(model)", f)
            case .loading(let model): run.context.progress("loading \(model)")
            case .transcribing(let f): run.context.progress("transcribing", f)
            case .selecting: run.context.progress("selecting")
            case .cutting(let done, let of): run.context.progress("\(captions == .burn ? "captioning" : "cutting") \(min(done + 1, of)) of \(of)", Double(done) / Double(max(of, 1)))
            }
        }
        run.context.note = report.notes?.joined(separator: " ")
        func clip(_ path: String) -> Value { RunInputKind.isVideo(path) ? .video(path) : .audio(path) }
        var files: [Value] = []
        for pick in report.clips {
            if let file = pick.file { files.append(clip(file)) }
            if let srt = pick.captions { files.append(.file(srt)) }
        }
        return [
            "clips": .list(report.clips.map { pick in
                var fields: [(String, Value)] = [("id", .number(Double(pick.id))), ("start", .number(pick.start)), ("end", .number(pick.end)),
                                                 ("durationSec", .number(pick.durationSec)), ("text", .text(pick.text)), ("score", .number(pick.score))]
                if let file = pick.file { fields.append(("file", clip(file))) }
                if let srt = pick.captions { fields.append(("captions", .file(srt))) }
                return .record(fields)
            }),
            "files": .list(files),
        ]
    }

    /// The audio or video file a step reads.
    static func audio(_ run: StepRun) throws -> String {
        guard let path = run.inputs["audio"]?.audioPath else {
            throw StepError("\(run.context.step.id) takes audio or video, and got \(run.inputs["audio"]?.kind ?? "nothing").")
        }
        return path
    }

    /// Words as voz gives them, each but the first with its leading space back, as
    /// sentences and captions expect.
    static func timedWords(_ value: Value?) -> [TimedWord] {
        (value?.present ?? []).compactMap { w -> (String, Double, Double)? in
            guard let start = w["start"]?.asNumber, let end = w["end"]?.asNumber else { return nil }
            return (w["text"].asText.trimmingCharacters(in: .whitespaces), start, end)
        }
        .enumerated().map { i, w in TimedWord(text: i == 0 ? w.0 : " " + w.0, start: w.1, end: w.2) }
    }
}
