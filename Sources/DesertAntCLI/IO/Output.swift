import ArgumentParser
import Foundation

// The flags every command shares, and the one place text and JSON leave the process.

/// Flags carried by every subcommand.
struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Machine-readable JSON output.")
    var json = false

    @Flag(name: .long, help: "Only the result, no headings or notes.")
    var quiet = false

    @Flag(name: .customLong("no-color"), help: "Never colorize, even on a terminal.")
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

    /// A line of human text. Suppressed under --json.
    func line(_ s: String = "") {
        guard !isJSON else { return }
        print(s.isEmpty ? s : indent + s)
    }

    /// A message for the person on stderr, whatever stdout carries: a file that failed
    /// in a batch. Printed under --quiet too, since an error is not a note.
    func warn(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }

    /// A blank line on a terminal, so a result stands apart from the prompt and the
    /// notes. Nothing in a pipe, under --json, or with --quiet.
    func space() {
        guard !isJSON, !options.quiet, isatty(STDOUT_FILENO) != 0 else { return }
        print()
    }

    /// A note, dimmed and wrapped at the terminal's width. Suppressed under --json or
    /// --quiet. A leading newline is kept as a blank line before the note.
    func note(_ s: String) {
        guard !isJSON, !options.quiet else { return }
        if s.hasPrefix("\n") { print() }
        let text = s.trimmingCharacters(in: .newlines)
        guard !text.isEmpty else { return }
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
