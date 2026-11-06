import AppKit

/// Markdown in and out. Covers what notes and READMEs use: headings,
/// paragraphs, lists, quotes, code, rules, tables, bold, italic, code spans
/// and links.
nonisolated enum MarkdownConverter {
    // MARK: - Markdown → HTML

    static func html(fromMarkdown markdown: String) -> String {
        HTMLWriter.html(MarkdownParser.blocks(markdown))
    }

    /// Wraps body HTML with the styles every conversion uses.
    static func htmlDocument(body: String, title: String = "") -> String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(escape(title))</title>
        <style>
        body { font-family: -apple-system, "Helvetica Neue", Helvetica, sans-serif; font-size: 11pt; line-height: 1.4; }
        code, pre { font-family: Menlo, monospace; font-size: 9.5pt; }
        pre { background: #f2f2f2; padding: 8px; }
        blockquote { color: #555; margin-left: 12px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #999; padding: 3px 6px; text-align: left; vertical-align: top; }
        th { background: #eee; }
        </style></head>
        <body>
        \(body)
        </body></html>
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Rich text → Markdown

    /// Markdown from styled text. Bigger or bold short lines become headings,
    /// list markers become "-" or "1.", bold, italic and links carry over.
    static func markdown(from text: NSAttributedString) -> String {
        let string = text.string as NSString
        let base = bodyFontSize(of: text)
        var blocks: [(text: String, isList: Bool)] = []

        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length), options: .byParagraphs
        ) { _, range, _, _ in
            let raw = string.substring(with: range)
            guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
                blocks.append(("", false))
                return
            }

            let style = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            let lists = style?.textLists ?? []
            var contentRange = range
            var prefix = ""

            if let list = lists.last {
                // Imported lists carry their marker as text: "\t•\tItem".
                let pattern = #"^\t*[^\t]{0,12}\t"#
                if let marker = raw.range(of: pattern, options: .regularExpression) {
                    contentRange.location += raw.utf16.distance(from: marker.lowerBound, to: marker.upperBound)
                    contentRange.length -= raw.utf16.distance(from: marker.lowerBound, to: marker.upperBound)
                }
                let indent = String(repeating: "  ", count: lists.count - 1)
                let ordered = list.markerFormat.rawValue.contains("decimal")
                    || list.markerFormat.rawValue.contains("alpha")
                    || list.markerFormat.rawValue.contains("roman")
                prefix = indent + (ordered ? "1. " : "- ")
            } else if let level = headingLevel(text, range: range, base: base) {
                prefix = String(repeating: "#", count: level) + " "
                let plain = string.substring(with: range).trimmingCharacters(in: .whitespaces)
                blocks.append((prefix + plain, false))
                return
            }

            blocks.append((prefix + inlineMarkdown(text, range: contentRange), !prefix.isEmpty))
        }

        // Blank line between blocks, single newline inside a list.
        var out = ""
        var previous: (text: String, isList: Bool)?
        for block in blocks {
            if block.text.isEmpty { previous = nil; continue }
            if let previous {
                out += previous.isList && block.isList ? "\n" : "\n\n"
            } else if !out.isEmpty {
                out += "\n\n"
            }
            out += block.text
            previous = block
        }
        return out + "\n"
    }

    /// Markdown from page text, where every line ends with a hard break.
    /// Lines run on into one paragraph; headings still stand alone.
    static func markdown(fromPDFText text: NSAttributedString) -> String {
        let md = markdown(from: text)
        var out: [String] = []
        for block in md.components(separatedBy: "\n\n") {
            if block.hasPrefix("#") || block.hasPrefix("- ") || block.hasPrefix("1. ") {
                out.append(block)
            } else if let last = out.last, !last.hasPrefix("#"), !last.hasPrefix("- "), !last.hasPrefix("1. "),
                      !last.hasSuffix(".") && !last.hasSuffix(":") {
                out[out.count - 1] = last + "\n" + block
            } else {
                out.append(block)
            }
        }
        return out.joined(separator: "\n\n")
    }

    static func markdownTable(_ rows: TableRows) -> String {
        guard let header = rows.first, !header.isEmpty else { return "" }
        let width = rows.map(\.count).max() ?? header.count
        func line(_ row: [String]) -> String {
            let cells = (row + Array(repeating: "", count: width - row.count)).map {
                $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: "<br>")
            }
            return "| " + cells.joined(separator: " | ") + " |"
        }
        let divider = "|" + Array(repeating: " --- |", count: width).joined()
        return ([line(header), divider] + rows.dropFirst().map(line)).joined(separator: "\n") + "\n"
    }

    private static func bodyFontSize(of text: NSAttributedString) -> CGFloat {
        // The size used by the most characters.
        var counts: [CGFloat: Int] = [:]
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            let size = (value as? NSFont)?.pointSize ?? 12
            counts[size.rounded(), default: 0] += range.length
        }
        return counts.max { $0.value < $1.value }?.key ?? 12
    }

    private static func headingLevel(_ text: NSAttributedString, range: NSRange, base: CGFloat) -> Int? {
        guard range.length <= 120 else { return nil }
        var largest: CGFloat = 0
        var allBold = true
        text.enumerateAttribute(.font, in: range) { value, sub, _ in
            let font = value as? NSFont
            largest = max(largest, font?.pointSize ?? base)
            let isWhitespace = (text.string as NSString).substring(with: sub)
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !isWhitespace, font?.fontDescriptor.symbolicTraits.contains(.bold) != true { allBold = false }
        }
        let ratio = largest / max(base, 1)
        if ratio >= 1.7 { return 1 }
        if ratio >= 1.35 { return 2 }
        if ratio >= 1.12 { return 3 }
        // A short bold line on its own reads as a heading too.
        if allBold, range.length <= 80, !(text.string as NSString).substring(with: range).hasSuffix(".") {
            return 3
        }
        return nil
    }

    private static func inlineMarkdown(_ text: NSAttributedString, range: NSRange) -> String {
        var out = ""
        text.enumerateAttributes(in: range) { attributes, sub, _ in
            var piece = (text.string as NSString).substring(with: sub)
                .replacingOccurrences(of: "\u{2028}", with: "  \n")
            let core = piece.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else { out += piece; return }

            let traits = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            var styled = core
            if traits.contains(.monoSpace) {
                styled = "`\(styled)`"
            } else {
                if traits.contains(.italic) { styled = "*\(styled)*" }
                if traits.contains(.bold) { styled = "**\(styled)**" }
            }
            if let link = attributes[.link] {
                let url = (link as? URL)?.absoluteString ?? (link as? String) ?? ""
                if !url.isEmpty { styled = "[\(styled)](\(url))" }
            }
            let leading = piece.prefix { $0 == " " }
            let trailing = String(piece.reversed().prefix { $0 == " " })
            piece = leading + styled + trailing
            out += piece
        }
        // "**a** **b**" → "**a b**" reads better and round-trips.
        return out.replacingOccurrences(of: "** **", with: " ")
    }
}
