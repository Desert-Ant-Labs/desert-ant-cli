import ArgumentParser
import Foundation

// `desertant doctor`. What this machine can run, what is downloaded, whether a newer
// release exists, and how the catalog stands.

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check the runtimes, cache, version, and catalog on this machine."
    )

    @OptionGroup var options: GlobalOptions

    struct Report: Encodable {
        let os: String
        let arch: String
        let coreml: Bool
        let mlx: Bool
        let litert: Bool
        let cachePath: String
        let cacheBytes: Int64
        let downloaded: [String]
        let runnable: [String]
        let version: String
        let coreVersion: String
        let latest: String?
        let updateAvailable: Bool
        let updateCommand: String
        let models: Int
        let shipping: Int
    }

    // Compile-time facts about this binary. MLX (the Title model) needs Apple silicon.
    private static let os: String = {
        #if os(macOS)
        "macOS"
        #elseif os(Linux)
        "Linux"
        #else
        "other"
        #endif
    }()
    private static let arch: String = {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }()
    static let hasCoreML: Bool = {
        #if canImport(CoreML)
        true
        #else
        false
        #endif
    }()
    private static let hasMLX: Bool = {
        #if os(macOS) && arch(arm64)
        true
        #else
        false
        #endif
    }()
    private static let hasLiteRT: Bool = {
        #if os(Linux)
        true
        #else
        false
        #endif
    }()

    func run() async throws {
        let out = Output(options: options)
        let m = Manifest.shared
        let shipping = m.models.filter(\.ships).count
        let downloaded = CacheLocation.downloaded
        let runnable = Runners.all.keys.sorted()
        let bytes = CacheLocation.sizeBytes
        let latest = await Release.latest()
        let newer = latest.map { Version.isNewer($0, than: Version.cli) } ?? false
        let source = Release.installSource

        if out.isJSON {
            out.emit(Report(
                os: Self.os, arch: Self.arch, coreml: Self.hasCoreML, mlx: Self.hasMLX,
                litert: Self.hasLiteRT, cachePath: CacheLocation.root, cacheBytes: bytes,
                downloaded: downloaded, runnable: runnable,
                version: Version.cli, coreVersion: Version.core, latest: latest,
                updateAvailable: newer, updateCommand: source.updateCommand,
                models: m.models.count, shipping: shipping
            ))
            return
        }

        Brand.header(out)
        let p = out.palette
        func check(_ ok: Bool, _ label: String) -> String {
            "  " + (ok ? p.accent("ok") : p.dim("--")) + "  " + label
        }

        out.line(p.bold("Version"))
        out.line("  desertant \(Version.cli), desert-ant-core \(Version.core)")
        if let latest, newer {
            out.line("  \(p.accent("\(latest) is out")). Run \(p.bold(source.updateCommand)).")
        } else if latest != nil {
            out.line("  \(p.dim("up to date"))")
        } else {
            out.line("  \(p.dim("could not check for a newer release"))")
        }
        out.line()
        out.line(p.bold("Machine"))
        out.line("  \(Self.os) \(Self.arch)")
        out.line()
        out.line(p.bold("Runtimes"))
        out.line(check(Self.hasCoreML, "Core ML"))
        out.line(check(Self.hasMLX, "MLX, Apple silicon"))
        out.line(check(Self.hasLiteRT, "LiteRT"))
        out.line()
        out.line(p.bold("Models"))
        out.line("  \(runnable.count) runnable on this machine: \(runnable.joined(separator: ", "))")
        out.line("  \(downloaded.isEmpty ? "none downloaded yet" : "\(downloaded.count) downloaded: " + downloaded.joined(separator: ", "))")
        out.line()
        out.line(p.bold("Cache"))
        out.line("  \(CacheLocation.root), \(CacheLocation.human(bytes))")
        out.line()
        out.line(p.bold("Catalog"))
        out.line("  \(m.models.count) models, \(shipping) with a live SDK")
        out.line()
    }
}
