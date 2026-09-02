// The brand line at the top of the screens a person reads; never in a pipe, under
// --json, or under --quiet. The logo is monochrome, never a hue (brand/VOICE.md).

enum Brand {
    static let name = "Desert Ant Labs"
    static let line = "Little brains in every product."

    /// The mark, as the glyph nearest to it: a heavy asterisk.
    static let mark = "\u{2731}"

    static func header(_ out: Output) {
        guard out.palette.enabled, !out.options.quiet else { return }
        let p = out.palette
        out.line()
        out.line("\(p.mark(mark)) \(p.wordmark(name))  \(p.dim(line))")
        out.line()
    }
}
