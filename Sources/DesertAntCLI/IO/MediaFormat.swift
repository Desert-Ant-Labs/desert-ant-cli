import Foundation

// Output keeps the input's container unless --output says otherwise. Apple platforms
// write mov, mp4, m4v, m4a, wav, aiff, and caf but not mp3, so an mp3 comes out as
// m4a, the nearest lossy container.

enum MediaFormat {
    static let writable: Set<String> = ["mov", "mp4", "m4v", "m4a", "wav", "aiff", "aif", "caf"]

    /// The extension an output should carry for `input`: the input's own when it can
    /// be written, else m4a for audio and mp4 for video.
    static func outputExtension(for input: String, hasVideo: Bool) -> String {
        let ext = URL(fileURLWithPath: input).pathExtension.lowercased()
        if writable.contains(ext) { return ext }
        return hasVideo ? "mp4" : "m4a"
    }

    /// A note for the reader when the container had to change, else nil.
    static func changeNote(from input: String, to output: String) -> String? {
        let from = URL(fileURLWithPath: input).pathExtension.lowercased()
        let to = URL(fileURLWithPath: output).pathExtension.lowercased()
        guard !from.isEmpty, from != to else { return nil }
        return "Written as \(to): this machine cannot write \(from)."
    }
}
