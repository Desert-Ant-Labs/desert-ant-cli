import Foundation

// ffmpeg's handling of a JPEG's EXIF orientation differs between versions, so the CLI
// decodes with -noautorotate and turns the pixels upright itself, as ImageIO does.

enum Exif {
    /// The EXIF orientation of a JPEG, 1...8, or 1 when there is none.
    static func orientation(jpeg bytes: [UInt8]) -> Int {
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return 1 }
        var i = 2
        while i + 4 <= bytes.count, bytes[i] == 0xFF {
            let marker = bytes[i + 1]
            if marker == 0xDA { break }
            let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            guard length >= 2, i + 2 + length <= bytes.count else { break }
            if marker == 0xE1, let value = tiffOrientation(Array(bytes[(i + 4)..<(i + 2 + length)])) {
                return value
            }
            i += 2 + length
        }
        return 1
    }

    private static func tiffOrientation(_ s: [UInt8]) -> Int? {
        guard s.count >= 14, Array(s[0..<6]) == Array("Exif\0\0".utf8) else { return nil }
        let base = 6
        let little: Bool
        switch (s[base], s[base + 1]) {
        case (0x49, 0x49): little = true
        case (0x4D, 0x4D): little = false
        default: return nil
        }
        func u16(_ at: Int) -> Int? {
            guard at >= 0, at + 2 <= s.count else { return nil }
            return little ? Int(s[at]) | Int(s[at + 1]) << 8 : Int(s[at]) << 8 | Int(s[at + 1])
        }
        func u32(_ at: Int) -> Int? {
            guard let a = u16(at), let b = u16(at + 2) else { return nil }
            return little ? a | b << 16 : a << 16 | b
        }
        guard let ifd = u32(base + 4), let count = u16(base + ifd) else { return nil }
        for n in 0..<count {
            let entry = base + ifd + 2 + n * 12
            guard let tag = u16(entry) else { return nil }
            if tag == 0x0112, let value = u16(entry + 8), (1...8).contains(value) { return value }
        }
        return nil
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
