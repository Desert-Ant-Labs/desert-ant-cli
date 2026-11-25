import Face
import Foundation

struct FaceRunner: SetRunner {
    let id = "face"
    let inputKind = RunInputKind.image
    let options = [
        RunOption(name: "people", help: "Group the photos into people, each with the photos they are in."),
        RunOption(name: "find", help: "List the photos of the person in this photo, most alike first."),
        RunOption(name: "strict", help: "With --find, count a match at 1 false match in 10,000 instead of 1 in 1,000."),
        RunOption(name: "min-confidence", help: "Leave out faces the detector scores below this, from 0 to 1. Default 0.35."),
        RunOption(name: "max-faces", help: "The most faces to find per photo, most confident first. Default 20."),
        RunOption(name: "faceprints", help: "Put each face's 128-number faceprint in the JSON, to compare faces later."),
    ]

    private let model = Face()

    func isDownloaded() -> Bool { model.isDownloaded() }
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws {
        try await model.download(progress: progress)
    }

    struct Photo: Encodable {
        let input: String
        let faces: [Found]
    }
    struct Found: Encodable {
        let box: Box
        let confidence: Double
        let landmarks: [Point]
        let faceprint: [Float]?
    }
    struct People: Encodable {
        let photos: Int
        let faces: Int
        let people: [Person]
    }
    struct Person: Encodable {
        let person: Int
        let photos: [String]
        let faces: [Seen]
    }
    struct Seen: Encodable {
        let input: String
        let box: Box?
        let confidence: Double
    }
    struct Ranked: Encodable {
        let input: String
        let score: Double
    }

    struct Settings {
        var options = Face.Options.recognition
        var level = Faceprint.Level.recommended
        var people = false
        var find: String?
        var faceprints = false
    }

    func settings(_ arguments: RunArguments) throws -> Settings {
        var s = Settings()
        func on(_ key: String) -> Bool { arguments[key] == "true" }
        if let text = arguments["min-confidence"] {
            guard let min = Double(text), (0...1).contains(min) else { throw RunError("min-confidence must be between 0 and 1.") }
            s.options.minimumConfidence = min
        }
        if let text = arguments["max-faces"] {
            guard let n = Int(text), (1...100).contains(n) else { throw RunError("max-faces must be a whole number between 1 and 100.") }
            s.options.maxFaces = n
        }
        s.people = on("people")
        s.find = arguments["find"]
        if s.people, s.find != nil { throw RunError("--people and --find each ask one question. Pass one of them.") }
        if let path = s.find, !FileManager.default.fileExists(atPath: path) { throw RunError("no file at \(path).") }
        if on("strict") {
            guard s.find != nil else { throw RunError("--strict sets how sure --find is, so pass it with --find.") }
            s.level = .strict
        }
        s.faceprints = on("faceprints")
        return s
    }

    func validate(_ arguments: RunArguments) throws { _ = try settings(arguments) }

    func wantsSet(_ arguments: RunArguments) -> Bool {
        guard let s = try? settings(arguments) else { return false }
        return s.people || s.find != nil
    }

    func run(_ input: String, arguments: RunArguments, out: Output) async throws {
        guard FileManager.default.fileExists(atPath: input) else { throw RunError("no file at \(input).") }
        let s = try settings(arguments)
        let progress = Progress(palette: out.palette, quiet: out.options.quiet)
        progress.update(nil, label: "finding faces")
        let faces = try await faces(in: input, s)
        progress.finish()
        if out.isJSON {
            out.emit(document(faces, input: input, s))
            return
        }
        let p = out.palette
        out.line(p.bold(count(faces.count, "face")))
        for f in faces {
            out.line(p.dim(String(format: "confidence %.2f  box %.2f, %.2f to %.2f, %.2f", f.confidence, f.box.x0, f.box.y0, f.box.x1, f.box.y1)))
        }
    }

    func runSet(_ inputs: [String], batch: Bool, arguments: RunArguments, out: Output) async throws {
        let s = try settings(arguments)
        var reference: DetectedFace?
        var photos = inputs
        if let path = s.find {
            let found = try await faces(in: path, s)
            guard let best = found.max(by: { $0.confidence < $1.confidence }) else { throw RunError("Face found no face in \(path).") }
            if found.count > 1 { out.warn("\(path) has \(found.count) faces. Finding the clearest one.") }
            reference = best
            photos.removeAll { canonical($0) == canonical(path) }
        }

        let progress = Progress(palette: out.palette, quiet: out.options.quiet)
        var seen: [(input: String, faces: [DetectedFace])] = []
        var failed = 0
        for (i, photo) in photos.enumerated() {
            progress.update(Double(i) / Double(photos.count), label: "finding faces in \(i + 1) of \(photos.count)")
            do {
                seen.append((photo, try await faces(in: photo, s)))
            } catch {
                progress.finish()
                out.warn("\(error)")
                failed += 1
            }
        }
        progress.finish()

        if let reference {
            find(reference, in: seen, s, out: out)
        } else {
            people(seen, out: out)
        }
        if failed > 0 {
            throw RunError("\(failed) of \(photos.count) files failed. The messages are above.")
        }
    }

    private func find(_ reference: DetectedFace, in seen: [(input: String, faces: [DetectedFace])], _ s: Settings, out: Output) {
        let all = seen.flatMap { photo in photo.faces.map { (input: photo.input, faceprint: $0.faceprint) } }
        var best: [String: Double] = [:]
        for match in Face.matches(for: reference.faceprint, in: all.map(\.faceprint), level: s.level) {
            best[all[match.index].input] = max(best[all[match.index].input] ?? 0, match.similarity)
        }
        let ranked = best.map { Ranked(input: $0.key, score: $0.value) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.input < $1.input }
        if out.isJSON {
            out.emit(ranked)
            return
        }
        for r in ranked { out.line("\(out.palette.dim(String(format: "%.2f", r.score)))  \(r.input)") }
        out.note("\(ranked.isEmpty ? "No" : "\(ranked.count)") of \(seen.count) photo\(seen.count == 1 ? "" : "s") show this person.")
    }

    private func people(_ seen: [(input: String, faces: [DetectedFace])], out: Output) {
        var library = FaceLibrary()
        for photo in seen {
            library.add(photo.faces, photo: photo.input, date: Pictures.captureDate(photo.input).map { Date(timeIntervalSince1970: $0) })
        }
        library.regroup()
        let people = library.people(.all).enumerated().map { i, person in
            let faces = person.faces.compactMap { library.face($0) }.map { Seen(input: $0.photo, box: $0.box, confidence: $0.confidence) }
            var photos: [String] = []
            for face in faces where !photos.contains(face.input) { photos.append(face.input) }
            return Person(person: i + 1, photos: photos, faces: faces)
        }
        let total = seen.reduce(0) { $0 + $1.faces.count }
        if out.isJSON {
            out.emit(People(photos: seen.count, faces: total, people: people))
            return
        }
        let p = out.palette
        for (i, person) in people.enumerated() {
            if i > 0 { out.line() }
            out.line(p.bold("person \(person.person)") + p.dim("  \(count(person.photos.count, "photo"))"))
            for photo in person.photos { out.line(p.dim(photo)) }
        }
        out.note("\(people.isEmpty ? "No" : "\(people.count)") \(people.count == 1 ? "person" : "people") in \(count(seen.count, "photo")), counting those in two photos or more.")
    }

    private func faces(in input: String, _ s: Settings) async throws -> [DetectedFace] {
        do {
            return try await model.faces(in: Pictures.pixels(input), options: s.options)
        } catch let error as FaceError {
            throw RunError("could not find faces in \(input): \(error.message)")
        }
    }

    func document(_ faces: [DetectedFace], input: String, _ s: Settings) -> Photo {
        Photo(input: input, faces: faces.map {
            Found(box: $0.box, confidence: $0.confidence, landmarks: $0.landmarks, faceprint: s.faceprints ? $0.faceprint.values : nil)
        })
    }

    private func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    private func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
