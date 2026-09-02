// Small text helpers shared across commands.

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
