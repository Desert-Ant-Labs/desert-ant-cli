#if canImport(CoreML) && canImport(AVFoundation)
import AVFoundation
import Foundation
import Transcript
import Voz

// Voz with word timestamps, for the `voz` command and the clips pipeline. Apple
// platforms only, since Voz drives Core ML directly. A video container is exported to
// a temporary audio file first, since Voz reads audio.

actor VozTranscriber: Transcriber {
    nonisolated let name = "voz"
    private var voz: Voz?

    struct Transcription: Sendable {
        let text: String
        let words: [TimedWord]
        let durationSec: Double
        let processingSec: Double
        var sentences: [Sentence] { Sentence.sentences(from: words) }
    }

    nonisolated func isDownloaded() -> Bool { VozModel.isAvailable() }

    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard voz == nil else { return }
        voz = try await Voz { progress($0.fraction) }
    }

    func transcribe(_ media: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [TimedWord] {
        try await transcription(of: media, progress: progress).words
    }

    func transcription(of media: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> Transcription {
        try await prepare { _ in }
        guard let voz else { throw RunError("voz did not load") }

        let audio = try await Self.audioOnly(media)
        defer { if audio != media { try? FileManager.default.removeItem(at: audio) } }

        let result = try await voz.transcribe(audio) { progress($0.fractionCompleted) }
        guard !result.words.isEmpty else { throw RunError("no speech found in \(media.lastPathComponent)") }
        return Transcription(text: result.text, words: Self.spaced(result.words),
                             durationSec: result.duration, processingSec: result.processingTime)
    }

    /// Voz emits bare words; `Sentence.sentences(from:)` expects each word to carry
    /// its leading space, or sentences run together.
    private static func spaced(_ words: [Word]) -> [TimedWord] {
        words.enumerated().map { index, word in
            TimedWord(text: index == 0 ? word.text : " " + word.text, start: word.start, end: word.end)
        }
    }

    /// The media itself when it is already audio, else its audio track exported to a
    /// temporary m4a.
    static func audioOnly(_ media: URL) async throws -> URL {
        let asset = AVURLAsset(url: media)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw RunError("\(media.lastPathComponent) has no audio track")
        }
        if try await asset.loadTracks(withMediaType: .video).isEmpty { return media }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw RunError("could not read the audio out of \(media.lastPathComponent)")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("desertant-\(UUID().uuidString).m4a")
        try await session.export(to: url, as: .m4a)
        return url
    }
}
#endif
