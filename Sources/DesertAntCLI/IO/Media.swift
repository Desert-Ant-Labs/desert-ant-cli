import AudioIO
import Foundation

// Audio for the file models. Off Apple, core reads and writes WAV only, so every
// other format goes through ffmpeg.

enum Media {
    static func decodeMono(_ path: String, sampleRate: Double) async throws -> [Float] {
        #if canImport(AVFoundation)
        return try await AudioIO.decode(path: path, sampleRate: sampleRate)
        #else
        if isWAV(path) { return try await AudioIO.decode(path: path, sampleRate: sampleRate) }
        let tools = try FFmpeg.require(for: path, fallback: "pass a WAV file")
        return try FFmpeg.decodeAudio(path, sampleRate: sampleRate, channels: 1, tools: tools)[0]
        #endif
    }

    static func decodeChannels(_ path: String, sampleRate: Double) async throws -> [[Float]] {
        #if canImport(AVFoundation)
        return try await AudioIO.decodeChannels(path: path, sampleRate: sampleRate)
        #else
        if isWAV(path) { return try await AudioIO.decodeChannels(path: path, sampleRate: sampleRate) }
        let tools = try FFmpeg.require(for: path, fallback: "pass a WAV file")
        return try FFmpeg.decodeAudio(path, sampleRate: sampleRate, tools: tools)
        #endif
    }

    /// Writes the container the extension names: WAV directly, anything else through ffmpeg.
    static func write(_ channels: [[Float]], sampleRate: Double, to path: String) throws {
        let wav = Data(AudioIO.encodeWAV(Resample.interleave(channels), sampleRate: Int(sampleRate),
                                         channels: channels.count))
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if ext == "wav" || ext == "wave" {
            try wav.write(to: URL(fileURLWithPath: path))
            return
        }
        let tools = try FFmpeg.require(for: path, fallback: "pass --output with a .wav name")
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("desertant-\(UUID().uuidString).wav")
        try wav.write(to: scratch)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FFmpeg.encode(wav: scratch.path, to: path, tools: tools)
    }

    /// Fails before any work when `path` needs ffmpeg and there is none.
    static func requireWriter(for path: String) throws {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard ext != "wav", ext != "wave", FFmpeg.tools == nil else { return }
        let name = URL(fileURLWithPath: path).lastPathComponent
        throw RunError("writing \(name) needs ffmpeg, which is not installed. Install ffmpeg with \(FFmpeg.installHint), or pass --output with a .wav name.")
    }

    static func isWAV(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let head = [UInt8](handle.readData(ofLength: 12))
        return head.count == 12 && Array(head[0..<4]) == Array("RIFF".utf8) && Array(head[8..<12]) == Array("WAVE".utf8)
    }
}
