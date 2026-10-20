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
        RunOption(name: "captions", help: "burn to draw captions into each clip, srt to write <clip>.srt beside it, or off. Default off."),
        RunOption(name: "caption-position", help: "Where burned captions go: bottom, center, or top. Default bottom."),
        RunOption(name: "caption-align", help: "How burned caption lines line up: left, center, or right. Default center."),
        RunOption(name: "caption-font", help: "A font family, or a .ttf or .otf file. Default Atkinson Hyperlegible, which ships with desertant."),
        RunOption(name: "caption-size", help: "The text's height as a share of the frame's height, as 0.06. Default: sized to the frame."),
        RunOption(name: "caption-weight", help: "The text's weight: regular, medium, semibold, bold, black, or 100 to 900. Default bold."),
        RunOption(name: "caption-color", help: "The text's color: a name such as white or yellow, or a hex color such as #ffcc00. Default white."),
        RunOption(name: "caption-style", help: "How the text stands out from the picture: outline, box, or shadow. Default outline."),
        RunOption(name: "quality", help: "The video quality of a clip with burned captions: low, medium, or high. Default high."),
    ]

    /// The caption settings from the options, checked.
    static func captions(_ arguments: RunArguments) throws -> (CaptionMode, CaptionStyle) {
        let name = arguments["captions"]?.lowercased() ?? "off"
        guard let mode = CaptionMode(rawValue: name) else { throw RunError("captions is burn, srt, or off, not \(name).") }
        let style = try CaptionStyle.parse(
            position: arguments["caption-position"], align: arguments["caption-align"], font: arguments["caption-font"],
            size: arguments["caption-size"], weight: arguments["caption-weight"], color: arguments["caption-color"],
            look: arguments["caption-style"], quality: arguments["quality"])
        if mode == .burn { _ = try CaptionFont.resolve(style.font, weight: style.weight) }
        return (mode, style)
    }

    func validate(_ arguments: RunArguments) throws { _ = try Self.captions(arguments) }

    private let pipeline = ClipPipeline()

    func isDownloaded() -> Bool { pipeline.clips.isDownloaded() }
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws {
        try await pipeline.clips.download(progress: progress)
    }

    func run(_ input: String, arguments: RunArguments, out: Output) async throws {
        guard FileManager.default.fileExists(atPath: input) else { throw RunError("no file at \(input)") }
        var request = ClipPipeline.Request(media: URL(fileURLWithPath: input))
        // `-` reads the transcript from stdin, as `desertant voz --json` or an SRT.
        request.transcript = try arguments["transcript"].map(TranscriptFile.url(option:))
        request.count = arguments.int("count")
        request.outputDirectory = arguments["output-dir"].map { URL(fileURLWithPath: $0) }
        request.selectOnly = arguments["select-only"] == "true"
        request.force = arguments["force"] == "true"
        (request.captions, request.style) = try Self.captions(arguments)

        let progress = Progress(palette: out.palette, quiet: out.options.quiet)
        let verb = request.captions == .burn ? "captioning" : "cutting"
        let started = Date()
        let report = try await pipeline.run(request) { phase in
            switch phase {
            case .downloading(let model, let f): progress.update(f, label: "downloading \(model), first run only")
            case .loading(let model): progress.update(nil, label: FirstLoad.label(model))
            case .transcribing(let f): progress.update(f, label: "transcribing")
            case .selecting: progress.update(nil, label: "selecting")
            case .cutting(let done, let of):
                progress.update(Double(done) / Double(max(of, 1)), label: "\(verb) \(min(done + 1, of)) of \(of)")
            }
        }
        progress.finish()
        for model in ["voz", "clips"] { FirstLoad.done(model) }
        for note in report.notes ?? [] { out.warn(note) }

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
            let span = "\(p.time(Format.stamp(pick.start))) to \(p.time(Format.stamp(pick.end)))"
            out.line("\(p.accent(String(format: "%2d", pick.id)))  \(span)  \(p.dim(Format.elapsed(pick.durationSec)))")
            out.line("    \(truncate(pick.text, to: 88))")
            if let file = pick.file { out.line("    \(p.dim(file))") }
            if let srt = pick.captions { out.line("    \(p.dim(srt))") }
        }
        let elapsed = Date().timeIntervalSince(started)
        out.note("\n\(report.clips.count) clip\(report.clips.count == 1 ? "" : "s") from \(Format.spoken(report.materialSec)) in \(Format.elapsed(elapsed)).")
    }

}
