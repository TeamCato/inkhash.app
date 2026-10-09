import Foundation
import InkhashCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownText = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
}

/// One note as a file for other apps: text as Markdown, handwriting as PDF. See ADR 0051.
@MainActor
enum NoteExport {
    static func contentType(of note: Note) -> UTType {
        note.kind == .text ? .markdownText : .pdf
    }

    static func data(for note: Note, load: (String) -> Data?) -> Data? {
        switch note.kind {
        case .text: Data((note.markdown ?? "").utf8)
        case .ink: NotePDF.data(for: note, load: load)
        }
    }

    /// Writes the note to a fresh temporary folder, under its title.
    static func file(for note: Note, load: (String) -> Data?) throws -> URL {
        guard let data = data(for: note, load: load) else { throw ExportError.damaged }
        let ext = note.kind == .text ? "md" : "pdf"
        let url = try ExportFolder.fresh().appendingPathComponent(ExportNames.fileName(note.displayTitle) + "." + ext)
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// Temporary folders for exports. Each export gets its own, so names never clash; the system
/// clears the temporary directory.
enum ExportFolder {
    static func fresh() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("inkhash-export", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// A note for the share sheet. The file is only made when someone picks a target.
struct SharedNote: Transferable {
    var note: Note
    var load: @MainActor @Sendable (String) -> Data?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { shared in
            SentTransferredFile(try await shared.file())
        }
        .exportingCondition { $0.note.kind == .ink }
        FileRepresentation(exportedContentType: .markdownText) { shared in
            SentTransferredFile(try await shared.file())
        }
        .exportingCondition { $0.note.kind == .text }
    }

    private func file() async throws -> URL {
        let note = note
        let load = load
        return try await MainActor.run { try NoteExport.file(for: note, load: load) }
    }
}

/// A finished export file for `fileExporter`, which saves it where the person picks.
struct ExportedFile: FileDocument {
    static let readableContentTypes: [UTType] = [.zip, .pdf, .markdownText]
    var url: URL

    init(url: URL) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url, options: .immediate)
    }
}
