import Foundation
import Transcript

// Writing a clip out of the source media: AVFoundation on Apple platforms, ffmpeg
// elsewhere.

/// What a media file holds, read before any model is fetched or run.
struct MediaInfo: Sendable {
    let hasVideo: Bool
    let hasAudio: Bool
    let durationSec: Double
    /// The picture as it plays, turned the way the file says to show it.
    var width = 0
    var height = 0
}

protocol MediaCutter: Sendable {
    /// The tracks and length of `source`.
    func probe(_ source: URL) async throws -> MediaInfo
    /// Lay `ranges` of `source` end to end and write them to `destination`.
    func cut(_ source: URL, ranges: [TimeRange], to destination: URL) async throws
    /// The ranges with `captions` drawn into the picture, which re-encodes the video.
    func cut(_ source: URL, ranges: [TimeRange], burning captions: BurnedCaptions, frame: CaptionFrame, to destination: URL) async throws
    /// `video`'s picture with `audio` as its sound, written to `destination`.
    func replaceAudio(of video: URL, with audio: URL, to destination: URL) async throws
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
        let video = try await asset.loadTracks(withMediaType: .video).first
        var size = CGSize.zero
        if let video {
            let (natural, transform) = try await video.load(.naturalSize, .preferredTransform)
            size = natural.applying(transform)
        }
        return MediaInfo(
            hasVideo: video != nil,
            hasAudio: try await !asset.loadTracks(withMediaType: .audio).isEmpty,
            durationSec: try await asset.load(.duration).seconds,
            width: Int(abs(size.width).rounded()), height: Int(abs(size.height).rounded())
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
        do {
            try await export(composition, preset: preset, as: type, to: destination)
        } catch where preset == AVAssetExportPresetPassthrough {
            // Passthrough stops on some AAC ranges, such as one that starts within the
            // first 0.1s of an m4a. Re-encoding the same range works.
            try? FileManager.default.removeItem(at: destination)
            try await export(composition, preset: video ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleM4A,
                             as: video ? .mp4 : .m4a,
                             to: destination)
        }
    }

    func replaceAudio(of video: URL, with audio: URL, to destination: URL) async throws {
        let picture = AVURLAsset(url: video), sound = AVURLAsset(url: audio)
        guard let sourceVideo = try await picture.loadTracks(withMediaType: .video).first,
              let sourceAudio = try await sound.loadTracks(withMediaType: .audio).first else {
            throw RunError("could not read the tracks of \(video.lastPathComponent) and \(audio.lastPathComponent).")
        }
        let length = try await picture.load(.duration)
        let composition = AVMutableComposition()
        let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        try track?.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: sourceVideo, at: .zero)
        track?.preferredTransform = try await sourceVideo.load(.preferredTransform)
        let soundLength = try await sound.load(.duration)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(length, soundLength)), of: sourceAudio, at: .zero)
        let type = Self.fileType(for: destination.pathExtension) ?? .mp4
        do {
            try await export(composition, preset: AVAssetExportPresetPassthrough, as: type, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            try await export(composition, preset: AVAssetExportPresetHighestQuality, as: .mp4, to: destination)
        }
    }

    private func export(_ composition: AVComposition, preset: String, as type: AVFileType, to destination: URL) async throws {
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw RunError("could not start an export for \(destination.lastPathComponent).")
        }
        // Destination already allowed this path, and AVFoundation will not write over a file.
        try? FileManager.default.removeItem(at: destination)
        do {
            try await session.export(to: destination, as: type)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw RunError("could not write \(destination.lastPathComponent): \(error.localizedDescription)")
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

    static func composition(of asset: AVAsset, keeping ranges: [TimeRange]) async throws -> AVComposition {
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

struct FFmpegCutter: MediaCutter {
    let tools: FFmpeg.Tools

    func probe(_ source: URL) async throws -> MediaInfo {
        let info = try FFmpeg.probe(source.path, tools: tools)
        let turned = abs(info.rotation) % 180 == 90
        return MediaInfo(hasVideo: info.hasVideo, hasAudio: info.hasAudio, durationSec: info.durationSec,
                         width: turned ? info.height : info.width, height: turned ? info.width : info.height)
    }

    func cut(_ source: URL, ranges: [TimeRange], to destination: URL) async throws {
        try FFmpeg.cut(source.path, ranges: ranges.map { ($0.start, $0.duration) }, to: destination.path, tools: tools)
    }

    func replaceAudio(of video: URL, with audio: URL, to destination: URL) async throws {
        try FFmpeg.run(tools.ffmpeg, ["-v", "error", "-nostdin", "-y", "-i", video.path, "-i", audio.path,
                                      "-map", "0:v:0", "-map", "1:a:0", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
                                      "-shortest", destination.path],
                       file: destination.path, writing: true)
    }
}
