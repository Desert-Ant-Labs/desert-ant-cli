// swift-tools-version: 6.1
import Foundation
import PackageDescription

// A trait request is unconditional and would pull mlx-swift into the Linux build,
// so DESERTANT_MLX=1 turns it on. Tools/check, install, and package set it on macOS.
let mlx = ProcessInfo.processInfo.environment["DESERTANT_MLX"] != nil

// Move this pin and CORE_REF together.
let core = "desert-ant-core"

func vendoredLibPath(_ runtime: String) -> [LinkerSetting] {
    #if os(Windows)
    let root = Context.packageDirectory
    for dir in ["\(root)/Vendor/\(runtime)/lib/windows-x64",
                "\(root)/../desert-ant-core/Vendor/\(runtime)/lib/windows-x64"]
    where FileManager.default.fileExists(atPath: dir) {
        return [.unsafeFlags(["-Xlinker", "/LIBPATH:\(dir)"], .when(platforms: [.windows]))]
    }
    #endif
    return []
}

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
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/desert-ant-labs/desert-ant-core.git", exact: "6.0.0", traits: mlx ? ["MLX"] : []),
    ],
    targets: [
        .executableTarget(
            name: "DesertAntCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Emo", package: core),
                .product(name: "Redact", package: core),
                .product(name: "Gist", package: core),
                .product(name: "Clear", package: core),
                .product(name: "Ear", package: core),
                .product(name: "Tongue", package: core),
                .product(name: "Toxic", package: core),
                .product(name: "AudioIO", package: core),
                .product(name: "Clips", package: core),
                .product(name: "Transcript", package: core),
                .product(name: "Voz", package: core, condition: .when(platforms: [.macOS, .linux, .windows])),
                .product(name: "Uhm", package: core),
                .product(name: "Moderator", package: core),
                .product(name: "Eye", package: core),
                .product(name: "Face", package: core),
                .product(name: "Who", package: core),
                .product(name: "ModelStore", package: core),
                .product(name: "Usage", package: core),
                .target(name: "CQuietLiteRt", condition: .when(platforms: [.linux])),
            ] + (mlx ? [.product(name: "Title", package: core, condition: .when(platforms: [.macOS]))] : []),
            swiftSettings: mlx ? [.define("TITLE")] : [],
            linkerSettings: vendoredLibPath("litert") + vendoredLibPath("onnxruntime")
        ),
        .target(name: "CQuietLiteRt"),
        .testTarget(
            name: "DesertAntCLITests",
            dependencies: ["DesertAntCLI"]
        ),
    ]
)
