import ArgumentParser
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#elseif os(Windows)
import WinSDK
#endif

enum APIKey {
    static let platformURL = "https://platform.desertant.com/api-keys"

    enum Source: String, Encodable {
        case environment, saved
    }

    static var current: (key: String, source: Source)? {
        if let value = ProcessInfo.processInfo.environment["DAL_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return (value, .environment)
        }
        if let value = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return (value, .saved)
        }
        return nil
    }

    static var file: URL {
        let env = ProcessInfo.processInfo.environment
        #if os(Windows)
        let base = env["APPDATA"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("AppData/Roaming")
        #else
        let base = env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config")
        #endif
        return base.appendingPathComponent("desertant/api-key")
    }

    static func looksValid(_ key: String) -> Bool {
        key.hasPrefix("dal_") && key.count > 8 && !key.contains(where: \.isWhitespace)
    }

    static func save(_ key: String) throws {
        let fm = FileManager.default
        let dir = file.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        try (key + "\n").write(to: file, atomically: false, encoding: .utf8)
    }

    static func remove() throws -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        try FileManager.default.removeItem(at: file)
        return true
    }

    static func masked(_ key: String) -> String {
        String(key.prefix(8)) + "..."
    }
}

struct NotAKey: LocalizedError, CustomStringConvertible {
    var description: String { "That is not an API key. API keys start with dal_. Create an API key at \(APIKey.platformURL)." }
    var errorDescription: String? { description }
}

struct Auth: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Set the API key for production use.",
        discussion: "You only need an API key when you use our models in production. Create a free key at \(APIKey.platformURL) and save the key with `desertant auth login`. In CI or a pipeline, set DAL_API_KEY instead.",
        subcommands: [Login.self, Status.self, Logout.self],
        defaultSubcommand: Status.self
    )

    struct Login: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Save your API key.",
            discussion: "Opens \(APIKey.platformURL) to create a key, then asks you to paste the key. With --with-key, reads the key from standard input instead, for scripts: `echo $KEY | desertant auth login --with-key`."
        )

        @Flag(name: .customLong("with-key"), help: "Read the key from standard input.")
        var withKey = false

        @Flag(name: .customLong("no-browser"), help: "Print the link instead of opening the browser.")
        var noBrowser = false

        @OptionGroup var options: GlobalOptions

        func run() throws {
            let out = Output(options: options)
            let key: String
            if withKey || !Terminal.isTTY(STDIN_FILENO) {
                key = (readLine(strippingNewline: true) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                out.line("Create a free API key at \(APIKey.platformURL)")
                if !noBrowser { openInBrowser(APIKey.platformURL) }
                key = Self.prompt("Paste your API key: ")
            }
            guard APIKey.looksValid(key) else { throw NotAKey() }
            try APIKey.save(key)
            if out.isJSON {
                out.emit(Status.Report(apiKey: true, source: .saved, path: APIKey.file.path))
            } else {
                out.line("Saved your API key to \(APIKey.file.path).")
            }
        }

        static func prompt(_ message: String) -> String {
            #if os(Windows)
            print(message, terminator: "")
            return (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            #else
            guard let raw = getpass(message) else { return "" }
            return String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
            #endif
        }

        private func openInBrowser(_ url: String) {
            #if os(Windows)
            _ = url.withCString(encodedAs: UTF16.self) { ShellExecuteW(nil, nil, $0, nil, nil, SW_SHOWNORMAL) }
            #else
            #if os(macOS)
            let tool = "/usr/bin/open"
            #else
            let tool = "/usr/bin/xdg-open"
            #endif
            guard FileManager.default.isExecutableFile(atPath: tool) else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = [url]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            #endif
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show whether an API key is set.")

        @OptionGroup var options: GlobalOptions

        struct Report: Encodable {
            let apiKey: Bool
            let source: APIKey.Source?
            let path: String
        }

        func run() throws {
            let out = Output(options: options)
            let current = APIKey.current
            if out.isJSON {
                out.emit(Report(apiKey: current != nil, source: current?.source, path: APIKey.file.path))
                return
            }
            switch current {
            case let (key, .environment)?:
                out.line("API key \(APIKey.masked(key)) is set, from DAL_API_KEY.")
            case let (key, .saved)?:
                out.line("API key \(APIKey.masked(key)) is set, saved in \(APIKey.file.path).")
            case nil:
                out.line("No API key is set. You only need an API key when you use our models in production. Run `desertant auth login` to save the key.")
            }
        }
    }

    struct Logout: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove the saved API key.")

        @OptionGroup var options: GlobalOptions

        func run() throws {
            let out = Output(options: options)
            let removed = try APIKey.remove()
            if out.isJSON {
                out.emit(Status.Report(apiKey: APIKey.current != nil, source: APIKey.current?.source, path: APIKey.file.path))
                return
            }
            out.line(removed ? "Removed the saved API key." : "No saved API key to remove.")
            if APIKey.current?.source == .environment {
                out.line("DAL_API_KEY is still set in this shell.")
            }
        }
    }
}
