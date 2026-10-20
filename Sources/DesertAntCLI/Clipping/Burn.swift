import Foundation
import Transcript

/// What happens to a clip's captions.
enum CaptionMode: String, Sendable, CaseIterable {
    /// Drawn into the picture, which re-encodes the clip.
    case burn
    /// Written beside the clip as an .srt file, with no re-encode.
    case srt
    case off
}

/// How burned-in captions look. macOS draws them with Core Text and Linux with libass,
/// from this one description, so a clip looks the same on both.
struct CaptionStyle: Sendable, Equatable {
    enum Position: String, Sendable, CaseIterable { case bottom, center, top }
    enum Align: String, Sendable, CaseIterable { case left, center, right }
    enum Look: String, Sendable, CaseIterable { case outline, box, shadow }
    enum Quality: String, Sendable, CaseIterable { case low, medium, high }

    var position = Position.bottom
    var align = Align.center
    /// A font family, or a path to a .ttf or .otf file. Nil is the font desertant ships.
    var font: String?
    /// The text's height as a share of the frame's height. Nil sizes it to the frame.
    var size: Double?
    var weight = 700
    var color = RGBA.white
    var look = Look.outline
    var quality = Quality.high

    struct RGBA: Sendable, Equatable {
        var r, g, b, a: Double

        static let white = RGBA(r: 1, g: 1, b: 1, a: 1)
        static let black = RGBA(r: 0, g: 0, b: 0, a: 1)

        static let named: [String: RGBA] = [
            "white": .white, "black": .black, "yellow": RGBA(r: 1, g: 0.86, b: 0, a: 1),
            "red": RGBA(r: 0.94, g: 0.2, b: 0.2, a: 1), "green": RGBA(r: 0.2, g: 0.8, b: 0.3, a: 1),
            "blue": RGBA(r: 0.2, g: 0.5, b: 1, a: 1), "cyan": RGBA(r: 0, g: 0.85, b: 0.9, a: 1),
            "magenta": RGBA(r: 0.9, g: 0.2, b: 0.8, a: 1),
        ]

        /// `white`, `#ffcc00`, or `#ffcc0080` with alpha.
        init?(_ text: String) {
            let t = text.trimmingCharacters(in: .whitespaces).lowercased()
            if let c = Self.named[t] { self = c; return }
            let hex = t.hasPrefix("#") ? String(t.dropFirst()) : t
            guard hex.count == 6 || hex.count == 8, let v = UInt32(hex, radix: 16) else { return nil }
            let full = hex.count == 6 ? v << 8 | 0xff : v
            self.init(r: Double(full >> 24 & 0xff) / 255, g: Double(full >> 16 & 0xff) / 255,
                      b: Double(full >> 8 & 0xff) / 255, a: Double(full & 0xff) / 255)
        }

        init(r: Double, g: Double, b: Double, a: Double) {
            self.r = r; self.g = g; self.b = b; self.a = a
        }

        func with(alpha: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: alpha) }
    }

    static let weights: [String: Int] = ["regular": 400, "medium": 500, "semibold": 600, "bold": 700, "black": 900]

    /// The style from command-line text, each value checked.
    static func parse(position: String?, align: String?, font: String?, size: String?, weight: String?,
                      color: String?, look: String?, quality: String?) throws -> CaptionStyle {
        var s = CaptionStyle()
        func pick<T: RawRepresentable & CaseIterable>(_ text: String?, _ name: String) throws -> T? where T.RawValue == String {
            guard let text else { return nil }
            guard let v = T(rawValue: text.lowercased()) else {
                throw RunError("\(name) is \(list: T.allCases.map(\.rawValue), or: true), not \(text).")
            }
            return v
        }
        s.position = try pick(position, "caption-position") ?? s.position
        s.align = try pick(align, "caption-align") ?? s.align
        s.look = try pick(look, "caption-style") ?? s.look
        s.quality = try pick(quality, "quality") ?? s.quality
        if let font, !font.trimmingCharacters(in: .whitespaces).isEmpty { s.font = font }
        if let size {
            guard let v = Double(size), v > 0, v <= 0.3 else {
                throw RunError("caption-size is the text's height as a share of the frame's, above 0 and at most 0.3, as 0.06, not \(size).")
            }
            s.size = v
        }
        if let weight {
            if let v = weights[weight.lowercased()] {
                s.weight = v
            } else if let v = Int(weight), (100...900).contains(v) {
                s.weight = v
            } else {
                throw RunError("caption-weight is regular, medium, semibold, bold, black, or 100 to 900, not \(weight).")
            }
        }
        if let color {
            guard let c = RGBA(color) else {
                throw RunError("caption-color is a name such as white or yellow, or a hex color such as #ffcc00, not \(color).")
            }
            s.color = c
        }
        return s
    }
}

/// Where captions go in one frame size: the text's pixel height, the margins, and how
/// many characters fit on a line.
struct CaptionFrame: Sendable, Equatable {
    let width: Int
    let height: Int
    /// The height of a line of text, in pixels.
    let lineHeight: Double
    let marginX: Double
    let marginY: Double
    /// The most characters on a line.
    let lineLength: Int

    init(width: Int, height: Int, style: CaptionStyle) {
        self.width = width
        self.height = height
        let w = Double(width), h = Double(height)
        // Sized to the short side, so a portrait clip gets the size a landscape one does.
        lineHeight = ((style.size ?? 0.07 * min(w, h) / h) * h).rounded()
        marginX = (w * 0.06).rounded()
        // Social apps put their buttons over the bottom and top of a tall video.
        marginY = (h * (h > w ? 0.16 : 0.08)).rounded()
        let fit = Int((w - 2 * marginX) / (lineHeight * 0.5))
        lineLength = max(12, min(32, fit))
    }

    /// The outline, padding, or shadow offset for a look, in pixels.
    func border(_ look: CaptionStyle.Look) -> Double {
        switch look {
        case .outline: (lineHeight * 0.075).rounded()
        case .box: (lineHeight * 0.2).rounded()
        case .shadow: (lineHeight * 0.06).rounded()
        }
    }
}

enum ClipCaptions {
    /// Words inside `ranges`, moved onto the clip's own timeline, where the ranges play
    /// end to end. A word belongs to the range its middle falls in.
    static func shift(_ words: [TimedWord], into ranges: [TimeRange]) -> [TimedWord] {
        var out: [TimedWord] = []
        var offset = 0.0
        for range in ranges {
            for w in words where (w.start + w.end) / 2 >= range.start && (w.start + w.end) / 2 < range.end {
                out.append(TimedWord(text: w.text, start: max(w.start, range.start) - range.start + offset,
                                     end: min(w.end, range.end) - range.start + offset))
            }
            offset += range.duration
        }
        return out
    }

    /// Short cues for a phone screen: at most two lines of `lineLength`, at most 3.5s,
    /// a new cue at the end of a sentence or after a pause. A cue stays up through a
    /// pause under a second, so the screen does not flicker between cues.
    static func social(_ words: [TimedWord], lineLength: Int) -> [Caption] {
        var cues: [Caption] = []
        var current: [TimedWord] = []
        func fits(_ ws: [TimedWord]) -> Bool {
            let lines = Captions.layout(ws, lineLength: lineLength).split(separator: "\n")
            return lines.count <= 2 && lines.allSatisfy { $0.count <= lineLength }
        }
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            cues.append(Caption(start: first.start, end: last.end, text: Captions.layout(current, lineLength: lineLength)))
            current = []
        }
        for word in words {
            if let first = current.first, let last = current.last,
               word.start - last.end > 0.7 || word.end - first.start > 3.5 || !fits(current + [word]) {
                flush()
            }
            current.append(word)
            if let end = word.text.trimmingCharacters(in: .whitespaces).last, ".?!".contains(end) { flush() }
        }
        flush()
        return Captions.settle(cues, minDuration: 0.6, closeGap: 1)
    }

    /// Words spread evenly over each sentence, for a transcript with times on sentences
    /// only.
    static func words(spreading sentences: [Sentence]) -> [TimedWord] {
        var out: [TimedWord] = []
        for s in sentences {
            let parts = s.text.split(whereSeparator: \.isWhitespace)
            guard !parts.isEmpty else { continue }
            let step = (s.end - s.start) / Double(parts.count)
            for (i, part) in parts.enumerated() {
                let start = s.start + Double(i) * step
                out.append(TimedWord(text: (out.isEmpty ? "" : " ") + part, start: start, end: start + step))
            }
        }
        return out
    }
}

/// Captions as an Advanced SubStation file for libass, laid out as the Core Text
/// renderer lays them out: lines broken in advance, no wrapping, the same margins.
enum ASS {
    static func file(_ cues: [Caption], frame: CaptionFrame, style: CaptionStyle, font: CaptionFont) -> String {
        let alignment: Int = {
            let column = style.align == .left ? 1 : style.align == .center ? 2 : 3
            switch style.position {
            case .bottom: return column
            case .center: return column + 3
            case .top: return column + 6
            }
        }()
        let border = frame.border(style.look)
        let black = CaptionStyle.RGBA.black
        let (borderStyle, outline, shadow, outlineColor, backColor): (Int, Double, Double, CaptionStyle.RGBA, CaptionStyle.RGBA) =
            switch style.look {
            case .outline: (1, border, 0, black, black)
            case .box: (3, border, 0, black.with(alpha: 0.7), black.with(alpha: 0.7))
            case .shadow: (1, 0, border, black, black.with(alpha: 0.6))
            }
        let fields = [
            "Default", font.family, num(frame.lineHeight), color(style.color), color(style.color), color(outlineColor), color(backColor),
            String(font.weight >= 600 ? -1 : 0), "0", "0", "0", "100", "100", "0", "0",
            String(borderStyle), num(outline), num(shadow), String(alignment),
            num(frame.marginX), num(frame.marginX), num(frame.marginY), "1",
        ]
        var out = """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: \(frame.width)
        PlayResY: \(frame.height)
        WrapStyle: 2
        ScaledBorderAndShadow: yes

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: \(fields.joined(separator: ","))

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text

        """
        for cue in cues {
            let text = cue.text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "{", with: "\\{")
                .replacingOccurrences(of: "\n", with: "\\N")
            out += "Dialogue: 0,\(stamp(cue.start)),\(stamp(cue.end)),Default,,0,0,0,,\(text)\n"
        }
        return out
    }

    /// `&HAABBGGRR`, where alpha 00 is opaque.
    static func color(_ c: CaptionStyle.RGBA) -> String {
        func byte(_ v: Double) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "&H%02X%02X%02X%02X", 255 - byte(c.a), byte(c.b), byte(c.g), byte(c.r))
    }

    /// `0:00:01.25`: hours, then centiseconds.
    static func stamp(_ seconds: Double) -> String {
        let cs = Int((max(0, seconds) * 100).rounded())
        return String(format: "%d:%02d:%02d.%02d", cs / 360_000, cs / 6000 % 60, cs / 100 % 60, cs % 100)
    }

    private static func num(_ v: Double) -> String { v.whole.map(String.init) ?? String(format: "%.2f", v) }
}

/// Captions to draw into one clip.
struct BurnedCaptions: Sendable {
    let cues: [Caption]
    let style: CaptionStyle
    let font: CaptionFont
}

#if canImport(AVFoundation)
import AVFoundation
import CoreText
import QuartzCore

extension AVFoundationCutter {
    /// The ranges laid end to end, with each cue drawn by Core Text into a layer that
    /// shows for the cue's time. Re-encodes the video.
    func cut(_ source: URL, ranges: [TimeRange], burning captions: BurnedCaptions, frame _: CaptionFrame, to destination: URL) async throws {
        let composition = try await Self.composition(of: AVURLAsset(url: source), keeping: ranges)
        let video = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: composition)
        let size = video.renderSize
        let frame = CaptionFrame(width: Int(size.width), height: Int(size.height), style: captions.style)
        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: size)
        let picture = CALayer()
        picture.frame = parent.frame
        parent.addSublayer(picture)
        let renderer = try CaptionRenderer(font: captions.font, frame: frame, style: captions.style)
        for cue in captions.cues {
            guard let layer = renderer.layer(cue) else { continue }
            let show = CABasicAnimation(keyPath: "opacity")
            show.fromValue = 1
            show.toValue = 1
            show.beginTime = cue.start <= 0 ? AVCoreAnimationBeginTimeAtZero : cue.start
            show.duration = cue.end - cue.start
            show.isRemovedOnCompletion = false
            layer.add(show, forKey: "show")
            parent.addSublayer(layer)
        }
        video.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: picture, in: parent)

        let preset = switch captions.style.quality {
        case .low: AVAssetExportPresetMediumQuality
        case .medium: AVAssetExportPreset1920x1080
        case .high: AVAssetExportPresetHighestQuality
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw RunError("could not start an export for \(destination.lastPathComponent).")
        }
        session.videoComposition = video
        let type: AVFileType = destination.pathExtension.lowercased() == "mov" ? .mov : .mp4
        do {
            try await session.export(to: destination, as: type)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw RunError("could not write \(destination.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

/// Draws a cue the way libass does: lines broken in advance, each a line height tall,
/// placed inside the margins, with an outline, a box, or a shadow.
struct CaptionRenderer {
    let font: CTFont
    let metrics: CaptionFont
    let frame: CaptionFrame
    let style: CaptionStyle

    init(font metrics: CaptionFont, frame: CaptionFrame, style: CaptionStyle) throws {
        let faces = (CTFontManagerCreateFontDescriptorsFromURL(metrics.file as CFURL) as? [CTFontDescriptor]) ?? []
        guard !faces.isEmpty else { throw RunError("could not load the font \(metrics.file.path).") }
        font = CTFontCreateWithFontDescriptor(faces[min(metrics.index, faces.count - 1)], metrics.emSize(lineHeight: frame.lineHeight), nil)
        self.metrics = metrics
        self.frame = frame
        self.style = style
    }

    /// One drawn line: its glyph outlines and where it sits, top-left origin.
    private struct Line {
        let path: CGPath
        let x: Double
        let top: Double
        let width: Double
    }

    private func lines(_ text: String) -> [Line] {
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let height = frame.lineHeight
        let block = Double(rows.count) * height
        let top: Double = switch style.position {
        case .bottom: Double(frame.height) - frame.marginY - block
        case .top: frame.marginY
        case .center: (Double(frame.height) - block) / 2
        }
        return rows.enumerated().map { i, row in
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: row, attributes: [kCTFontAttributeName as NSAttributedString.Key: font]))
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            let path = CGMutablePath()
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
                for (glyph, at) in zip(glyphs, positions) {
                    guard let outline = CTFontCreatePathForGlyph(runFont, glyph, nil) else { continue }
                    path.addPath(outline, transform: CGAffineTransform(translationX: at.x, y: at.y))
                }
            }
            let x: Double = switch style.align {
            case .left: frame.marginX
            case .center: (Double(frame.width) - width) / 2
            case .right: Double(frame.width) - frame.marginX - width
            }
            return Line(path: path, x: x, top: Double(i) * height + top, width: width)
        }
    }

    /// The cue as a layer the size of what it draws, bottom-left origin as video
    /// composition layers use.
    func layer(_ cue: Caption) -> CALayer? {
        let lines = lines(cue.text)
        guard !lines.isEmpty else { return nil }
        let border = frame.border(style.look)
        let reach = style.look == .shadow ? border : border + 1
        let minX = lines.map(\.x).min()! - reach, maxX = lines.map { $0.x + $0.width }.max()! + reach + (style.look == .shadow ? border : 0)
        let minY = lines[0].top - reach, maxY = lines.last!.top + frame.lineHeight + reach + (style.look == .shadow ? border : 0)
        let box = CGRect(x: floor(minX), y: floor(minY), width: ceil(maxX - minX) + 1, height: ceil(maxY - minY) + 1)
        guard let context = CGContext(data: nil, width: Int(box.width), height: Int(box.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let baseline = metrics.baseline(lineHeight: frame.lineHeight)
        func color(_ c: CaptionStyle.RGBA) -> CGColor { CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a) }
        /// From top-left frame coordinates to the context's bottom-left ones.
        func place(_ line: Line, dx: Double = 0, dy: Double = 0) -> CGAffineTransform {
            CGAffineTransform(translationX: line.x - box.minX + dx, y: box.maxY - (line.top + baseline) - dy)
        }
        for line in lines {
            switch style.look {
            case .box:
                context.setFillColor(color(CaptionStyle.RGBA.black.with(alpha: 0.7)))
                context.fill(CGRect(x: line.x - border - box.minX, y: box.maxY - line.top - frame.lineHeight - border,
                                    width: line.width + 2 * border, height: frame.lineHeight + 2 * border))
            case .shadow:
                var t = place(line, dx: border, dy: border)
                if let p = line.path.copy(using: &t) {
                    context.addPath(p)
                    context.setFillColor(color(CaptionStyle.RGBA.black.with(alpha: 0.6)))
                    context.fillPath()
                }
            case .outline:
                var t = place(line)
                if let p = line.path.copy(using: &t) {
                    context.addPath(p)
                    context.setLineWidth(2 * border)
                    context.setLineJoin(.round)
                    context.setStrokeColor(color(.black))
                    context.strokePath()
                }
            }
        }
        for line in lines {
            var t = place(line)
            if let p = line.path.copy(using: &t) {
                context.addPath(p)
                context.setFillColor(color(style.color))
                context.fillPath()
            }
        }
        guard let image = context.makeImage() else { return nil }
        let layer = CALayer()
        layer.contents = image
        layer.frame = CGRect(x: box.minX, y: Double(frame.height) - box.maxY, width: box.width, height: box.height)
        layer.opacity = 0
        return layer
    }
}
#endif

extension FFmpegCutter {
    /// The ranges cut with exact seeking and laid end to end, the captions drawn by
    /// libass, in one encode.
    func cut(_ source: URL, ranges: [TimeRange], burning captions: BurnedCaptions, frame: CaptionFrame, to destination: URL) async throws {
        let kept = ranges.filter { $0.duration > 0 }
        guard !kept.isEmpty else { throw RunError("the clip's time range is outside the source.") }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("desertant-burn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        // libass finds the font by family in this folder, which holds only that file.
        let fonts = scratch.appendingPathComponent("fonts")
        try FileManager.default.createDirectory(at: fonts, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: captions.font.file, to: fonts.appendingPathComponent(captions.font.file.lastPathComponent))
        let subtitles = scratch.appendingPathComponent("captions.ass")
        try ASS.file(captions.cues, frame: frame, style: captions.style, font: captions.font).write(to: subtitles, atomically: true, encoding: .utf8)

        var arguments = ["-v", "error", "-nostdin", "-y"]
        var graph: [String] = []
        for (i, range) in kept.enumerated() {
            arguments += ["-ss", String(format: "%.3f", range.start), "-t", String(format: "%.3f", range.duration), "-i", source.path]
            graph.append("[\(i):v:0]setpts=PTS-STARTPTS[v\(i)];[\(i):a:0]asetpts=PTS-STARTPTS[a\(i)]")
        }
        let pairs = kept.indices.map { "[v\($0)][a\($0)]" }.joined()
        graph.append("\(pairs)concat=n=\(kept.count):v=1:a=1[v][a]")
        graph.append("[v]subtitles=filename=\(subtitles.path):fontsdir=\(fonts.path)[out]")
        arguments += ["-filter_complex", graph.joined(separator: ";"), "-map", "[out]", "-map", "[a]"]
        let (crf, preset) = switch captions.style.quality {
        case .low: ("28", "veryfast")
        case .medium: ("23", "fast")
        case .high: ("18", "medium")
        }
        let audio = ["-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", destination.path]
        do {
            try FFmpeg.run(tools.ffmpeg, arguments + ["-c:v", "libx264", "-crf", crf, "-preset", preset, "-pix_fmt", "yuv420p"] + audio,
                           file: destination.path, writing: true)
        } catch {
            // An ffmpeg built without libx264 encodes with its default encoder instead.
            try? FileManager.default.removeItem(at: destination)
            try FFmpeg.run(tools.ffmpeg, arguments + ["-pix_fmt", "yuv420p"] + audio, file: destination.path, writing: true)
        }
    }
}
