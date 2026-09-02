import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking  // URLSession lives here on Linux.
#endif

// The CLI's version, from the `VERSION` file that `Tools/release` bumps and
// `Tools/embed` compiles in, and the core SDK version from the embedded manifest.

enum Version {
    /// This CLI, e.g. "0.1.0".
    static let cli = Embedded.version

    /// The desert-ant-core release the vendored manifest came from.
    static var core: String { Manifest.shared.sdkVersion }

    /// What `--version` prints.
    static var full: String { "\(cli) (desert-ant-core \(core))" }

    /// Numeric semver compare on "major.minor.patch"; a tag's leading "v" is ignored.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "v")).split(separator: ".")
                .map { Int($0) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// The published releases, and how this binary got here.
enum Release {
    static let repo = "Desert-Ant-Labs/desert-ant-cli"
    static let installScript = "https://raw.githubusercontent.com/\(repo)/main/install.sh"

    /// The latest release version, or nil when offline or the lookup fails. Never
    /// blocks a command for long: the request gives up after 3s.
    static func latest() async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.setValue("desert-ant-cli/\(Version.cli)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        return tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
    }

    /// How the running binary was installed, judged from where it lives.
    enum Source {
        case homebrew
        case mise
        case script(binDir: String)
        case source

        var updateCommand: String {
            switch self {
            case .homebrew: "brew upgrade desertant"
            case .mise: "mise upgrade ubi:\(Release.repo)"
            case .script: "desertant update"
            case .source: "git pull && Tools/install"
            }
        }
    }

    static var installSource: Source {
        guard let exe = Bundle.main.executablePath else { return .source }
        let path = URL(fileURLWithPath: exe).resolvingSymlinksInPath().path
        if path.contains("/Cellar/") || path.contains("/homebrew/") || path.contains("/linuxbrew/") {
            return .homebrew
        }
        if path.contains("/mise/") { return .mise }
        if path.contains("/.build/") { return .source }
        // The script installs into a private directory and symlinks into bin, which is
        // all the installer needs back.
        let bin = ProcessInfo.processInfo.environment["DESERTANT_BIN"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin")
        return .script(binDir: bin)
    }
}
