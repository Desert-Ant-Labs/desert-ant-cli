import Foundation

// Clips: short clips from a talk, a podcast, or a meeting recording. The pipeline
// lives in Clipping/; this maps it onto the command line.

struct ClipsRunner: ModelRunner {
    let id = "clips"
    let inputKind = RunInputKind.file
    let emits: String? = "clips"
    let accepts = [Intake(kind: "transcript", option: "transcript")]
    let options = [
        RunOption(name: "count", help: "How many clips to look for. Default: the model sizes it to the recording."),
        RunOption(name: "output-dir", help: "Where the clip files go. Default: beside the input."),
        RunOption(name: "transcript", help: "An .srt, .vtt, or .json transcript instead of transcribing; `-` reads one from stdin."),
        RunOption(name: "select-only", help: "Report the moments as timestamps without writing files."),
        RunOption(name: "force", help: "Replace existing clip files instead of stepping aside to new names."),
    ]

    private let pipeline = ClipPipeline()

    func isDownloaded() -> Bool { pipeline.clips.isDownloaded() }
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws {
        try await pipeline.clips.download(progress: progress)
    }

    func run(_ input: String, arguments: RunArguments, out: Output) async throws {
        guard FileManager.default.fileExists(atPath: input) else { throw RunError("no file at \(input)") }
        var request = ClipPipeline.Request(media: URL(fileURLWithPath: input))
        request.transcript = try arguments["transcript"].map { path in
            // `-` reads the transcript from stdin, as `desertant voz --json` or an SRT.
            guard path == "-" else { return URL(fileURLWithPath: path) }
            guard let text = readStdin() else { throw RunError("--transcript - needs a transcript on stdin.") }
            let ext = text.hasPrefix("{") || text.hasPrefix("[") ? "json" : "srt"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("desertant-\(UUID().uuidString).\(ext)")
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        request.count = arguments.int("count")
        request.outputDirectory = arguments["output-dir"].map { URL(fileURLWithPath: $0) }
        request.selectOnly = arguments["select-only"] == "true"
        request.force = arguments["force"] == "true"

        let progress = Progress(palette: out.palette, quiet: out.options.quiet)
        let started = Date()
        let report = try await pipeline.run(request) { phase in
            switch phase {
            case .downloading(let model, let f): progress.update(f, label: "downloading \(model), first run only")
            case .loading(let model): progress.update(nil, label: "loading \(model), slower the first time on this Mac")
            case .transcribing(let f): progress.update(f, label: "transcribing")
            case .selecting: progress.update(nil, label: "selecting")
            case .cutting(let done, let of): progress.update(Double(done) / Double(max(of, 1)), label: "cutting \(min(done + 1, of)) of \(of)")
            }
        }
        progress.finish()

        if out.isJSON {
            out.emit(report)
            return
        }

        let p = out.palette
        guard !report.clips.isEmpty else {
            out.line("No clip stood out in \(report.sentences) sentences.")
            return
        }
        for pick in report.clips {
            let span = "\(p.accent(Format.stamp(pick.start))) to \(p.accent(Format.stamp(pick.end)))"
            out.line("\(p.accent(String(format: "%2d", pick.id)))  \(span)  \(p.dim(Format.elapsed(pick.durationSec)))")
            out.line("    \(truncate(pick.text, to: 88))")
            if let file = pick.file { out.line("    \(p.dim(file))") }
        }
        let elapsed = Date().timeIntervalSince(started)
        out.note("\n\(report.clips.count) clip\(report.clips.count == 1 ? "" : "s") from \(Format.spoken(report.materialSec)) in \(Format.elapsed(elapsed)).")
    }

}
