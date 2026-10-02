import Foundation

/// A cell reference inside a formula, optionally sheet-qualified, with absolute flags.
nonisolated struct FormulaRef: Equatable, Sendable {
  /// Sentinel for open-ended row/column bounds (e.g. `A2:A`, `A:A`).
  static let open = Int.max / 4

  var sheet: String?
  var row: Int
  var col: Int
  var absRow: Bool
  var absCol: Bool

  var address: CellAddress {
    CellAddress(row: isRowOpen ? 0 : row, col: isColOpen ? 0 : col)
  }

  var isRowOpen: Bool { row >= Self.open }
  var isColOpen: Bool { col >= Self.open }
  var isLocal: Bool { sheet == nil }

  func isOnSheet(_ name: String) -> Bool {
    guard let sheet else { return true }
    return sheet.caseInsensitiveCompare(name) == .orderedSame
  }

  func adjusted(rowDelta: Int, colDelta: Int) -> FormulaRef? {
    let newRow: Int
    if isRowOpen || absRow {
      newRow = row
    } else {
      newRow = row + rowDelta
      guard newRow >= 0 else { return nil }
    }
    let newCol: Int
    if isColOpen || absCol {
      newCol = col
    } else {
      newCol = col + colDelta
      guard newCol >= 0 else { return nil }
    }
    return FormulaRef(sheet: sheet, row: newRow, col: newCol, absRow: absRow, absCol: absCol)
  }
}

nonisolated indirect enum FormulaExpr: Equatable {
  case number(Double)
  case string(String)
  case boolean(Bool)
  case error(FormulaError)
  case namedRange(String)
  case cellRef(FormulaRef)
  case range(FormulaRef, FormulaRef)
  case unary(UnaryOp, FormulaExpr)
  case binary(BinaryOp, FormulaExpr, FormulaExpr)
  case call(String, [FormulaExpr])
}

nonisolated enum UnaryOp: Equatable {
  case negate
  case plus
}

nonisolated enum BinaryOp: Equatable {
  case add
  case subtract
  case multiply
  case divide
  case power
  case concat
  case eq
  case ne
  case lt
  case gt
  case le
  case ge
}
