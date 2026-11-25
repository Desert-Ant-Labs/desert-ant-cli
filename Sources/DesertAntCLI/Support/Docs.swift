import ArgumentParser

struct Docs: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "docs",
        abstract: "Read the docs, offline, from the binary.",
        discussion: "The pages are \(Embedded.docs.map(\.name).joined(separator: ", "))."
    )

    @Argument(help: "A page name, such as agents or json. Without it, desertant prints the index.")
    var page: String?

    @OptionGroup var options: GlobalOptions

    struct Page: Encodable {
        let name: String
        let title: String
        let markdown: String
    }
    struct Listing: Encodable {
        let name: String
        let title: String
    }

    static func title(of markdown: String) -> String {
        markdown.split(separator: "\n").first { $0.hasPrefix("# ") }
            .map { String($0.dropFirst(2)) } ?? ""
    }

    func run() throws {
        let out = Output(options: options)
        let name = page?.lowercased() ?? "index"
        guard let doc = Embedded.docs.first(where: { $0.name == name }) else {
            throw ValidationError("No page named \(name). Pages: \(Embedded.docs.map(\.name).joined(separator: ", ")).")
        }

        if out.isJSON {
            if page == nil {
                out.emit(Embedded.docs.map { Listing(name: $0.name, title: Self.title(of: $0.markdown)) })
            } else {
                out.emit(Page(name: doc.name, title: Self.title(of: doc.markdown), markdown: doc.markdown))
            }
            return
        }

        let p = out.palette
        var inFence = false
        for line in doc.markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.hasPrefix("```") {
                inFence.toggle()
                out.line(p.dim(s))
            } else if !inFence, s.hasPrefix("#") {
                out.line(p.bold(s))
            } else {
                out.line(s)
            }
        }
    }
}
