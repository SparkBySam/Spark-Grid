import Foundation

/// Chart embedded on a sheet (Spark-native; also stored in xlsx as a custom part).
struct SheetChart: Identifiable, Codable, Equatable, Sendable {
  enum Kind: String, Codable, Sendable, CaseIterable {
    case bar
    case line
    case area

    var title: String {
      switch self {
      case .bar: return "Bar"
      case .line: return "Line"
      case .area: return "Area"
      }
    }
  }

  var id: UUID
  var kind: Kind
  var title: String
  /// Inclusive data range (first row/column may be labels).
  var dataRange: CellRange
  /// Top-left of chart frame in sheet cell coordinates.
  var anchorRow: Int
  var anchorCol: Int
  /// Size in cell spans (approx).
  var rowSpan: Int
  var colSpan: Int

  init(
    id: UUID = UUID(),
    kind: Kind = .bar,
    title: String = "Chart",
    dataRange: CellRange,
    anchorRow: Int,
    anchorCol: Int,
    rowSpan: Int = 12,
    colSpan: Int = 8
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.dataRange = dataRange
    self.anchorRow = anchorRow
    self.anchorCol = anchorCol
    self.rowSpan = max(4, rowSpan)
    self.colSpan = max(4, colSpan)
  }
}
