import ArgumentParser

// The site's three hubs: audio, text, vision. The manifest carries a Hugging Face
// pipeline tag instead, so discovery maps the tag onto a hub; a model with no
// pipeline tag (the closed betas) falls back to its Hub tags.

enum Group: String, CaseIterable, Sendable, ExpressibleByArgument {
    case audio, text, vision

    /// Pipeline tags by hub. Anything unlisted is text, the catalog's largest hub.
    private static let audioPipelines: Set<String> = [
        "audio-classification", "audio-to-audio", "automatic-speech-recognition",
        "voice-activity-detection", "text-to-speech",
    ]
    private static let visionPrefixes = ["image", "video", "object-detection", "depth"]

    static func of(_ model: Model) -> Group {
        if let tag = model.hub.pipelineTag {
            if audioPipelines.contains(tag) { return .audio }
            if visionPrefixes.contains(where: tag.hasPrefix) { return .vision }
            return .text
        }
        let tags = Set(model.hub.tags)
        if !tags.isDisjoint(with: ["audio", "speech"]) { return .audio }
        if !tags.isDisjoint(with: ["image", "video", "vision", "face", "nsfw"]) { return .vision }
        return .text
    }
}
