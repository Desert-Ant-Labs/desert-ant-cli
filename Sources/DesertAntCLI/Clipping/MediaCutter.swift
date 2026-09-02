import Foundation
import Transcript

// Writing a clip out of the source media. AVFoundation does it on Apple platforms;
// another platform can bring its own cutter behind the same protocol.

/// What a media file holds, read before any model is fetched or run.
struct MediaInfo: Sendable {
    let hasVideo: Bool
    let hasAudio: Bool
    let durationSec: Double
}

protocol MediaCutter: Sendable {
    /// The tracks and length of `source`.
    func probe(_ source: URL) async throws -> MediaInfo
    /// Lay `ranges` of `source` end to end and write them to `destination`.
    func cut(_ source: URL, ranges: [TimeRange], to destination: URL) async throws
}

#if canImport(AVFoundation)
import AVFoundation

/// A composition of the kept ranges, exported at the highest quality preset for
/// video and as M4A for audio. Modeled on the Clipper app's cutter.
struct AVFoundationCutter: MediaCutter {
    func probe(_ source: URL) async throws -> MediaInfo {
        let asset = AVURLAsset(url: source)
        guard try await asset.load(.isReadable) else {
            throw RunError("\(source.lastPathComponent) is not a media file this machine can read")
        }
        return MediaInfo(
            hasVideo: try await !asset.loadTracks(withMediaType: .video).isEmpty,
            hasAudio: try await !asset.loadTracks(withMediaType: .audio).isEmpty,
            durationSec: try await asset.load(.duration).seconds
        )
    }

    /// Cuts are passthrough: the tracks are copied, not re-encoded, and the output
    /// keeps the container the destination's extension names. Video cuts land on
    /// keyframes.
    func cut(_ source: URL, ranges: [TimeRange], to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let composition = try await Self.composition(of: asset, keeping: ranges)
        let video = try await !composition.loadTracks(withMediaType: .video).isEmpty
        let wanted = Self.fileType(for: destination.pathExtension)
        var preset = AVAssetExportPresetPassthrough
        var type = wanted ?? (video ? .mp4 : .m4a)
        if let passthrough = AVAssetExportSession(asset: composition, presetName: preset),
           !passthrough.supportedFileTypes.contains(type) {
            // The source's codecs cannot go into that container as they are.
            preset = video ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleM4A
            type = video ? .mp4 : .m4a
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw RunError("could not start an export for \(source.lastPathComponent)")
        }
        do {
            try await session.export(to: destination, as: type)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw RunError("writing \(destination.lastPathComponent) failed: \(error.localizedDescription)")
        }
    }

    private static func fileType(for ext: String) -> AVFileType? {
        switch ext.lowercased() {
        case "mov": .mov
        case "mp4": .mp4
        case "m4v": .m4v
        case "m4a": .m4a
        case "wav": .wav
        case "aiff", "aif": .aiff
        case "caf": .caf
        default: nil
        }
    }

    private static func composition(of asset: AVAsset, keeping ranges: [TimeRange]) async throws -> AVComposition {
        let composition = AVMutableComposition()
        let sourceVideo = try await asset.loadTracks(withMediaType: .video).first
        let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first
        guard sourceVideo != nil || sourceAudio != nil else {
            throw RunError("no playable track in the source")
        }
        let whole = try await CMTimeRange(start: .zero, duration: asset.load(.duration))
        let video = sourceVideo.flatMap { _ in
            composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        let audio = sourceAudio.flatMap { _ in
            composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }

        var cursor = CMTime.zero
        for range in ranges {
            let span = CMTimeRange(
                start: CMTime(seconds: range.start, preferredTimescale: 600),
                duration: CMTime(seconds: range.duration, preferredTimescale: 600)
            ).intersection(whole)
            guard span.duration > .zero else { continue }
            if let sourceVideo, let video { try video.insertTimeRange(span, of: sourceVideo, at: cursor) }
            if let sourceAudio, let audio { try audio.insertTimeRange(span, of: sourceAudio, at: cursor) }
            cursor = cursor + span.duration
        }
        guard cursor > .zero else { throw RunError("the clip's time range lies outside the source") }
        if let sourceVideo, let video {
            video.preferredTransform = try await sourceVideo.load(.preferredTransform)
        }
        return composition
    }
}
#endif
