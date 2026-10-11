import Foundation

// Output keeps the input's container unless --output says otherwise. A Mac, or Linux
// with ffmpeg, writes mov, mp4, m4v, m4a, wav, aiff, and caf, so an mp3 comes out as
// m4a, the nearest lossy container. Linux without ffmpeg writes WAV only.

enum MediaFormat {
    static let writable: Set<String> = {
        #if canImport(AVFoundation)
        return all
        #else
        return FFmpeg.tools == nil ? ["wav"] : all
        #endif
    }()

    private static let all: Set<String> = ["mov", "mp4", "m4v", "m4a", "wav", "aiff", "aif", "caf"]

    /// The input's own extension when it can be written, else m4a for audio and mp4
    /// for video, or wav where only WAV can be written.
    static func outputExtension(for input: String, hasVideo: Bool) -> String {
        let ext = URL(fileURLWithPath: input).pathExtension.lowercased()
        if writable.contains(ext) { return ext }
        if writable == ["wav"] { return "wav" }
        return hasVideo ? "mp4" : "m4a"
    }

    static func changeNote(from input: String, to output: String) -> String? {
        let from = URL(fileURLWithPath: input).pathExtension.lowercased()
        let to = URL(fileURLWithPath: output).pathExtension.lowercased()
        guard !from.isEmpty, from != to else { return nil }
        return "Written as \(to): this machine cannot write \(from)."
    }
}
