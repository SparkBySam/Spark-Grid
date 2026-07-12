import CoreGraphics
import Foundation

/// A workbook-scoped named range (e.g. Sales → Sheet1!A1:B10).
struct NamedRange: Codable, Equatable, Sendable {
  var name: String
  var sheetName: String
  var startRow: Int
  var startCol: Int
  var endRow: Int
  var endCol: Int

  var range: CellRange {
    CellRange(
      start: CellAddress(row: startRow, col: startCol),
      end: CellAddress(row: endRow, col: endCol)
    )
  }

  init(name: String, sheetName: String, range: CellRange) {
    let n = range.normalized
    self.name = name
    self.sheetName = sheetName
    self.startRow = n.minRow
    self.startCol = n.minCol
    self.endRow = n.maxRow
    self.endCol = n.maxCol
  }
}

struct Workbook: Codable, Equatable, Sendable {
  static let defaultRowCount = 1_000
  static let defaultColumnCount = 26
  static let defaultColumnWidth: CGFloat = 80
  static let defaultRowHeight: CGFloat = 22

  var sheets: [Sheet]
  var activeSheetIndex: Int
  /// Global named ranges, keyed by uppercase name.
  var namedRanges: [String: NamedRange]

  init(
    sheets: [Sheet] = [Sheet(name: "Sheet1")],
    activeSheetIndex: Int = 0,
    namedRanges: [String: NamedRange] = [:]
  ) {
    self.sheets = sheets.isEmpty ? [Sheet(name: "Sheet1")] : sheets
    self.activeSheetIndex = min(max(0, activeSheetIndex), self.sheets.count - 1)
    self.namedRanges = namedRanges
  }

  var activeSheet: Sheet {
    get { sheets[activeSheetIndex] }
    set { sheets[activeSheetIndex] = newValue }
  }

  var isEffectivelyEmpty: Bool {
    sheets.allSatisfy(\.cells.isEmpty) && namedRanges.isEmpty
  }

  static var empty: Workbook { Workbook() }

  mutating func setNamedRange(_ range: NamedRange) {
    namedRanges[range.name.uppercased()] = range
  }

  mutating func removeNamedRange(named name: String) {
    namedRanges.removeValue(forKey: name.uppercased())
  }

  func namedRange(named name: String) -> NamedRange? {
    namedRanges[name.uppercased()]
  }
}
