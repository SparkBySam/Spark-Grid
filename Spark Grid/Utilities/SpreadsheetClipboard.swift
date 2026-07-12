import Foundation
import AppKit

/// Tab-separated grid clipboard encoding (compatible with Excel, Google Sheets, Numbers).
enum SpreadsheetClipboard {
  /// Custom pasteboard type for formula paste with relative adjustment.
  static let formulaGridType = NSPasteboard.PasteboardType("app.sparkgrid.formula-grid")

  struct FormulaGridPayload: Codable, Equatable {
    var originRow: Int
    var originCol: Int
    var grid: [[String]]
  }

  static func copyText(from sheet: Sheet, range: CellRange) -> String {
    copyText(from: sheet, range: range, shrinkLargeSelection: true)
  }

  private static func copyText(from sheet: Sheet, range: CellRange, shrinkLargeSelection: Bool) -> String {
    let bounds = range.normalized
    let rowCount = bounds.maxRow - bounds.minRow + 1
    let colCount = bounds.maxCol - bounds.minCol + 1

    // For huge selections (e.g. whole sheet), only emit the populated sub-range.
    if shrinkLargeSelection, rowCount * colCount > 4_000, let used = sheet.populatedBounds {
      let usedNorm = used.normalized
      let minRow = max(bounds.minRow, usedNorm.minRow)
      let maxRow = min(bounds.maxRow, usedNorm.maxRow)
      let minCol = max(bounds.minCol, usedNorm.minCol)
      let maxCol = min(bounds.maxCol, usedNorm.maxCol)
      guard minRow <= maxRow, minCol <= maxCol else { return "" }
      return copyText(
        from: sheet,
        range: CellRange(
          start: CellAddress(row: minRow, col: minCol),
          end: CellAddress(row: maxRow, col: maxCol)
        ),
        shrinkLargeSelection: false
      )
    }

    var rows: [String] = []
    rows.reserveCapacity(rowCount)

    for row in bounds.minRow...bounds.maxRow {
      var fields: [String] = []
      fields.reserveCapacity(colCount)
      for col in bounds.minCol...bounds.maxCol {
        fields.append(sheet.cell(at: CellAddress(row: row, col: col)).raw)
      }
      rows.append(fields.joined(separator: "\t"))
    }
    return rows.joined(separator: "\n")
  }

  static func grid(from sheet: Sheet, range: CellRange) -> [[String]] {
    let bounds = range.normalized
    var grid: [[String]] = []
    for row in bounds.minRow...bounds.maxRow {
      var fields: [String] = []
      for col in bounds.minCol...bounds.maxCol {
        fields.append(sheet.cell(at: CellAddress(row: row, col: col)).raw)
      }
      grid.append(fields)
    }
    return grid
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

  static func writeFormulaGrid(_ payload: FormulaGridPayload, tsv: String) {
    let board = NSPasteboard.general
    board.clearContents()
    board.setString(tsv, forType: .string)
    if let data = try? JSONEncoder().encode(payload) {
      board.setData(data, forType: formulaGridType)
    }
  }

  static func readFormulaGrid() -> FormulaGridPayload? {
    guard let data = NSPasteboard.general.data(forType: formulaGridType) else { return nil }
    return try? JSONDecoder().decode(FormulaGridPayload.self, from: data)
  }
}
