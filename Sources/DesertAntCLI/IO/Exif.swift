import Foundation

// ffmpeg's handling of a JPEG's EXIF orientation differs between versions, so the CLI
// decodes with -noautorotate and turns the pixels upright itself, as ImageIO does.

enum Exif {
    /// The start of a file, where a JPEG keeps its EXIF: header segments are at most 64KB each.
    static func head(_ path: String) -> [UInt8] {
        FileHandle(forReadingAtPath: path).map { [UInt8]($0.readData(ofLength: 256 * 1024)) } ?? []
    }

    /// The EXIF orientation of a JPEG, 1...8, or 1 when there is none.
    static func orientation(jpeg bytes: [UInt8]) -> Int {
        guard let tiff = TIFF(jpeg: bytes), let value = tiff.short(0x0112, in: tiff.ifd0), (1...8).contains(value) else { return 1 }
        return value
    }

    /// When a JPEG was taken, `2026:10:18 10:38:33`, and its `+02:00` offset when it records one.
    static func dateTimeOriginal(jpeg bytes: [UInt8]) -> (stamp: String, offset: String?)? {
        guard let tiff = TIFF(jpeg: bytes), let pointer = tiff.long(0x8769, in: tiff.ifd0),
              let stamp = tiff.ascii(0x9003, in: pointer) else { return nil }
        return (stamp, tiff.ascii(0x9011, in: pointer))
    }

    /// The TIFF block inside a JPEG's EXIF segment, read by tag.
    private struct TIFF {
        let s: [UInt8]
        let little: Bool
        private(set) var ifd0 = 0

        init?(jpeg bytes: [UInt8]) {
            guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
            var i = 2
            while i + 4 <= bytes.count, bytes[i] == 0xFF {
                let marker = bytes[i + 1]
                if marker == 0xDA { break }
                let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
                guard length >= 2, i + 2 + length <= bytes.count else { break }
                let segment = Array(bytes[(i + 4)..<(i + 2 + length)])
                if marker == 0xE1, segment.count >= 14, Array(segment[0..<6]) == Array("Exif\0\0".utf8) {
                    s = Array(segment[6...])
                    switch (s[0], s[1]) {
                    case (0x49, 0x49): little = true
                    case (0x4D, 0x4D): little = false
                    default: return nil
                    }
                    guard let first = u32(4) else { return nil }
                    ifd0 = first
                    return
                }
                i += 2 + length
            }
            return nil
        }

        func u16(_ at: Int) -> Int? {
            guard at >= 0, at + 2 <= s.count else { return nil }
            return little ? Int(s[at]) | Int(s[at + 1]) << 8 : Int(s[at]) << 8 | Int(s[at + 1])
        }

        func u32(_ at: Int) -> Int? {
            guard let a = u16(at), let b = u16(at + 2) else { return nil }
            return little ? a | b << 16 : a << 16 | b
        }

        /// The 12-byte entry for `tag` in the directory at `ifd`.
        private func entry(_ tag: Int, in ifd: Int) -> Int? {
            guard let count = u16(ifd) else { return nil }
            for n in 0..<count {
                let at = ifd + 2 + n * 12
                guard let found = u16(at) else { return nil }
                if found == tag { return at }
            }
            return nil
        }

        func short(_ tag: Int, in ifd: Int) -> Int? { entry(tag, in: ifd).flatMap { u16($0 + 8) } }
        func long(_ tag: Int, in ifd: Int) -> Int? { entry(tag, in: ifd).flatMap { u32($0 + 8) } }

        /// An ASCII value: inline when it fits in four bytes, else at the offset the entry holds.
        func ascii(_ tag: Int, in ifd: Int) -> String? {
            guard let at = entry(tag, in: ifd), let count = u32(at + 4), count > 0 else { return nil }
            guard let start = count <= 4 ? at + 8 : u32(at + 8), start + count <= s.count else { return nil }
            let text = String(decoding: s[start..<(start + count)].prefix { $0 != 0 }, as: UTF8.self)
            return text.isEmpty ? nil : text
        }
    }

    /// RGB pixels turned upright for an EXIF orientation. 5-8 swap width and height.
    static func upright(_ rgb: [UInt8], width: Int, height: Int, orientation: Int)
        -> (width: Int, height: Int, rgb: [UInt8]) {
        guard (2...8).contains(orientation), rgb.count == width * height * 3 else { return (width, height, rgb) }
        let swaps = orientation >= 5
        let w = swaps ? height : width, h = swaps ? width : height
        var out = [UInt8](repeating: 0, count: rgb.count)
        for y in 0..<h {
            for x in 0..<w {
                let (sx, sy): (Int, Int)
                switch orientation {
                case 2: (sx, sy) = (width - 1 - x, y)
                case 3: (sx, sy) = (width - 1 - x, height - 1 - y)
                case 4: (sx, sy) = (x, height - 1 - y)
                case 5: (sx, sy) = (y, x)
                case 6: (sx, sy) = (y, height - 1 - x)
                case 7: (sx, sy) = (width - 1 - y, height - 1 - x)
                default: (sx, sy) = (width - 1 - y, x)
                }
                let from = (sy * width + sx) * 3, to = (y * w + x) * 3
                out[to] = rgb[from]
                out[to + 1] = rgb[from + 1]
                out[to + 2] = rgb[from + 2]
            }
        }
        return (w, h, out)
    }
}
