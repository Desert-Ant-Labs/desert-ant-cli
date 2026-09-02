// The loader is the mark: a plus that blooms into the asterisk and settles again, in
// sage, on the brand loader's 2.2s cycle (desert-ant-swift, LoaderData). Only glyphs
// with no emoji presentation, so no terminal swaps in a color emoji.

struct Loader: Sendable {
    static let cycle = 2.2
    private static let frames = ["+", "\u{271A}", "\u{2731}", "\u{2732}", "\u{2217}", "\u{2732}", "\u{2731}", "\u{271A}"]

    func frame(at t: Double, palette: Palette) -> String {
        var phase = (t / Self.cycle).truncatingRemainder(dividingBy: 1)
        if phase < 0 { phase += 1 }
        let glyph = Self.frames[Int(phase * Double(Self.frames.count)) % Self.frames.count]
        return palette.accent(glyph)
    }
}
