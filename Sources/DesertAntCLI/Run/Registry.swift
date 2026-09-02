// The runner registry: the CLI's selection from the catalog. To add a model, write its
// adapter under `Adapters/` and list it here; discovery, `info`, `pull`, `schema`, and
// `run` all read this map. `all` is built on first use, so a discovery command never
// touches a model SDK.

enum Runners {
    static let all: [String: any ModelRunner] = {
        var registry: [String: any ModelRunner] = [:]
        for runner in portable + appleOnly {
            registry[runner.id] = runner
        }
        return registry
    }()

    /// Core ML on Apple, LiteRT on Linux.
    private static let portable: [any ModelRunner] = [
        EmoRunner(),
        RedactRunner(),
        GistRunner(),
        ClearRunner(),
        EarRunner(),
        // Selection is portable; transcribing and cutting gate themselves inside.
        ClipsRunner(),
    ]

    /// Models whose frameworks exist only on Apple platforms.
    private static let appleOnly: [any ModelRunner] = {
        var runners: [any ModelRunner] = []
        #if canImport(CoreML) && canImport(AVFoundation)
        runners += [VozRunner(), UhmRunner()]
        #endif
        #if TITLE
        runners.append(TitleRunner())
        #endif
        return runners
    }()

    /// Shipping models the CLI leaves out on purpose, and the reason a reader sees.
    static let excluded: [String: String] = [
        "shapes": "takes stroke points, a job for the SDK",
        "align": "refines Apple SpeechAnalyzer timestamps; voz already times every word",
    ]

    static func runner(for id: String) -> (any ModelRunner)? { all[id.lowercased()] }
}
