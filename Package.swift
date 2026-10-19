// swift-tools-version: 6.1
import Foundation
import PackageDescription

// desert-ant-cli. Run every Desert Ant Labs model from the terminal, discover the
// catalog, and hand the same models to a coding agent as JSON.
//
// The catalog is manifest.json, a vendored copy of the registry desert-ant-core
// publishes, compiled in by Tools/embed. Running a model is a thin per-model adapter
// over its desert-ant-core SDK.

// Title runs on MLX behind core's `MLX` package trait. A trait request in a manifest
// is unconditional and would pull mlx-swift into the Linux build, so the trait is
// turned on at manifest time by DESERTANT_MLX=1, which Tools/check, Tools/install,
// and Tools/package set on macOS. The Title code sits behind `#if TITLE`.
let mlx = ProcessInfo.processInfo.environment["DESERTANT_MLX"] != nil

// desert-ant-core comes from GitHub, pinned to the release CORE_REF names. Move both
// together: CORE_REF feeds the manifest sync and CI, this pin feeds the build.
let core = "desert-ant-core"

let package = Package(
    name: "desert-ant-cli",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "desertant", targets: ["DesertAntCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/desert-ant-labs/desert-ant-core.git", exact: "4.0.0", traits: mlx ? ["MLX"] : []),
    ],
    targets: [
        .executableTarget(
            name: "DesertAntCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                // The CLI's selection from the catalog (see Run/Registry.swift).
                .product(name: "Emo", package: core),
                .product(name: "Redact", package: core),
                .product(name: "Gist", package: core),
                .product(name: "Clear", package: core),
                .product(name: "Ear", package: core),
                .product(name: "Tongue", package: core),
                // Audio decode for the models that take samples (ear, uhm).
                .product(name: "AudioIO", package: core),
                // The clips pipeline and transcripts. Voz runs on Core ML on Apple, LiteRT on Linux.
                .product(name: "Clips", package: core),
                .product(name: "Transcript", package: core),
                .product(name: "Voz", package: core, condition: .when(platforms: [.macOS, .linux])),
                .product(name: "Uhm", package: core, condition: .when(platforms: [.macOS])),
                .product(name: "Moderator", package: core),
                .product(name: "Eye", package: core),
                .product(name: "Who", package: core),
                // The download cache lives here; the cache command reads its root.
                .product(name: "ModelStore", package: core),
                // Core's requests in flight, waited for before exit (see Root.swift).
                .product(name: "Usage", package: core),
                // LiteRT's log level, set to errors on Linux.
                .target(name: "CQuietLiteRt", condition: .when(platforms: [.linux])),
            ] + (mlx ? [.product(name: "Title", package: core, condition: .when(platforms: [.macOS]))] : []),
            swiftSettings: mlx ? [.define("TITLE")] : []
            // No resources on purpose: the manifest, version, and docs are compiled in
            // (Generated/Embedded.swift, from Tools/embed) so the binary is one file.
        ),
        .target(name: "CQuietLiteRt"),
        .testTarget(
            name: "DesertAntCLITests",
            dependencies: ["DesertAntCLI"]
        ),
    ]
)
