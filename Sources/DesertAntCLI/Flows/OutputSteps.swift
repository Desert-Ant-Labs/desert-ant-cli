import Foundation

enum OutputSteps {
    static let all: [StepDef] = [view, table]

    static let view = StepDef(
        type: "view", summary: "Prints the value, and puts it in the --json outputs.", category: .output,
        inputs: [Port(id: "value", type: .any)],
        noMap: true
    ) { run in
        guard let value = run.inputs["value"] else { return [:] }
        run.context.run.show(run.context.step.id, value, text: lines(value))
        return [:]
    }

    /// Lines up lists item by item, a column each.
    static let table = StepDef(
        type: "table", summary: "Prints lists side by side, a row per item and a column per input.", category: .output,
        inputs: ["a", "b", "c"].map { Port(id: $0, type: .any, optional: true) },
        defaults: ["columns": ""],
        noMap: true
    ) { run in
        let keys = ["a", "b", "c"].filter { run.inputs[$0] != nil }
        guard !keys.isEmpty else { return [:] }
        let given = (run.params["columns"]?.string ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let headers = keys.enumerated().map { i, key in i < given.count && !given[i].isEmpty ? given[i] : key }
        let columns = keys.map { run.inputs[$0]!.items }
        let count = columns.map(\.count).max() ?? 0
        let rows: [[Value?]] = (0..<count).map { i in columns.map { i < $0.count ? $0[i] : nil } }
        let value = Value.list(rows.map { row in
            .record(zip(headers, row).map { ($0, $1 ?? .text("")) })
        })
        run.context.run.show(run.context.step.id, value, text: align([headers] + rows.map { $0.map { cell($0) } }))
        return [:]
    }

    /// A value as terminal lines: a list one item per line, a record as JSON.
    static func lines(_ value: Value) -> [String] {
        switch value {
        case .list, .stream: return value.items.map { cell($0) }
        case .record: return value.json().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        default: return value.asText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        }
    }

    static func cell(_ value: Value?) -> String {
        guard let value else { return "" }
        if case .record = value { return value.json(pretty: false) }
        if let path = value.path { return path }
        return value.asText.replacingOccurrences(of: "\n", with: " ")
    }

    /// Columns padded to their widest cell, two spaces apart.
    static func align(_ rows: [[String]]) -> [String] {
        let widths = (0..<(rows.map(\.count).max() ?? 0)).map { c in rows.map { c < $0.count ? displayWidth($0[c]) : 0 }.max() ?? 0 }
        return rows.map { row in
            row.enumerated().map { c, text in
                c == row.count - 1 ? text : text + String(repeating: " ", count: widths[c] - displayWidth(text))
            }.joined(separator: "  ").replacing(#/\s+$/#, with: "")
        }
    }
}
