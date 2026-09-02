import Foundation

// The name this process was started as: `da` or `desertant`. Help and hints use it, so
// what the screen suggests is what the reader just typed.

enum Invocation {
    static let name: String = {
        let raw = CommandLine.arguments.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "desertant"
        return raw == "da" ? "da" : "desertant"
    }()
}
