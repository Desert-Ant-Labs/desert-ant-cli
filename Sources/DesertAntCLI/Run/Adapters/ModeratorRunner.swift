import Foundation
import Moderator

// Moderator: whether an image shows nudity or sexual activity. ImageIO decodes the
// file on Apple platforms and ffmpeg elsewhere.

struct ModeratorRunner: ModelRunner {
    let id = "moderator"
    let inputKind = RunInputKind.image
    let options = [
        RunOption(name: "threshold", help: "Flag an image when its score reaches this value, from 0 to 1. Default 0.5."),
        RunOption(name: "policy", help: "standard, or allow-topless to allow a bare chest. Default standard."),
        RunOption(name: "quality", help: "How many crops Moderator scores: fast, balanced, or accurate. Default accurate."),
    ]

    private let model = Moderator()

    func isDownloaded() -> Bool { model.isDownloaded() }
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws {
        try await model.download(progress: progress)
    }

    struct Document: Encodable {
        let input: String
        let nsfw: Bool
        let score: Double
        let threshold: Double
        let policy: String
        let quality: String
        let regions: Regions
    }
    struct Regions: Encodable {
        let nipples: Double
        let genitals: Double
        let buttocks: Double
        let nude: Double
        let sexAct: Double
    }

    private static let policies: [String: Policy] = ["standard": .standard, "allow-topless": .allowTopless]
    private static let qualities: [String: Quality] = ["fast": .fast, "balanced": .balanced, "accurate": .accurate]

    private struct Settings {
        let options: Options
        let policy: String
        let quality: String
    }

    private func settings(_ arguments: RunArguments) throws -> Settings {
        var opts = Options()
        if let t = arguments.double("threshold") {
            guard (0...1).contains(t) else { throw RunError("threshold must be between 0 and 1.") }
            opts.threshold = t
        }
        let policyName = arguments["policy"]?.lowercased() ?? "standard"
        guard let policy = Self.policies[policyName] else {
            throw RunError("policy must be standard or allow-topless.")
        }
        let qualityName = arguments["quality"]?.lowercased() ?? "accurate"
        guard let quality = Self.qualities[qualityName] else {
            throw RunError("quality must be fast, balanced, or accurate.")
        }
        opts.policy = policy
        opts.quality = quality
        return Settings(options: opts, policy: policyName, quality: qualityName)
    }

    func validate(_ arguments: RunArguments) throws { _ = try settings(arguments) }

    func run(_ input: String, arguments: RunArguments, out: Output) async throws {
        guard FileManager.default.fileExists(atPath: input) else { throw RunError("no file at \(input).") }
        let settings = try settings(arguments)
        let opts = settings.options

        let pixels = try Self.pixels(input)
        let progress = Progress(palette: out.palette, quiet: out.options.quiet)
        progress.update(nil, label: "analyzing")
        let result = try await model.analyze(pixels, options: opts)
        progress.finish()

        let r = result.regions
        if out.isJSON {
            // The path as typed, like every other file model.
            out.emit(Document(
                input: input,
                nsfw: result.isNSFW, score: result.score, threshold: opts.threshold,
                policy: settings.policy, quality: settings.quality,
                regions: Regions(nipples: r.nipples, genitals: r.genitals, buttocks: r.buttocks,
                                 nude: r.nude, sexAct: r.sexAct)))
            return
        }
        let p = out.palette
        let verdict = result.isNSFW ? p.accent("nsfw") : p.bold("safe")
        out.line("\(verdict)  \(p.dim(String(format: "%.2f", result.score)))")
        let detail = [("nipples", r.nipples), ("genitals", r.genitals), ("buttocks", r.buttocks),
                      ("nude", r.nude), ("sex act", r.sexAct)]
        out.line(p.dim(detail.map { "\($0.0) \(String(format: "%.2f", $0.1))" }.joined(separator: "  ")))
    }

    /// Whether a photo is flagged at `threshold`, and its score, for the flow step.
    static func check(_ path: String, threshold: Double, with model: Moderator) async throws -> (nsfw: Bool, score: Double) {
        var options = Options()
        options.threshold = threshold
        let result = try await model.analyze(pixels(path), options: options)
        return (result.isNSFW, result.score)
    }

    static func pixels(_ input: String) throws -> ImagePixels {
        #if canImport(ImageIO)
        do {
            return try ImagePixels(contentsOf: URL(fileURLWithPath: input))
        } catch {
            throw RunError("could not read \(input) as an image.")
        }
        #else
        let tools = try FFmpeg.require(for: input)
        guard let image = try? FFmpeg.decodeImage(input, tools: tools) else {
            throw RunError("could not read \(input) as an image.")
        }
        let upright = Exif.upright(image.rgb, width: image.width, height: image.height,
                                   orientation: Exif.orientation(jpeg: Exif.head(input)))
        return try ImagePixels(width: upright.width, height: upright.height, rgb: upright.rgb)
        #endif
    }
}
