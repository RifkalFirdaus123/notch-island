import Foundation

/// A run of text with one style.
nonisolated struct TextRun: Equatable, Sendable {
    var text: String
    var bold = false
    var italic = false
    var strike = false
    var code = false
    var link: String?
}

/// A simple structured document: what Markdown, plain text and tables become
/// before being written as HTML or Word. Writing Word ourselves (instead of
/// through AppKit) keeps tables, lists and headings intact in Word.
nonisolated enum DocBlock: Equatable, Sendable {
    case heading(Int, [TextRun])
    /// "\n" inside a run is a line break.
    case paragraph([TextRun])
    case list(ordered: Bool, items: [[TextRun]])
    case quote([TextRun])
    case code(String)
    case rule
    /// The first row is the header.
    case table([[[TextRun]]])

    static func table(_ rows: TableRows) -> DocBlock {
        .table(rows.map { $0.map { [TextRun(text: $0)] } })
    }

    var tableColumnCount: Int {
        if case .table(let rows) = self { return rows.map(\.count).max() ?? 0 }
        return 0
    }
}

// MARK: - Markdown → blocks

nonisolated enum MarkdownParser {
    static func blocks(_ markdown: String) -> [DocBlock] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [DocBlock] = []
        var paragraph: [String] = []
        var list: (ordered: Bool, items: [[TextRun]])?
        var i = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(inline(paragraph.joined(separator: "\n"))))
            paragraph = []
        }
        func closeList() {
            if let list { blocks.append(.list(ordered: list.ordered, items: list.items)) }
            list = nil
        }

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph(); closeList()
                let fence = String(trimmed.prefix(3))
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[i])
                    i += 1
                }
                blocks.append(.code(code.joined(separator: "\n")))
                i += 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph(); closeList()
            } else if let level = headingLevel(trimmed) {
                flushParagraph(); closeList()
                let text = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: #"\s+#+$"#, with: "", options: .regularExpression)
                blocks.append(.heading(level, inline(text)))
            } else if trimmed.range(of: #"^([-*_])(\s*\1){2,}$"#, options: .regularExpression) != nil {
                flushParagraph(); closeList()
                blocks.append(.rule)
            } else if trimmed.hasPrefix(">") {
                flushParagraph(); closeList()
                var quote: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    quote.append(t.dropFirst().trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(inline(quote.joined(separator: "\n"))))
                continue
            } else if trimmed.hasPrefix("|"), i + 1 < lines.count, isTableDivider(lines[i + 1]) {
                flushParagraph(); closeList()
                var rows = [tableCells(trimmed)]
                i += 2
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(tableCells(lines[i]))
                    i += 1
                }
                blocks.append(.table(rows.map { $0.map(inline) }))
                continue
            } else if let item = listItem(trimmed) {
                flushParagraph()
                if list?.ordered != item.ordered { closeList(); list = (item.ordered, []) }
                list?.items.append(inline(item.text))
            } else if list != nil, lines[i].hasPrefix("  ") || lines[i].hasPrefix("\t") {
                // Indented continuation of the last list item.
                if var current = list, !current.items.isEmpty {
                    current.items[current.items.count - 1] += [TextRun(text: " ")] + inline(trimmed)
                    list = current
                }
            } else {
                closeList()
                paragraph.append(trimmed)
            }
            i += 1
        }
        flushParagraph(); closeList()
        return blocks
    }

    /// Paragraphs separated by blank lines; single newlines are kept.
    static func blocks(plainText text: String) -> [DocBlock] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { .paragraph([TextRun(text: $0)]) }
    }

    // MARK: Inline

    static func inline(_ text: String) -> [TextRun] {
        var runs: [TextRun] = []
        parse(Array(text), style: TextRun(text: ""), into: &runs)
        // Merge neighbours with the same style.
        var merged: [TextRun] = []
        for run in runs where !run.text.isEmpty {
            if var last = merged.last, sameStyle(last, run) {
                last.text += run.text
                merged[merged.count - 1] = last
            } else {
                merged.append(run)
            }
        }
        return merged
    }

    private static func sameStyle(_ a: TextRun, _ b: TextRun) -> Bool {
        a.bold == b.bold && a.italic == b.italic && a.strike == b.strike && a.code == b.code && a.link == b.link
    }

    private static func parse(_ chars: [Character], style: TextRun, into runs: inout [TextRun]) {
        var buffer = ""
        var i = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            var run = style
            run.text = buffer
            runs.append(run)
            buffer = ""
        }
        func find(_ marker: String, from start: Int) -> Int? {
            let m = Array(marker)
            var j = start
            while j + m.count <= chars.count {
                if Array(chars[j..<(j + m.count)]) == m, j > start, chars[j - 1] != " " {
                    // In "***" the closing pair is the last two.
                    var end = j
                    while m.count == 2, end + 2 < chars.count, chars[end + 2] == m[0] { end += 1 }
                    return end
                }
                j += 1
            }
            return nil
        }
        func isWordChar(_ index: Int) -> Bool {
            index >= 0 && index < chars.count && (chars[index].isLetter || chars[index].isNumber)
        }

        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil

            if c == "\\", let next, "\\`*_{}[]()#+-.!|~>".contains(next) {
                buffer.append(next)
                i += 2
                continue
            }
            if c == "`", let end = chars[(i + 1)...].firstIndex(of: "`") {
                flush()
                var run = style
                run.text = String(chars[(i + 1)..<end])
                run.code = true
                runs.append(run)
                i = end + 1
                continue
            }
            if (c == "*" || c == "_"), next == c, i + 2 < chars.count, chars[i + 2] != " ",
               let end = find(String([c, c]), from: i + 2) {
                flush()
                var inner = style
                inner.bold = true
                parse(Array(chars[(i + 2)..<end]), style: inner, into: &runs)
                i = end + 2
                continue
            }
            if c == "~", next == "~", i + 2 < chars.count, let end = find("~~", from: i + 2) {
                flush()
                var inner = style
                inner.strike = true
                parse(Array(chars[(i + 2)..<end]), style: inner, into: &runs)
                i = end + 2
                continue
            }
            if (c == "*" || c == "_"), next != nil, next != " ", !(c == "_" && isWordChar(i - 1)),
               let end = find(String(c), from: i + 1), !(c == "_" && isWordChar(end + 1)) {
                flush()
                var inner = style
                inner.italic = true
                parse(Array(chars[(i + 1)..<end]), style: inner, into: &runs)
                i = end + 1
                continue
            }
            if c == "!" && next == "[" || c == "[" {
                let open = c == "!" ? i + 1 : i
                if let close = chars[open...].firstIndex(of: "]"), close + 1 < chars.count, chars[close + 1] == "(",
                   let paren = chars[(close + 1)...].firstIndex(of: ")") {
                    flush()
                    let label = Array(chars[(open + 1)..<close])
                    let target = String(chars[(close + 2)..<paren]).split(separator: " ").first.map(String.init) ?? ""
                    var inner = style
                    if c == "[" { inner.link = target }
                    parse(label, style: inner, into: &runs)
                    i = paren + 1
                    continue
                }
            }
            buffer.append(c)
            i += 1
        }
        flush()
    }

    // MARK: Block helpers

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        return rest.isEmpty || rest.first == " " ? hashes : nil
    }

    private static func listItem(_ line: String) -> (ordered: Bool, text: String)? {
        if let range = line.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
            var text = String(line[range.upperBound...])
            for box in ["[ ] ", "[x] ", "[X] "] where text.hasPrefix(box) {
                text = (box == "[ ] " ? "☐ " : "☑ ") + text.dropFirst(4)
            }
            return (false, text)
        }
        if let range = line.range(of: #"^\d{1,9}[.)]\s+"#, options: .regularExpression) {
            return (true, String(line[range.upperBound...]))
        }
        return nil
    }

    private static func isTableDivider(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces)
            .range(of: #"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$"#, options: .regularExpression) != nil
    }

    private static func tableCells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") && !t.hasSuffix("\\|") { t.removeLast() }
        return t.replacingOccurrences(of: "\\|", with: "\u{1F}")
            .components(separatedBy: "|")
            .map { $0.replacingOccurrences(of: "\u{1F}", with: "|").trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: - Blocks → HTML

nonisolated enum HTMLWriter {
    static func html(_ blocks: [DocBlock], title: String = "") -> String {
        MarkdownConverter.htmlDocument(body: blocks.map(block).joined(separator: "\n"), title: title)
    }

    private static func block(_ block: DocBlock) -> String {
        switch block {
        case .heading(let level, let runs): "<h\(level)>\(inline(runs))</h\(level)>"
        case .paragraph(let runs): "<p>\(inline(runs))</p>"
        case .quote(let runs): "<blockquote><p>\(inline(runs))</p></blockquote>"
        case .code(let text): "<pre><code>\(MarkdownConverter.escape(text))</code></pre>"
        case .rule: "<hr>"
        case .list(let ordered, let items):
            "<\(ordered ? "ol" : "ul")>\n"
                + items.map { "<li>\(inline($0))</li>" }.joined(separator: "\n")
                + "\n</\(ordered ? "ol" : "ul")>"
        case .table(let rows):
            table(rows)
        }
    }

    private static func table(_ rows: [[[TextRun]]]) -> String {
        guard let header = rows.first else { return "<table></table>" }
        let width = rows.map(\.count).max() ?? header.count
        func cells(_ row: [[TextRun]], _ tag: String) -> String {
            (row + Array(repeating: [], count: width - row.count)).map { "<\(tag)>\(inline($0))</\(tag)>" }.joined()
        }
        return "<table>\n<tr>\(cells(header, "th"))</tr>\n"
            + rows.dropFirst().map { "<tr>\(cells($0, "td"))</tr>" }.joined(separator: "\n")
            + "\n</table>"
    }

    static func inline(_ runs: [TextRun]) -> String {
        runs.map { run in
            var s = MarkdownConverter.escape(run.text).replacingOccurrences(of: "\n", with: "<br>")
            if run.code { s = "<code>\(s)</code>" }
            if run.italic { s = "<i>\(s)</i>" }
            if run.bold { s = "<b>\(s)</b>" }
            if run.strike { s = "<s>\(s)</s>" }
            if let link = run.link { s = "<a href=\"\(MarkdownConverter.escape(link))\">\(s)</a>" }
            return s
        }.joined()
    }
}

// MARK: - Blocks → DOCX

/// Writes WordprocessingML directly, with real Word styles (Heading 1–6),
/// numbered and bulleted lists, bordered tables with a repeating header row
/// and clickable links.
nonisolated enum DocxWriter {
    static func make(_ blocks: [DocBlock], landscape: Bool = false) -> Data {
        var links: [String] = []
        var lists = 0
        var orderedLists: [Int] = []
        var body = ""

        func runs(_ runs: [TextRun], bold: Bool = false, size: Int? = nil) -> String {
            runs.map { run in
                // Word rejects run properties out of schema order.
                var props = ""
                if run.code { props += "<w:rStyle w:val=\"CodeChar\"/>" }
                else if run.link != nil { props += "<w:rStyle w:val=\"Hyperlink\"/>" }
                if run.bold || bold { props += "<w:b/>" }
                if run.italic { props += "<w:i/>" }
                if run.strike { props += "<w:strike/>" }
                if let size { props += "<w:sz w:val=\"\(size)\"/><w:szCs w:val=\"\(size)\"/>" }
                let parts = run.text.components(separatedBy: "\n").map {
                    "<w:t xml:space=\"preserve\">\(XLSX.escape($0))</w:t>"
                }
                let r = "<w:r>\(props.isEmpty ? "" : "<w:rPr>\(props)</w:rPr>")\(parts.joined(separator: "<w:br/>"))</w:r>"
                guard let link = run.link else { return r }
                links.append(link)
                return "<w:hyperlink r:id=\"rIdLink\(links.count)\">\(r)</w:hyperlink>"
            }.joined()
        }
        func paragraph(_ content: String, style: String? = nil, extra: String = "") -> String {
            let props = (style.map { "<w:pStyle w:val=\"\($0)\"/>" } ?? "") + extra
            return "<w:p>\(props.isEmpty ? "" : "<w:pPr>\(props)</w:pPr>")\(content)</w:p>"
        }

        for block in blocks {
            switch block {
            case .heading(let level, let content):
                // Direct formatting too, for readers that ignore styles.
                let level = min(level, 6)
                body += paragraph(runs(content, bold: true, size: headingSizes[level - 1]), style: "Heading\(level)")
            case .paragraph(let content):
                body += paragraph(runs(content))
            case .quote(let content):
                body += paragraph(runs(content), style: "Quote")
            case .code(let text):
                for line in text.components(separatedBy: "\n") {
                    body += paragraph(runs([TextRun(text: line)]), style: "CodeBlock")
                }
            case .rule:
                body += paragraph("", extra: "<w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"999999\"/></w:pBdr>")
            case .list(let ordered, let items):
                lists += 1
                if ordered { orderedLists.append(lists) }
                for item in items {
                    body += paragraph(runs(item), style: "ListParagraph",
                                      extra: "<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"\(lists)\"/></w:numPr>")
                }
            case .table(let rows):
                let width = rows.map(\.count).max() ?? 0
                guard width > 0 else { continue }
                body += "<w:tbl><w:tblPr><w:tblStyle w:val=\"TableGrid\"/><w:tblW w:w=\"5000\" w:type=\"pct\"/>"
                    + "<w:tblLook w:val=\"04A0\" w:firstRow=\"1\" w:lastRow=\"0\" w:firstColumn=\"0\" w:lastColumn=\"0\" w:noHBand=\"0\" w:noVBand=\"1\"/>"
                    + "</w:tblPr><w:tblGrid>"
                    + String(repeating: "<w:gridCol/>", count: width) + "</w:tblGrid>"
                for (index, row) in rows.enumerated() {
                    let isHeader = index == 0 && rows.count > 1
                    body += "<w:tr>" + (isHeader ? "<w:trPr><w:tblHeader/></w:trPr>" : "")
                    for cell in row + Array(repeating: [], count: width - row.count) {
                        let shade = isHeader ? "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"EDEDED\"/>" : ""
                        body += "<w:tc><w:tcPr><w:tcW w:w=\"0\" w:type=\"auto\"/>\(shade)</w:tcPr>"
                            + paragraph(runs(cell, bold: isHeader), extra: "<w:spacing w:after=\"0\"/>")
                            + "</w:tc>"
                    }
                    body += "</w:tr>"
                }
                // Word needs a paragraph between neighbouring tables.
                body += "</w:tbl>" + paragraph("")
            }
        }

        // A4, 2 cm margins.
        let (w, h) = landscape ? (16838, 11906) : (11906, 16838)
        let section = "<w:sectPr><w:pgSz w:w=\"\(w)\" w:h=\"\(h)\"\(landscape ? " w:orient=\"landscape\"" : "")/>"
            + "<w:pgMar w:top=\"1134\" w:right=\"1134\" w:bottom=\"1134\" w:left=\"1134\" w:header=\"709\" w:footer=\"709\" w:gutter=\"0\"/></w:sectPr>"

        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
        <w:body>\(body)\(section)</w:body></w:document>
        """

        let linkRels = links.enumerated().map { index, url in
            "<Relationship Id=\"rIdLink\(index + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(XLSX.escape(url))\" TargetMode=\"External\"/>"
        }.joined()

        let numbering = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
        <w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="singleLevel"/>\
        <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/><w:lvlJc w:val="left"/>\
        <w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl></w:abstractNum>\
        <w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="singleLevel"/>\
        <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/><w:lvlJc w:val="left"/>\
        <w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl></w:abstractNum>\
        \((0..<max(lists, 1)).map { n in
            let ordered = orderedLists.contains(n + 1)
            return "<w:num w:numId=\"\(n + 1)\"><w:abstractNumId w:val=\"\(ordered ? 1 : 0)\"/>"
                + (ordered ? "<w:lvlOverride w:ilvl=\"0\"><w:startOverride w:val=\"1\"/></w:lvlOverride>" : "")
                + "</w:num>"
        }.joined())\
        </w:numbering>
        """

        let files: [(String, String)] = [
            ("[Content_Types].xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
            <Default Extension="xml" ContentType="application/xml"/>\
            <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
            <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>\
            <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>\
            </Types>
            """),
            ("_rels/.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
            </Relationships>
            """),
            ("word/_rels/document.xml.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
            <Relationship Id="rIdNumbering" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>\
            \(linkRels)</Relationships>
            """),
            ("word/document.xml", document),
            ("word/styles.xml", styles),
            ("word/numbering.xml", numbering),
        ]
        return ZipArchive.make(files.map { (path: $0.0, data: Data($0.1.utf8)) })
    }

    /// Half-points, Heading 1–6.
    private static let headingSizes = [36, 30, 26, 24, 22, 22]

    private static func heading(_ level: Int, size: Int) -> String {
        "<w:style w:type=\"paragraph\" w:styleId=\"Heading\(level)\"><w:name w:val=\"heading \(level)\"/>"
            + "<w:basedOn w:val=\"Normal\"/><w:next w:val=\"Normal\"/><w:uiPriority w:val=\"9\"/><w:qFormat/>"
            + "<w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before=\"240\" w:after=\"80\"/><w:outlineLvl w:val=\"\(level - 1)\"/></w:pPr>"
            + "<w:rPr><w:b/><w:sz w:val=\"\(size)\"/><w:szCs w:val=\"\(size)\"/></w:rPr></w:style>"
    }

    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
    <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/>\
    <w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="id-ID"/></w:rPr></w:rPrDefault>\
    <w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>\
    <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>\
    \(heading(1, size: 36))\(heading(2, size: 30))\(heading(3, size: 26))\(heading(4, size: 24))\(heading(5, size: 22))\(heading(6, size: 22))\
    <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:qFormat/>\
    <w:pPr><w:pBdr><w:left w:val="single" w:sz="12" w:space="8" w:color="BBBBBB"/></w:pBdr><w:ind w:left="567"/></w:pPr>\
    <w:rPr><w:i/><w:color w:val="555555"/></w:rPr></w:style>\
    <w:style w:type="paragraph" w:styleId="CodeBlock"><w:name w:val="Code Block"/><w:basedOn w:val="Normal"/>\
    <w:pPr><w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>\
    <w:rPr><w:rFonts w:ascii="Menlo" w:hAnsi="Menlo" w:cs="Menlo"/><w:sz w:val="19"/></w:rPr></w:style>\
    <w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/>\
    <w:pPr><w:spacing w:after="40"/><w:ind w:left="720"/><w:contextualSpacing/></w:pPr></w:style>\
    <w:style w:type="character" w:styleId="CodeChar"><w:name w:val="Code"/>\
    <w:rPr><w:rFonts w:ascii="Menlo" w:hAnsi="Menlo" w:cs="Menlo"/><w:sz w:val="19"/><w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/></w:rPr></w:style>\
    <w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/>\
    <w:rPr><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr></w:style>\
    <w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/>\
    <w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="999999"/>\
    <w:left w:val="single" w:sz="4" w:space="0" w:color="999999"/><w:bottom w:val="single" w:sz="4" w:space="0" w:color="999999"/>\
    <w:right w:val="single" w:sz="4" w:space="0" w:color="999999"/><w:insideH w:val="single" w:sz="4" w:space="0" w:color="999999"/>\
    <w:insideV w:val="single" w:sz="4" w:space="0" w:color="999999"/></w:tblBorders>\
    <w:tblCellMar><w:top w:w="40" w:type="dxa"/><w:left w:w="100" w:type="dxa"/><w:bottom w:w="40" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>\
    </w:styles>
    """
}
