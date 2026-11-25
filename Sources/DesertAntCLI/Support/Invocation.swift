import Foundation

enum Invocation {
    static let name: String = {
        let raw = CommandLine.arguments.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "desertant"
        return raw == "da" ? "da" : "desertant"
    }()
}
