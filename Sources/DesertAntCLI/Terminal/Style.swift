import Foundation

// The terminal look, from the brand tokens (brand/packages/tokens/src/color*.json):
// sage for the lab and the loader, teal for a model's name, muted and faint for
// labels and hints. The terminal's own foreground carries the body; bold is emphasis.

/// A 24-bit color from the brand tokens.
struct Color: Sendable {
    let r, g, b: UInt8

    init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }

    /// From a `#rrggbb` string, the form the brand token files use.
    init(hex: String) {
        let n = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        r = UInt8((n >> 16) & 0xFF)
        g = UInt8((n >> 8) & 0xFF)
        b = UInt8(n & 0xFF)
    }

    static let cream = Color(hex: "#FBFAF4")
    static let ink = Color(hex: "#0E1113")
    static let sage = Color(hex: "#ADB49C")
    static let teal = Color(hex: "#C3D3CE")
    static let darkTeal = Color(hex: "#1C525D")

    static func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let t = max(0, min(1, t))
        func mix(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8((Double(x) + (Double(y) - Double(x)) * t).rounded()) }
        return Color(r: mix(a.r, b.r), g: mix(a.g, b.g), b: mix(a.b, b.b))
    }
}

/// Dark or light terminal. A color that reads on one vanishes on the other.
enum Theme: Sendable {
    case dark, light

    /// `DESERTANT_THEME=light|dark` wins; else `COLORFGBG` ("fg;bg", where a bg of 7
    /// or 15 is light); else dark.
    static func detect() -> Theme {
        let env = ProcessInfo.processInfo.environment
        switch env["DESERTANT_THEME"]?.lowercased() {
        case "light": return .light
        case "dark": return .dark
        default: break
        }
        if let bg = env["COLORFGBG"]?.split(separator: ";").last, let n = Int(bg) {
            return n == 7 || n == 15 ? .light : .dark
        }
        return .dark
    }

    // color.text.muted and color.text.faint from the dark and light token sets.
    var muted: Color { self == .dark ? Color(hex: "#9AA5A1") : Color(hex: "#57606A") }
    var faint: Color { self == .dark ? Color(hex: "#6E7975") : Color(hex: "#9AA1A5") }
    /// The loader's plate: bg.raised on dark, bg.inset on light.
    var plate: Color { self == .dark ? Color(hex: "#262E2C") : Color(hex: "#E9E8E0") }
    /// The logo: dark uses the inverted mark (cream on ink), light the standard mark
    /// (ink on the 10% plate).
    var logoInk: Color { self == .dark ? .cream : .ink }
    var logoPlate: Color { self == .dark ? .ink : Color(hex: "#E3E3DD") }
}

/// Whether and how to paint. Decided once from the environment.
struct Palette: Sendable {
    let enabled: Bool
    let theme: Theme

    init(enabled: Bool, theme: Theme = .dark) {
        self.enabled = enabled
        self.theme = theme
    }

    /// Off when output is not a terminal, NO_COLOR is set, --no-color was passed, or
    /// output is JSON.
    static func resolve(noColor: Bool, json: Bool) -> Palette {
        if noColor || json { return Palette(enabled: false) }
        if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return Palette(enabled: false) }
        return Palette(enabled: isatty(STDOUT_FILENO) != 0, theme: Theme.detect())
    }

    func bold(_ s: String) -> String {
        guard enabled else { return s }
        return "\u{1B}[1m\(s)\u{1B}[0m"
    }

    /// Sage: a status that landed, the loader.
    func accent(_ s: String) -> String { paint(.sage, s) }
    /// Teal, bold: a model's name. Dark teal on a light terminal, where teal fades.
    func model(_ s: String) -> String { bold(paint(theme == .dark ? .teal : .darkTeal, s)) }

    /// A timestamp beside a line: dark teal, quieter than the text it dates.
    func time(_ s: String) -> String { paint(.darkTeal, s) }
    /// Muted: labels and notes.
    func dim(_ s: String) -> String { paint(theme.muted, s) }
    /// Faint: hints and placeholders.
    func faint(_ s: String) -> String { paint(theme.faint, s) }

    func paint(_ c: Color, _ s: String) -> String {
        guard enabled else { return s }
        return "\u{1B}[38;2;\(c.r);\(c.g);\(c.b)m\(s)\u{1B}[0m"
    }

    /// The mark on its plate: a glyph in the logo's ink over the logo's plate.
    func mark(_ s: String) -> String {
        guard enabled else { return s }
        let fg = theme.logoInk, bg = theme.logoPlate
        return "\u{1B}[1;38;2;\(fg.r);\(fg.g);\(fg.b);48;2;\(bg.r);\(bg.g);\(bg.b)m \(s) \u{1B}[0m"
    }

    /// The wordmark: bold in the logo's ink.
    func wordmark(_ s: String) -> String { bold(paint(theme.logoInk, s)) }
}
