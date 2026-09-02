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
    var palette: Palette { options.palette }
    var isJSON: Bool { options.json }

    /// A line of human text. Suppressed under --json.
    func line(_ s: String = "") {
        guard !isJSON else { return }
        print(s)
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
        for line in wrap(text, width: min(Terminal.columns, 100)) { print(palette.dim(line)) }
    }

    /// Emit a JSON value. Used only under --json.
    func emit<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            FileHandle.standardError.write(Data("could not encode the result\n".utf8))
            return
        }
        print(text)
    }
}

/// Read all of stdin as text, or nil when stdin is a terminal (nothing piped).
func readStdin() -> String? {
    guard isatty(STDIN_FILENO) == 0 else { return nil }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (text?.isEmpty ?? true) ? nil : text
}
