import ArgumentParser
import Foundation

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Print the result as JSON, for scripts and agents.")
    var json = false

    @Flag(name: .long, help: "Print only the result, without headings, notes, or progress.")
    var quiet = false

    @Flag(name: .customLong("no-color"), help: "Print without color, even on a terminal.")
    var noColor = false

    var palette: Palette { Palette.resolve(noColor: noColor, json: json) }
}

struct Output {
    let options: GlobalOptions
    var batch: Batch? = nil
    var indent = ""
    var palette: Palette { options.palette }
    var isJSON: Bool { options.json }

    func line(_ s: String = "") {
        guard !isJSON else { return }
        guard !s.isEmpty else { return Spacing.shared.breakNext() }
        Spacing.shared.open(.result)
        print(indent + s)
    }

    /// Printed under --json too, since a format the reader asked for wins.
    func text(_ s: String) {
        guard !s.isEmpty else { return }
        Spacing.shared.open(.result)
        print(s, terminator: s.hasSuffix("\n") ? "" : "\n")
    }

    /// Printed under --quiet too, since an error is not a note.
    func warn(_ s: String) {
        Terminal.writeError(s + "\n")
    }

    func space() {
        guard !isJSON else { return }
        Spacing.shared.breakNext()
    }

    /// Off a terminal, stdout carries the result alone, so `voz --format srt > a.srt` stays a valid .srt.
    var decorates: Bool { !isJSON && !options.quiet && Terminal.isTTY(STDOUT_FILENO) }

    func note(_ s: String) {
        guard decorates else { return }
        let text = s.trimmingCharacters(in: .newlines)
        guard !text.isEmpty else { return }
        Spacing.shared.open(.note)
        for line in wrap(text, width: min(Terminal.columns, 100) - indent.count) { print(indent + palette.dim(line)) }
    }

    func emit<T: Encodable>(_ value: T) {
        if let batch {
            batch.append(value)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            Terminal.writeError("could not encode the result\n")
            return
        }
        print(text)
    }
}

final class Batch: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AnyEncodable] = []

    func append<T: Encodable>(_ value: T) {
        lock.lock()
        items.append(AnyEncodable(value))
        lock.unlock()
    }

    var all: [AnyEncodable] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

struct AnyEncodable: Encodable {
    private let encodeInto: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { encodeInto = { try value.encode(to: $0) } }
    func encode(to encoder: Encoder) throws { try encodeInto(encoder) }
}

func readStdin() -> String? {
    guard !Terminal.isTTY(STDIN_FILENO) else { return nil }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (text?.isEmpty ?? true) ? nil : text
}

extension Output {
    func hints(_ rows: [(command: String, does: String)]) {
        guard decorates, !rows.isEmpty else { return }
        let p = palette
        let commands = rows.map { "\(Invocation.name) \($0.command)" }
        let keyWidth = commands.map(displayWidth).max() ?? 0
        let room = max(24, min(Terminal.columns, 110) - indent.count - keyWidth - 4)
        Spacing.shared.open(.hints)
        for (command, row) in zip(commands, rows) {
            let pad = String(repeating: " ", count: keyWidth - displayWidth(command))
            for (i, text) in wrap(row.does, width: room).enumerated() {
                let key = i == 0 ? command + pad : String(repeating: " ", count: keyWidth)
                print(indent + "  " + p.dim(key) + "  " + p.faint(text))
            }
        }
    }
}

final class Spacing: @unchecked Sendable {
    enum Block { case result, note, hints }

    static let shared = Spacing()
    private let lock = NSLock()
    private var last: Block?
    private var pending = false

    func breakNext() {
        lock.lock()
        pending = true
        lock.unlock()
    }

    func open(_ block: Block) {
        lock.lock()
        defer { lock.unlock() }
        if let last, pending || last != block { print() }
        last = block
        pending = false
    }
}
