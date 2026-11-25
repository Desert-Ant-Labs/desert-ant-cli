import Foundation
import ModelStore

// Must match core's cache path: `<platform cache>/desert-ant-models` (desert-ant-core, ModelStore.swift).

enum CacheLocation {
    static var root: String {
        (FoundationFileSystem().defaultCacheRoot() as NSString)
            .appendingPathComponent("desert-ant-models")
    }

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

    static var downloaded: [String] {
        Runners.all.values.filter { $0.isDownloaded() }.map(\.id).sorted()
    }

    static func human(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 { return "\(bytes / 1_000_000_000)GB" }
        if bytes >= 1_000_000 { return "\(bytes / 1_000_000)MB" }
        if bytes >= 1_000 { return "\(bytes / 1_000)KB" }
        return "\(bytes)B"
    }
}
