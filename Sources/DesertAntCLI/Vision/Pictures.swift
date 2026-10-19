import Eye
import Foundation
#if canImport(ImageIO) && canImport(AVFoundation)
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

// Pixels in and out for Eye: ImageIO and AVFoundation on Apple platforms, ffmpeg elsewhere.

enum Pictures {
    /// A photo's pixels, upright per its EXIF orientation.
    static func pixels(_ path: String) throws -> ImagePixels {
        #if canImport(ImageIO)
        do {
            return try ImagePixels(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw RunError("could not read \(path) as an image.")
        }
        #else
        let tools = try FFmpeg.require(for: path)
        let source = HEIF.isHEIF(path) ? try HEIF.convert(path) : path
        defer { if source != path { try? FileManager.default.removeItem(atPath: source) } }
        guard let image = try? FFmpeg.decodeImage(source, tools: tools) else {
            throw RunError("could not read \(path) as an image.")
        }
        let head = Exif.head(source)
        if source != path { HEIF.remember(Exif.dateTimeOriginal(jpeg: head), for: path) }
        let upright = Exif.upright(image.rgb, width: image.width, height: image.height,
                                   orientation: Exif.orientation(jpeg: head))
        return try ImagePixels(width: upright.width, height: upright.height, rgb: upright.rgb)
        #endif
    }

    /// When the photo was taken, in seconds since 1970, from its EXIF; nil when it does not say.
    static func captureDate(_ path: String) -> Double? {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let stamp = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        return exifDate(stamp, offset: exif[kCGImagePropertyExifOffsetTimeOriginal] as? String)
        #else
        let taken = HEIF.isHEIF(path) ? HEIF.taken(path) : Exif.dateTimeOriginal(jpeg: Exif.head(path))
        guard let taken else { return nil }
        return exifDate(taken.stamp, offset: taken.offset)
        #endif
    }

    /// `2026:10:18 10:38:33` with an optional `+02:00`, read as local time without one.
    static func exifDate(_ stamp: String, offset: String?) -> Double? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = offset == nil ? "yyyy:MM:dd HH:mm:ss" : "yyyy:MM:dd HH:mm:ssXXXXX"
        return f.date(from: stamp + (offset ?? ""))?.timeIntervalSince1970
    }

    /// `1:1`, `16:9`, `4:5`, or a plain ratio like `1.91`, as width over height.
    static func aspect(_ text: String) -> Double? {
        let parts = text.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        switch parts.count {
        case 1: return parts[0].flatMap { $0 > 0 ? $0 : nil }
        case 2:
            guard let w = parts[0], let h = parts[1], w > 0, h > 0 else { return nil }
            return w / h
        default: return nil
        }
    }

    /// `box` trimmed about its center to exactly `aspect` (width over height) in an image
    /// of `width` x `height` pixels. Eye's best crop for an aspect can be up to 10% off it.
    static func exact(_ box: Box, aspect: Double, width: Int, height: Int) -> Box {
        let w = box.width * Double(width), h = box.height * Double(height)
        guard w > 0, h > 0 else { return box }
        let cx = (box.x0 + box.x1) / 2, cy = (box.y0 + box.y1) / 2
        if w / h > aspect {
            let half = h * aspect / Double(width) / 2
            return Box(x0: cx - half, y0: box.y0, x1: cx + half, y1: box.y1)
        }
        let half = w / aspect / Double(height) / 2
        return Box(x0: box.x0, y0: cy - half, x1: box.x1, y1: cy + half)
    }

    /// The `box` of `pixels`, in 0...1, rounded out to whole pixels and kept inside the image.
    static func crop(_ pixels: ImagePixels, to box: Box) throws -> ImagePixels {
        let w = pixels.width, h = pixels.height, ch = pixels.channels
        let x0 = max(0, min(w - 1, Int((box.x0 * Double(w)).rounded(.down))))
        let y0 = max(0, min(h - 1, Int((box.y0 * Double(h)).rounded(.down))))
        let x1 = max(x0 + 1, min(w, Int((box.x1 * Double(w)).rounded(.up))))
        let y1 = max(y0 + 1, min(h, Int((box.y1 * Double(h)).rounded(.up))))
        var out: [UInt8] = []
        out.reserveCapacity((x1 - x0) * (y1 - y0) * ch)
        for y in y0..<y1 {
            out += pixels.bytes[((y * w + x0) * ch)..<((y * w + x1) * ch)]
        }
        return ch == 4 ? try ImagePixels(width: x1 - x0, height: y1 - y0, rgba: out)
            : try ImagePixels(width: x1 - x0, height: y1 - y0, rgb: out)
    }

    /// Write `pixels`, or the `box` of them, as an image file in the format the extension names.
    static func write(_ pixels: ImagePixels, box: Box? = nil, to path: String) throws {
        let image = try box.map { try crop(pixels, to: $0) } ?? pixels
        #if canImport(ImageIO)
        guard let cg = cgImage(image) else { throw RunError("could not build an image to write \(path).") }
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type(for: url.pathExtension).identifier as CFString, 1, nil) else {
            throw RunError("could not write \(path).")
        }
        CGImageDestinationAddImage(destination, cg, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw RunError("could not write \(path).")
        }
        #else
        let tools = try FFmpeg.require(for: path)
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent("desertant-\(UUID().uuidString).raw")
        try Data(image.bytes).write(to: raw)
        defer { try? FileManager.default.removeItem(at: raw) }
        try FFmpeg.run(tools.ffmpeg, [
            "-v", "error", "-nostdin", "-y", "-f", "rawvideo", "-pix_fmt", image.channels == 4 ? "rgba" : "rgb24",
            "-s", "\(image.width)x\(image.height)", "-i", raw.path, "-frames:v", "1", "-update", "1", "-q:v", "2", path,
        ], file: path, writing: true)
        #endif
    }

    /// The extension a written image keeps: the input's own when this platform writes it, else jpg.
    static func outputExtension(for input: String) -> String {
        let ext = (input as NSString).pathExtension.lowercased()
        #if canImport(ImageIO)
        let writable: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff"]
        #else
        let writable: Set<String> = ["jpg", "jpeg", "png", "tif", "tiff"]
        #endif
        return writable.contains(ext) ? ext : "jpg"
    }

    #if canImport(ImageIO)
    private static func type(for ext: String) -> UTType {
        switch ext.lowercased() {
        case "png": .png
        case "heic", "heif": .heic
        case "tif", "tiff": .tiff
        default: .jpeg
        }
    }

    private static func cgImage(_ pixels: ImagePixels) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels.bytes) as CFData) else { return nil }
        let info = pixels.channels == 4 ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.none.rawValue
        return CGImage(width: pixels.width, height: pixels.height, bitsPerComponent: 8, bitsPerPixel: 8 * pixels.channels,
                       bytesPerRow: pixels.width * pixels.channels, space: space, bitmapInfo: CGBitmapInfo(rawValue: info),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
    #endif
}

#if !canImport(ImageIO)
/// HEIC through libheif's command-line tools. ffmpeg cannot be used for it: up to 6.1 it
/// does not open an iPhone's HEIC, and 7.1 reads the photo as separate tiles.
enum HEIF {
    static func isHEIF(_ path: String) -> Bool { ["heic", "heif"].contains((path as NSString).pathExtension.lowercased()) }

    /// The photo as a temporary JPEG: upright, orientation 1, the EXIF kept. Quality 92
    /// moves Eye's scores by under 0.02 and is a fifth the size of a PNG. The caller
    /// removes the file.
    static func convert(_ path: String) throws -> String {
        let search = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        guard let tool = ["heif-dec", "heif-convert"].lazy.compactMap({ name in
            search.lazy.map { (String($0) as NSString).appendingPathComponent(name) }
                .first { FileManager.default.isExecutableFile(atPath: $0) }
        }).first else {
            throw RunError("reading \((path as NSString).lastPathComponent) needs libheif, which is not installed. Install libheif's tools with \(installHint), or convert the photo to JPEG.")
        }
        let jpeg = FileManager.default.temporaryDirectory.appendingPathComponent("desertant-\(UUID().uuidString).jpg").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["-q", "92", path, jpeg]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: jpeg) else {
            try? FileManager.default.removeItem(atPath: jpeg)
            throw RunError("libheif could not read \(path). iPhone photos need a newer libheif and its HEVC decoder, such as Ubuntu 24.04's libheif-plugin-libde265, or convert the photo to JPEG.")
        }
        return jpeg
    }

    /// Capture times read while converting, so `--duplicates` converts each photo once.
    private nonisolated(unsafe) static var times: [String: (stamp: String, offset: String?)?] = [:]
    private static let lock = NSLock()

    static func remember(_ taken: (stamp: String, offset: String?)?, for path: String) {
        lock.withLock { times[path] = taken }
    }

    static func taken(_ path: String) -> (stamp: String, offset: String?)? {
        if let known = lock.withLock({ times[path] }) { return known }
        guard let jpeg = try? convert(path) else { return nil }
        defer { try? FileManager.default.removeItem(atPath: jpeg) }
        let taken = Exif.dateTimeOriginal(jpeg: Exif.head(jpeg))
        remember(taken, for: path)
        return taken
    }

    /// How to install libheif's tools here, as a phrase that follows "with".
    static var installHint: String {
        let release = (try? String(contentsOfFile: "/etc/os-release", encoding: .utf8)) ?? ""
        if release.contains("fedora") { return "`sudo dnf install libheif-tools`" }
        if release.contains("debian") || release.contains("ubuntu") { return "`sudo apt install libheif-examples libheif-plugin-libde265`" }
        if release.contains("arch") { return "`sudo pacman -S libheif`" }
        return "your package manager"
    }
}
#endif

/// Frames read out of a video, upright, at the times asked for.
struct VideoFrames {
    let durationSec: Double
    #if canImport(AVFoundation)
    private let generator: AVAssetImageGenerator
    #else
    private let path: String
    private let tools: FFmpeg.Tools
    private let maxSide: Double?
    #endif

    /// `maxSide` bounds the longer side of each frame; nil reads frames at full size.
    /// `tolerance` is how far from the time asked a frame may sit, in seconds.
    init(_ path: String, maxSide: Double? = 1280, tolerance: Double = 0.25) async throws {
        #if canImport(AVFoundation)
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard try await asset.load(.isReadable), try await !asset.loadTracks(withMediaType: .video).isEmpty else {
            throw RunError("\(path) has no video track this machine can read.")
        }
        durationSec = try await asset.load(.duration).seconds
        generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let maxSide { generator.maximumSize = CGSize(width: maxSide, height: maxSide) }
        // A frame near the time scores the same as the exact one, and seeks much faster.
        let window = CMTime(seconds: tolerance, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = window
        generator.requestedTimeToleranceAfter = window
        #else
        // ffmpeg seeks to the exact frame, so there is no tolerance to set.
        tools = try FFmpeg.require(for: path)
        let probe = try FFmpeg.probe(path, tools: tools)
        guard probe.hasVideo else { throw RunError("\(path) has no video track.") }
        self.path = path
        self.maxSide = maxSide
        durationSec = probe.durationSec
        #endif
    }

    /// Times every `every` seconds, from half a step in, so the first frame is not a fade from black.
    func times(every: Double) -> [Double] {
        guard durationSec > 0 else { return [0] }
        let step = max(every, 0.1)
        return Array(stride(from: min(step / 2, durationSec / 2), to: durationSec, by: step))
    }

    /// The frame nearest `time`, and the time it actually sits at.
    func frame(at time: Double) async throws -> (pixels: ImagePixels, time: Double) {
        #if canImport(AVFoundation)
        let (image, actual) = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
        return (try ImagePixels(image), actual.seconds)
        #else
        // ffmpeg turns the frame upright, and a PPM carries the size it ends up with.
        let fit = maxSide.map { ["-vf", "scale='min(iw,\(Int($0)))':'min(ih,\(Int($0)))':force_original_aspect_ratio=decrease"] } ?? []
        let data = try FFmpeg.run(tools.ffmpeg, ["-v", "error", "-nostdin", "-ss", String(format: "%.3f", time), "-i", path,
                                                 "-frames:v", "1"] + fit + ["-f", "image2pipe", "-vcodec", "ppm", "-"], file: path)
        guard let ppm = Self.ppm([UInt8](data)) else { throw RunError("could not read a frame of \(path) at \(Format.stamp(time)).") }
        return (try ImagePixels(width: ppm.width, height: ppm.height, rgb: ppm.rgb), time)
        #endif
    }

    /// A binary PPM (`P6`, 8 bits): width, height, and maximum value, then RGB bytes.
    static func ppm(_ bytes: [UInt8]) -> (width: Int, height: Int, rgb: [UInt8])? {
        guard bytes.count > 2, bytes[0] == UInt8(ascii: "P"), bytes[1] == UInt8(ascii: "6") else { return nil }
        var fields: [Int] = []
        var i = 2
        while fields.count < 3, i < bytes.count {
            if bytes[i] == UInt8(ascii: "#") {
                while i < bytes.count, bytes[i] != 0x0A { i += 1 }
            } else if (0x30...0x39).contains(bytes[i]) {
                var n = 0
                while i < bytes.count, (0x30...0x39).contains(bytes[i]) { n = n * 10 + Int(bytes[i] - 0x30); i += 1 }
                fields.append(n)
                continue
            }
            i += 1
        }
        // One whitespace byte separates the maximum value from the pixels.
        i += 1
        guard fields.count == 3, fields[2] == 255, fields[0] > 0, fields[1] > 0 else { return nil }
        let count = fields[0] * fields[1] * 3
        guard bytes.count - i >= count else { return nil }
        return (fields[0], fields[1], Array(bytes[i..<(i + count)]))
    }
}
