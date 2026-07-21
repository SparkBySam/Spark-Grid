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
  /// Raw `xl/theme/theme1.xml` from import — round-tripped on export when present.
  var xlsxThemeData: Data?

  init(
    sheets: [Sheet] = [Sheet(name: "Sheet1")],
    activeSheetIndex: Int = 0,
    namedRanges: [String: NamedRange] = [:],
    xlsxThemeData: Data? = nil
  ) {
    self.sheets = sheets.isEmpty ? [Sheet(name: "Sheet1")] : sheets
    self.activeSheetIndex = min(max(0, activeSheetIndex), self.sheets.count - 1)
    self.namedRanges = namedRanges
    self.xlsxThemeData = xlsxThemeData
  }

  enum CodingKeys: String, CodingKey {
    case sheets, activeSheetIndex, namedRanges, xlsxThemeData
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    sheets = try c.decode([Sheet].self, forKey: .sheets)
    activeSheetIndex = try c.decode(Int.self, forKey: .activeSheetIndex)
    namedRanges = try c.decodeIfPresent([String: NamedRange].self, forKey: .namedRanges) ?? [:]
    xlsxThemeData = try c.decodeIfPresent(Data.self, forKey: .xlsxThemeData)
    if sheets.isEmpty { sheets = [Sheet(name: "Sheet1")] }
    activeSheetIndex = min(max(0, activeSheetIndex), sheets.count - 1)
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(sheets, forKey: .sheets)
    try c.encode(activeSheetIndex, forKey: .activeSheetIndex)
    try c.encode(namedRanges, forKey: .namedRanges)
    try c.encodeIfPresent(xlsxThemeData, forKey: .xlsxThemeData)
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
