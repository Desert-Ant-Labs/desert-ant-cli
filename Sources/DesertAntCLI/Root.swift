import ArgumentParser
import Foundation
import Usage

@main
struct DesertAnt: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "desertant",
        abstract: "Run Desert Ant Labs on-device models from the terminal.",
        discussion: """
        desertant runs small, focused models on your own machine. They suggest emoji, \
        redact personal details, transcribe speech, cut clips, and sort photos. Each \
        model downloads once, and nothing leaves the device when it runs.

        Run a model by its verb, such as `desertant emo "pay my bills"`, or by its id \
        with `run`. `flow run` chains several models in one command, and \
        `flow templates` lists the ready-made flows. Browse the catalog with `models`, \
        `search`, and `info`. Add `--json` to any command for a machine-readable \
        result. `docs` prints the docs offline, and `docs agents` is the guide for \
        coding agents.
        """,
        // The CLI and the core SDK move separately; a bug report needs both.
        version: Version.full,
        subcommands: {
            var commands: [ParsableCommand.Type] = [
            Home.self,
            Models.self,
            Search.self,
            Info.self,
            Doctor.self,
            Pull.self,
            Cache.self,
            Run.self,
            EmoVerb.self,
            RedactVerb.self,
            GistVerb.self,
            TongueVerb.self,
            ClearVerb.self,
            EarVerb.self,
            WhoVerb.self,
            VozVerb.self,
            UhmVerb.self,
            ClipsVerb.self,
            ToxicVerb.self,
            ModeratorVerb.self,
            EyeVerb.self,
            FaceVerb.self,
            FlowCommand.self,
            Schema.self,
            Docs.self,
            Setup.self,
            Auth.self,
            Update.self,
            ]
            // Title runs on MLX and is compiled in only when the build asks for it.
            #if TITLE
            commands.append(TitleVerb.self)
            #endif
            return commands
        }(),
        defaultSubcommand: Home.self
    )

    /// A process that exits under a license request in flight can crash.
    static func main() async {
        if let key = APIKey.current?.key {
            Usage.DesertAnt.configure(apiKey: key)
        }
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
            await Usage.DesertAnt.flushLicenses()
        } catch {
            await Usage.DesertAnt.flushLicenses()
            exit(withError: error)
        }
    }
}
