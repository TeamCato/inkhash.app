import Foundation
import InkhashCore

/// Writes one workspace of this device as an export file, named after it and the day.
/// Handwriting becomes PDF here, since only the app can render it. See ADR 0051.
@MainActor
enum WorkspaceExporter {
    static func export(_ workspace: Workspace, store: LocalStore, now: Date = Date()) throws -> (url: URL, summary: WorkspaceExport.Summary) {
        let day = now.formatted(.iso8601.year().month().day())
        let url = try ExportFolder.fresh().appendingPathComponent("\(ExportNames.fileName(workspace.name)) \(day).zip")
        let load: (String) -> Data? = { try? store.blob($0) }
        let summary = try WorkspaceExport.write(
            to: url,
            workspace: workspace.name,
            notes: try store.list().map(\.note),
            blob: { try store.blob($0) },
            pdf: { NotePDF.data(for: $0, load: load) }
        )
        return (url, summary)
    }
}
