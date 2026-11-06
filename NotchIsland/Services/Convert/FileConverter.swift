import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

enum ConversionError: LocalizedError {
    case unsupported
    case unreadable
    case noText
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .unsupported: String(localized: "This file can't be converted to that format.")
        case .unreadable: String(localized: "The file couldn't be read.")
        case .noText: String(localized: "No text was found in the file.")
        case .writeFailed: String(localized: "The converted file couldn't be saved.")
        }
    }
}

/// The converted file, plus a note when the result is only an
/// approximation (for example because an engine isn't installed).
nonisolated struct ConversionOutcome: Sendable {
    var url: URL
    var notice: String?
}

/// Which outside engines a conversion may use (tests turn them off).
nonisolated struct ConversionOptions: Sendable {
    var useWord = true
    var usePDFEngine = true

    static let builtInOnly = ConversionOptions(useWord: false, usePDFEngine: false)
}

/// Converts files between document, spreadsheet and image formats. System
/// frameworks do most of the work; Microsoft Word (Word → PDF) and the
/// optional PDF engine (PDF → Word / Excel) are used when available.
/// Runs synchronously; call it off the main thread.
nonisolated enum FileConverter {
    static func targets(for url: URL) -> [FileFormat] {
        guard let kind = SourceKind(url: url) else { return [] }
        let own = kind.ownFormat(url)
        return kind.targets.filter { $0 != own && (!$0.isImage || canWrite($0)) }
    }

    /// Menu label for a target; reading text out of an image says it uses OCR.
    static func title(of format: FileFormat, from source: URL?) -> String {
        if format == .txt, let source, SourceKind(url: source) == .image {
            return String(localized: "Text from Image (OCR)")
        }
        return format.title
    }

    /// Writes the converted file into `directory`. A PDF with several pages
    /// converted to images, or a workbook with several sheets converted to
    /// CSV, gives a folder.
    static func convert(
        _ source: URL, to target: FileFormat, in directory: URL, options: ConversionOptions = ConversionOptions()
    ) throws -> ConversionOutcome {
        guard let kind = SourceKind(url: source), targets(for: source).contains(target) else {
            throw ConversionError.unsupported
        }
        let baseName = source.deletingPathExtension().lastPathComponent

        switch kind {
        case .pdf:
            return try convertPDF(source, to: target, baseName: baseName, in: directory, options: options)
        case .image:
            return ConversionOutcome(url: try convertImage(source, to: target, baseName: baseName, in: directory))
        case .csv:
            let rows = CSV.parse(try readText(source), delimiter: source.pathExtension.lowercased() == "tsv" ? "\t" : nil)
            return ConversionOutcome(url: try writeSheets([Sheet(name: baseName, rows: rows)], to: target, baseName: baseName, in: directory))
        case .xlsx:
            let sheets = try readWorkbook(source)
            return ConversionOutcome(url: try writeSheets(sheets, to: target, baseName: baseName, in: directory))
        case .document(let ext):
            return try convertDocument(source, ext: ext, to: target, baseName: baseName, in: directory, options: options)
        }
    }

    // MARK: - Documents

    private static func convertDocument(
        _ source: URL, ext: String, to target: FileFormat, baseName: String, in directory: URL, options: ConversionOptions
    ) throws -> ConversionOutcome {
        let isWordFile = ["docx", "doc", "odt", "rtf", "rtfd"].contains(ext)

        // Word lays the document out exactly as it shows it.
        if target == .pdf, isWordFile {
            var notice = String(localized: "Made without Microsoft Word, so the layout may differ from the original.")
            if options.useWord, ConversionEngines.isWordInstalled {
                let url = uniqueURL(baseName, "pdf", in: directory)
                do {
                    try ConversionEngines.wordToPDF(source, output: url)
                    return ConversionOutcome(url: url)
                } catch {
                    NSLog("NotchIsland: Word conversion failed: \(error)")
                    notice = error.localizedDescription + " " + String(localized: "Used the built-in converter instead.")
                }
            }
            let text = try readDocument(source, ext: ext)
            return ConversionOutcome(url: try writeDocument(text, to: .pdf, baseName: baseName, in: directory), notice: notice)
        }

        // Markdown and plain text have a structure we can write as real
        // Word headings, lists and tables.
        if target == .docx || target == .html, ["md", "markdown", "txt", "text"].contains(ext) {
            let text = try readText(source)
            let blocks = ext.hasPrefix("t") ? MarkdownParser.blocks(plainText: text) : MarkdownParser.blocks(text)
            let landscape = blocks.contains { $0.tableColumnCount > 6 }
            let data = target == .docx
                ? DocxWriter.make(blocks, landscape: landscape)
                : Data(HTMLWriter.html(blocks, title: baseName).utf8)
            return ConversionOutcome(url: try write(data, baseName, target, in: directory))
        }

        let text = try readDocument(source, ext: ext)
        return ConversionOutcome(url: try writeDocument(text, to: target, baseName: baseName, in: directory))
    }

    // MARK: - PDF

    private static func convertPDF(
        _ source: URL, to target: FileFormat, baseName: String, in directory: URL, options: ConversionOptions
    ) throws -> ConversionOutcome {
        guard let pdf = PDFDocument(url: source) else { throw ConversionError.unreadable }
        guard !pdf.isLocked else { throw ConversionError.unreadable }

        if target.isImage {
            let pages = (0..<pdf.pageCount).compactMap { pdf.page(at: $0) }
            guard !pages.isEmpty else { throw ConversionError.unreadable }
            if pages.count == 1, let image = render(pages[0]) {
                let url = uniqueURL(baseName, target.fileExtension, in: directory)
                try writeImage(image, to: url, format: target)
                return ConversionOutcome(url: url)
            }
            let folder = uniqueURL("\(baseName) (\(target.title))", nil, in: directory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let digits = String(pages.count).count
            for (index, page) in pages.enumerated() {
                guard let image = render(page) else { continue }
                let number = String(repeating: "0", count: digits - String(index + 1).count) + String(index + 1)
                try writeImage(image, to: folder.appendingPathComponent("\(baseName)-\(number).\(target.fileExtension)"), format: target)
            }
            return ConversionOutcome(url: folder)
        }

        let engine = options.usePDFEngine && ConversionEngines.isPDFEngineInstalled
        let installHint = String(localized: "Install the PDF engine in Settings › File Conversion for better results.")

        // pdf2docx rebuilds paragraphs, tables and images in place.
        if target == .docx, engine {
            let url = uniqueURL(baseName, "docx", in: directory)
            do {
                try ConversionEngines.pdfToDocx(source, output: url)
                return ConversionOutcome(url: url)
            } catch {
                try? FileManager.default.removeItem(at: url)
                NSLog("NotchIsland: pdf2docx failed: \(error)")
            }
        }

        // pdfplumber finds tables by their lines or column alignment.
        if target == .xlsx || target == .csv, engine {
            do {
                let tables = try ConversionEngines.pdfTables(source)
                if !tables.isEmpty {
                    var perPage: [Int: Int] = [:]
                    let sheets = tables.map { table -> Sheet in
                        perPage[table.page, default: 0] += 1
                        let n = perPage[table.page]!
                        let name = String(localized: "Page \(table.page)") + (n > 1 ? " (\(n))" : "")
                        return Sheet(name: name, rows: table.rows)
                    }
                    if target == .xlsx {
                        return ConversionOutcome(url: try write(XLSX.make(sheets), baseName, .xlsx, in: directory))
                    }
                    // One CSV, tables separated by an empty row.
                    let rows = sheets.enumerated().flatMap { index, sheet in (index > 0 ? [[""]] : []) + sheet.rows }
                    return ConversionOutcome(url: try write(Data(CSV.serialize(rows).utf8), baseName, .csv, in: directory))
                }
            } catch {
                NSLog("NotchIsland: pdfplumber failed: \(error)")
            }
        }

        let text = pdfText(pdf)
        guard !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConversionError.noText
        }

        switch target {
        case .csv, .xlsx:
            let notice = engine
                ? String(localized: "No tables were found, so each line became a row.")
                : String(localized: "Columns were guessed from spacing.") + " " + installHint
            let rows = rows(fromPDFText: text.string)
            return ConversionOutcome(
                url: try writeSheets([Sheet(name: baseName, rows: rows)], to: target, baseName: baseName, in: directory),
                notice: notice
            )
        case .md:
            return ConversionOutcome(url: try write(Data(MarkdownConverter.markdown(fromPDFText: text).utf8), baseName, .md, in: directory))
        case .docx:
            let notice = String(localized: "Only the text was kept.") + " " + installHint
            return ConversionOutcome(url: try writeDocument(text, to: target, baseName: baseName, in: directory), notice: notice)
        default:
            return ConversionOutcome(url: try writeDocument(text, to: target, baseName: baseName, in: directory))
        }
    }

    /// Every page's styled text; pages without text (scans) are read with OCR.
    static func pdfText(_ pdf: PDFDocument) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            var pageText = page.attributedString ?? NSAttributedString()
            if pageText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let image = render(page), let recognized = try? recognizeText(in: image), !recognized.isEmpty {
                pageText = plainAttributed(recognized)
            }
            if result.length > 0 { result.append(NSAttributedString(string: "\n\n")) }
            result.append(pageText)
        }
        return result
    }

    /// Splits each line into cells at tabs or runs of two or more spaces,
    /// which is how text extraction lays out table columns.
    static func rows(fromPDFText text: String) -> TableRows {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                line.replacingOccurrences(of: #"\t+| {2,}"#, with: "\u{1F}", options: .regularExpression)
                    .components(separatedBy: "\u{1F}")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            }
    }

    /// Draws a page at 2× (144 dpi) on white.
    static func render(_ page: PDFPage, scale: CGFloat = 2) -> CGImage? {
        guard let cgPage = page.pageRef else { return nil }
        let box = cgPage.getBoxRect(.cropBox)
        let rotated = cgPage.rotationAngle % 180 != 0
        let size = rotated ? CGSize(width: box.height, height: box.width) : box.size
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.concatenate(cgPage.getDrawingTransform(
            .cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true
        ))
        context.drawPDFPage(cgPage)
        return context.makeImage()
    }

    // MARK: - Images

    private static func convertImage(_ source: URL, to target: FileFormat, baseName: String, in directory: URL) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0 else { throw ConversionError.unreadable }
        // Animated GIFs and multi-page TIFFs: every frame becomes a PDF page.
        let frameCount = target == .pdf ? CGImageSourceGetCount(imageSource) : 1
        let frames = (0..<frameCount).compactMap { orientedImage(imageSource, at: $0) }
        guard let first = frames.first else { throw ConversionError.unreadable }

        switch target {
        case .txt:
            let text = try recognizeText(in: first)
            guard !text.isEmpty else { throw ConversionError.noText }
            return try write(Data(text.utf8), baseName, .txt, in: directory)
        case .pdf:
            let data = NSMutableData()
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw ConversionError.writeFailed }
            for frame in frames {
                // 144 dpi: a 2× screenshot prints at its on-screen size.
                var box = CGRect(x: 0, y: 0, width: CGFloat(frame.width) / 2, height: CGFloat(frame.height) / 2)
                context.beginPage(mediaBox: &box)
                context.draw(frame, in: box)
                context.endPage()
            }
            context.closePDF()
            return try write(data as Data, baseName, .pdf, in: directory)
        default:
            let url = uniqueURL(baseName, target.fileExtension, in: directory)
            try writeImage(first, to: url, format: target)
            return url
        }
    }

    /// The frame with its EXIF rotation applied, at full size.
    private static func orientedImage(_ source: CGImageSource, at index: Int) -> CGImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0 else { return CGImageSourceCreateImageAtIndex(source, index, nil) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, index, nil)
    }

    static func canWrite(_ format: FileFormat) -> Bool {
        let types = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return types.contains(format.utType.identifier)
    }

    private static func writeImage(_ image: CGImage, to url: URL, format: FileFormat) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, format.utType.identifier as CFString, 1, nil
        ) else { throw ConversionError.writeFailed }
        // JPEG has no transparency; put see-through areas on white, not black.
        let output = format == .jpeg ? flattened(image) ?? image : image
        let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        CGImageDestinationAddImage(destination, output, options)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.writeFailed }
    }

    private static func flattened(_ image: CGImage) -> CGImage? {
        guard image.alphaInfo != .none, image.alphaInfo != .noneSkipLast, image.alphaInfo != .noneSkipFirst,
              let context = CGContext(
                  data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(.white)
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// Text in an image, in reading order, with the language detected.
    static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    // MARK: - Documents

    private static func readDocument(_ url: URL, ext: String) throws -> NSAttributedString {
        switch ext {
        case "txt", "text":
            return plainAttributed(try readText(url))
        case "md", "markdown":
            return try attributed(fromHTML: MarkdownConverter.html(fromMarkdown: try readText(url)))
        case "html", "htm":
            return try attributed(fromHTML: try readText(url))
        default:
            let type: NSAttributedString.DocumentType = switch ext {
            case "docx": .officeOpenXML
            case "doc": .docFormat
            case "odt": .openDocument
            case "rtfd": .rtfd
            default: .rtf
            }
            do {
                return try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil)
            } catch {
                throw ConversionError.unreadable
            }
        }
    }

    private static func writeDocument(
        _ text: NSAttributedString, to target: FileFormat, baseName: String, in directory: URL, landscape: Bool = false
    ) throws -> URL {
        let range = NSRange(location: 0, length: text.length)
        let data: Data
        switch target {
        case .pdf:
            data = DocumentRenderer.pdfData(from: text, landscape: landscape)
        case .txt:
            data = Data(text.string.utf8)
        case .md:
            data = Data(MarkdownConverter.markdown(from: text).utf8)
        case .docx, .rtf, .html:
            let type: NSAttributedString.DocumentType = switch target {
            case .docx: .officeOpenXML
            case .rtf: .rtf
            default: .html
            }
            do {
                data = try text.data(from: range, documentAttributes: [.documentType: type])
            } catch {
                throw ConversionError.writeFailed
            }
        default:
            throw ConversionError.unsupported
        }
        return try write(data, baseName, target, in: directory)
    }

    // MARK: - Spreadsheets

    private static func readWorkbook(_ url: URL) throws -> [Sheet] {
        do {
            let sheets = try XLSX.readSheets(Data(contentsOf: url))
            let filled = sheets.filter { !$0.rows.isEmpty }
            return filled.isEmpty ? Array(sheets.prefix(1)) : filled
        } catch {
            throw ConversionError.unreadable
        }
    }

    /// Writes one or more sheets. Documents get a heading per sheet when
    /// there are several, and turn landscape when a table is wide.
    private static func writeSheets(_ sheets: [Sheet], to target: FileFormat, baseName: String, in directory: URL) throws -> URL {
        guard sheets.contains(where: { !$0.rows.isEmpty }) else { throw ConversionError.noText }
        let titled = sheets.count > 1
        let landscape = sheets.contains { ($0.rows.map(\.count).max() ?? 0) > 6 }

        func blocks() -> [DocBlock] {
            sheets.flatMap { sheet -> [DocBlock] in
                let table = DocBlock.table(sheet.rows)
                return titled ? [.heading(2, [TextRun(text: sheet.name)]), table] : [table]
            }
        }

        switch target {
        case .csv:
            guard sheets.count > 1 else {
                return try write(Data(CSV.serialize(sheets[0].rows).utf8), baseName, .csv, in: directory)
            }
            let folder = uniqueURL("\(baseName) (CSV)", nil, in: directory)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                throw ConversionError.writeFailed
            }
            for sheet in sheets {
                let name = sheet.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                _ = try write(Data(CSV.serialize(sheet.rows).utf8), name, .csv, in: folder)
            }
            return folder
        case .xlsx:
            return try write(XLSX.make(sheets), baseName, .xlsx, in: directory)
        case .md:
            let md = sheets.map { (titled ? "## \($0.name)\n\n" : "") + MarkdownConverter.markdownTable($0.rows) }
                .joined(separator: "\n")
            return try write(Data(md.utf8), baseName, .md, in: directory)
        case .html:
            return try write(Data(HTMLWriter.html(blocks(), title: baseName).utf8), baseName, .html, in: directory)
        case .docx:
            return try write(DocxWriter.make(blocks(), landscape: landscape), baseName, .docx, in: directory)
        case .pdf:
            let text = try attributed(fromHTML: HTMLWriter.html(blocks(), title: baseName))
            return try writeDocument(text, to: .pdf, baseName: baseName, in: directory, landscape: landscape)
        default:
            throw ConversionError.unsupported
        }
    }

    /// AppKit's HTML importer runs WebKit and must be used on the main thread.
    static func attributed(fromHTML html: String) throws -> NSAttributedString {
        let data = Data(html.utf8)
        let parse = { () throws -> NSAttributedString in
            try NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
            )
        }
        do {
            if Thread.isMainThread { return try parse() }
            return try DispatchQueue.main.sync(execute: parse)
        } catch {
            throw ConversionError.unreadable
        }
    }

    private static func plainAttributed(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.black,
        ])
    }

    /// UTF-8, then UTF-16 with a BOM, then Windows Latin-1 for old exports.
    private static func readText(_ url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url) else { throw ConversionError.unreadable }
        for encoding in [String.Encoding.utf8, .utf16, .windowsCP1252] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        throw ConversionError.unreadable
    }

    // MARK: - Output

    private static func write(_ data: Data, _ baseName: String, _ format: FileFormat, in directory: URL) throws -> URL {
        let url = uniqueURL(baseName, format.fileExtension, in: directory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .withoutOverwriting)
        } catch {
            throw ConversionError.writeFailed
        }
        return url
    }

    /// "Name.ext", or "Name 2.ext", "Name 3.ext"… if taken.
    static func uniqueURL(_ baseName: String, _ ext: String?, in directory: URL) -> URL {
        func make(_ name: String) -> URL {
            ext.map { directory.appendingPathComponent(name).appendingPathExtension($0) }
                ?? directory.appendingPathComponent(name, isDirectory: true)
        }
        var candidate = make(baseName)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = make("\(baseName) \(counter)")
            counter += 1
        }
        return candidate
    }
}

/// Lays styled text out on A4 pages and draws them into a PDF.
nonisolated enum DocumentRenderer {
    static let portrait = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 56

    static func pdfData(from text: NSAttributedString, landscape: Bool = false) -> Data {
        let pageSize = landscape ? CGSize(width: portrait.height, height: portrait.width) : portrait
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let containerSize = CGSize(width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)

        // Add pages until every glyph has a place.
        var containers: [NSTextContainer] = []
        while containers.count < 5000 {
            let container = NSTextContainer(size: containerSize)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            containers.append(container)
            let range = layout.glyphRange(for: container)
            if NSMaxRange(range) >= layout.numberOfGlyphs || range.length == 0 { break }
        }

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        for container in containers {
            context.beginPDFPage(nil)
            context.saveGState()
            // TextKit draws top-down.
            context.translateBy(x: 0, y: pageSize.height)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            let range = layout.glyphRange(for: container)
            let origin = CGPoint(x: margin, y: margin)
            // Paper is white: resolve system colors as in light mode.
            NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
                layout.drawBackground(forGlyphRange: range, at: origin)
                layout.drawGlyphs(forGlyphRange: range, at: origin)
            }
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}
