import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SpreadsheetDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }
  static var writableContentTypes: [UTType] { [.commaSeparatedText] }

  var workbook: Workbook

  init(workbook: Workbook = .empty) {
    self.workbook = workbook
  }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }
    let name = configuration.file.preferredFilename?.deletingPathExtension ?? "Sheet1"
    workbook = try Self.workbook(from: data, sheetName: name.isEmpty ? "Sheet1" : name)
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    let csv = CSVCodec.exportCSV(from: workbook.activeSheet)
    guard let data = csv.data(using: .utf8) else {
      throw CocoaError(.fileWriteInapplicableStringEncoding)
    }
    return FileWrapper(regularFileWithContents: data)
  }

  static func workbook(from data: Data, sheetName: String) throws -> Workbook {
    let text = decodeText(from: data)
    var sheet = Sheet(name: sheetName)
    sheet.cells = CSVCodec.importCSV(text)
    return Workbook(sheets: [sheet])
  }

  static func load(from url: URL) throws -> SpreadsheetDocument {
    let data = try Data(contentsOf: url)
    let name = url.deletingPathExtension().lastPathComponent
    let workbook = try workbook(from: data, sheetName: name.isEmpty ? "Sheet1" : name)
    return SpreadsheetDocument(workbook: workbook)
  }

  private static func decodeText(from data: Data) -> String {
    if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
    if let utf16 = String(data: data, encoding: .utf16) { return utf16 }
    if let macRoman = String(data: data, encoding: .macOSRoman) { return macRoman }
    return String(decoding: data, as: UTF8.self)
  }
}

private extension String {
  var deletingPathExtension: String {
    (self as NSString).deletingPathExtension
  }
}
