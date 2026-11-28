import Foundation
#if os(Windows)
import WinSDK
#endif

enum Terminal {
    /// Windows deprecates the POSIX name.
    static func isTTY(_ fd: Int32) -> Bool {
        #if os(Windows)
        return _isatty(fd) != 0
        #else
        return isatty(fd) != 0
        #endif
    }

    /// Not FileHandle.standardError, which keeps the handle core's LiteRT log capture closes on Windows.
    static func writeError(_ text: String) {
        let bytes = Array(text.utf8)
        bytes.withUnsafeBytes { raw in
            #if os(Windows)
            _ = _write(2, raw.baseAddress, UInt32(raw.count))
            #else
            _ = write(2, raw.baseAddress, raw.count)
            #endif
        }
    }

    /// UTF-8 and ANSI color in a Windows console, with the code page put back on exit.
    static func prepareConsole() {
        #if os(Windows)
        savedCodePage = GetConsoleOutputCP()
        if SetConsoleOutputCP(UINT(CP_UTF8)) {
            atexit { _ = SetConsoleOutputCP(Terminal.savedCodePage) }
        }
        for id in [STD_OUTPUT_HANDLE, STD_ERROR_HANDLE] {
            let handle = GetStdHandle(id)
            var mode: DWORD = 0
            if GetConsoleMode(handle, &mode) {
                _ = SetConsoleMode(handle, mode | DWORD(ENABLE_VIRTUAL_TERMINAL_PROCESSING))
            }
        }
        #endif
    }

    #if os(Windows)
    nonisolated(unsafe) private static var savedCodePage: UINT = 0
    #endif

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
