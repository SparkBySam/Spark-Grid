import Foundation

/// Chart embedded on a sheet (Spark-native; also stored in xlsx as a custom part).
struct SheetChart: Identifiable, Codable, Equatable, Sendable {
  enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
    case bar
    case line
    case area

    var id: String { rawValue }

    var title: String {
      switch self {
      case .bar: return "Bar"
      case .line: return "Line"
      case .area: return "Area"
      }
    }
  }

  /// How Y values are produced from the data range.
  enum ValueMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Plot numbers from `valueColumn`.
    case values
    /// Count rows for each distinct category label (good for CRM / lead dumps).
    case count

    var id: String { rawValue }

    var title: String {
      switch self {
      case .values: return "Values"
      case .count: return "Count of rows"
      }
    }
  }

  var id: UUID
  var kind: Kind
  var title: String
  /// Inclusive data range (may include a header row).
  var dataRange: CellRange
  /// Absolute column index used for category / X labels. `nil` = infer at render time (legacy).
  var categoryColumn: Int?
  /// Absolute column index used for Y values when `valueMode == .values`.
  var valueColumn: Int?
  var hasHeaderRow: Bool
  var valueMode: ValueMode
  /// Top-left of chart frame in sheet cell coordinates (future on-sheet placement).
  var anchorRow: Int
  var anchorCol: Int
  var rowSpan: Int
  var colSpan: Int

  init(
    id: UUID = UUID(),
    kind: Kind = .bar,
    title: String = "Chart",
    dataRange: CellRange,
    categoryColumn: Int? = nil,
    valueColumn: Int? = nil,
    hasHeaderRow: Bool = true,
    valueMode: ValueMode = .values,
    anchorRow: Int,
    anchorCol: Int,
    rowSpan: Int = 12,
    colSpan: Int = 8
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.dataRange = dataRange
    self.categoryColumn = categoryColumn
    self.valueColumn = valueColumn
    self.hasHeaderRow = hasHeaderRow
    self.valueMode = valueMode
    self.anchorRow = anchorRow
    self.anchorCol = anchorCol
    self.rowSpan = max(4, rowSpan)
    self.colSpan = max(4, colSpan)
  }

  enum CodingKeys: String, CodingKey {
    case id, kind, title, dataRange
    case categoryColumn, valueColumn, hasHeaderRow, valueMode
    case anchorRow, anchorCol, rowSpan, colSpan
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .bar
    title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Chart"
    dataRange = try c.decode(CellRange.self, forKey: .dataRange)
    categoryColumn = try c.decodeIfPresent(Int.self, forKey: .categoryColumn)
    valueColumn = try c.decodeIfPresent(Int.self, forKey: .valueColumn)
    hasHeaderRow = try c.decodeIfPresent(Bool.self, forKey: .hasHeaderRow) ?? true
    valueMode = try c.decodeIfPresent(ValueMode.self, forKey: .valueMode) ?? .values
    anchorRow = try c.decodeIfPresent(Int.self, forKey: .anchorRow) ?? 0
    anchorCol = try c.decodeIfPresent(Int.self, forKey: .anchorCol) ?? 0
    rowSpan = try c.decodeIfPresent(Int.self, forKey: .rowSpan) ?? 12
    colSpan = try c.decodeIfPresent(Int.self, forKey: .colSpan) ?? 8
  }
}
