import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking  // URLSession lives here on Linux.
#endif

enum Version {
    static let cli = Embedded.version

    static var core: String { Manifest.shared.sdkVersion }

    static var full: String { "\(cli) (desert-ant-core \(core))" }

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

enum Release {
    static let repo = "Desert-Ant-Labs/desert-ant-cli"
    static let installScript = "https://raw.githubusercontent.com/\(repo)/main/install.sh"
    static let windowsInstallScript = "https://raw.githubusercontent.com/\(repo)/main/install.ps1"

    static func latest() async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.setValue("desert-ant-cli/\(Version.cli)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        return tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
    }

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
        let url = URL(fileURLWithPath: exe).resolvingSymlinksInPath()
        let path = url.path.replacingOccurrences(of: "\\", with: "/")
        if path.contains("/Cellar/") || path.contains("/homebrew/") || path.contains("/linuxbrew/") {
            return .homebrew
        }
        if path.contains("/mise/") { return .mise }
        if path.contains("/.build/") { return .source }
        #if os(Windows)
        // install.ps1 puts the binary, da.exe, and the DLLs in one folder on PATH.
        return .script(binDir: url.deletingLastPathComponent().path)
        #else
        let bin = ProcessInfo.processInfo.environment["DESERTANT_BIN"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin")
        return .script(binDir: bin)
        #endif
    }
}
