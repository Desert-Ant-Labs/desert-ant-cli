import Foundation

// The first load of a model version on a machine also specializes it for the Neural
// Engine, which takes a while. A marker per model and weights revision remembers that
// it has happened, so the loading label only warns when the wait is real.

enum FirstLoad {
    private static func marker(_ id: String) -> URL {
        let revision = Manifest.shared.model(id)?.weights.revision ?? "unknown"
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent("desertant/loaded/\(id)-\(revision)")
    }

    /// The progress label for loading `id`.
    static func label(_ id: String) -> String {
        FileManager.default.fileExists(atPath: marker(id).path)
            ? "loading \(id)"
            : "loading \(id), slower the first time on this Mac"
    }

    /// Record that `id` has loaded once on this machine.
    static func done(_ id: String) {
        let url = marker(id)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data().write(to: url)
    }
}
