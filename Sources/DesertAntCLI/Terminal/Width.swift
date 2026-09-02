import Foundation

// The terminal's width, so a list fits on one line per row instead of wrapping.

enum Terminal {
    /// Columns available on stdout: the tty's width, else `COLUMNS`, else 100.
    static var columns: Int {
        var size = winsize()
        // Glibc types the request as Int32 where ioctl wants UInt; Darwin already agrees.
        if isatty(STDOUT_FILENO) != 0, ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0, size.ws_col > 0 {
            return Int(size.ws_col)
        }
        if let env = ProcessInfo.processInfo.environment["COLUMNS"], let n = Int(env), n > 0 { return n }
        return 100
    }
}
