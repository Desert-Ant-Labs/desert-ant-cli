import Foundation
import ModelStore

// Where core keeps downloaded weights: `<platform cache>/desert-ant-models`
// (desert-ant-core, ModelStore.swift). Read here once so `cache` and `doctor` agree.

enum CacheLocation {
    static var root: String {
        (FoundationFileSystem().defaultCacheRoot() as NSString)
            .appendingPathComponent("desert-ant-models")
    }

    /// Total bytes under the cache, or 0 when nothing has been downloaded.
    static var sizeBytes: Int64 {
        guard let e = FileManager.default.enumerator(atPath: root) else { return 0 }
        var total: Int64 = 0
        while let name = e.nextObject() as? String {
            let full = (root as NSString).appendingPathComponent(name)
            if let bytes = (try? FileManager.default.attributesOfItem(atPath: full))?[.size] as? Int64 {
                total += bytes
            }
        }
        return total
    }

    /// Ids of the runnable models whose weights are on disk, A-Z.
    static var downloaded: [String] {
        Runners.all.values.filter { $0.isDownloaded() }.map(\.id).sorted()
    }

    /// Bytes as a person reads them: 45MB, 608MB, 2GB. Unit against the number.
    static func human(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 { return "\(bytes / 1_000_000_000)GB" }
        if bytes >= 1_000_000 { return "\(bytes / 1_000_000)MB" }
        if bytes >= 1_000 { return "\(bytes / 1_000)KB" }
        return "\(bytes)B"
    }
}
