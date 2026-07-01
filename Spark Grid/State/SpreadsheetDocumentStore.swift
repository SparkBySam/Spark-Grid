import Foundation
import Observation

@Observable
@MainActor
final class SpreadsheetDocumentStore {
  var document = SpreadsheetDocument()
  var fileURL: URL?

  var windowTitle: String {
    fileURL?.lastPathComponent ?? "Spark Sheets"
  }

  var hasOpenFile: Bool { fileURL != nil }

  func newDocument() {
    document = SpreadsheetDocument()
    fileURL = nil
  }

  func load(from url: URL) throws {
    document = try SpreadsheetDocument.load(from: url)
    fileURL = url
  }

  func save(to url: URL? = nil) throws {
    let destination = url ?? fileURL
    guard let destination else { return }
    let csv = CSVCodec.exportCSV(from: document.workbook.activeSheet)
    try csv.write(to: destination, atomically: true, encoding: .utf8)
    fileURL = destination
  }
}
