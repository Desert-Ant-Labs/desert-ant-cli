import ArgumentParser
import Foundation

// `desertant update`. A script install runs the installer again; Homebrew, mise, and
// source builds own their binaries, so those get the one command to run instead.

struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update the CLI to the latest release."
    )

    @Flag(name: .long, help: "Only report whether a newer release exists.")
    var check = false

    @OptionGroup var global: GlobalOptions

    struct Report: Encodable {
        let current: String
        let latest: String?
        let updateAvailable: Bool
        let installedVia: String
        let updateCommand: String
    }

    func run() async throws {
        let out = Output(options: global)
        let p = out.palette
        let source = Release.installSource
        let latest = await Release.latest()
        let newer = latest.map { Version.isNewer($0, than: Version.cli) } ?? false

        if out.isJSON {
            out.emit(Report(current: Version.cli, latest: latest, updateAvailable: newer,
                            installedVia: label(source), updateCommand: source.updateCommand))
            if !check { out.note(action(for: source, newer: newer)) }
            return
        }

        guard let latest else {
            out.line("\(p.dim("current"))  \(Version.cli)")
            out.line("Could not reach GitHub to check for a newer release.")
            return
        }
        out.line("\(p.dim("current"))  \(Version.cli)")
        out.line("\(p.dim("latest "))  \(latest)")
        guard newer else {
            out.line(p.accent("Up to date."))
            return
        }
        if check {
            out.line("\(latest) is out. Run \(p.bold(source.updateCommand)).")
            return
        }

        switch source {
        case .script(let binDir):
            out.note("Installing \(latest) into \(binDir).")
            try await runInstaller(binDir: binDir)
        case .homebrew, .mise, .source:
            out.line("This copy is managed by \(label(source)). Run \(p.bold(source.updateCommand)).")
        }
    }

    private func label(_ s: Release.Source) -> String {
        switch s {
        case .homebrew: "homebrew"
        case .mise: "mise"
        case .script: "install script"
        case .source: "a source build"
        }
    }

    private func action(for source: Release.Source, newer: Bool) -> String {
        newer ? "Run \(source.updateCommand)." : "Up to date."
    }

    /// Run the install script again for the same bin directory. Replacing a running
    /// binary is safe on macOS and Linux: `install` writes a new file.
    private func runInstaller(binDir: String) async throws {
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = ["-c", "curl -fsSL \(Release.installScript) | sh"]
        var env = ProcessInfo.processInfo.environment
        env["DESERTANT_BIN"] = binDir
        sh.environment = env
        try sh.run()
        sh.waitUntilExit()
        guard sh.terminationStatus == 0 else {
            throw RunError("the installer exited with status \(sh.terminationStatus).")
        }
    }
}
