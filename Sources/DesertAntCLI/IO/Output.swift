import ArgumentParser
import Foundation

// The flags every command shares, and the one place text and JSON leave the process.

/// Flags carried by every subcommand.
struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Print the result as JSON, for scripts and agents.")
    var json = false

    @Flag(name: .long, help: "Print only the result, without headings, notes, or progress.")
    var quiet = false

    @Flag(name: .customLong("no-color"), help: "Print without color, even on a terminal.")
    var noColor = false

    /// The painting decision for this run.
    var palette: Palette { Palette.resolve(noColor: noColor, json: json) }
}

/// Where a command writes its result, with the flags that decide how.
struct Output {
    let options: GlobalOptions
    /// Set while several inputs run in one process: `emit` collects each result here
    /// instead of printing, and the loop prints the list once at the end.
    var batch: Batch? = nil
    /// Put in front of every text line, so one input's lines sit under its name.
    var indent = ""
    var palette: Palette { options.palette }
    var isJSON: Bool { options.json }

    /// A line of human text. Suppressed under --json. An empty line asks for a break
    /// before whatever prints next; see `Spacing`.
    func line(_ s: String = "") {
        guard !isJSON else { return }
        guard !s.isEmpty else { return Spacing.shared.breakNext() }
        Spacing.shared.open(.result)
        print(indent + s)
    }

    /// Text that is already laid out, such as a transcript or an .srt, printed as it is.
    /// Printed under --json too, since a format the reader asked for wins.
    func text(_ s: String) {
        guard !s.isEmpty else { return }
        Spacing.shared.open(.result)
        print(s, terminator: s.hasSuffix("\n") ? "" : "\n")
    }

    /// A message for the person on stderr, whatever stdout carries: a file that failed
    /// in a batch. Printed under --quiet too, since an error is not a note.
    func warn(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }

    /// End a block: whatever prints next starts after one blank line.
    func space() {
        guard !isJSON else { return }
        Spacing.shared.breakNext()
    }

    /// Whether notes and hints show: on a terminal, without --json or --quiet. In a pipe
    /// or a file, stdout carries the result alone, so `voz --format srt > a.srt` stays
    /// a valid .srt.
    var decorates: Bool { !isJSON && !options.quiet && isatty(STDOUT_FILENO) != 0 }

    /// A note, dimmed and wrapped at the terminal's width, shown only when `decorates`.
    /// Notes in a row form one block, set apart from the result.
    func note(_ s: String) {
        guard decorates else { return }
        let text = s.trimmingCharacters(in: .newlines)
        guard !text.isEmpty else { return }
        Spacing.shared.open(.note)
        for line in wrap(text, width: min(Terminal.columns, 100) - indent.count) { print(indent + palette.dim(line)) }
    }

    /// Emit a JSON value. Used only under --json. In a batch the value is collected
    /// and printed with the others as one array.
    func emit<T: Encodable>(_ value: T) {
        if let batch {
            batch.append(value)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            FileHandle.standardError.write(Data("could not encode the result\n".utf8))
            return
        }
        print(text)
    }
}

/// The results of a batch, in input order, printed as one JSON array at the end.
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

/// One runner's result with its type erased, so a batch can hold any of them.
struct AnyEncodable: Encodable {
    private let encodeInto: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { encodeInto = { try value.encode(to: $0) } }
    func encode(to encoder: Encoder) throws { try encodeInto(encoder) }
}

/// Read all of stdin as text, or nil when stdin is a terminal (nothing piped).
func readStdin() -> String? {
    guard isatty(STDIN_FILENO) == 0 else { return nil }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (text?.isEmpty ?? true) ? nil : text
}

extension Output {
    /// What to type next: each command and what it does, in two aligned columns, the
    /// command named the way the reader started this one. Shown only when `decorates`.
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

/// The blank lines between blocks of text output, decided in one place: one blank line
/// between a result, its notes, and the hints, and none before the first line or after
/// the last, so the output sits right under the command and the prompt follows it.
final class Spacing: @unchecked Sendable {
    enum Block { case result, note, hints }

    static let shared = Spacing()
    private let lock = NSLock()
    private var last: Block?
    private var pending = false

    /// Ask for a blank line before the next block. Nothing prints if nothing follows.
    func breakNext() {
        lock.lock()
        pending = true
        lock.unlock()
    }

    /// About to print a line of `block`: put a blank line first when it starts a new
    /// block after earlier output.
    func open(_ block: Block) {
        lock.lock()
        defer { lock.unlock() }
        if let last, pending || last != block { print() }
        last = block
        pending = false
    }
}
