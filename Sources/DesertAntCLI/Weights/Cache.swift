import ArgumentParser
import Foundation

// `desertant cache`. Where the weights live, how big they are, and which models are
// on disk. `--path` prints just the directory; `--clean --force` empties it.

struct Cache: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cache",
        abstract: "Show or clear the downloaded model cache."
    )

    @Flag(name: .long, help: "Print only the cache directory.")
    var path = false

    @Flag(name: .long, help: "Delete every downloaded model.")
    var clean = false

    @Flag(name: .long, help: "Confirm --clean without the prompt.")
    var force = false

    @OptionGroup var options: GlobalOptions

    struct Report: Encodable {
        let path: String
        let sizeBytes: Int64
        let size: String
        let downloaded: [String]
    }

    func run() throws {
        let out = Output(options: options)
        let root = CacheLocation.root

        if path {
            print(root)
            return
        }

        if clean {
            guard force else {
                out.line("This deletes every downloaded model under \(root), a directory other Desert Ant apps share.")
                out.note("Run again with --clean --force to confirm.")
                return
            }
            if FileManager.default.fileExists(atPath: root) {
                try FileManager.default.removeItem(atPath: root)
            }
            if out.isJSON { out.emit(["cleaned": true]) } else {
                out.line("\(out.palette.accent("cleaned"))  the cache is empty.")
            }
            return
        }

        let bytes = CacheLocation.sizeBytes
        let downloaded = CacheLocation.downloaded
        if out.isJSON {
            out.emit(Report(path: root, sizeBytes: bytes, size: CacheLocation.human(bytes),
                            downloaded: downloaded))
            return
        }

        let p = out.palette
        out.line()
        out.line("\(p.dim("path    "))\(root)")
        out.line("\(p.dim("size    "))\(CacheLocation.human(bytes))")
        out.line("\(p.dim("models  "))\(downloaded.isEmpty ? p.dim("none downloaded yet") : downloaded.joined(separator: ", "))")
        out.line()
    }
}
