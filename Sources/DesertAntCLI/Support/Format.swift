// Time the way the brand writes it (brand/VOICE.md): a measured time takes the
// compact unit against the number ("in 41s", "2m 10s"), the material being
// measured stays in words ("48 minutes of audio").

enum Format {
    /// A measured duration: "41s", "2m 10s", "1h 03m".
    static func elapsed(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return seconds < 10 ? String(format: "%.1fs", seconds) : "\(s)s" }
        let m = s / 60, rest = s % 60
        if m < 60 { return rest == 0 ? "\(m)m" : "\(m)m \(rest)s" }
        return String(format: "%dh %02dm", m / 60, m % 60)
    }

    /// The material's length in words: "12 seconds", "48 minutes", "1 hour 12 minutes".
    static func spoken(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) second\(s == 1 ? "" : "s")" }
        let m = s / 60
        if m < 60 { return "\(m) minute\(m == 1 ? "" : "s")" }
        let h = m / 60, rest = m % 60
        let hours = "\(h) hour\(h == 1 ? "" : "s")"
        return rest == 0 ? hours : "\(hours) \(rest) minute\(rest == 1 ? "" : "s")"
    }

    /// "70x realtime", rounded to a whole number.
    static func realtime(material: Double, elapsed: Double) -> String {
        guard elapsed > 0 else { return "" }
        return "\(Int((material / elapsed).rounded()))x realtime"
    }
}

extension Format {
    /// `1:04:07` or `4:07`, the way a person reads a timestamp.
    static func stamp(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
