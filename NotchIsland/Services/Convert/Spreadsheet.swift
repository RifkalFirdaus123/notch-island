import Foundation

/// A table of text cells, the common ground for CSV, XLSX and tables pulled
/// out of PDFs.
typealias TableRows = [[String]]

// MARK: - CSV

nonisolated enum CSV {
    /// Parses RFC 4180 CSV. The delimiter (comma, semicolon or tab) is
    /// guessed from the first line, since spreadsheets set to Indonesian or
    /// European locales export with semicolons.
    static func parse(_ text: String, delimiter: Character? = nil) -> TableRows {
        var text = text
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let separator = delimiter ?? detectDelimiter(text)

        var rows: TableRows = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        func endRow() {
            row.append(field)
            field = ""
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    let next = iterator.next()
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        pending = next
                    }
                } else {
                    field.append(char)
                }
            } else if char == "\"" && field.isEmpty {
                inQuotes = true
            } else if char == separator {
                row.append(field)
                field = ""
            } else if char == "\n" || char == "\r\n" || char == "\r" {
                endRow()
            } else {
                field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    static func serialize(_ rows: TableRows, delimiter: Character = ",") -> String {
        rows.map { row in
            row.map { field in
                let needsQuotes = field.contains(delimiter) || field.contains("\"")
                    || field.contains("\n") || field.contains("\r")
                    || field.first == " " || field.last == " "
                guard needsQuotes else { return field }
                return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            .joined(separator: String(delimiter))
        }
        .joined(separator: "\r\n") + "\r\n"
    }

    private static func detectDelimiter(_ text: String) -> Character {
        var counts: [Character: Int] = [",": 0, ";": 0, "\t": 0]
        var inQuotes = false
        for char in text {
            if char == "\"" { inQuotes.toggle() }
            if char.isNewline && !inQuotes { break }
            if !inQuotes, counts[char] != nil { counts[char, default: 0] += 1 }
        }
        // max(by:) keeps the first of equal counts, so ties favor the comma.
        let candidates: [Character] = [",", ";", "\t"]
        let best = candidates.max { counts[$0, default: 0] < counts[$1, default: 0] } ?? ","
        return counts[best, default: 0] > 0 ? best : ","
    }
}

// MARK: - XLSX

/// One worksheet.
nonisolated struct Sheet: Equatable, Sendable {
    var name: String
    var rows: TableRows
}

nonisolated enum XLSX {
    enum XLSXError: Error {
        case noWorksheet
    }

    static func make(_ rows: TableRows, sheetName: String = "Sheet1") -> Data {
        make([Sheet(name: sheetName, rows: rows)])
    }

    /// A workbook with one sheet per entry. Cells that look like plain
    /// numbers are stored as numbers so they can be summed; everything else
    /// (including numbers with leading zeros, like phone numbers) stays text.
    static func make(_ sheets: [Sheet]) -> Data {
        let sheets = sheets.isEmpty ? [Sheet(name: "Sheet1", rows: [])] : sheets
        let names = uniqueSheetNames(sheets.map(\.name))

        var files: [(String, String)] = [
            ("[Content_Types].xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
            <Default Extension="xml" ContentType="application/xml"/>\
            <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
            \(sheets.indices.map { "<Override PartName=\"/xl/worksheets/sheet\($0 + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" }.joined())\
            <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\
            </Types>
            """),
            ("_rels/.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
            </Relationships>
            """),
            ("xl/workbook.xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\
            \(names.enumerated().map { "<sheet name=\"\(escape($1))\" sheetId=\"\($0 + 1)\" r:id=\"rId\($0 + 1)\"/>" }.joined())\
            </sheets></workbook>
            """),
            ("xl/_rels/workbook.xml.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            \(sheets.indices.map { "<Relationship Id=\"rId\($0 + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0 + 1).xml\"/>" }.joined())\
            <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
            </Relationships>
            """),
            // Style 1: bold header row.
            ("xl/styles.xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
            <fonts count="2"><font><sz val="12"/><name val="Calibri"/></font><font><b/><sz val="12"/><name val="Calibri"/></font></fonts>\
            <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>\
            <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
            <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
            <cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>\
            <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>\
            <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>\
            </styleSheet>
            """),
        ]
        for (index, sheet) in sheets.enumerated() {
            files.append(("xl/worksheets/sheet\(index + 1).xml", worksheet(sheet.rows)))
        }
        return ZipArchive.make(files.map { (path: $0.0, data: Data($0.1.utf8)) })
    }

    private static func worksheet(_ rows: TableRows) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        """
        // Columns sized to their longest value (within reason).
        let width = rows.map(\.count).max() ?? 0
        if width > 0 {
            xml += "<cols>"
            for c in 0..<width {
                let longest = rows.prefix(500).map { $0.count > c ? $0[c].count : 0 }.max() ?? 0
                xml += "<col min=\"\(c + 1)\" max=\"\(c + 1)\" width=\"\(min(60, max(8, longest + 2)))\" customWidth=\"1\"/>"
            }
            xml += "</cols>"
        }
        xml += "<sheetData>"
        let boldHeader = rows.count > 1
        for (r, row) in rows.enumerated() {
            xml += "<row r=\"\(r + 1)\">"
            for (c, value) in row.enumerated() where !value.isEmpty {
                let ref = columnName(c) + String(r + 1)
                let style = r == 0 && boldHeader ? " s=\"1\"" : ""
                if isNumber(value) {
                    xml += "<c r=\"\(ref)\"\(style)><v>\(value)</v></c>"
                } else {
                    xml += "<c r=\"\(ref)\"\(style) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(value))</t></is></c>"
                }
            }
            xml += "</row>"
        }
        return xml + "</sheetData></worksheet>"
    }

    /// Excel's rules: 1–31 characters, no []:*?/\, unique ignoring case.
    private static func uniqueSheetNames(_ names: [String]) -> [String] {
        var used: Set<String> = []
        return names.enumerated().map { index, raw in
            var base = String(raw.filter { !"[]:*?/\\".contains($0) }.prefix(31))
                .trimmingCharacters(in: CharacterSet(charactersIn: "' "))
            if base.isEmpty { base = "Sheet\(index + 1)" }
            var name = base
            var counter = 2
            while used.contains(name.lowercased()) {
                let suffix = " (\(counter))"
                name = String(base.prefix(31 - suffix.count)) + suffix
                counter += 1
            }
            used.insert(name.lowercased())
            return name
        }
    }

    // MARK: Reading

    /// The first worksheet's cells as text.
    static func read(_ data: Data) throws -> TableRows {
        guard let first = try readSheets(data).first else { throw XLSXError.noWorksheet }
        return first.rows
    }

    /// Every worksheet in workbook order. Dates and times come out as
    /// "2026-11-06" / "2026-11-06 14:30"; formulas as their last result.
    static func readSheets(_ data: Data) throws -> [Sheet] {
        let files = try ZipArchive.entries(of: data)
        let shared = files["xl/sharedStrings.xml"].map(SharedStringsParser.parse) ?? []
        let dateStyles = files["xl/styles.xml"].map(StylesParser.dateStyles) ?? [:]
        let workbook = files["xl/workbook.xml"].map(WorkbookParser.parse) ?? WorkbookParser.Result()
        let rels = files["xl/_rels/workbook.xml.rels"].map(RelationshipsParser.parse) ?? [:]
        let context = SheetParser.Context(sharedStrings: shared, dateStyles: dateStyles, uses1904: workbook.uses1904)

        var sheets: [Sheet] = []
        for entry in workbook.sheets {
            guard let target = rels[entry.relationship] else { continue }
            let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            guard let xml = files[path] else { continue }
            sheets.append(Sheet(name: entry.name, rows: SheetParser.parse(xml, context: context)))
        }
        if sheets.isEmpty, let xml = files["xl/worksheets/sheet1.xml"] {
            sheets.append(Sheet(name: "Sheet1", rows: SheetParser.parse(xml, context: context)))
        }
        guard !sheets.isEmpty else { throw XLSXError.noWorksheet }
        return sheets
    }

    // MARK: Helpers

    static func columnName(_ index: Int) -> String {
        var name = ""
        var n = index + 1
        while n > 0 {
            let r = (n - 1) % 26
            name = String(UnicodeScalar(UInt8(65 + r))) + name
            n = (n - 1) / 26
        }
        return name
    }

    /// Zero-based column index from a cell reference like "AB12".
    static func columnIndex(_ ref: String) -> Int? {
        let letters = ref.prefix { $0.isLetter }.uppercased()
        guard !letters.isEmpty else { return nil }
        return letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }

    private static func isNumber(_ value: String) -> Bool {
        value.range(of: #"^-?(0|[1-9][0-9]{0,14})(\.[0-9]+)?$"#, options: .regularExpression) != nil
    }

    /// Excel stores 0.1 + 0.2 as "0.30000000000000004"; show it as Excel does.
    static func displayNumber(_ raw: String) -> String {
        guard raw.count > 15, let value = Double(raw), value.isFinite else { return raw }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesSignificantDigits = true
        formatter.maximumSignificantDigits = 15
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? raw
    }

    /// A day serial number as an ISO date, with the time when there is one.
    static func dateString(serial: Double, uses1904: Bool, timeOnly: Bool) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let epoch = uses1904
            ? DateComponents(calendar: calendar, year: 1904, month: 1, day: 1).date!
            : DateComponents(calendar: calendar, year: 1899, month: 12, day: 30).date!
        let seconds = (serial * 86_400).rounded()
        let date = epoch.addingTimeInterval(seconds)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let hasTime = seconds.truncatingRemainder(dividingBy: 86_400) != 0
        if timeOnly && serial < 1 {
            formatter.dateFormat = seconds.truncatingRemainder(dividingBy: 60) == 0 ? "HH:mm" : "HH:mm:ss"
        } else {
            formatter.dateFormat = hasTime ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        }
        return formatter.string(from: date)
    }

    static func escape(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            // XML 1.0 forbids most control characters.
            case "\t", "\n", "\r": out.unicodeScalars.append(scalar)
            case _ where scalar.value < 0x20: continue
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}

// MARK: - XML parsers

nonisolated private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var inText = false
    /// Phonetic hints (<rPh>) carry their own <t>, which isn't cell text.
    private var phoneticDepth = 0

    static func parse(_ data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "si": current = ""
        case "rPh": phoneticDepth += 1
        case "t": inText = phoneticDepth == 0
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "si": strings.append(current)
        case "rPh": phoneticDepth -= 1
        case "t": inText = false
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }
}

/// Which cell styles (indexes into <cellXfs>) show numbers as dates or times.
nonisolated final class StylesParser: NSObject, XMLParserDelegate {
    enum Kind: Sendable { case date, time }

    private var customFormats: [Int: String] = [:]
    private var cellFormats: [Int] = []
    private var inCellXfs = false

    static func dateStyles(_ data: Data) -> [Int: Kind] {
        let delegate = StylesParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        var result: [Int: Kind] = [:]
        for (index, id) in delegate.cellFormats.enumerated() {
            if let kind = kind(formatID: id, code: delegate.customFormats[id]) { result[index] = kind }
        }
        return result
    }

    /// Built-in date formats are 14–22 and 45–47; custom ones are judged by
    /// their date and time letters outside quotes and brackets.
    static func kind(formatID: Int, code: String?) -> Kind? {
        switch formatID {
        case 14...17, 22: return .date
        case 18...21, 45...47: return .time
        default: break
        }
        guard let code else { return nil }
        let bare = code
            .replacingOccurrences(of: #""[^"]*""#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\\."#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .lowercased()
        if bare.contains("y") || bare.contains("d") { return .date }
        if bare.contains("h") || bare.contains("s") { return .time }
        return bare.contains("m") ? .date : nil
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "numFmt":
            if let id = attributes["numFmtId"].flatMap(Int.init), let code = attributes["formatCode"] {
                customFormats[id] = code
            }
        case "cellXfs": inCellXfs = true
        case "xf" where inCellXfs: cellFormats.append(attributes["numFmtId"].flatMap(Int.init) ?? 0)
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "cellXfs" { inCellXfs = false }
    }
}

nonisolated private final class SheetParser: NSObject, XMLParserDelegate {
    struct Context {
        var sharedStrings: [String]
        var dateStyles: [Int: StylesParser.Kind]
        var uses1904: Bool
    }

    private let context: Context
    private var cells: [Int: [Int: String]] = [:]
    private var rowIndex = -1
    private var nextColumn = 0
    private var cellColumn = 0
    private var cellType = ""
    private var cellStyle = 0
    private var value = ""
    private var capturing = false

    init(context: Context) {
        self.context = context
    }

    static func parse(_ data: Data, context: Context) -> TableRows {
        let delegate = SheetParser(context: context)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.rows
    }

    private var rows: TableRows {
        guard let lastRow = cells.keys.max() else { return [] }
        let width = (cells.values.compactMap { $0.keys.max() }.max() ?? -1) + 1
        return (0...lastRow).map { r in
            (0..<width).map { c in cells[r]?[c] ?? "" }
        }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "row":
            rowIndex = attributes["r"].flatMap(Int.init).map { $0 - 1 } ?? rowIndex + 1
            nextColumn = 0
        case "c":
            cellColumn = attributes["r"].flatMap(XLSX.columnIndex) ?? nextColumn
            nextColumn = cellColumn + 1
            cellType = attributes["t"] ?? "n"
            cellStyle = attributes["s"].flatMap(Int.init) ?? 0
            value = ""
        case "v", "t":
            capturing = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "v", "t":
            capturing = false
        case "c":
            let text: String
            switch cellType {
            case "s":
                text = Int(value).flatMap { context.sharedStrings.indices.contains($0) ? context.sharedStrings[$0] : nil } ?? ""
            case "b":
                text = value == "1" ? "TRUE" : "FALSE"
            case "n":
                if let kind = context.dateStyles[cellStyle], let serial = Double(value) {
                    text = XLSX.dateString(serial: serial, uses1904: context.uses1904, timeOnly: kind == .time)
                } else {
                    text = XLSX.displayNumber(value)
                }
            default:
                text = value
            }
            if !text.isEmpty { cells[max(rowIndex, 0), default: [:]][cellColumn] = text }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing { value += string }
    }
}

/// Sheet names and their relationship ids, in workbook order.
nonisolated private final class WorkbookParser: NSObject, XMLParserDelegate {
    struct Result {
        var sheets: [(name: String, relationship: String)] = []
        var uses1904 = false
    }

    private var result = Result()

    static func parse(_ data: Data) -> Result {
        let delegate = WorkbookParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.result
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "workbookPr":
            result.uses1904 = ["1", "true"].contains(attributes["date1904"] ?? "")
        case "sheet":
            if let id = attributes["r:id"] {
                result.sheets.append((attributes["name"] ?? "Sheet\(result.sheets.count + 1)", id))
            }
        default:
            break
        }
    }
}

nonisolated private final class RelationshipsParser: NSObject, XMLParserDelegate {
    private var targets: [String: String] = [:]

    static func parse(_ data: Data) -> [String: String] {
        let delegate = RelationshipsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.targets
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "Relationship", let id = attributes["Id"], let target = attributes["Target"] {
            targets[id] = target
        }
    }
}
