import Foundation

// A file or image verb takes one path, several, or a folder. Expansion happens once,
// here, so every runner still sees one file at a time and the shell keeps doing the
// globbing. A folder is filtered by what the model reads; the rest is reported once.

enum Inputs {
    struct Expanded {
        /// The files to run, in the order given; a folder's files A-Z by name.
        let files: [String]
        /// Files inside a folder the model does not read, for one note.
        let skipped: [String]
        /// Whether the result is a list: more than one path, or any folder.
        let isBatch: Bool
    }

    static func expand(_ paths: [String], kind: RunInputKind, recursive: Bool) throws -> Expanded {
        let fm = FileManager.default
        var files: [String] = []
        var skipped: [String] = []
        var sawFolder = false
        var passedFolders = false
        for path in paths {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                files.append(path)
                continue
            }
            sawFolder = true
            let listed = try list(URL(fileURLWithPath: path), recursive: recursive)
            passedFolders = passedFolders || listed.passedFolders
            for name in listed.names {
                let ext = (name as NSString).pathExtension.lowercased()
                if kind.extensions.contains(ext) {
                    // Joined as typed, so a relative folder stays relative on screen.
                    files.append((path as NSString).appendingPathComponent(name))
                } else {
                    skipped.append(name)
                }
            }
        }
        let isBatch = sawFolder || paths.count > 1
        if files.isEmpty, sawFolder {
            throw RunError("no \(kind.noun) files in \(paths.joined(separator: ", "))\(passedFolders ? ". Pass --recursive to look inside its folders" : "").")
        }
        return Expanded(files: files, skipped: skipped, isBatch: isBatch)
    }

    /// Visible files under `dir` as relative names, A-Z. Hidden entries and, without
    /// `recursive`, folders are left out; `passedFolders` says whether any were.
    private static func list(_ dir: URL, recursive: Bool) throws -> (names: [String], passedFolders: Bool) {
        let fm = FileManager.default
        var names: [String] = []
        var passed = false
        for entry in try fm.contentsOfDirectory(atPath: dir.path).sorted() where !entry.hasPrefix(".") {
            var isDir: ObjCBool = false
            let full = dir.appendingPathComponent(entry)
            guard fm.fileExists(atPath: full.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if recursive {
                    names += try list(full, recursive: true).names.map { "\(entry)/\($0)" }
                } else {
                    passed = true
                }
            } else {
                names.append(entry)
            }
        }
        return (names, passed)
    }
}
