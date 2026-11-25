// `all` is built on first use, so a discovery command never touches a model SDK.

enum Runners {
    static let all: [String: any ModelRunner] = {
        var registry: [String: any ModelRunner] = [:]
        for runner in portable + platformGated {
            registry[runner.id] = runner
        }
        return registry
    }()

    private static let portable: [any ModelRunner] = [
        EmoRunner(),
        RedactRunner(),
        GistRunner(),
        ClearRunner(),
        EarRunner(),
        TongueRunner(),
        ToxicRunner(),
        ModeratorRunner(),
        EyeRunner(),
        FaceRunner(),
        WhoRunner(),
        ClipsRunner(),
        UhmRunner(),
    ]

    private static let platformGated: [any ModelRunner] = {
        var runners: [any ModelRunner] = []
        #if canImport(Voz)
        runners.append(VozRunner())
        #endif
        #if TITLE
        runners.append(TitleRunner())
        #endif
        return runners
    }()

    static let excluded: [String: String] = [
        "shapes": "takes stroke points, a job for the SDK",
        "align": "refines Apple SpeechAnalyzer timestamps; voz already times every word",
    ]

    static let unavailable: [String: String] = [:]

    static func runner(for id: String) -> (any ModelRunner)? { all[id.lowercased()] }
}
