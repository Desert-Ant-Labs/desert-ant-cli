import Foundation

enum RunInputKind: String, Sendable {
    case text
    case file
    case image
    case visual
}

struct RunOption: Sendable {
    let name: String
    let help: String
}

struct Intake: Sendable {
    let kind: String
    let option: String
}

protocol ModelRunner: Sendable {
    var id: String { get }
    var inputKind: RunInputKind { get }
    var options: [RunOption] { get }
    var emits: String? { get }
    var accepts: [Intake] { get }

    func validate(_ arguments: RunArguments) throws

    func isDownloaded() -> Bool
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws

    func run(_ input: String, arguments: RunArguments, out: Output) async throws
}

extension ModelRunner {
    func validate(_ arguments: RunArguments) throws {}
    var options: [RunOption] { [] }
    var emits: String? { nil }
    var accepts: [Intake] { [] }
}

protocol SetRunner: ModelRunner {
    func wantsSet(_ arguments: RunArguments) -> Bool
    func runSet(_ inputs: [String], batch: Bool, arguments: RunArguments, out: Output) async throws
}

struct RunArguments: Sendable {
    private(set) var values: [String: String] = [:]

    init(_ pairs: [String] = []) {
        for pair in pairs {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            values[String(pair[..<eq]).lowercased()] = String(pair[pair.index(after: eq)...])
        }
    }

    mutating func set(_ key: String, _ value: Any?) {
        guard let value else { return }
        values[key.lowercased()] = "\(value)"
    }

    subscript(_ key: String) -> String? { values[key.lowercased()] }
    func int(_ key: String) -> Int? { self[key].flatMap(Int.init) }
    func double(_ key: String) -> Double? { self[key].flatMap(Double.init) }
}

struct RunError: Error, CustomStringConvertible {
    let description: String
    init(_ m: String) { description = m }
}

extension RunInputKind {
    var placeholder: String {
        switch self {
        case .text: "\"<text>\""
        case .file: "<file>"
        case .image: "<image>"
        case .visual: "<photo or video>"
        }
    }

    var extensions: Set<String> {
        switch self {
        case .text: []
        case .file: ["mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac", "mp4", "mov", "m4v"]
        case .image: ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp"]
        case .visual: Self.image.extensions.union(Self.videoExtensions)
        }
    }

    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    static func isVideo(_ path: String) -> Bool {
        videoExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    var noun: String {
        switch self {
        case .text: "text"
        case .file: "audio or video"
        case .image: "image"
        case .visual: "image or video"
        }
    }

    var rejected: String {
        switch self {
        case .text: "not text"
        case .file: "not audio or video"
        case .image: "not an image"
        case .visual: "not an image or video"
        }
    }
}
