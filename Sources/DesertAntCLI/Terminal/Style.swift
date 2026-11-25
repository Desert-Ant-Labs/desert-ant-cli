import Foundation

struct Color: Sendable {
    let r, g, b: UInt8

    init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }

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

enum Theme: Sendable {
    case dark, light

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

    var muted: Color { self == .dark ? Color(hex: "#9AA5A1") : Color(hex: "#57606A") }
    var faint: Color { self == .dark ? Color(hex: "#6E7975") : Color(hex: "#9AA1A5") }
    var plate: Color { self == .dark ? Color(hex: "#262E2C") : Color(hex: "#E9E8E0") }
    var logoInk: Color { self == .dark ? .cream : .ink }
    var logoPlate: Color { self == .dark ? .ink : Color(hex: "#E3E3DD") }
}

struct Palette: Sendable {
    let enabled: Bool
    let theme: Theme

    init(enabled: Bool, theme: Theme = .dark) {
        self.enabled = enabled
        self.theme = theme
    }

    static func resolve(noColor: Bool, json: Bool) -> Palette {
        if noColor || json { return Palette(enabled: false) }
        if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return Palette(enabled: false) }
        return Palette(enabled: Terminal.isTTY(STDOUT_FILENO), theme: Theme.detect())
    }

    func bold(_ s: String) -> String {
        guard enabled else { return s }
        return "\u{1B}[1m\(s)\u{1B}[0m"
    }

    func accent(_ s: String) -> String { paint(.sage, s) }
    func model(_ s: String) -> String { bold(paint(theme == .dark ? .teal : .darkTeal, s)) }

    func time(_ s: String) -> String { paint(.darkTeal, s) }
    func dim(_ s: String) -> String { paint(theme.muted, s) }
    func faint(_ s: String) -> String { paint(theme.faint, s) }

    func paint(_ c: Color, _ s: String) -> String {
        guard enabled else { return s }
        return "\u{1B}[38;2;\(c.r);\(c.g);\(c.b)m\(s)\u{1B}[0m"
    }

    func mark(_ s: String) -> String {
        guard enabled else { return s }
        let fg = theme.logoInk, bg = theme.logoPlate
        return "\u{1B}[1;38;2;\(fg.r);\(fg.g);\(fg.b);48;2;\(bg.r);\(bg.g);\(bg.b)m \(s) \u{1B}[0m"
    }

    func wordmark(_ s: String) -> String { bold(paint(theme.logoInk, s)) }
}
