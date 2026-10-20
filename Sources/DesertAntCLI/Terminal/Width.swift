import Foundation
#if os(Windows)
import WinSDK
#endif

// The terminal's width, so a list fits on one line per row instead of wrapping.

enum Terminal {
    /// Whether a file descriptor is a terminal. Windows deprecates the POSIX name.
    static func isTTY(_ fd: Int32) -> Bool {
        #if os(Windows)
        return _isatty(fd) != 0
        #else
        return isatty(fd) != 0
        #endif
    }

    /// Columns available on stdout: the tty's width, else `COLUMNS`, else 100.
    static var columns: Int {
        #if os(Windows)
        // Fails when stdout is redirected, which stands in for the isatty check.
        var info = CONSOLE_SCREEN_BUFFER_INFO()
        if GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &info) {
            let width = Int(info.srWindow.Right) - Int(info.srWindow.Left) + 1
            if width > 0 { return width }
        }
        #else
        var size = winsize()
        // Glibc types the request as Int32 where ioctl wants UInt; Darwin already agrees.
        if isTTY(STDOUT_FILENO), ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0, size.ws_col > 0 {
            return Int(size.ws_col)
        }
        #endif
        if let env = ProcessInfo.processInfo.environment["COLUMNS"], let n = Int(env), n > 0 { return n }
        return 100
    }
}
