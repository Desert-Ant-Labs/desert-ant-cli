import Foundation

// A once-a-day look at the latest release, for the home screen only. The result is
// cached so a day of `da` costs one request, and nothing runs under --json, in a
// pipe, or with DESERTANT_NO_UPDATE_CHECK set.

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

    /// A line to show when a newer release exists, else nil.
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
