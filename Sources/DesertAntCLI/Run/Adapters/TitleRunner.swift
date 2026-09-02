#if TITLE
import Foundation
import Title

// Title: a short title and description for a passage of text. Runs on MLX, so Apple
// silicon only, in a build made with DESERTANT_MLX=1 (the Tools scripts set it on macOS).

struct TitleRunner: ModelRunner {
    let id = "title"
    let inputKind = RunInputKind.text

    func isDownloaded() -> Bool { TitleModel.isAvailable() }
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await TitleModel.resolve { progress($0.fraction) }
    }

    struct Document: Encodable {
        let title: String
        let description: String
    }

    func run(_ input: String, arguments: RunArguments, out: Output) async throws {
        let progress = Progress(palette: out.palette, quiet: out.options.quiet)
        progress.update(nil, label: "loading title, slower the first time on this Mac")
        let stored = try await TitleModel.resolve { _ in }
        let titles = try await Titles(directory: URL(fileURLWithPath: stored.rootPath))
        progress.update(nil, label: "writing")
        let card = try await titles.describe(input)
        progress.finish()

        if out.isJSON {
            out.emit(Document(title: card.title, description: card.description))
            return
        }
        out.line(out.palette.bold(card.title))
        out.line(card.description)
    }
}
#endif
