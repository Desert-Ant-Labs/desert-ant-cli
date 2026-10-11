import XCTest
@testable import DesertAntCLI

// The media layer Linux runs on: ffmpeg's probe and decode, EXIF orientation, and
// WAV in pure Swift. The ffmpeg tests make their own media and skip without ffmpeg.

final class MediaTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func tools() throws -> FFmpeg.Tools {
        try XCTUnwrap(FFmpeg.tools, "ffmpeg is not on PATH")
    }

    private func requireFFmpeg() throws -> FFmpeg.Tools {
        guard let tools = FFmpeg.tools else { throw XCTSkip("ffmpeg is not on PATH") }
        return tools
    }

    @discardableResult
    private func make(_ name: String, _ arguments: [String]) throws -> String {
        let path = dir.appendingPathComponent(name).path
        try FFmpeg.run(try tools().ffmpeg, ["-v", "error", "-nostdin", "-y"] + arguments + [path], file: path, writing: true)
        return path
    }

    // MARK: - Pure

    func testProbeParsesStreamsAndDuration() throws {
        let json = """
        {"streams": [{"codec_type": "video", "width": 640, "height": 360},
                     {"codec_type": "audio", "channels": 2},
                     {"codec_type": "subtitle"}],
         "format": {"duration": "12.480000"}}
        """
        let probe = try XCTUnwrap(FFmpeg.parseProbe(Data(json.utf8)))
        XCTAssertEqual(probe, FFmpeg.Probe(hasVideo: true, hasAudio: true, durationSec: 12.48,
                                           channels: 2, width: 640, height: 360))
        XCTAssertNil(FFmpeg.parseProbe(Data("not json".utf8)))
    }

    func testDeinterleaveSplitsChannels() {
        let floats: [Float] = [0.5, -0.5, 0.25, -0.25, 1, -1]
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        XCTAssertEqual(FFmpeg.deinterleave(data, channels: 2), [[0.5, 0.25, 1], [-0.5, -0.25, -1]])
        XCTAssertEqual(FFmpeg.deinterleave(data, channels: 1), [floats])
    }

    func testInstallHintFollowsTheDistribution() {
        XCTAssertEqual(FFmpeg.installHint(osRelease: "ID=ubuntu\nID_LIKE=debian"), "`sudo apt install ffmpeg`")
        XCTAssertEqual(FFmpeg.installHint(osRelease: "ID=debian"), "`sudo apt install ffmpeg`")
        XCTAssertEqual(FFmpeg.installHint(osRelease: "ID=linuxmint\nID_LIKE=\"ubuntu debian\""), "`sudo apt install ffmpeg`")
        XCTAssertEqual(FFmpeg.installHint(osRelease: "ID=fedora"), "`sudo dnf install ffmpeg-free`")
        XCTAssertEqual(FFmpeg.installHint(osRelease: "ID=\"rocky\"\nID_LIKE=\"rhel centos fedora\""),
                       "`sudo dnf install ffmpeg` from RPM Fusion")
        XCTAssertEqual(FFmpeg.installHint(osRelease: "ID=arch"), "`sudo pacman -S ffmpeg`")
        XCTAssertEqual(FFmpeg.installHint(osRelease: "ID=\"opensuse-tumbleweed\"\nID_LIKE=\"opensuse suse\""),
                       "`sudo zypper install ffmpeg`")
        XCTAssertEqual(FFmpeg.installHint(osRelease: ""), "your package manager")
    }

    func testLocateNeedsBothTools() throws {
        let bin = dir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let ffmpeg = bin.appendingPathComponent("ffmpeg").path
        FileManager.default.createFile(atPath: ffmpeg, contents: Data(), attributes: [.posixPermissions: 0o755])
        XCTAssertNil(FFmpeg.locate(path: "/nowhere:\(bin.path)"))
        let ffprobe = bin.appendingPathComponent("ffprobe").path
        FileManager.default.createFile(atPath: ffprobe, contents: Data(), attributes: [.posixPermissions: 0o755])
        XCTAssertEqual(FFmpeg.locate(path: "/nowhere:\(bin.path)")?.ffprobe, ffprobe)
    }

    /// A 3x2 image whose pixel at (x, y) is (x, y, 7).
    private let image: [UInt8] = (0..<2).flatMap { y in (0..<3).flatMap { x in [UInt8(x), UInt8(y), 7] } }

    private func pixel(_ rgb: [UInt8], width: Int, _ x: Int, _ y: Int) -> [UInt8] {
        Array(rgb[((y * width + x) * 3)..<((y * width + x) * 3 + 3)])
    }

    func testUprightTurnsEachOrientation() {
        // Where the stored top-left pixel ends up, upright.
        let cases: [(Int, Int, Int, Int, Int)] = [
            // orientation, width, height, x, y
            (1, 3, 2, 0, 0), (2, 3, 2, 2, 0), (3, 3, 2, 2, 1), (4, 3, 2, 0, 1),
            (5, 2, 3, 0, 0), (6, 2, 3, 1, 0), (7, 2, 3, 1, 2), (8, 2, 3, 0, 2),
        ]
        for (orientation, w, h, x, y) in cases {
            let out = Exif.upright(image, width: 3, height: 2, orientation: orientation)
            XCTAssertEqual(out.width, w, "orientation \(orientation)")
            XCTAssertEqual(out.height, h, "orientation \(orientation)")
            XCTAssertEqual(pixel(out.rgb, width: w, x, y), [0, 0, 7], "orientation \(orientation)")
        }
    }

    /// A JPEG header with an EXIF orientation tag, in either byte order.
    private func jpegHeader(orientation: Int, littleEndian: Bool) -> [UInt8] {
        func u16(_ v: Int) -> [UInt8] { littleEndian ? [UInt8(v & 0xFF), UInt8(v >> 8)] : [UInt8(v >> 8), UInt8(v & 0xFF)] }
        func u32(_ v: Int) -> [UInt8] { littleEndian ? u16(v & 0xFFFF) + u16(v >> 16) : u16(v >> 16) + u16(v & 0xFFFF) }
        var tiff: [UInt8] = littleEndian ? [0x49, 0x49] : [0x4D, 0x4D]
        tiff += u16(42) + u32(8)
        tiff += u16(1) + u16(0x0112) + u16(3) + u32(1)
        tiff += u16(orientation) + [0, 0] + u32(0)
        let app1: [UInt8] = Array("Exif\0\0".utf8) + tiff
        let length = app1.count + 2
        let head: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE1, UInt8(length >> 8), UInt8(length & 0xFF)]
        return head + app1 + [0xFF, 0xDA, 0, 2]
    }

    func testOrientationReadsEitherByteOrder() {
        for orientation in 1...8 {
            XCTAssertEqual(Exif.orientation(jpeg: jpegHeader(orientation: orientation, littleEndian: true)), orientation)
            XCTAssertEqual(Exif.orientation(jpeg: jpegHeader(orientation: orientation, littleEndian: false)), orientation)
        }
        XCTAssertEqual(Exif.orientation(jpeg: [0x89, 0x50, 0x4E, 0x47]), 1, "a PNG has no EXIF here")
        XCTAssertEqual(Exif.orientation(jpeg: [0xFF, 0xD8, 0xFF, 0xE1, 0x7F]), 1, "a cut-off header")
    }

    func testWAVRoundTripsWithoutFFmpeg() async throws {
        let path = dir.appendingPathComponent("tone.wav").path
        let left = (0..<1600).map { Float(sin(Double($0) / 10)) * 0.5 }
        let right = left.map { -$0 }
        try Media.write([left, right], sampleRate: 16_000, to: path)
        XCTAssertTrue(Media.isWAV(path))
        let back = try await Media.decodeChannels(path, sampleRate: 16_000)
        XCTAssertEqual(back.count, 2)
        XCTAssertEqual(back[0].count, 1600)
        XCTAssertEqual(back[0][100], left[100], accuracy: 1e-3)
        XCTAssertEqual(back[1][100], right[100], accuracy: 1e-3)
        let mono = try await Media.decodeMono(path, sampleRate: 16_000)
        XCTAssertEqual(mono.count, 1600)
    }

    func testIsWAVReadsTheHeaderNotTheName() throws {
        let fake = dir.appendingPathComponent("fake.wav").path
        FileManager.default.createFile(atPath: fake, contents: Data("ID3 not a wave file".utf8))
        XCTAssertFalse(Media.isWAV(fake))
        XCTAssertFalse(Media.isWAV(dir.appendingPathComponent("missing.wav").path))
    }

    // MARK: - With ffmpeg

    func testDecodesCompressedAudio() async throws {
        let tools = try requireFFmpeg()
        let mp3 = try make("tone.m4a", ["-f", "lavfi", "-i", "sine=frequency=440:duration=2:sample_rate=44100", "-ac", "2"])
        let probe = try FFmpeg.probe(mp3, tools: tools)
        XCTAssertTrue(probe.hasAudio)
        XCTAssertFalse(probe.hasVideo)
        XCTAssertEqual(probe.channels, 2)
        XCTAssertEqual(probe.durationSec, 2, accuracy: 0.1)
        let mono = try FFmpeg.decodeAudio(mp3, sampleRate: 16_000, channels: 1, tools: tools)
        XCTAssertEqual(mono.count, 1)
        XCTAssertEqual(Double(mono[0].count), 32_000, accuracy: 1_600)
        XCTAssertGreaterThan(mono[0].map(abs).max() ?? 0, 0.1, "a sine should not decode to silence")
        let both = try FFmpeg.decodeAudio(mp3, sampleRate: 48_000, tools: tools)
        XCTAssertEqual(both.count, 2)
    }

    func testVideoWithoutAudioSaysSo() throws {
        let tools = try requireFFmpeg()
        let video = try make("silent.mp4", ["-f", "lavfi", "-i", "testsrc=size=64x48:duration=1:rate=10", "-pix_fmt", "yuv420p"])
        XCTAssertThrowsError(try FFmpeg.decodeAudio(video, sampleRate: 16_000, tools: tools)) { error in
            XCTAssertEqual("\(error)", "silent.mp4 has no audio track.")
        }
    }

    func testDecodesAnImageAsStored() throws {
        let tools = try requireFFmpeg()
        let png = try make("red.png", ["-f", "lavfi", "-i", "color=c=red:size=40x30", "-frames:v", "1"])
        let image = try FFmpeg.decodeImage(png, tools: tools)
        XCTAssertEqual(image.width, 40)
        XCTAssertEqual(image.height, 30)
        XCTAssertEqual(image.rgb.count, 40 * 30 * 3)
        XCTAssertGreaterThan(image.rgb[0], 240)
        XCTAssertLessThan(image.rgb[1], 10)
        let text = dir.appendingPathComponent("notes.png").path
        FileManager.default.createFile(atPath: text, contents: Data("hello".utf8))
        XCTAssertThrowsError(try FFmpeg.decodeImage(text, tools: tools))
    }

    func testRotatedJPEGComesOutUpright() throws {
        _ = try requireFFmpeg()
        let jpeg = try make("wide.jpg", ["-f", "lavfi", "-i", "testsrc=size=64x32", "-frames:v", "1"])
        var bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: jpeg)))
        // Stand an EXIF segment with orientation 6 (turn right) after the SOI marker.
        let exif = jpegHeader(orientation: 6, littleEndian: false)
        bytes.insert(contentsOf: exif[2..<(exif.count - 4)], at: 2)
        let rotated = dir.appendingPathComponent("rotated.jpg")
        try Data(bytes).write(to: rotated)
        let pixels = try ModeratorRunner.pixels(rotated.path)
        XCTAssertEqual(pixels.width, 32)
        XCTAssertEqual(pixels.height, 64)

        let turned = try make("turned.png", ["-i", jpeg, "-vf", "transpose=clock"])
        let expected = try FFmpeg.decodeImage(turned, tools: try tools())
        var diff = 0
        for i in 0..<(32 * 64) {
            for c in 0..<3 {
                diff += abs(Int(pixels.bytes[i * pixels.channels + c]) - Int(expected.rgb[i * 3 + c]))
            }
        }
        XCTAssertLessThan(Double(diff) / Double(32 * 64 * 3), 8, "the upright pixels should match ffmpeg's own turn")
    }

    func testCutsOneRangeAndSeveral() throws {
        let tools = try requireFFmpeg()
        let source = try make("talk.mp4", [
            "-f", "lavfi", "-i", "testsrc=size=64x48:duration=10:rate=25",
            "-f", "lavfi", "-i", "sine=frequency=300:duration=10",
            "-pix_fmt", "yuv420p", "-g", "25", "-shortest",
        ])
        let one = dir.appendingPathComponent("one.mp4").path
        try FFmpeg.cut(source, ranges: [(2, 3)], to: one, tools: tools)
        let first = try FFmpeg.probe(one, tools: tools)
        XCTAssertTrue(first.hasVideo && first.hasAudio)
        XCTAssertEqual(first.durationSec, 3, accuracy: 0.5)

        let two = dir.appendingPathComponent("two.mp4").path
        try FFmpeg.cut(source, ranges: [(1, 2), (6, 2)], to: two, tools: tools)
        XCTAssertEqual(try FFmpeg.probe(two, tools: tools).durationSec, 4, accuracy: 0.6)

        let audio = dir.appendingPathComponent("two.m4a").path
        try FFmpeg.cut(source, ranges: [(0, 1), (5, 1)], to: audio, tools: tools)
        let clip = try FFmpeg.probe(audio, tools: tools)
        XCTAssertFalse(clip.hasVideo)
        XCTAssertEqual(clip.durationSec, 2, accuracy: 0.5)

        XCTAssertThrowsError(try FFmpeg.cut(source, ranges: [(3, 0)], to: one, tools: tools))
    }

    func testWritesCompressedAudioThroughFFmpeg() async throws {
        _ = try requireFFmpeg()
        let path = dir.appendingPathComponent("out.m4a").path
        let tone = (0..<48_000).map { Float(sin(Double($0) / 20)) * 0.3 }
        try Media.write([tone], sampleRate: 48_000, to: path)
        XCTAssertFalse(Media.isWAV(path))
        let back = try await Media.decodeMono(path, sampleRate: 48_000)
        XCTAssertEqual(Double(back.count), 48_000, accuracy: 4_800)
    }

    func testFailedRunNamesTheFileAndFFmpegsReason() throws {
        let tools = try requireFFmpeg()
        let missing = dir.appendingPathComponent("gone.mp3").path
        XCTAssertThrowsError(try FFmpeg.probe(missing, tools: tools)) { error in
            XCTAssertTrue("\(error)".hasPrefix("ffmpeg could not read gone.mp3: "), "\(error)")
        }
    }
}
