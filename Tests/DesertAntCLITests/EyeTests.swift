import Eye
import XCTest
@testable import DesertAntCLI

// Eye's command-line side: options that conflict fail before any download, crops come
// out at the aspect asked for, capture times read from EXIF, and a video's matching
// frames become time spans.

final class EyeTests: XCTestCase {
    private let eye = EyeRunner()

    func testAspectsParse() {
        XCTAssertEqual(Pictures.aspect("16:9")!, 16.0 / 9, accuracy: 1e-9)
        XCTAssertEqual(Pictures.aspect("1:1"), 1)
        XCTAssertEqual(Pictures.aspect("1.91"), 1.91)
        XCTAssertNil(Pictures.aspect("0:1"))
        XCTAssertNil(Pictures.aspect("wide"))
        XCTAssertNil(Pictures.aspect("1:2:3"))
    }

    func testExactCropHitsTheAspectInsideTheBox() {
        // A 4000x3000 photo and a box that is 1.09 wide in pixels, where 1:1 was asked.
        let box = Box(x0: 0.1, y0: 0.1, x1: 0.8, y1: 0.95)
        let exact = Pictures.exact(box, aspect: 1, width: 4000, height: 3000)
        XCTAssertEqual(exact.width * 4000, exact.height * 3000, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(exact.x0, box.x0)
        XCTAssertLessThanOrEqual(exact.x1, box.x1)
        XCTAssertEqual((exact.x0 + exact.x1) / 2, (box.x0 + box.x1) / 2, accuracy: 1e-9)
        let tall = Pictures.exact(box, aspect: 4.0 / 5, width: 4000, height: 3000)
        XCTAssertEqual(tall.width * 4000 / (tall.height * 3000), 0.8, accuracy: 1e-6)
    }

    func testCaptureTimeReadsTheOffset() {
        let local = Pictures.exifDate("2026:10:18 10:38:33", offset: "+02:00")
        let utc = Pictures.exifDate("2026:10:18 08:38:33", offset: "+00:00")
        XCTAssertNotNil(local)
        XCTAssertEqual(local, utc)
        XCTAssertNotNil(Pictures.exifDate("2026:10:18 10:38:33", offset: nil))
        XCTAssertNil(Pictures.exifDate("yesterday", offset: nil))
    }

    func testOneQuestionAtATime() {
        XCTAssertThrowsError(try eye.settings(RunArguments(["duplicates=true", "best=true"])))
        XCTAssertThrowsError(try eye.settings(RunArguments(["sort=aesthetic", "similar-to=/nope.jpg"])))
        XCTAssertNoThrow(try eye.settings(RunArguments(["best=true", "has=dog"])))
    }

    func testOptionsAreCheckedBeforeAnyDownload() {
        XCTAssertThrowsError(try eye.settings(RunArguments(["parts=photo,colour"])))
        XCTAssertThrowsError(try eye.settings(RunArguments(["crop=1:1", "parts=photo"])), "a crop needs layout")
        XCTAssertThrowsError(try eye.settings(RunArguments(["crop=square"])))
        XCTAssertThrowsError(try eye.settings(RunArguments(["max-faces=-1"])))
        XCTAssertThrowsError(try eye.settings(RunArguments(["similar-to=/nope.jpg"])))
        XCTAssertThrowsError(try eye.settings(RunArguments(["every=0"])))
    }

    func testFiltersAndQuestionsTakeTheSetPath() throws {
        XCTAssertFalse(eye.wantsSet(RunArguments()))
        XCTAssertFalse(eye.wantsSet(RunArguments(["crop=1:1", "tags=3"])))
        XCTAssertTrue(eye.wantsSet(RunArguments(["has=Dog, beach"])))
        XCTAssertTrue(eye.wantsSet(RunArguments(["duplicates=true"])))
        let s = try eye.settings(RunArguments(["has=Dog, beach", "not=blurry", "strict=true"]))
        XCTAssertEqual(s.has, [Tag("dog"), Tag("beach")])
        XCTAssertEqual(s.not, [.blurry])
        XCTAssertEqual(s.level, .strict)
    }

    func testAPPMFrameParsesWithAComment() throws {
        let rgb: [UInt8] = [1, 2, 3, 4, 5, 6]
        let ppm = Array("P6\n# ffmpeg\n2 1\n255\n".utf8) + rgb
        let frame = try XCTUnwrap(VideoFrames.ppm(ppm))
        XCTAssertEqual(frame.width, 2)
        XCTAssertEqual(frame.height, 1)
        XCTAssertEqual(frame.rgb, rgb)
        XCTAssertNil(VideoFrames.ppm(Array("P6\n2 1\n255\n".utf8) + [1, 2]), "cut short")
        XCTAssertNil(VideoFrames.ppm(Array("P5\n2 1\n255\n".utf8) + rgb), "gray, not RGB")
    }

    func testCropKeepsThePixelsInsideTheBox() throws {
        // A 4x2 RGB image whose red channel is the pixel's index.
        let pixels = try ImagePixels(width: 4, height: 2, rgb: (0..<8).flatMap { [UInt8($0), 0, 0] })
        let right = try Pictures.crop(pixels, to: Box(x0: 0.5, y0: 0, x1: 1, y1: 1))
        XCTAssertEqual(right.width, 2)
        XCTAssertEqual(right.height, 2)
        XCTAssertEqual(stride(from: 0, to: right.bytes.count, by: 3).map { right.bytes[$0] }, [2, 3, 6, 7])
        let sliver = try Pictures.crop(pixels, to: Box(x0: 0.99, y0: 0.99, x1: 1.2, y1: 1.2))
        XCTAssertEqual(sliver.width, 1, "a box past the edge keeps one pixel inside")
    }

    func testMatchingFramesBecomeSpans() {
        let frames: [(time: Double, match: Bool)] = [(0.5, false), (1.5, true), (2.5, true), (3.5, false), (4.5, true)]
        let spans = eye.spans(frames, every: 1, duration: 4.8)
        XCTAssertEqual(spans.map(\.start), [1, 4])
        XCTAssertEqual(spans.map(\.end), [3, 4.8])
    }
}
