// Word wrap for the terminal, so a column reads as a paragraph instead of a cut-off
// line. Breaks at spaces; a single word longer than the width stands on its own line.

func wrap(_ text: String, width: Int) -> [String] {
    let width = max(1, width)
    var lines: [String] = []
    var line = ""
    for word in text.split(separator: " ", omittingEmptySubsequences: true) {
        if line.isEmpty {
            line = String(word)
        } else if line.count + 1 + word.count <= width {
            line += " " + word
        } else {
            lines.append(line)
            line = String(word)
        }
    }
    if !line.isEmpty { lines.append(line) }
    return lines.isEmpty ? [""] : lines
}

/// Two columns: a key on the left, a paragraph on the right that wraps under itself.
/// `tag` is a short remark set in dim on its own line under the paragraph.
func column(_ key: String, keyWidth: Int, text: String, width: Int, tag: String? = nil,
            palette: Palette, keyStyle: (String) -> String = { $0 }) -> [String] {
    let indent = String(repeating: " ", count: keyWidth + 2)
    let room = max(24, width - keyWidth - 2)
    var lines = wrap(text, width: room).enumerated().map { i, line in
        (i == 0 ? keyStyle(key.padding(toLength: keyWidth, withPad: " ", startingAt: 0)) + "  " : indent) + line
    }
    if let tag { lines.append(indent + palette.dim(tag)) }
    return lines
}
