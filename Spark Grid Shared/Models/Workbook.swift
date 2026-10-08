import CoreGraphics
import Foundation

/// A workbook-scoped defined name. Static ranges resolve to cells. Formulas such as
/// `OFFSET(...)` stay as `refersTo` and are not treated as a cell range.
struct NamedRange: Codable, Equatable, Sendable {
  var name: String
  var sheetName: String
  var startRow: Int
  var startCol: Int
  var endRow: Int
  var endCol: Int
  /// Original refers-to text from the workbook or the name manager.
  var refersTo: String?
  /// False for formulas (OFFSET and anything else that is not a static reference).
  var resolvesToRange: Bool

  var range: CellRange {
    CellRange(
      start: CellAddress(row: startRow, col: startCol),
      end: CellAddress(row: endRow, col: endCol)
    )
  }

  /// What the name manager shows. Formula names keep their text; they are not rewritten as A1.
  var referenceText: String {
    if let refersTo {
      let trimmed = refersTo.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
    }
    return Self.coordinateReference(sheetName: sheetName, range: range)
  }

  init(name: String, sheetName: String, range: CellRange) {
    let n = range.normalized
    self.name = name
    self.sheetName = sheetName
    self.startRow = n.minRow
    self.startCol = n.minCol
    self.endRow = n.maxRow
    self.endCol = n.maxCol
    self.refersTo = nil
    self.resolvesToRange = true
  }

  /// A defined name whose refers-to is not a static range.
  init(formulaName name: String, refersTo: String, sheetName: String) {
    self.name = name
    self.sheetName = sheetName
    self.startRow = 0
    self.startCol = 0
    self.endRow = 0
    self.endCol = 0
    self.refersTo = refersTo
    self.resolvesToRange = false
  }

  static func coordinateReference(sheetName: String, range: CellRange) -> String {
    let n = range.normalized
    let sheetRef = sheetName.replacingOccurrences(of: "'", with: "''")
    let start = CellAddress(row: n.minRow, col: n.minCol).a1
    let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
    if start == end { return "'\(sheetRef)'!\(start)" }
    return "'\(sheetRef)'!\(start):\(end)"
  }

  enum CodingKeys: String, CodingKey {
    case name, sheetName, startRow, startCol, endRow, endCol, refersTo, resolvesToRange
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = try c.decode(String.self, forKey: .name)
    sheetName = try c.decode(String.self, forKey: .sheetName)
    startRow = try c.decode(Int.self, forKey: .startRow)
    startCol = try c.decode(Int.self, forKey: .startCol)
    endRow = try c.decode(Int.self, forKey: .endRow)
    endCol = try c.decode(Int.self, forKey: .endCol)
    refersTo = try c.decodeIfPresent(String.self, forKey: .refersTo)
    resolvesToRange = try c.decodeIfPresent(Bool.self, forKey: .resolvesToRange) ?? true
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(name, forKey: .name)
    try c.encode(sheetName, forKey: .sheetName)
    try c.encode(startRow, forKey: .startRow)
    try c.encode(startCol, forKey: .startCol)
    try c.encode(endRow, forKey: .endRow)
    try c.encode(endCol, forKey: .endCol)
    try c.encodeIfPresent(refersTo, forKey: .refersTo)
    try c.encode(resolvesToRange, forKey: .resolvesToRange)
  }
}

/// Parses a defined-name formula into a static range, or keeps the text when it is not one.
enum DefinedNameFormula {
  static func make(name: String, formula: String, sheets: [Sheet], localSheet: String?) -> NamedRange {
    var text = formula.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("=") {
      text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
      text = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let fallback = localSheet ?? sheets.first?.name ?? "Sheet1"
    guard isStaticReference(text) else {
      return NamedRange(formulaName: name, refersTo: text, sheetName: fallback)
    }

    let start: FormulaRef
    let end: FormulaRef
    if let range = A1Reference.parseFormulaRange(text) {
      start = range.0
      end = range.1
    } else if let cell = A1Reference.parseFormulaRef(text) {
      start = cell
      end = cell
    } else {
      return NamedRange(formulaName: name, refersTo: text, sheetName: fallback)
    }

    var resolvedStart = start
    var resolvedEnd = end
    if resolvedStart.sheet == nil {
      resolvedStart.sheet = localSheet ?? end.sheet ?? sheets.first?.name
    }
    if resolvedEnd.sheet == nil {
      resolvedEnd.sheet = resolvedStart.sheet
    }
    guard let sheetName = resolvedStart.sheet ?? resolvedEnd.sheet,
          let sheet = sheets.first(where: { $0.name.caseInsensitiveCompare(sheetName) == .orderedSame })
    else {
      return NamedRange(formulaName: name, refersTo: text, sheetName: fallback)
    }

    let bounds = A1Reference.resolvedBounds(
      start: resolvedStart,
      end: resolvedEnd,
      maxRow: max(0, sheet.effectiveRowCount - 1),
      maxCol: max(0, sheet.effectiveColumnCount - 1)
    )
    var named = NamedRange(
      name: name,
      sheetName: sheet.name,
      range: CellRange(
        start: CellAddress(row: bounds.minRow, col: bounds.minCol),
        end: CellAddress(row: bounds.maxRow, col: bounds.maxCol)
      )
    )
    named.refersTo = text
    return named
  }

  /// Functions, unions, and arithmetic are not a single range.
  private static func isStaticReference(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    var quoted = false
    for character in text {
      if character == "'" {
        quoted.toggle()
        continue
      }
      if quoted { continue }
      switch character {
      case "(", ")", ",", "+", "-", "*", "/", "&", "^", "=", "<", ">":
        return false
      default:
        break
      }
    }
    return true
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
