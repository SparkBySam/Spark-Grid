import Foundation

/// Session-only filter on the active sheet (not persisted to xlsx/csv).
struct SheetFilterState: Equatable, Sendable {
  /// Inclusive data range including the header row.
  var range: CellRange
  /// Per-column selected display values. Missing key = all values visible for that column.
  var selectedValuesByColumn: [Int: Set<String>]
  /// Columns that still sit in `range` but no longer participate (chevron removed / criteria cleared).
  var excludedColumns: Set<Int> = []

  var headerRow: Int { range.normalized.minRow }

  var dataRows: ClosedRange<Int> {
    let n = range.normalized
    return (n.minRow + 1)...n.maxRow
  }

  func isColumnActive(_ col: Int) -> Bool {
    let n = range.normalized
    return col >= n.minCol && col <= n.maxCol && !excludedColumns.contains(col)
  }

  func isRowHidden(_ row: Int, sheet: Sheet, displayString: (CellAddress) -> String) -> Bool {
    isRowHidden(row, sheet: sheet, displayString: displayString, excludingColumn: nil)
  }

  func uniqueValues(forColumn col: Int, sheet: Sheet, displayString: (CellAddress) -> String) -> [String] {
    let n = range.normalized
    guard isColumnActive(col), n.maxRow > n.minRow else { return [] }
    var seen = Set<String>()
    var ordered: [String] = []
    for row in (n.minRow + 1)...n.maxRow {
      // Cascade: only list values from rows still visible under *other* columns' filters.
      if isRowHidden(row, sheet: sheet, displayString: displayString, excludingColumn: col) {
        continue
      }
      let value = displayString(CellAddress(row: row, col: col))
      if seen.insert(value).inserted {
        ordered.append(value)
      }
    }
    return ordered.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  /// Like `isRowHidden`, but ignores the filter on `excludingColumn` so that column's menu can widen.
  func isRowHidden(
    _ row: Int,
    sheet: Sheet,
    displayString: (CellAddress) -> String,
    excludingColumn: Int?
  ) -> Bool {
    let n = range.normalized
    guard row > n.minRow, row <= n.maxRow else { return false }
    for col in n.minCol...n.maxCol {
      if let excludingColumn, col == excludingColumn { continue }
      guard isColumnActive(col) else { continue }
      guard let allowed = selectedValuesByColumn[col] else { continue }
      let value = displayString(CellAddress(row: row, col: col))
      if !allowed.contains(value) { return true }
    }
    return false
  }
}

enum FindScope: String, CaseIterable, Sendable {
  case sheet
  case selection
}

enum SortDirection: String, CaseIterable, Sendable {
  case ascending
  case descending
}
