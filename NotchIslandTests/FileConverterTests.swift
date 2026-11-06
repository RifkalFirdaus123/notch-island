import AppKit
import Foundation
import PDFKit
import Testing
@testable import NotchIsland

struct FileConverterTests {
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileConverterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: - Pieces

    @Test func zipRoundTrips() throws {
        let big = Data(String(repeating: "hello notch ", count: 500).utf8)
        let archive = ZipArchive.make([(path: "a.txt", data: big), (path: "dir/é.xml", data: Data("x".utf8))])
        let entries = try ZipArchive.entries(of: archive)
        #expect(entries["a.txt"] == big)
        #expect(entries["dir/é.xml"] == Data("x".utf8))
        #expect(archive.count < big.count) // deflated
    }

    @Test func crcMatchesKnownValue() {
        #expect(ZipArchive.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func csvParsesQuotesAndSemicolons() {
        #expect(CSV.parse("a,\"b, c\",\"say \"\"hi\"\"\"\r\n1,2,3\n") == [["a", "b, c", "say \"hi\""], ["1", "2", "3"]])
        #expect(CSV.parse("nama;umur\nBudi;30") == [["nama", "umur"], ["Budi", "30"]])
        #expect(CSV.parse("\"multi\nline\",x") == [["multi\nline", "x"]])
    }

    @Test func csvSerializeRoundTrips() {
        let rows: TableRows = [["a", "b,c", "q\"uote"], ["line\nbreak", "", " pad"]]
        #expect(CSV.parse(CSV.serialize(rows)) == rows)
    }

    @Test func xlsxRoundTrips() throws {
        let rows: TableRows = [["Name", "Qty", "Phone"], ["Kopi & Teh", "12.5", "0812"], ["<b>", "", "3"]]
        let read = try XLSX.read(XLSX.make(rows))
        #expect(read == rows)
    }

    @Test func columnNames() {
        #expect(XLSX.columnName(0) == "A")
        #expect(XLSX.columnName(25) == "Z")
        #expect(XLSX.columnName(26) == "AA")
        #expect(XLSX.columnIndex("AB12") == 27)
    }

    @Test func markdownToHTML() {
        let html = MarkdownConverter.html(fromMarkdown: """
        # Title
        Some **bold** and *italic* with `co*de*` and [link](https://x.com).

        - one
        - two

        | a | b |
        |---|---|
        | 1 | 2 |
        """)
        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("<b>bold</b>"))
        #expect(html.contains("<i>italic</i>"))
        #expect(html.contains("<code>co*de*</code>"))
        #expect(html.contains("<a href=\"https://x.com\">link</a>"))
        #expect(html.contains("<ul>\n<li>one</li>\n<li>two</li>\n</ul>"))
        #expect(html.contains("<th>a</th>"))
        #expect(html.contains("<td>2</td>"))
    }

    @Test func markdownTable() {
        #expect(MarkdownConverter.markdownTable([["a", "b"], ["1"]]) == "| a | b |\n| --- | --- |\n| 1 |  |\n")
    }

    @Test func pdfTextSplitsIntoColumns() {
        #expect(FileConverter.rows(fromPDFText: "Name   Qty\nKopi\t3\n\n") == [["Name", "Qty"], ["Kopi", "3"]])
    }

    @Test func offersTargetsBySource() {
        let pdf = FileConverter.targets(for: URL(fileURLWithPath: "/a.pdf"))
        #expect(pdf.contains(.docx) && pdf.contains(.xlsx) && pdf.contains(.png) && !pdf.contains(.pdf))
        #expect(!FileConverter.targets(for: URL(fileURLWithPath: "/a.md")).contains(.md))
        #expect(FileConverter.targets(for: URL(fileURLWithPath: "/a.png")).contains(.jpeg))
        #expect(!FileConverter.targets(for: URL(fileURLWithPath: "/a.jpeg")).contains(.jpeg))
        #expect(FileConverter.targets(for: URL(fileURLWithPath: "/a.zip")).isEmpty)
    }

    // MARK: - End to end

    @Test func textToPDFAndBack() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("notes.txt")
        try "Halo dari notch\n".write(to: source, atomically: true, encoding: .utf8)

        let pdfURL = try FileConverter.convert(source, to: .pdf, in: folder, options: .builtInOnly).url
        #expect(pdfURL.lastPathComponent == "notes.pdf")
        let pdf = try #require(PDFDocument(url: pdfURL))
        #expect(pdf.string?.contains("Halo dari notch") == true)

        let back = try FileConverter.convert(pdfURL, to: .txt, in: folder, options: .builtInOnly).url
        #expect(back.lastPathComponent == "notes 2.txt") // notes.txt is taken
        #expect(try String(contentsOf: back, encoding: .utf8).contains("Halo dari notch"))
    }

    @Test func markdownToDocxAndBack() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("readme.md")
        try "# Judul\n\nTeks **tebal** biasa.\n".write(to: source, atomically: true, encoding: .utf8)

        let docx = try FileConverter.convert(source, to: .docx, in: folder, options: .builtInOnly).url
        let files = try ZipArchive.entries(of: Data(contentsOf: docx))
        #expect(files["word/document.xml"] != nil)

        let md = try String(contentsOf: FileConverter.convert(docx, to: .md, in: folder, options: .builtInOnly).url, encoding: .utf8)
        #expect(md.contains("# Judul"))
        #expect(md.contains("**tebal**"))
    }

    @Test func csvToXlsxToCsv() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("data.csv")
        try "nama;jumlah\nBudi;3\n".write(to: source, atomically: true, encoding: .utf8)

        let xlsx = try FileConverter.convert(source, to: .xlsx, in: folder, options: .builtInOnly).url
        let csv = try FileConverter.convert(xlsx, to: .csv, in: folder, options: .builtInOnly).url
        #expect(try String(contentsOf: csv, encoding: .utf8) == "nama,jumlah\r\nBudi,3\r\n")
    }

    @Test func imageConversions() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = NSImage(size: NSSize(width: 40, height: 20), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let source = folder.appendingPathComponent("shot.png")
        try png.write(to: source)

        let jpeg = try FileConverter.convert(source, to: .jpeg, in: folder, options: .builtInOnly).url
        #expect(jpeg.pathExtension == "jpg")
        #expect(NSImage(contentsOf: jpeg) != nil)

        let pdfURL = try FileConverter.convert(source, to: .pdf, in: folder, options: .builtInOnly).url
        let pdf = try #require(PDFDocument(url: pdfURL))
        #expect(pdf.pageCount == 1)

        // Single page back to PNG gives one file; two pages give a folder.
        let single = try FileConverter.convert(pdfURL, to: .png, in: folder, options: .builtInOnly).url
        #expect(single.pathExtension == "png")
        pdf.insert(try #require(pdf.page(at: 0)?.copy() as? PDFPage), at: 1)
        let twoPages = folder.appendingPathComponent("two.pdf")
        #expect(pdf.write(to: twoPages))
        let pages = try FileConverter.convert(twoPages, to: .png, in: folder, options: .builtInOnly).url
        #expect(try FileManager.default.contentsOfDirectory(atPath: pages.path).sorted() == ["two-1.png", "two-2.png"])
    }

    // MARK: - Structured documents and workbooks

    @Test func inlineMarkdownRuns() {
        let runs = MarkdownParser.inline("a **b *c*** `d*e` [f](https://x.id) snake_case_name")
        #expect(runs.contains(TextRun(text: "b ", bold: true)))
        #expect(runs.contains(TextRun(text: "c", bold: true, italic: true)))
        #expect(runs.contains(TextRun(text: "d*e", code: true)))
        #expect(runs.contains(TextRun(text: "f", link: "https://x.id")))
        #expect(runs.last?.text.hasSuffix("snake_case_name") == true)
    }

    @Test func markdownBlocks() {
        let blocks = MarkdownParser.blocks("# T\n\n1. a\n2. b\n\n| x | y |\n|---|---|\n| 1 | 2 |\n\n```\ncode\n```")
        #expect(blocks.count == 4)
        #expect(blocks[0] == .heading(1, [TextRun(text: "T")]))
        #expect(blocks[1] == .list(ordered: true, items: [[TextRun(text: "a")], [TextRun(text: "b")]]))
        #expect(blocks[2].tableColumnCount == 2)
        #expect(blocks[3] == .code("code"))
    }

    @Test func docxHasRealTablesListsAndLinks() throws {
        let data = DocxWriter.make(MarkdownParser.blocks("# Judul\n\n- satu\n\n[web](https://a.b)\n\n| a | b |\n|--|--|\n| 1 | 2 |"))
        let files = try ZipArchive.entries(of: data)
        let document = String(decoding: try #require(files["word/document.xml"]), as: UTF8.self)
        #expect(document.contains("<w:pStyle w:val=\"Heading1\"/>"))
        #expect(document.contains("<w:numId w:val=\"1\"/>"))
        #expect(document.contains("<w:tbl>"))
        #expect(document.contains("<w:hyperlink r:id=\"rIdLink1\">"))
        let rels = String(decoding: try #require(files["word/_rels/document.xml.rels"]), as: UTF8.self)
        #expect(rels.contains("Target=\"https://a.b\" TargetMode=\"External\""))
        // Every part is well-formed XML.
        for (path, part) in files {
            #expect(XMLParser(data: part).parse(), "\(path)")
        }
    }

    @Test func xlsxKeepsEverySheet() throws {
        let sheets = [Sheet(name: "Jan", rows: [["a"]]), Sheet(name: "Feb/Mar", rows: [["b", "2"]]), Sheet(name: "jan", rows: [["c"]])]
        let read = try XLSX.readSheets(XLSX.make(sheets))
        #expect(read.map(\.name) == ["Jan", "FebMar", "jan (2)"])
        #expect(read.map(\.rows) == sheets.map(\.rows))
    }

    @Test func excelDatesAndNumbers() {
        #expect(XLSX.dateString(serial: 46_332, uses1904: false, timeOnly: false) == "2026-11-06")
        #expect(XLSX.dateString(serial: 46_332.5, uses1904: false, timeOnly: false) == "2026-11-06 12:00")
        #expect(XLSX.dateString(serial: 0.75, uses1904: false, timeOnly: true) == "18:00")
        #expect(XLSX.displayNumber("0.30000000000000004") == "0.3")
        #expect(XLSX.displayNumber("12.5") == "12.5")
        #expect(StylesParser.kind(formatID: 14, code: nil) == .date)
        #expect(StylesParser.kind(formatID: 164, code: "dd/mm/yyyy") == .date)
        #expect(StylesParser.kind(formatID: 165, code: "[$Rp-421]#,##0.00") == nil)
        #expect(StylesParser.kind(formatID: 166, code: "#,##0 \"hari\"") == nil)
        #expect(StylesParser.kind(formatID: 167, code: "h:mm AM/PM") == .time)
    }

    @Test func readsDatesFromAnExcelFile() throws {
        // A minimal workbook as Excel writes it: a date style and a shared string.
        let files: [(path: String, data: Data)] = [
            ("xl/workbook.xml", Data(#"<workbook xmlns:r="r"><sheets><sheet name="Data" sheetId="1" r:id="rId1"/></sheets></workbook>"#.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(#"<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>"#.utf8)),
            ("xl/sharedStrings.xml", Data(#"<sst><si><t>Tanggal</t></si></sst>"#.utf8)),
            ("xl/styles.xml", Data(#"<styleSheet><cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs></styleSheet>"#.utf8)),
            ("xl/worksheets/sheet1.xml", Data(#"<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c></row><row r="2"><c r="A2" s="1"><v>46332</v></c><c r="B2"><v>3</v></c></row></sheetData></worksheet>"#.utf8)),
        ]
        let sheets = try XLSX.readSheets(ZipArchive.make(files))
        #expect(sheets == [Sheet(name: "Data", rows: [["Tanggal", ""], ["2026-11-06", "3"]])])
    }

    @Test func spreadsheetToWordMakesARealTable() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("wide.csv")
        try "a,b,c,d,e,f,g\n1,2,3,4,5,6,7\n".write(to: source, atomically: true, encoding: .utf8)

        let docx = try FileConverter.convert(source, to: .docx, in: folder, options: .builtInOnly).url
        let document = String(decoding: try #require(ZipArchive.entries(of: Data(contentsOf: docx))["word/document.xml"]), as: UTF8.self)
        #expect(document.contains("<w:tbl>"))
        #expect(document.contains("w:orient=\"landscape\"")) // 7 columns

        let pdf = try #require(PDFDocument(url: FileConverter.convert(source, to: .pdf, in: folder, options: .builtInOnly).url))
        let page = try #require(pdf.page(at: 0))
        #expect(page.bounds(for: .mediaBox).width > page.bounds(for: .mediaBox).height)
    }

    @Test func pdfToWordWithoutEngineSaysSo() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("a.txt")
        try "Halo".write(to: source, atomically: true, encoding: .utf8)
        let pdf = try FileConverter.convert(source, to: .pdf, in: folder, options: .builtInOnly).url
        let outcome = try FileConverter.convert(pdf, to: .docx, in: folder, options: .builtInOnly)
        #expect(outcome.notice != nil)
    }
}
