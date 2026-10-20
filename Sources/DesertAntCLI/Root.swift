import ArgumentParser
import Foundation
import Usage

// desertant. The root command and the tree under it. The binary installs as
// `desertant` with a `da` alias.

@main
struct DesertAnt: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "desertant",
        abstract: "Run Desert Ant Labs on-device models from the terminal.",
        discussion: """
        Small, focused models that run on your own machine: emoji suggestions, PII \
        redaction, topic tagging, speech enhancement. Weights download once and \
        cache; nothing leaves the device when a model runs.

        Browse the catalog with `models`, `search`, and `info`. Run a model by its verb \
        (`desertant emo "pay my bills"`) or uniformly with `run`. Add `--json` to any \
        command for a machine-readable result. `docs` prints the docs offline; \
        `docs agents` is the contract for a coding agent.
        """,
        // The CLI and the core SDK move separately; a bug report needs both.
        version: Version.full,
        subcommands: {
            var commands: [ParsableCommand.Type] = [
            // Discover.
            Home.self,
            Models.self,
            Search.self,
            Info.self,
            Doctor.self,
            // Weights.
            Pull.self,
            Cache.self,
            // Run.
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
            ModeratorVerb.self,
            EyeVerb.self,
            FlowCommand.self,
            // Agents.
            Schema.self,
            Docs.self,
            Setup.self,
            // Itself.
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

    /// ArgumentParser's own entry point, plus a wait for core's network requests still in
    /// flight: a process that exits under one can crash on the way out.
    static func main() async {
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
            await TelemetryDebug.shared.flushAndWait()
        } catch {
            await TelemetryDebug.shared.flushAndWait()
            exit(withError: error)
        }
    }
}
