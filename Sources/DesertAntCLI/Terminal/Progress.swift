import Foundation

// One progress line on stderr: the loader, a label, and a percentage when there is
// one. The loader runs on its own clock so a phase with no measurable progress still
// moves. Nothing draws unless stderr is a terminal, so a captured log holds only text.

final class Progress: @unchecked Sendable {
    private let palette: Palette
    private let live: Bool
    private let lock = NSLock()
    private var label = ""
    private var fraction: Double?
    private var ticker: Task<Void, Never>?
    private let started = Date()

    init(palette: Palette, quiet: Bool) {
        self.palette = palette
        live = !quiet && isatty(STDERR_FILENO) != 0
    }

    /// Set what the line says. `fraction` is 0...1, or nil when the phase has no
    /// measurable progress.
    func update(_ fraction: Double?, label: String) {
        lock.lock()
        self.label = label
        self.fraction = fraction
        lock.unlock()
        guard live else { return }
        if ticker == nil {
            ticker = Task.detached(priority: .utility) { [weak self] in
                while !Task.isCancelled {
                    self?.draw()
                    try? await Task.sleep(nanoseconds: 80_000_000)
                }
            }
        }
    }

    /// Clear the line, ready for the result on stdout.
    func finish() {
        ticker?.cancel()
        ticker = nil
        guard live else { return }
        FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8))
    }

    private func draw() {
        lock.lock()
        let label = label, fraction = fraction
        lock.unlock()
        let loader = Loader().frame(at: Date().timeIntervalSince(started), palette: palette)
        let pct = fraction.map { "  \(Int((max(0, min(1, $0)) * 100).rounded()))%" } ?? ""
        // The trailing space keeps a block cursor off the last letter.
        FileHandle.standardError.write(Data("\r\u{1B}[2K\(loader)  \(palette.dim(label + pct)) ".utf8))
    }
}
