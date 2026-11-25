import Foundation

enum UpdateCheck {
    private struct Cached: Codable {
        let latest: String?
        let checkedAt: Date
    }

    private static var file: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent("desertant/latest-release.json")
    }

    static func notice(interactive: Bool) async -> String? {
        guard interactive, ProcessInfo.processInfo.environment["DESERTANT_NO_UPDATE_CHECK"] == nil else { return nil }
        var cached = (try? JSONDecoder().decode(Cached.self, from: Data(contentsOf: file)))
        if cached == nil || Date().timeIntervalSince(cached!.checkedAt) > 86_400 {
            cached = Cached(latest: await Release.latest(), checkedAt: Date())
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(cached).write(to: file)
        }
        guard let latest = cached?.latest, Version.isNewer(latest, than: Version.cli) else { return nil }
        return "\(latest) is out: \(Release.installSource.updateCommand)"
    }
}
