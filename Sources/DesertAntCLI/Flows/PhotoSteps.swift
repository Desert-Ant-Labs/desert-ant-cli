import Eye
import Foundation
import Moderator
#if canImport(Vision)
import ImageIO
import Vision
#endif

/// Eye's readings of a run's photos by path, so a later step asks about a photo
/// without running Eye on it again.
actor EyeReadings {
    private var byPath: [String: Analysis] = [:]

    func reading(_ path: String, _ eye: Eye) async throws -> Analysis {
        if let known = byPath[path] { return known }
        let pixels = try Pictures.pixels(path)
        let analysis: Analysis
        do {
            analysis = try await eye.analyze(pixels)
        } catch let error as EyeError {
            throw StepError("could not analyze \(path): \(error.message)")
        }
        byPath[path] = analysis
        return analysis
    }
}

enum PhotoSteps {
    static let all: [StepDef] = [eye, moderator, duplicates, readtext]

    static func reading(_ path: String, _ run: StepRun) async throws -> Analysis {
        let models = run.context.run.models
        let eye = await models.model("eye") { Eye() }
        let readings = await models.model("eye-readings") { EyeReadings() }
        return try await readings.reading(path, eye)
    }

    static func photo(_ run: StepRun) throws -> String {
        guard case .image(let path)? = run.inputs["image"] else {
            throw StepError("\(run.context.step.id) takes a photo, and got \(run.inputs["image"]?.kind ?? "nothing").")
        }
        return path
    }

    static let eye = StepDef(
        type: "eye", summary: "Reads a photo: what it shows, its kind, its quality, its faces, and its framing.",
        category: .model, model: "eye",
        inputs: [Port(id: "image", type: .image)],
        outputs: EyeFields.all.map { Port(id: $0.id, type: .any) },
        defaults: ["fields": .null]
    ) { run in
        let path = try photo(run)
        run.context.progress("analyzing")
        let reading = EyeReading(try await reading(path, run), input: path)
        var out: [String: Value] = [:]
        for field in EyeFields.all { out[field.id] = field.read(reading) }
        return out
    }

    static let moderator = StepDef(
        type: "moderator", summary: "Checks whether a photo is safe to show: no nudity or sexual activity.",
        category: .model, model: "moderator",
        inputs: [Port(id: "image", type: .image)],
        outputs: [Port(id: "safe", type: .any), Port(id: "score", type: .any), Port(id: "image", type: .image)],
        defaults: ["threshold": 0.5]
    ) { run in
        let path = try photo(run)
        let model = await run.context.run.models.model("moderator") { Moderator() }
        let threshold = run.params["threshold"]?.number ?? 0.5
        guard (0...1).contains(threshold) else { throw StepError("threshold must be between 0 and 1.") }
        run.context.progress("analyzing")
        let result = try await ModeratorRunner.check(path, threshold: threshold, with: model)
        return ["safe": .bool(!result.nsfw), "score": .number(result.score), "image": .image(path)]
    }

    /// Groups near-duplicates and keeps the best of each group, as `da eye --duplicates`.
    static let duplicates = StepDef(
        type: "duplicates", summary: "Finds near-duplicate photos, and splits the photos to keep from the rest.",
        category: .logic, model: "eye",
        inputs: [Port(id: "photos", type: .image, list: true)],
        outputs: [Port(id: "keep", type: .image, each: true), Port(id: "others", type: .image, each: true), Port(id: "groups", type: .any)],
        noMap: true
    ) { run in
        let photos = (run.inputs["photos"]?.present ?? []).compactMap { v -> String? in
            if case .image(let p) = v { p } else { nil }
        }
        var analyses: [Analysis] = []
        for (i, path) in photos.enumerated() {
            run.context.progress("analyzing \(i + 1) of \(photos.count)", Double(i) / Double(max(photos.count, 1)))
            analyses.append(try await reading(path, run))
        }
        let dates = photos.map(Pictures.captureDate)
        let groups = Eye.duplicates(in: analyses, dates: dates.allSatisfy { $0 != nil } ? dates : nil)
        let others = Set(groups.flatMap { $0.dropFirst() })
        return [
            "keep": .list(photos.indices.filter { !others.contains($0) }.map { .image(photos[$0]) }),
            "others": .list(photos.indices.filter { others.contains($0) }.map { .image(photos[$0]) }),
            "groups": .list(groups.map { g in .list(g.map { .image(photos[$0]) }) }),
        ]
    }

    #if canImport(Vision)
    static let readtext = StepDef(
        type: "readtext", summary: "Reads the text in a photo, a scan, or a screenshot, with Apple's Vision. macOS only.",
        category: .logic,
        inputs: [Port(id: "image", type: .image)],
        outputs: [Port(id: "text", type: .text), Port(id: "lines", type: .text, each: true)],
        defaults: ["fast": false]
    ) { run in
        let path = try photo(run)
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw StepError("could not read \(path) as an image.") }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (props?[kCGImagePropertyOrientation] as? NSNumber).flatMap { CGImagePropertyOrientation(rawValue: $0.uint32Value) } ?? .up
        let fast = run.params["fast"]?.bool ?? false
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = !fast
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return ["text": .text(lines.joined(separator: "\n")), "lines": .list(lines.map { .text($0) })]
    }
    #else
    static let readtext = StepDef(
        type: "readtext", summary: "Reads the text in a photo, a scan, or a screenshot, with Apple's Vision. macOS only.",
        category: .logic,
        inputs: [Port(id: "image", type: .image)],
        outputs: [Port(id: "text", type: .text), Port(id: "lines", type: .text, each: true)],
        unavailable: "readtext uses Apple's Vision and runs on macOS only"
    ) { _ in throw StepError("readtext runs on macOS only.") }
    #endif
}

/// One photo as Eye read it, with the raw outputs behind the tags.
struct EyeReading {
    let analysis: Analysis
    let input: String

    init(_ analysis: Analysis, input: String) {
        self.analysis = analysis
        self.input = input
    }

    var photo: Photo? { analysis.details?.photo }
    var layout: Details.Layout? { analysis.details?.layout }

    /// Detections that are confident enough and big enough to be real rather than noise.
    var people: [Detection] { (layout?.people ?? []).filter { $0.confidence >= 0.25 && $0.box.width * $0.box.height >= 0.003 } }
    var pets: [Detection] { (layout?.pets ?? []).filter { $0.confidence >= 0.25 && $0.box.width * $0.box.height >= 0.003 } }
    var faces: [FaceDetails] { (analysis.details?.faces ?? []).filter { $0.confidence >= 0.25 && $0.box.width * $0.box.height >= 0.003 } }
}

/// The fields the eye step gives, by the names a flow file uses.
enum EyeFields {
    struct Field: Sendable {
        let id: String
        let read: @Sendable (EyeReading) -> Value?
    }

    private static func ranked(_ scores: [String: Double], limit: Int) -> [(label: String, score: Double)] {
        Array(scores.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit).map { ($0.key, $0.value) })
    }

    private static func top(_ scores: [String: Double]?) -> String { ranked(scores ?? [:], limit: 1).first?.label ?? "" }

    private static func words(_ s: String) -> String { s.replacingOccurrences(of: "_or_", with: " or ").replacingOccurrences(of: "_", with: " ") }

    private static func score(_ v: Double?) -> Value? { v.map { .number(($0 * 1000).rounded() / 1000) } }

    /// Builds the document `da eye --json` writes, for the `detail` field.
    private static let runner = EyeRunner()

    private static let animals = ["Animal", "Pet", "Cat", "Dog", "Bird", "Horse", "Mammal", "Kitten", "Puppy", "Fish", "Reptile"]

    /// Scene tags that say how a picture was made rather than what is in it.
    private static let style: Set<String> = ["Drawing", "Painting", "Handwriting", "Art", "Cartoon", "Sketch", "Illustration", "Child art", "Whiteboard", "Black-and-white"]

    private static let why = [
        "forgettable": "nothing special", "accidental": "taken by accident", "unusable": "unusable",
        "bad_framing": "badly framed", "bad_lighting": "too dark or too bright", "test_or_duplicate_shot": "test shot or duplicate",
        "reference_photo": "saved for reference", "low_content": "nothing in it",
    ]

    /// What a photo shows: the top scene, and up to two more within 0.15 of it.
    static func subject(_ scenes: [String: Double]) -> [String] {
        let list = ranked(scenes, limit: 40).filter { !style.contains($0.label) }
        let best = list.first?.score ?? 0
        return list.prefix(3).filter { $0.score >= best - 0.15 }.map(\.label)
    }

    /// Eye scores every reason to drop a photo on its own, and good photos often score
    /// 0.8 on one. A photo is dropped when a reason beats Eye's own keeper score by a
    /// wide margin.
    static func reason(_ reject: [String: Double], blur: [String: Double]) -> String {
        guard let (reason, value) = reject.filter({ $0.key != "keeper" }).max(by: { $0.value < $1.value }),
              value >= 0.8, value - (reject["keeper"] ?? 0) >= 0.45 else { return "keeper" }
        if reason == "technical_flaw" {
            let b = top(blur)
            return !b.isEmpty && b != "none" ? "blurry" : "poor quality"
        }
        return why[reason] ?? words(reason)
    }

    static let all: [Field] = [
        Field(id: "subject") { .list(subject($0.photo?.scenes ?? [:]).map { .text($0) }) },
        Field(id: "scenes") { r in .list(ranked(r.photo?.scenes ?? [:], limit: 5).map { .record([("label", .text($0.label)), ("score", .number($0.score))]) }) },
        Field(id: "type") { .text(words(top($0.photo?.type))) },
        Field(id: "animal") { r in .bool(animals.contains { (r.photo?.scenes[$0] ?? 0) >= 0.8 }) },
        Field(id: "people") { .number(Double($0.people.count)) },
        Field(id: "pets") { .number(Double($0.pets.count)) },
        Field(id: "keeper") { score($0.photo?.keeper ?? $0.analysis.scores?.keeper) },
        Field(id: "reason") { r in .text(reason(r.photo?.reject ?? [:], blur: r.photo?.blur ?? [:])) },
        Field(id: "aesthetic") { score($0.photo?.aesthetic ?? $0.analysis.scores?.aesthetic) },
        Field(id: "cover") { score($0.photo?.cover ?? $0.analysis.scores?.cover) },
        Field(id: "sharp") { score($0.analysis.details?.sharpness?.score) },
        Field(id: "blur") { .text(top($0.photo?.blur)) },
        Field(id: "sensitive") { r in
            guard let (k, v) = r.photo?.sensitive.max(by: { $0.value < $1.value }), v >= 0.5 else { return .text("none") }
            return .text(words(k))
        },
        Field(id: "faces") { .number(Double($0.faces.count)) },
        Field(id: "smile") { score($0.faces.map(\.smile).max().map { max(0, $0) }) },
        Field(id: "eyesOpen") { score($0.faces.map(\.eyesOpen).min()) },
        Field(id: "looking") { score($0.faces.map(\.looking).max()) },
        Field(id: "expression") { .text(words(top($0.faces.first?.expression))) },
        Field(id: "shot") { .text(words(top($0.layout?.shot))) },
        Field(id: "crop") { r in
            guard let b = r.layout?.crops.max(by: { $0.score < $1.score })?.box else { return nil }
            return .record([("x0", .number(b.x0)), ("y0", .number(b.y0)), ("x1", .number(b.x1)), ("y1", .number(b.y1))])
        },
        Field(id: "detail") { r in
            guard let settings = try? runner.settings(RunArguments()),
                  let data = try? JSONEncoder().encode(runner.document(r.analysis, input: r.input, time: nil, crop: nil, settings)) else { return nil }
            return (try? JSONDecoder().decode(JSONValue.self, from: data))?.value
        },
    ]
}
