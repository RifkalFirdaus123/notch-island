import Foundation
import UniformTypeIdentifiers

/// A format a file can be converted to.
nonisolated enum FileFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf, docx, rtf, html, txt, md, csv, xlsx, png, jpeg, heic, tiff

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        default: rawValue
        }
    }

    var utType: UTType {
        switch self {
        case .pdf: .pdf
        case .docx: UTType(filenameExtension: "docx") ?? .data
        case .rtf: .rtf
        case .html: .html
        case .txt: .plainText
        case .md: UTType(filenameExtension: "md") ?? .plainText
        case .csv: .commaSeparatedText
        case .xlsx: UTType(filenameExtension: "xlsx") ?? .data
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        }
    }

    /// Menu label, e.g. "Word (.docx)".
    var title: String {
        switch self {
        case .pdf: "PDF"
        case .docx: String(localized: "Word (.docx)")
        case .rtf: String(localized: "Rich Text (.rtf)")
        case .html: String(localized: "Web Page (.html)")
        case .txt: String(localized: "Plain Text (.txt)")
        case .md: "Markdown (.md)"
        case .csv: "CSV (.csv)"
        case .xlsx: String(localized: "Excel (.xlsx)")
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        }
    }

    var isImage: Bool { [.png, .jpeg, .heic, .tiff].contains(self) }
}

/// What kind of content a source file holds, which decides how it is read.
nonisolated enum SourceKind: Equatable, Sendable {
    case pdf
    /// Rich or plain text read with AppKit's importers (docx, doc, odt,
    /// rtf, html) or as text (txt, md).
    case document(String)
    case csv
    case xlsx
    case image

    init?(url: URL) {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": self = .pdf
        case "docx", "doc", "odt", "rtf", "rtfd", "html", "htm", "txt", "text", "md", "markdown":
            self = .document(ext)
        case "csv", "tsv": self = .csv
        case "xlsx": self = .xlsx
        default:
            guard let type = UTType(filenameExtension: ext), type.conforms(to: .image),
                  !type.conforms(to: .pdf) else { return nil }
            self = .image
        }
    }

    /// The format this file already is, so it isn't offered as a target.
    func ownFormat(_ url: URL) -> FileFormat? {
        switch url.pathExtension.lowercased() {
        case "pdf": .pdf
        case "docx": .docx
        case "rtf": .rtf
        case "html", "htm": .html
        case "txt", "text": .txt
        case "md", "markdown": .md
        case "csv": .csv
        case "xlsx": .xlsx
        case "png": .png
        case "jpg", "jpeg": .jpeg
        case "heic", "heif": .heic
        case "tif", "tiff": .tiff
        default: nil
        }
    }

    var targets: [FileFormat] {
        switch self {
        case .pdf: [.docx, .txt, .md, .rtf, .html, .xlsx, .csv, .png, .jpeg]
        case .document: [.pdf, .docx, .md, .txt, .rtf, .html]
        case .csv: [.xlsx, .pdf, .docx, .md, .html]
        case .xlsx: [.csv, .pdf, .docx, .md, .html]
        case .image: [.png, .jpeg, .heic, .tiff, .pdf, .txt]
        }
    }
}
