import Foundation

enum SearchPath {
    static var current: String { variable("PATH") ?? "" }

    static func find(_ name: String, in path: String = current) -> String? {
        let fm = FileManager.default
        #if os(Windows)
        // A name with a PATHEXT extension runs, as cmd.exe decides it; npm installs .cmd files.
        let suffixes = (variable("PATHEXT") ?? ".COM;.EXE;.BAT;.CMD").split(separator: ";").map { String($0).lowercased() }
        let runs = { fm.fileExists(atPath: $0) }
        let separator: Character = ";"
        #else
        let suffixes = [""]
        let runs = { fm.isExecutableFile(atPath: $0) }
        let separator: Character = ":"
        #endif
        return path.split(separator: separator).lazy
            .flatMap { dir in suffixes.lazy.map { (String(dir) as NSString).appendingPathComponent(name + $0) } }
            .first(where: runs)
    }

    private static func variable(_ name: String) -> String? {
        let env = ProcessInfo.processInfo.environment
        #if os(Windows)
        // Windows spells it Path, and treats the name without regard to case.
        return env.first { $0.key.uppercased() == name }?.value
        #else
        return env[name]
        #endif
    }
}
