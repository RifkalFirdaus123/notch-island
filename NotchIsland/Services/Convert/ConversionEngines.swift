import AppKit
import Foundation

/// Outside tools that convert better than the built-in code when present:
/// Microsoft Word for Word → PDF, and a private Python environment with
/// pdf2docx (PDF → Word, keeping layout) and pdfplumber (PDF tables).
nonisolated enum ConversionEngines {
    enum EngineError: LocalizedError {
        case wordNotAuthorized
        case wordFailed(String)
        case pythonNotFound
        case installFailed(String)
        case engineFailed(String)

        var errorDescription: String? {
            switch self {
            case .wordNotAuthorized:
                String(localized: "Allow NotchIsland to control Microsoft Word in System Settings › Privacy & Security › Automation.")
            case .wordFailed(let detail):
                String(localized: "Microsoft Word couldn't convert the file: \(detail)")
            case .pythonNotFound:
                String(localized: "Python 3 wasn't found. Install it with Homebrew (brew install python) or from python.org.")
            case .installFailed(let detail):
                String(localized: "The PDF engine couldn't be installed: \(detail)")
            case .engineFailed(let detail):
                String(localized: "The PDF engine failed: \(detail)")
            }
        }
    }

    // MARK: - Microsoft Word

    static let wordBundleID = "com.microsoft.Word"

    static var isWordInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: wordBundleID) != nil
    }

    /// Opens the document in Word and saves it as PDF, so the PDF matches
    /// what Word shows. Word is sandboxed and asks for access to files
    /// elsewhere, so the work happens inside its own container.
    static func wordToPDF(_ source: URL, output: URL) throws {
        let container = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(wordBundleID)/Data/Library/Caches/NotchIsland", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let input = container.appendingPathComponent("document." + source.pathExtension.lowercased())
        let pdf = container.appendingPathComponent("document.pdf")
        try FileManager.default.copyItem(at: source, to: input)

        let script = """
        on run argv
            set inputPath to item 1 of argv
            set outputPath to item 2 of argv
            set wasRunning to application id "\(wordBundleID)" is running
            tell application id "\(wordBundleID)"
                open file name inputPath
                set doc to active document
                save as doc file name outputPath file format format PDF
                close doc saving no
                if not wasRunning and (count of documents) is 0 then quit saving no
            end tell
        end run
        """
        let result = try run("/usr/bin/osascript", ["-e", script, input.path, pdf.path], timeout: 300)
        if result.status != 0 {
            if result.errorOutput.contains("-1743") || result.errorOutput.contains("Not authorized") {
                throw EngineError.wordNotAuthorized
            }
            throw EngineError.wordFailed(lastLine(result.errorOutput))
        }
        guard FileManager.default.fileExists(atPath: pdf.path) else {
            throw EngineError.wordFailed(String(localized: "no PDF was produced"))
        }
        try FileManager.default.moveItem(at: pdf, to: output)
    }

    // MARK: - PDF engine (Python)

    /// ~/Library/Application Support/NotchIsland/PDFEngine, a virtualenv.
    static var engineDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchIsland/PDFEngine", isDirectory: true)
    }

    private static var enginePython: URL {
        engineDirectory.appendingPathComponent("bin/python3")
    }

    /// Written last by `installPDFEngine`, so a half-finished install
    /// doesn't count.
    private static var installedMarker: URL {
        engineDirectory.appendingPathComponent(".installed")
    }

    static var isPDFEngineInstalled: Bool {
        FileManager.default.fileExists(atPath: installedMarker.path)
            && FileManager.default.isExecutableFile(atPath: enginePython.path)
    }

    static let enginePackages = ["pdf2docx", "pdfplumber"]

    /// A Python 3 to build the environment from. Apple's /usr/bin/python3
    /// only works with the developer tools installed (otherwise it opens an
    /// install prompt), so it's checked last and only when they are.
    static func findSystemPython() -> URL? {
        var candidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
        let frameworks = URL(fileURLWithPath: "/Library/Frameworks/Python.framework/Versions/Current/bin/python3")
        candidates.append(frameworks.path)
        if FileManager.default.fileExists(atPath: "/Library/Developer/CommandLineTools/usr/bin/python3")
            || FileManager.default.fileExists(atPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/python3") {
            candidates.append("/usr/bin/python3")
        }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            guard let result = try? run(path, ["-c", "import sys, venv; print(sys.version_info >= (3, 9))"], timeout: 30),
                  result.status == 0, result.output.contains("True") else { continue }
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// Creates the virtualenv and installs the packages from PyPI (about
    /// 450 MB with their dependencies). Takes a minute or two.
    static func installPDFEngine() throws {
        guard let python = findSystemPython() else { throw EngineError.pythonNotFound }
        try? FileManager.default.removeItem(at: engineDirectory)

        var result = try run(python.path, ["-m", "venv", engineDirectory.path], timeout: 300)
        guard result.status == 0 else { throw EngineError.installFailed(lastLine(result.errorOutput)) }

        result = try run(enginePython.path, [
            "-m", "pip", "install", "--disable-pip-version-check", "--no-input", "--only-binary=:all:",
        ] + enginePackages, timeout: 1800)
        guard result.status == 0 else {
            try? FileManager.default.removeItem(at: engineDirectory)
            throw EngineError.installFailed(lastLine(result.errorOutput.isEmpty ? result.output : result.errorOutput))
        }
        try Data().write(to: installedMarker)
    }

    static func removePDFEngine() {
        try? FileManager.default.removeItem(at: engineDirectory)
    }

    /// pdf2docx: rebuilds the page as Word paragraphs, tables and images.
    static func pdfToDocx(_ source: URL, output: URL) throws {
        try runEngine("docx", source.path, output.path)
    }

    /// pdfplumber: tables drawn with lines, or lined up text when a page
    /// has none. Each table is the page number and its rows.
    static func pdfTables(_ source: URL) throws -> [(page: Int, rows: TableRows)] {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("tables-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: output) }
        try runEngine("tables", source.path, output.path)

        struct Table: Decodable { let page: Int; let rows: [[String]] }
        let tables = try JSONDecoder().decode([Table].self, from: Data(contentsOf: output))
        return tables.map { ($0.page, $0.rows) }
    }

    private static let engineScript = #"""
    import json, sys, warnings, logging
    warnings.filterwarnings("ignore")
    logging.disable(logging.CRITICAL)
    command, source, output = sys.argv[1:4]

    if command == "docx":
        import re
        from pdf2docx import Converter
        from pdf2docx.font.Fonts import Fonts

        # Subset fonts often carry only a PostScript name ("AAAAAG+ArialMT"),
        # which pdf2docx turns into an empty font name, so Word falls back to
        # its default font. Use the family Word knows instead ("Arial").
        def readable_font(name):
            name = name.split("+")[-1].split(",")[0].split("-")[0]
            name = re.sub(r"(PSMT|PS|MT)$", "", name)
            return re.sub(r"(?<=[a-z])(?=[A-Z])", " ", name).strip()

        family_name = Fonts.get_font_family_name

        def family_or_postscript_name(tt):
            name = family_name(tt)
            if not name:
                for record in tt["name"].names:
                    if record.nameID in (4, 6):
                        name = record.toUnicode()
                        break
            return readable_font(name) if name else name

        Fonts._normalized_font_name = staticmethod(readable_font)
        Fonts.get_font_family_name = staticmethod(family_or_postscript_name)

        converter = Converter(source)
        try:
            converter.convert(output)
        finally:
            converter.close()

        # Justified lines in the PDF fill the column exactly; pdf2docx adds a
        # small right indent, so Word wraps one word early and every page
        # overflows. Give justified paragraphs their full width back.
        import shutil, tempfile, zipfile

        def widen(match):
            block = match.group(0)
            if 'w:val="both"' not in block:
                return block
            return re.sub(r'(<w:ind\b[^>]*?)\bw:right="([0-9]+)"',
                          lambda m: m.group(1) + ('w:right="0"' if int(m.group(2)) < 600 else m.group(0)[len(m.group(1)):]),
                          block)

        temporary = tempfile.mktemp(suffix=".docx")
        with zipfile.ZipFile(output) as zin, zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                data = zin.read(item.filename)
                if item.filename == "word/document.xml":
                    data = re.sub(r"<w:pPr>.*?</w:pPr>", widen, data.decode("utf-8"), flags=re.S).encode("utf-8")
                zout.writestr(item, data)
        shutil.move(temporary, output)

    elif command == "tables":
        import pdfplumber

        def clean(table):
            rows = [[" ".join((cell or "").split()) for cell in row] for row in table]
            rows = [row for row in rows if any(row)]
            # Drop columns that are empty in every row.
            keep = [i for i in range(max((len(r) for r in rows), default=0)) if any(i < len(r) and r[i] for r in rows)]
            return [[row[i] if i < len(row) else "" for i in keep] for row in rows]

        found = []
        with pdfplumber.open(source) as pdf:
            for number, page in enumerate(pdf.pages, start=1):
                tables = [clean(t) for t in page.extract_tables()]
                tables = [t for t in tables if t and max(len(r) for r in t) > 1]
                if not tables:
                    text = page.extract_tables({"vertical_strategy": "text", "horizontal_strategy": "text"})
                    tables = [t for t in (clean(t) for t in text) if len(t) > 1 and max(len(r) for r in t) > 1]
                found += [{"page": number, "rows": t} for t in tables]
        with open(output, "w", encoding="utf-8") as f:
            json.dump(found, f, ensure_ascii=False)
    """#

    private static func runEngine(_ arguments: String...) throws {
        let result = try run(enginePython.path, ["-I", "-c", engineScript] + arguments, timeout: 900)
        guard result.status == 0 else { throw EngineError.engineFailed(lastLine(result.errorOutput)) }
    }

    // MARK: - Processes

    struct ProcessResult {
        var status: Int32
        var output: String
        var errorOutput: String
    }

    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()

        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        defer { timer.cancel() }

        // Drain both pipes at once so a chatty tool can't fill one and stall.
        nonisolated(unsafe) var errorData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errorData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outputData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        return ProcessResult(
            status: process.terminationStatus,
            output: String(decoding: outputData, as: UTF8.self),
            errorOutput: String(decoding: errorData, as: UTF8.self)
        )
    }

    private static func lastLine(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        return String((lines.last { !$0.isEmpty } ?? "").prefix(300))
    }
}
