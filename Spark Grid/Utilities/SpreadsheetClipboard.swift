import Foundation

/// Tab-separated grid clipboard encoding (compatible with Excel, Google Sheets, Numbers).
enum SpreadsheetClipboard {
  static func copyText(from sheet: Sheet, range: CellRange) -> String {
    let bounds = range.normalized
    var rows: [String] = []
    rows.reserveCapacity(bounds.maxRow - bounds.minRow + 1)

    for row in bounds.minRow...bounds.maxRow {
      var fields: [String] = []
      fields.reserveCapacity(bounds.maxCol - bounds.minCol + 1)
      for col in bounds.minCol...bounds.maxCol {
        fields.append(sheet.cell(at: CellAddress(row: row, col: col)).raw)
      }
      rows.append(fields.joined(separator: "\t"))
    }
    return rows.joined(separator: "\n")
  }

  static func parseGrid(_ text: String) -> [[String]] {
    let normalized = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")

    guard !normalized.isEmpty else { return [] }

    return normalized.split(separator: "\n", omittingEmptySubsequences: false).map { line in
      String(line).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    }
  }

  static var hasContent: Bool {
    NSPasteboard.general.string(forType: .string) != nil
  }
}

import AppKit
