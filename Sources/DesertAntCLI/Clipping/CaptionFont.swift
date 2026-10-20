import Foundation
#if canImport(CoreText)
import CoreText
#endif

/// A font file and the numbers both renderers size text by. libass scales a font so
/// that its Windows ascent and descent together fill the line height, and Core Text
/// is given the same em size, so a line of text is the same size on macOS and Linux.
struct CaptionFont: Sendable, Equatable {
    let file: URL
    /// The face within a collection.
    let index: Int
    let family: String
    let weight: Int
    let unitsPerEm: Double
    let ascent: Double
    let descent: Double

    /// The em size that makes a line `lineHeight` pixels tall.
    func emSize(lineHeight: Double) -> Double { lineHeight * unitsPerEm / (ascent + descent) }

    /// The baseline's distance below the top of a line.
    func baseline(lineHeight: Double) -> Double { lineHeight * ascent / (ascent + descent) }

    /// The font desertant ships, beside the binary in `fonts/`.
    static let bundledName = "Inclusive Sans"

    static func resolve(_ name: String?, weight: Int) throws -> CaptionFont {
        guard let name else { return try bundled(weight: weight) }
        let expanded = (name as NSString).expandingTildeInPath
        if name.contains("/") || ["ttf", "otf", "ttc"].contains((name as NSString).pathExtension.lowercased()) {
            guard FileManager.default.fileExists(atPath: expanded) else { throw RunError("no font file at \(name).") }
            return try read(URL(fileURLWithPath: expanded), index: 0)
        }
        if name.caseInsensitiveCompare(bundledName) == .orderedSame { return try bundled(weight: weight) }
        return try system(name, weight: weight)
    }

    static func bundled(weight: Int) throws -> CaptionFont {
        let file = weight >= 600 ? "InclusiveSans-Bold.ttf" : "InclusiveSans-Regular.ttf"
        guard let folder = fontsFolder else {
            throw RunError("could not find the fonts folder that ships beside desertant. Reinstall desertant, or pass --caption-font with a font file.")
        }
        return try read(folder.appendingPathComponent(file), index: 0)
    }

    /// `fonts/` beside the binary, or in a folder above it for a build in the repo.
    static var fontsFolder: URL? {
        guard var dir = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent() else { return nil }
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("fonts")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("InclusiveSans-Bold.ttf").path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    /// A family installed on this machine: Core Text finds it on a Mac, fontconfig on
    /// Linux.
    static func system(_ family: String, weight: Int) throws -> CaptionFont {
        #if canImport(CoreText)
        let traits = [kCTFontWeightTrait: weightTrait(weight)] as CFDictionary
        let wanted = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family, kCTFontTraitsAttribute: traits] as CFDictionary)
        guard let match = CTFontDescriptorCreateMatchingFontDescriptor(wanted, NSSet(object: kCTFontFamilyNameAttribute)),
              let url = CTFontDescriptorCopyAttribute(match, kCTFontURLAttribute) as? URL else {
            throw RunError("no font named \(family) on this Mac. Pick a family from Font Book, or pass a .ttf or .otf file.")
        }
        let font = CTFontCreateWithFontDescriptor(match, 12, nil)
        let postscript = CTFontCopyPostScriptName(font) as String
        let faces = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]) ?? []
        let index = faces.firstIndex { (CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String) == postscript } ?? 0
        return try read(url, index: index)
        #else
        let fc = ["/usr/bin/fc-match", "/bin/fc-match", "/usr/local/bin/fc-match"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let fc else {
            throw RunError("finding the font \(family) needs fontconfig's fc-match, which is not installed. Pass a .ttf or .otf file instead.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fc)
        process.arguments = ["-f", "%{file}\n%{index}\n%{family}", "\(family):weight=\(fontconfigWeight(weight))"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard process.terminationStatus == 0, lines.count >= 3,
              lines[2].split(separator: ",").contains(where: { $0.caseInsensitiveCompare(family) == .orderedSame }) else {
            throw RunError("no font named \(family) on this machine. Pick a family from `fc-list : family`, or pass a .ttf or .otf file.")
        }
        return try read(URL(fileURLWithPath: lines[0]), index: Int(lines[1]) ?? 0)
        #endif
    }

    #if canImport(CoreText)
    /// Core Text's weight scale, -1 to 1, for a CSS weight.
    private static func weightTrait(_ w: Int) -> Double {
        switch w {
        case ..<200: -0.8
        case ..<300: -0.6
        case ..<400: -0.4
        case ..<500: 0
        case ..<600: 0.23
        case ..<700: 0.3
        case ..<800: 0.4
        case ..<900: 0.56
        default: 0.62
        }
    }
    #else
    private static func fontconfigWeight(_ w: Int) -> String {
        switch w {
        case ..<350: "light"
        case ..<450: "regular"
        case ..<550: "medium"
        case ..<650: "demibold"
        case ..<800: "bold"
        default: "black"
        }
    }
    #endif

    /// The family, weight, and metrics from a TrueType or OpenType file's own tables.
    static func read(_ url: URL, index: Int) throws -> CaptionFont {
        guard let data = try? Data(contentsOf: url), data.count > 12 else { throw RunError("could not read the font \(url.path).") }
        let bytes = [UInt8](data)
        func u16(_ o: Int) -> Int { o + 2 <= bytes.count ? Int(bytes[o]) << 8 | Int(bytes[o + 1]) : 0 }
        func i16(_ o: Int) -> Int { Int(Int16(bitPattern: UInt16(u16(o)))) }
        func u32(_ o: Int) -> Int { u16(o) << 16 | u16(o + 2) }
        var start = 0
        if bytes.starts(with: Array("ttcf".utf8)) {
            let count = u32(8)
            start = u32(12 + 4 * min(max(index, 0), max(count - 1, 0)))
        }
        var tables: [String: Int] = [:]
        for i in 0..<u16(start + 4) {
            let record = start + 12 + 16 * i
            guard record + 16 <= bytes.count else { break }
            tables[String(decoding: bytes[record..<record + 4], as: UTF8.self)] = u32(record + 8)
        }
        guard let head = tables["head"], let name = tables["name"] else {
            throw RunError("\(url.lastPathComponent) is not a TrueType or OpenType font.")
        }
        let unitsPerEm = Double(u16(head + 18))
        var ascent = 0.0, descent = 0.0, weight = 400
        if let os2 = tables["OS/2"] {
            weight = u16(os2 + 4)
            ascent = Double(u16(os2 + 74))
            descent = Double(u16(os2 + 76))
        }
        if ascent + descent <= 0, let hhea = tables["hhea"] {
            ascent = Double(i16(hhea + 4))
            descent = Double(-i16(hhea + 6))
        }
        guard unitsPerEm > 0, ascent + descent > 0 else { throw RunError("\(url.lastPathComponent) has no metrics to size text by.") }

        // The typographic family (16) before the legacy one (1), Windows Unicode first.
        let storage = name + u16(name + 4)
        var found: [Int: String] = [:]
        for i in 0..<u16(name + 2) {
            let r = name + 6 + 12 * i
            let platform = u16(r), id = u16(r + 6), length = u16(r + 8), offset = storage + u16(r + 10)
            guard id == 1 || id == 16, offset + length <= bytes.count else { continue }
            let raw = Data(bytes[offset..<offset + length])
            let text = platform == 3 || platform == 0
                ? String(data: raw, encoding: .utf16BigEndian)
                : String(data: raw, encoding: .macOSRoman)
            if let text, !text.isEmpty, found[id] == nil || platform == 3 { found[id] = text }
        }
        guard let family = found[16] ?? found[1] else { throw RunError("\(url.lastPathComponent) has no family name.") }
        return CaptionFont(file: url, index: index, family: family, weight: weight, unitsPerEm: unitsPerEm, ascent: ascent, descent: descent)
    }
}
