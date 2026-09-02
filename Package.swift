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

// desert-ant-core is always the sibling checkout; CORE_REF names the ref it is at.
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
        .package(path: "../desert-ant-core", traits: mlx ? ["MLX"] : []),
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
                // Audio decode for the models that take samples (ear, uhm).
                .product(name: "AudioIO", package: core),
                // The clips pipeline: selection everywhere, Voz on Apple platforms.
                .product(name: "Clips", package: core),
                .product(name: "Transcript", package: core),
                .product(name: "Voz", package: core, condition: .when(platforms: [.macOS])),
                .product(name: "Uhm", package: core, condition: .when(platforms: [.macOS])),
                // The download cache lives here; the cache command reads its root.
                .product(name: "ModelStore", package: core),
            ] + (mlx ? [.product(name: "Title", package: core, condition: .when(platforms: [.macOS]))] : []),
            swiftSettings: mlx ? [.define("TITLE")] : []
            // No resources on purpose: the manifest, version, and docs are compiled in
            // (Generated/Embedded.swift, from Tools/embed) so the binary is one file.
        ),
        .testTarget(
            name: "DesertAntCLITests",
            dependencies: ["DesertAntCLI"]
        ),
    ]
)
