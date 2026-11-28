import Foundation

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
        live = !quiet && Terminal.isTTY(STDERR_FILENO)
    }

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

    func finish() {
        ticker?.cancel()
        ticker = nil
        guard live else { return }
        Terminal.writeError("\r\u{1B}[2K")
    }

    private func draw() {
        lock.lock()
        let label = label, fraction = fraction
        lock.unlock()
        let loader = Loader().frame(at: Date().timeIntervalSince(started), palette: palette)
        let pct = fraction.map { "  \(Int((max(0, min(1, $0)) * 100).rounded()))%" } ?? ""
        // The trailing space keeps a block cursor off the last letter.
        Terminal.writeError("\r\u{1B}[2K\(loader)  \(palette.dim(label + pct)) ")
    }
}
