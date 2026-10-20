// Small text helpers shared across commands.

extension String {
    /// Right-aligned in `width` columns, for a column of numbers or times.
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}

/// Shorten a string to at most `width` characters, cutting on a word boundary and
/// marking the cut with a single ellipsis. Short strings pass through unchanged.
func truncate(_ s: String, to width: Int) -> String {
    guard s.count > width else { return s }
    let cut = s.prefix(width - 1)
    if let space = cut.lastIndex(of: " ") {
        return cut[..<space] + "\u{2026}"
    }
    return cut + "\u{2026}"
}

/// Columns a string takes on a terminal: two for an emoji or a wide East Asian
/// character, one for anything else.
func displayWidth(_ s: String) -> Int {
    s.reduce(0) { sum, ch in
        guard let first = ch.unicodeScalars.first else { return sum }
        let wide = ch.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
            || (0x1100...0x115F).contains(first.value) || (0x2E80...0xA4CF).contains(first.value)
            || (0xAC00...0xD7A3).contains(first.value) || (0xF900...0xFAFF).contains(first.value)
            || (0xFF00...0xFF60).contains(first.value) || (0xFFE0...0xFFE6).contains(first.value)
        return sum + (wide ? 2 : 1)
    }
}
