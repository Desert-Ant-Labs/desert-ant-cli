import ArgumentParser
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
            if !check { out.line(action(for: source, newer: newer)) }
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
            out.line("Installing \(latest) into \(binDir).")
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

    /// macOS and Linux replace a running binary safely; on Windows install.ps1 moves the running files aside.
    private func runInstaller(binDir: String) async throws {
        let process = Process()
        var env = ProcessInfo.processInfo.environment
        #if os(Windows)
        guard let url = URL(string: Release.windowsInstallScript),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw RunError("could not download \(Release.windowsInstallScript).")
        }
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("desertant-install-\(UUID().uuidString).ps1")
        try data.write(to: script)
        defer { try? FileManager.default.removeItem(at: script) }
        process.executableURL = URL(fileURLWithPath: SearchPath.find("powershell")
            ?? #"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"#)
        process.arguments = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script.path]
        env["DESERTANT_HOME"] = binDir
        #else
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "curl -fsSL \(Release.installScript) | sh"]
        env["DESERTANT_BIN"] = binDir
        #endif
        process.environment = env
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RunError("the installer exited with status \(process.terminationStatus).")
        }
    }
}
