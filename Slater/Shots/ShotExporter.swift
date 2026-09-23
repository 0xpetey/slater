import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes a Shot to disk, only when the user saves it (ADR 0001).
enum ShotExporter {
    enum Format: String, CaseIterable, Identifiable {
        /// One searchable file: the translated view, the original and the text (ShotPDF).
        case pdf
        /// `<name>-original.png` and `<name>-translated.png`.
        case image
        /// `<name>.md`, the Japanese and English for each Block.
        case text

        var id: Self { self }

        var title: String {
            switch self {
            case .pdf: "PDF"
            case .image: "Images"
            case .text: "Text"
            }
        }

        /// Only the format is remembered, never any content.
        static var lastUsed: Format {
            get { UserDefaults.standard.string(forKey: "exportFormat").flatMap(Format.init) ?? .pdf }
            set { UserDefaults.standard.set(newValue.rawValue, forKey: "exportFormat") }
        }
    }

    /// Writes the file(s) for `format` in `directory`, named after `baseName`: `<name>.pdf`, or
    /// `<name>-original.png` and `<name>-translated.png`, or `<name>.md`. If any would replace an
    /// existing file, all of them get a number (`<name> 2`) instead. Returns the files written.
    @discardableResult
    static func write(
        original: CGImage, translated: CGImage, markdown: String, pdf: Data,
        format: Format, directory: URL, baseName: String
    ) throws -> [URL] {
        var name = baseName
        var number = 2
        while files(for: format, name: name, in: directory).contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            name = "\(baseName) \(number)"
            number += 1
        }

        let urls = files(for: format, name: name, in: directory)
        for url in urls {
            switch url.lastPathComponent {
            case "\(name).pdf": try pdf.write(to: url, options: .atomic)
            case "\(name)-original.png": try writePNG(original, to: url)
            case "\(name)-translated.png": try writePNG(translated, to: url)
            default: try markdown.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        return urls
    }

    private static func files(for format: Format, name: String, in directory: URL) -> [URL] {
        let names = switch format {
        case .pdf: ["\(name).pdf"]
        case .image: ["\(name)-original.png", "\(name)-translated.png"]
        case .text: ["\(name).md"]
        }
        return names.map { directory.appendingPathComponent($0) }
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
