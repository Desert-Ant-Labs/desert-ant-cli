import Eye
import Foundation

// Eye: a photo's kind, scores, tags, and crop. A filter or a question (--duplicates,
// --best, --similar-to, --sort) is about the photos together. A video is sampled into frames.

struct EyeRunner: SetRunner {
    let id = "eye"
    let inputKind = RunInputKind.visual
    let options = [
        RunOption(name: "has", help: "Keep only the photos with all of these tags, comma-separated, such as \"dog,beach\". On a video, list the moments with them."),
        RunOption(name: "not", help: "Leave out the photos with any of these tags, such as \"blurry,screenshot\"."),
        RunOption(name: "strict", help: "Count a tag only at confidence 0.9 instead of 0.5. Use it before moving or deleting files."),
        RunOption(name: "duplicates", help: "Group near-duplicate photos, the photo to keep first in each group."),
        RunOption(name: "best", help: "Pick the photo to keep from the set: eyes open first, then the best faces, then the keeper score."),
        RunOption(name: "similar-to", help: "Rank the photos by how alike they are to this photo."),
        RunOption(name: "sort", help: "Rank the photos by aesthetic, keeper, cover, sharpness, or a tag's confidence."),
        RunOption(name: "limit", help: "With --sort or --similar-to, how many photos to list."),
        RunOption(name: "crop", help: "Also write the best crop at this aspect ratio, such as 1:1, 16:9, or 4:5. On a video, Eye crops the thumbnail."),
        RunOption(name: "thumbnail", help: "On a video, also write the frame that makes the best thumbnail, as <input>_thumbnail.jpg."),
        RunOption(name: "every", help: "On a video, the seconds between the frames Eye analyzes. Default 1, at most 100 frames."),
        RunOption(name: "output-dir", help: "Where crops and thumbnails go. By default, they go beside the input."),
        RunOption(name: "force", help: "Replace an existing file instead of writing name-2.ext."),
        RunOption(name: "parts", help: "What Eye computes, comma-separated: photo, layout, faces, or sharpness. Default all four. Fewer parts run faster."),
        RunOption(name: "max-faces", help: "The most faces to analyze per photo, most confident first. Default 20."),
        RunOption(name: "tags", help: "How many tags to print per photo. Default 8. The JSON has every tag above the cutoff."),
        RunOption(name: "all-tags", help: "Put every tag's confidence in the JSON, also those below the cutoff."),
        RunOption(name: "embedding", help: "Put the 512-number embedding in the JSON, to compare photos later."),
    ]

    private let model = Eye()

    func isDownloaded() -> Bool { model.isDownloaded() }
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws {
        do {
            try await model.download(progress: progress)
        } catch {
            throw RunError("could not download eye: \(error.localizedDescription) Eye is in closed beta, so set HF_TOKEN to a Hugging Face token with access to desert-ant-labs/eye.")
        }
    }

    struct Photo: Encodable {
        let input: String
        /// A video frame's time in seconds; nil for a photo.
        let time: Double?
        let model: String
        let width: Int
        let height: Int
        let kind: String?
        let scores: Scores?
        let sharpness: Double?
        let rotation: Int?
        let tags: [String: Double]
        let faces: [Face]?
        let people: [Detection]?
        let pets: [Detection]?
        let crop: Crop?
        let embedding: [Float]?
    }
    struct Face: Encodable {
        let box: Box
        let confidence: Double
        let quality: Double
        let pose: Pose
        let tags: [String: Double]
    }
    struct Crop: Encodable {
        let aspect: String
        let box: Box
        let file: String?
    }
    struct Video: Encodable {
        let input: String
        let durationSec: Double
        let every: Double
        let kind: String?
        /// Each tag that holds in a frame, and the share of frames it holds in.
        let tags: [String: Double]
        let thumbnail: Thumbnail?
        /// With --has or --not, the stretches where every frame matches.
        let matches: [Span]?
        let frames: [Photo]
    }
    struct Thumbnail: Encodable {
        let time: Double
        let cover: Double?
        let crop: Box?
        let file: String?
    }
    struct Span: Encodable {
        let start: Double
        let end: Double
    }
    struct Group: Encodable {
        let keep: String
        let others: [String]
    }
    struct Duplicates: Encodable {
        let photos: Int
        let groups: [Group]
    }
    struct Best: Encodable {
        let best: String
        let photos: Int
    }
    struct Ranked: Encodable {
        let input: String
        let score: Double
    }

    enum Question: Equatable {
        case duplicates, best
        case similar(String)
        case sort(String)
    }

    struct Settings {
        var options = Options()
        var level = Level.recommended
        var has: [Tag] = []
        var not: [Tag] = []
        var question: Question?
        var limit: Int?
        var crop: (text: String, aspect: Double)?
        var thumbnail = false
        var every: Double?
        var outputDir: String?
        var force = false
        var shown = 8
        var allTags = false
        var embedding = false

        var filters: Bool { !has.isEmpty || !not.isEmpty }
        func keeps(_ a: Analysis) -> Bool {
            has.allSatisfy { a.has($0, level) } && !not.contains { a.has($0, level) }
        }
    }

    private static let partNames: [String: Parts] = ["photo": .photo, "layout": .layout, "faces": .faces, "sharpness": .sharpness]
    private static let scoreKeys = ["aesthetic", "keeper", "cover", "sharpness"]

    func settings(_ arguments: RunArguments) throws -> Settings {
        var s = Settings()
        func on(_ key: String) -> Bool { arguments[key] == "true" }
        func tags(_ key: String) -> [Tag] {
            (arguments[key] ?? "").split(separator: ",").map { Tag(String($0).trimmingCharacters(in: .whitespaces).lowercased()) }
                .filter { !$0.rawValue.isEmpty }
        }
        if let list = arguments["parts"] {
            var parts: Parts = []
            for name in list.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
                guard let part = Self.partNames[name] else {
                    throw RunError("parts are photo, layout, faces, and sharpness, not \(name).")
                }
                parts.insert(part)
            }
            s.options.parts = parts
        }
        if let n = arguments["max-faces"] {
            guard let faces = Int(n), (0...100).contains(faces) else { throw RunError("max-faces must be a whole number between 0 and 100.") }
            s.options.maxFaces = faces
        }
        s.level = on("strict") ? .strict : .recommended
        s.has = tags("has")
        s.not = tags("not")

        var questions: [Question] = []
        if on("duplicates") { questions.append(.duplicates) }
        if on("best") { questions.append(.best) }
        if let path = arguments["similar-to"] { questions.append(.similar(path)) }
        if let key = arguments["sort"]?.lowercased() { questions.append(.sort(key)) }
        guard questions.count <= 1 else {
            throw RunError("--duplicates, --best, --similar-to, and --sort each ask one question. Pass one of them.")
        }
        s.question = questions.first
        if case .similar(let path) = s.question, !FileManager.default.fileExists(atPath: path) {
            throw RunError("no file at \(path).")
        }
        if let n = arguments["limit"] {
            guard let limit = Int(n), limit > 0 else { throw RunError("limit must be a whole number above 0.") }
            s.limit = limit
        }
        if let text = arguments["crop"] {
            guard let aspect = Pictures.aspect(text) else { throw RunError("crop is an aspect like 1:1, 16:9, or 4:5, not \(text).") }
            s.crop = (text, aspect)
        }
        if s.crop != nil, !s.options.parts.contains(.layout) {
            throw RunError("a crop needs the layout part. Leave --parts out, or add layout.")
        }
        s.thumbnail = on("thumbnail")
        if let every = arguments.double("every") {
            guard every >= 0.1 else { throw RunError("every must be 0.1 seconds or more.") }
            s.every = every
        }
        s.outputDir = arguments["output-dir"]
        s.force = on("force")
        if let n = arguments["tags"] {
            guard let shown = Int(n), shown >= 0 else { throw RunError("tags must be a whole number, 0 or more.") }
            s.shown = shown
        }
        s.allTags = on("all-tags")
        s.embedding = on("embedding")
        return s
    }

    func validate(_ arguments: RunArguments) throws { _ = try settings(arguments) }

    func wantsSet(_ arguments: RunArguments) -> Bool {
        guard let s = try? settings(arguments) else { return false }
        return s.question != nil || s.filters
    }

    func run(_ input: String, arguments: RunArguments, out: Output) async throws {
        guard FileManager.default.fileExists(atPath: input) else { throw RunError("no file at \(input).") }
        let s = try settings(arguments)
        if RunInputKind.isVideo(input) {
            try await video(input, s, out: out)
            return
        }
        let progress = Progress(palette: out.palette, quiet: out.options.quiet)
        progress.update(nil, label: "analyzing")
        let pixels = try Pictures.pixels(input)
        let analysis = try await analyze(pixels, input: input, s)
        progress.finish()
        let crop = try writeCrop(of: pixels, analysis, input: input, s)
        if out.isJSON {
            out.emit(document(analysis, input: input, time: nil, crop: crop, s))
            return
        }
        show(analysis, crop: crop, s, out: out)
    }

    private func analyze(_ pixels: ImagePixels, input: String, _ s: Settings) async throws -> Analysis {
        do {
            return try await model.analyze(pixels, options: s.options)
        } catch let error as EyeError {
            throw RunError("could not analyze \(input): \(error.message)")
        }
    }

    private func show(_ a: Analysis, crop: Crop?, _ s: Settings, out: Output) {
        let p = out.palette
        var head = p.bold(a.kind.map { name($0) } ?? "photo")
        if let scores = a.scores {
            head += "  " + p.dim(String(format: "keeper %.2f  aesthetic %.2f  cover %.2f", scores.keeper, scores.aesthetic, scores.cover))
        }
        if let sharp = a.details?.sharpness?.score { head += p.dim(String(format: "  sharpness %.2f", sharp)) }
        out.line(head)
        let tags = a.tags(s.level).filter { $0 != a.kind }.prefix(s.shown).map { name($0) }
        if !tags.isEmpty { out.line(tags.joined(separator: ", ")) }
        var notes: [String] = []
        if let faces = a.faces, !faces.isEmpty {
            let closed = faces.filter { $0.has(.eyesClosed, s.level) }.count
            notes.append("\(faces.count) face\(faces.count == 1 ? "" : "s")" + (closed > 0 ? ", \(closed) with eyes closed" : ""))
        }
        if let pets = a.pets, !pets.isEmpty { notes.append("\(pets.count) pet\(pets.count == 1 ? "" : "s")") }
        if let rotation = a.rotation { notes.append("turned \(rotation)° clockwise") }
        if !notes.isEmpty { out.line(p.dim(notes.joined(separator: ", "))) }
        if let file = crop?.file { out.line(p.dim("crop  \(file)")) }
    }

    private func video(_ input: String, _ s: Settings, out: Output) async throws {
        let frames = try await VideoFrames(input)
        let every = s.every ?? max(1, frames.durationSec / 100)
        let times = frames.times(every: every)
        let progress = Progress(palette: out.palette, quiet: out.options.quiet)
        var seen: [(time: Double, analysis: Analysis)] = []
        for (i, t) in times.enumerated() {
            progress.update(Double(i) / Double(times.count), label: "analyzing frame \(i + 1) of \(times.count)")
            guard let frame = try? await frames.frame(at: t) else { continue }
            seen.append((frame.time, try await analyze(frame.pixels, input: input, s)))
        }
        progress.finish()
        guard !seen.isEmpty else { throw RunError("could not read a frame of \(input).") }

        // The best cover among frames with no blur and nobody's eyes closed.
        let clean = seen.filter { !$0.analysis.has(.eyesClosed) && !$0.analysis.has(.blurry) }
        let pick = (clean.isEmpty ? seen : clean).max { ($0.analysis.scores?.cover ?? 0) < ($1.analysis.scores?.cover ?? 0) }!
        let box = s.crop.flatMap { cropBox(pick.analysis, aspect: $0.aspect) }
        var file: String?
        if s.thumbnail || s.crop != nil {
            let full = try await VideoFrames(input, maxSide: nil, tolerance: 0).frame(at: pick.time)
            let path = try destination(for: input, suffix: "_thumbnail", ext: "jpg", s)
            try Pictures.write(full.pixels, box: box, to: path)
            file = path
        }

        var counts: [Tag: Int] = [:]
        var kinds: [Tag: Int] = [:]
        for (_, a) in seen {
            for tag in a.tags(s.level) { counts[tag, default: 0] += 1 }
            if let kind = a.kind { kinds[kind, default: 0] += 1 }
        }
        let shares = counts.mapValues { Double($0) / Double(seen.count) }
        let kind = kinds.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
        let matches = s.filters ? spans(seen.map { ($0.time, s.keeps($0.analysis)) }, every: every, duration: frames.durationSec) : nil

        if out.isJSON {
            out.emit(Video(
                input: input, durationSec: frames.durationSec, every: every, kind: kind?.rawValue,
                tags: Dictionary(uniqueKeysWithValues: shares.map { ($0.key.rawValue, $0.value) }),
                thumbnail: Thumbnail(time: pick.time, cover: pick.analysis.scores?.cover, crop: box, file: file),
                matches: matches,
                frames: seen.map { document($0.analysis, input: input, time: $0.time, crop: nil, s) }))
            return
        }
        let p = out.palette
        if let matches {
            if matches.isEmpty { out.line(p.dim("no frame matches")) }
            for m in matches {
                out.line("\(p.time(Format.stamp(m.start))) to \(p.time(Format.stamp(m.end)))  \(p.dim(Format.elapsed(m.end - m.start)))")
            }
            if let file { out.line(p.dim(file)) }
            return
        }
        out.line(p.bold(kind.map { name($0) } ?? "video") + p.dim("  \(Format.spoken(frames.durationSec)), \(seen.count) frames"))
        // On screen, the tags in at least a quarter of the frames.
        let common = shares.filter { $0.value >= 0.25 && $0.key != kind }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(s.shown).map { name($0.key) }
        if !common.isEmpty { out.line(common.joined(separator: ", ")) }
        let cover = pick.analysis.scores.map { String(format: "  cover %.2f", $0.cover) } ?? ""
        out.line("thumbnail  \(p.time(Format.stamp(pick.time)))" + p.dim(cover))
        if let file { out.line(p.dim(file)) }
    }

    /// Runs of matching frames as time spans, each frame standing for the step around it.
    func spans(_ frames: [(time: Double, match: Bool)], every: Double, duration: Double) -> [Span] {
        var out: [Span] = []
        var start: Double?
        var last = 0.0
        for (time, match) in frames {
            if match {
                if start == nil { start = max(0, time - every / 2) }
                last = min(duration, time + every / 2)
            } else if let s = start {
                out.append(Span(start: s, end: last))
                start = nil
            }
        }
        if let s = start { out.append(Span(start: s, end: last)) }
        return out
    }

    func runSet(_ inputs: [String], batch: Bool, arguments: RunArguments, out: Output) async throws {
        let s = try settings(arguments)
        var photos = inputs.filter { !RunInputKind.isVideo($0) }
        let videos = inputs.filter(RunInputKind.isVideo)
        // One video with a filter is that video's document, its matches inside.
        if !batch, photos.isEmpty, videos.count == 1, s.question == nil {
            try await video(videos[0], s, out: out)
            return
        }
        if s.question != nil, !videos.isEmpty {
            guard !photos.isEmpty else { throw RunError("that question compares photos, and these are videos. Pass photos, or ask about a video with --has.") }
            out.warn("Left out \(videos.count) video\(videos.count == 1 ? "" : "s"): the question compares photos.")
        }
        var reference: Analysis?
        if case .similar(let path) = s.question {
            reference = try await analyze(Pictures.pixels(path), input: path, s)
            photos.removeAll { canonical($0) == canonical(path) }
        }

        let progress = Progress(palette: out.palette, quiet: out.options.quiet)
        var analyzed: [(input: String, analysis: Analysis)] = []
        var failed = 0
        for (i, photo) in photos.enumerated() {
            progress.update(Double(i) / Double(photos.count), label: "analyzing \(i + 1) of \(photos.count)")
            do {
                analyzed.append((photo, try await analyze(Pictures.pixels(photo), input: photo, s)))
            } catch {
                progress.finish()
                out.warn("\(error)")
                failed += 1
            }
        }
        progress.finish()
        warnUnknown(s.has + s.not, in: analyzed.map(\.analysis), out: out)

        try await answer(analyzed.filter { s.keeps($0.analysis) }, of: analyzed.count, videos: videos, reference: reference, s, out: out)
        if failed > 0 {
            throw RunError("\(failed) of \(photos.count) files failed. The messages are above.")
        }
    }

    /// The answer about the photos that pass the filters, `total` the photos read.
    private func answer(_ kept: [(input: String, analysis: Analysis)], of total: Int, videos: [String],
                        reference: Analysis?, _ s: Settings, out: Output) async throws {
        let p = out.palette
        switch s.question {
        case nil:
            let crops = try writeCrops(kept, s, out: out)
            if out.isJSON {
                var docs = kept.map { AnyEncodable(document($0.analysis, input: $0.input, time: nil, crop: crops[$0.input], s)) }
                for video in videos {
                    let batch = Batch()
                    var each = out
                    each.batch = batch
                    try await self.video(video, s, out: each)
                    docs += batch.all
                }
                out.emit(docs)
                return
            }
            for photo in kept { out.line(photo.input) }
            for video in videos {
                out.line(p.bold(video))
                var each = out
                each.indent = "  "
                try await self.video(video, s, out: each)
            }
            if total > 0 {
                out.note("\(kept.count) of \(total) photo\(total == 1 ? "" : "s") match.")
            }

        case .duplicates:
            let dates = kept.map { Pictures.captureDate($0.input) }
            // A photo without a capture time drops out of a dated grouping, so dates
            // count only when every photo has one.
            let indices = Eye.duplicates(in: kept.map(\.analysis), dates: dates.allSatisfy { $0 != nil } ? dates : nil)
            let groups = indices.map { g in Group(keep: kept[g[0]].input, others: g.dropFirst().map { kept[$0].input }) }
            try writeCrops(indices.map { kept[$0[0]] }, s, out: out)
            if out.isJSON {
                out.emit(Duplicates(photos: kept.count, groups: groups))
                return
            }
            for (i, g) in groups.enumerated() {
                if i > 0 { out.line() }
                out.line("\(g.keep)  \(p.accent("keep"))")
                for other in g.others { out.line(p.dim(other)) }
            }
            let extra = groups.reduce(0) { $0 + $1.others.count }
            out.note("\(groups.isEmpty ? "No" : "\(groups.count)") group\(groups.count == 1 ? "" : "s") of near-duplicates in \(kept.count) photos"
                     + (extra > 0 ? ". \(extra) could go." : "."))

        case .best:
            guard let i = Eye.best(of: kept.map(\.analysis)) else { throw RunError("no photo to choose from.") }
            try writeCrops([kept[i]], s, out: out)
            if out.isJSON {
                out.emit(Best(best: kept[i].input, photos: kept.count))
                return
            }
            out.line(kept[i].input)
            out.note(kept.count == 1 ? "The only photo that matches." : "The best of \(kept.count) photos.")

        case .similar:
            guard let reference else { return }
            let ranked = Eye.similar(to: reference, in: kept.map(\.analysis), limit: s.limit ?? kept.count)
                .map { Ranked(input: kept[$0.index].input, score: $0.similarity) }
            try rankedOutput(ranked, kept, s, out: out)

        case .sort(let key):
            let scored = try kept.map { photo -> Ranked in
                guard let score = try score(photo.analysis, key) else {
                    throw RunError("\(photo.input) has no \(key) score. Leave --parts out, or add the part it needs.")
                }
                return Ranked(input: photo.input, score: score)
            }
            let ranked = Array(scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.input < $1.input }.prefix(s.limit ?? scored.count))
            try rankedOutput(ranked, kept, s, out: out)
        }
    }

    private func rankedOutput(_ ranked: [Ranked], _ kept: [(input: String, analysis: Analysis)], _ s: Settings, out: Output) throws {
        try writeCrops(kept.filter { k in ranked.contains { $0.input == k.input } }, s, out: out)
        if out.isJSON {
            out.emit(ranked)
            return
        }
        for r in ranked { out.line("\(out.palette.dim(String(format: "%.2f", r.score)))  \(r.input)") }
    }

    /// A score by name, or a tag's confidence; nil when the part behind it did not run.
    private func score(_ a: Analysis, _ key: String) throws -> Double? {
        switch key {
        case "aesthetic": return a.scores?.aesthetic
        case "keeper": return a.scores?.keeper
        case "cover": return a.scores?.cover
        case "sharpness": return a.details?.sharpness?.score
        default:
            guard let confidence = a.confidence(Tag(key)) else {
                throw RunError("sort takes \(Self.scoreKeys.joined(separator: ", ")), or a tag, and eye has no tag \(key).")
            }
            return confidence
        }
    }

    /// A tag no photo has a confidence for is most likely a typo, which would match nothing.
    private func warnUnknown(_ tags: [Tag], in analyses: [Analysis], out: Output) {
        guard !analyses.isEmpty else { return }
        for tag in tags where !analyses.contains(where: { $0.confidence(tag) != nil }) {
            out.warn("Eye has no tag \(tag.rawValue), or the part it needs did not run. `desertant docs eye` lists the tags.")
        }
    }

    private func writeCrop(of pixels: ImagePixels, _ a: Analysis, input: String, _ s: Settings) throws -> Crop? {
        guard let crop = s.crop else { return nil }
        guard let box = cropBox(a, aspect: crop.aspect) else { throw RunError("Eye found no crop for \(input).") }
        let path = try destination(for: input, suffix: "_crop", ext: Pictures.outputExtension(for: input), s)
        try Pictures.write(pixels, box: box, to: path)
        return Crop(aspect: crop.text, box: box, file: path)
    }

    /// Crops of the photos an answer names, by input. The paths go to stderr, so stdout
    /// stays the answer.
    @discardableResult
    private func writeCrops(_ photos: [(input: String, analysis: Analysis)], _ s: Settings, out: Output) throws -> [String: Crop] {
        guard s.crop != nil else { return [:] }
        var crops: [String: Crop] = [:]
        for photo in photos {
            if let crop = try writeCrop(of: Pictures.pixels(photo.input), photo.analysis, input: photo.input, s) {
                crops[photo.input] = crop
                if !out.isJSON, !out.options.quiet { out.warn("crop  \(crop.file ?? "")") }
            }
        }
        return crops
    }

    /// Eye's best crop at `aspect`, trimmed to exactly that aspect.
    private func cropBox(_ a: Analysis, aspect: Double) -> Box? {
        a.bestCrop(aspect: aspect).map { Pictures.exact($0, aspect: aspect, width: a.width, height: a.height) }
    }

    private func destination(for input: String, suffix: String, ext: String, _ s: Settings) throws -> String {
        var path = Destination.sibling(of: input, suffix: suffix, extension: ext)
        if let dir = s.outputDir {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            path = (dir as NSString).appendingPathComponent((path as NSString).lastPathComponent)
        }
        return try Destination.resolve(requested: nil, default: path, input: input, force: s.force)
    }

    func document(_ a: Analysis, input: String, time: Double?, crop: Crop?, _ s: Settings) -> Photo {
        let tags = s.allTags ? a.confidences : a.confidences.filter { $0.value >= s.level.cutoff }
        return Photo(
            input: input, time: time, model: a.model, width: a.width, height: a.height,
            kind: a.kind?.rawValue, scores: a.scores, sharpness: a.details?.sharpness?.score, rotation: a.rotation,
            tags: Dictionary(uniqueKeysWithValues: tags.map { ($0.key.rawValue, $0.value) }),
            faces: a.faces?.map { f in
                Face(box: f.box, confidence: f.detectionConfidence, quality: f.quality, pose: f.pose,
                     tags: Dictionary(uniqueKeysWithValues: f.confidences.map { ($0.key.rawValue, $0.value) }))
            },
            people: a.people, pets: a.pets, crop: crop, embedding: s.embedding ? a.embedding : nil)
    }

    /// A tag as a reader writes it: `group_shot` -> `group shot`.
    private func name(_ tag: Tag) -> String { tag.rawValue.replacingOccurrences(of: "_", with: " ") }

    private func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
