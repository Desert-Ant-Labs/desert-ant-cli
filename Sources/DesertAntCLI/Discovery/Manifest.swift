import Foundation

// The catalog, decoded from the vendored `manifest.json`. Field names and enum domains
// match what `desert-ant-core/mise-tasks/check/manifest` enforces.

/// The whole registry: the org, its license, and every model.
struct Manifest: Codable, Sendable {
    var schemaVersion: Int
    var sdkVersion: String
    var org: Org
    var license: License
    var models: [Model]

    struct Org: Codable, Sendable {
        var name: String
        var site: String
        var github: String
        var hub: String
        var npmScope: String
        var mavenGroup: String
    }

    struct License: Codable, Sendable {
        var id: String
        var url: String
    }
}

/// One model in the catalog.
struct Model: Codable, Sendable {
    var id: String
    var name: String
    var tagline: String
    var summary: String
    var category: String
    var lifecycle: Lifecycle
    var visibility: Visibility
    var home: String?
    var sdks: [String: SDK]
    var weights: Weights
    var runtime: [Runtime]
    var variants: [Variant]
    var hub: Hub
    var languages: Languages?
    var demo: Demo?

    struct SDK: Codable, Sendable {
        var status: SDKStatus
        var package: String?
        var platforms: [Platform]?
        var version: String?
    }

    struct Weights: Codable, Sendable {
        var source: WeightsSource
        var repo: String?
        var url: String?
        var revision: String?
        var license: String?
    }

    struct Variant: Codable, Sendable {
        var id: String
        var `default`: Bool
        var note: String?
    }

    struct Hub: Codable, Sendable {
        var tags: [String]
        var pipelineTag: String?
        var libraryName: String?
    }

    struct Languages: Codable, Sendable {
        var count: Int?
        var codes: [String]?
        var basis: String
        var source: String?
    }

    struct Demo: Codable, Sendable {
        var space: String?
        var embed: String?
        var page: String?
    }
}

// MARK: - Enum domains

// An unknown value decodes to `.other` so a newer manifest never breaks an older
// binary. Each enum spells out `init(from:)` because a synthesized decoder would win
// over a protocol default and lose the fallback.

extension RawRepresentable where RawValue == String {
    /// Decode a string, falling back to `other` for an unknown value.
    static func lenient(from decoder: Decoder, other: Self) throws -> Self {
        Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? other
    }
}

enum Lifecycle: String, Codable, Sendable {
    case stable, beta, experimental, deprecated, other
    case closedBeta = "closed-beta"
    init(from decoder: Decoder) throws { self = try Self.lenient(from: decoder, other: .other) }
}

enum Visibility: String, Codable, Sendable {
    case `public`, `internal`, other
    init(from decoder: Decoder) throws { self = try Self.lenient(from: decoder, other: .other) }
}

enum SDKStatus: String, Codable, Sendable {
    case live, planned, none, other
    init(from decoder: Decoder) throws { self = try Self.lenient(from: decoder, other: .other) }
}

enum Platform: String, Codable, Sendable {
    case apple, android, linux, windows, web, node, other
    init(from decoder: Decoder) throws { self = try Self.lenient(from: decoder, other: .other) }
}

enum Runtime: String, Codable, Sendable {
    case coreml, litert, mlx, pure, other
    init(from decoder: Decoder) throws { self = try Self.lenient(from: decoder, other: .other) }

    /// The name people know it by.
    var label: String {
        switch self {
        case .coreml: "Core ML"
        case .litert: "LiteRT"
        case .mlx: "MLX"
        case .pure: "pure Swift"
        case .other: "other"
        }
    }
}

enum WeightsSource: String, Codable, Sendable {
    case hub, bundled, none, other
    init(from decoder: Decoder) throws { self = try Self.lenient(from: decoder, other: .other) }
}

// MARK: - Loading and querying

extension Manifest {
    /// The decoded embedded manifest. One that does not decode is a build error
    /// (Tools/embed validates the JSON), so it traps rather than throwing.
    static let shared: Manifest = {
        do {
            return try JSONDecoder().decode(Manifest.self, from: Data(Embedded.manifest.utf8))
        } catch {
            fatalError("embedded manifest did not decode: \(error)")
        }
    }()

    /// A model by id, case-insensitive, or nil.
    func model(_ id: String) -> Model? {
        models.first { $0.id == id.lowercased() }
    }

    /// Every model A-Z by id, sorted so no command depends on the manifest's order.
    var byID: [Model] { models.sorted { $0.id < $1.id } }
}

extension Model {
    /// The Swift SDK entry, whatever its status.
    var swift: SDK? { sdks["swift"] }

    /// Whether any SDK ships this model, the same test `manifest-docs.mjs` uses.
    var ships: Bool { sdks.values.contains { $0.status == .live } }

    /// The platforms the Swift SDK runs on, for display.
    var swiftPlatforms: [Platform] { swift?.platforms ?? [] }

    /// What `search` matches against: every name a person might type.
    var searchHaystack: String {
        ([id, name, tagline, summary, category] + hub.tags).joined(separator: " ").lowercased()
    }
}

extension Manifest {
    /// A model's one-line summary, for the verb's help and the home screen.
    static func summary(_ id: String) -> String { shared.model(id)?.summary ?? id }
}
