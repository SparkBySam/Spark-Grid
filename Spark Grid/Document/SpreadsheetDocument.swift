import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
  /// Excel Open XML workbook (.xlsx).
  static var spreadsheetML: UTType {
    UTType(importedAs: "org.openxmlformats.spreadsheetml.sheet")
  }
}

struct SpreadsheetDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.spreadsheetML, .commaSeparatedText, .plainText] }
  static var writableContentTypes: [UTType] { [.spreadsheetML, .commaSeparatedText] }

  var workbook: Workbook

  init(workbook: Workbook = .empty) {
    self.workbook = workbook
  }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }
    let name = configuration.file.preferredFilename?.deletingPathExtension ?? "Sheet1"
    let contentType = configuration.contentType
    workbook = try Self.workbook(
      from: data,
      sheetName: name.isEmpty ? "Sheet1" : name,
      contentType: contentType
    )
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    let type = configuration.contentType
    if type.conforms(to: .spreadsheetML) || type.identifier == UTType.spreadsheetML.identifier {
      let data = try XLSXCodec.exportWorkbook(workbook)
      return FileWrapper(regularFileWithContents: data)
    }
    let csv = CSVCodec.exportCSV(from: workbook.activeSheet)
    guard let data = csv.data(using: .utf8) else {
      throw CocoaError(.fileWriteInapplicableStringEncoding)
    }
    return FileWrapper(regularFileWithContents: data)
  }

  static func workbook(from data: Data, sheetName: String, contentType: UTType? = nil) throws -> Workbook {
    if isXLSX(data: data, contentType: contentType) {
      return try XLSXCodec.importWorkbook(from: data)
    }
    let text = decodeText(from: data)
    var sheet = Sheet(name: sheetName)
    sheet.cells = CSVCodec.importCSV(text)
    return Workbook(sheets: [sheet])
  }

  static func load(from url: URL) throws -> SpreadsheetDocument {
    let data = try Data(contentsOf: url)
    let name = url.deletingPathExtension().lastPathComponent
    let type = UTType(filenameExtension: url.pathExtension)
    let workbook = try workbook(
      from: data,
      sheetName: name.isEmpty ? "Sheet1" : name,
      contentType: type
    )
    return SpreadsheetDocument(workbook: workbook)
  }

  private static func isXLSX(data: Data, contentType: UTType?) -> Bool {
    if let contentType,
       contentType.conforms(to: .spreadsheetML)
        || contentType.identifier == "org.openxmlformats.spreadsheetml.sheet"
        || contentType.identifier == "com.microsoft.excel.xlsx"
    {
      return true
    }
    // ZIP local file header signature
    return data.starts(with: [0x50, 0x4B, 0x03, 0x04]) || data.starts(with: [0x50, 0x4B, 0x05, 0x06])
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
