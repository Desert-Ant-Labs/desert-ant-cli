import ArgumentParser
import Foundation

// `desertant setup [agent]`. Writes the adapter each coding agent reads, from the
// copies inside the binary: a skill for Claude Code and Pi, a marked section in
// AGENTS.md for Codex. With no agent named, every agent found on this machine.

struct Setup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Set up Claude Code, Codex, or Pi to use desertant.",
        discussion: "Writes into the current project. --global writes where the agent looks for every project. Run again after an update to refresh."
    )

    enum Agent: String, CaseIterable, ExpressibleByArgument {
        case claude, codex, pi

        /// Whether the agent seems to be on this machine.
        var isPresent: Bool {
            let home = NSHomeDirectory()
            switch self {
            case .claude: return Setup.onPath("claude") || FileManager.default.fileExists(atPath: home + "/.claude")
            case .codex: return Setup.onPath("codex") || FileManager.default.fileExists(atPath: home + "/.codex")
            case .pi: return Setup.onPath("pi") || FileManager.default.fileExists(atPath: home + "/.pi")
            }
        }

        /// Where the adapter goes, in a project or for the user.
        func destination(global: Bool) -> String {
            let root = global ? NSHomeDirectory() : FileManager.default.currentDirectoryPath
            switch self {
            case .claude: return root + "/.claude/skills/desertant/SKILL.md"
            case .pi: return global ? root + "/.pi/agent/skills/desertant/SKILL.md" : root + "/.pi/skills/desertant/SKILL.md"
            case .codex: return root + (global ? "/.codex/AGENTS.md" : "/AGENTS.md")
            }
        }
    }

    @Argument(help: "claude, codex, or pi. Omit for every agent found on this machine.")
    var agent: Agent?

    @Flag(name: .long, help: "Write where the agent looks for every project, not this one.")
    var global = false

    @OptionGroup var options: GlobalOptions

    struct Written: Encodable {
        let agent: String
        let path: String
        let action: String
    }

    static func onPath(_ name: String) -> Bool {
        (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
            .contains { FileManager.default.isExecutableFile(atPath: "\($0)/\(name)") }
    }

    static let markerStart = "<!-- desertant start -->"
    static let markerEnd = "<!-- desertant end -->"

    /// `text` with the desertant section replaced, or appended when there is none.
    static func withSection(_ text: String, body: String) -> String {
        let section = "\(markerStart)\n\(body.trimmingCharacters(in: .newlines))\n\(markerEnd)\n"
        if let start = text.range(of: markerStart), let end = text.range(of: markerEnd) {
            return text.replacingCharacters(in: start.lowerBound..<end.upperBound, with: section.trimmingCharacters(in: .newlines))
        }
        let base = text.isEmpty ? "" : text.trimmingCharacters(in: .newlines) + "\n\n"
        return base + section
    }

    func run() throws {
        let out = Output(options: options)
        let targets = agent.map { [$0] } ?? Agent.allCases.filter(\.isPresent)
        guard !targets.isEmpty else {
            throw RunError("no coding agent found on this machine. Name one: desertant setup claude, codex, or pi.")
        }
        func page(_ name: String) throws -> String {
            guard let doc = Embedded.docs.first(where: { $0.name == name }) else { throw RunError("the \(name) page is missing from this build.") }
            return doc.markdown
        }
        var results: [Written] = []

        for target in targets {
            let path = target.destination(global: global)
            let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            let content: String
            switch target {
            case .claude, .pi: content = try page("skill")
            case .codex: content = Self.withSection(existing, body: try page("codex"))
            }
            let action: String
            if existing == content {
                action = "current"
            } else {
                try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                        withIntermediateDirectories: true)
                try content.write(toFile: path, atomically: true, encoding: .utf8)
                action = existing.isEmpty ? "written" : "updated"
            }
            results.append(Written(agent: target.rawValue, path: path, action: action))
        }

        if out.isJSON {
            out.emit(results)
            return
        }
        let p = out.palette
        for r in results {
            out.line("\(p.accent(r.action.padding(toLength: 8, withPad: " ", startingAt: 0)))\(p.model(r.agent))  \(p.dim(r.path))")
        }
    }
}
