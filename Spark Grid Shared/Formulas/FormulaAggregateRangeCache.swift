import Foundation

/// Stable identity for a rectangular range used by conditional aggregates (COUNTIFS, SUMIFS, …).
struct AggregateRangeKey: Hashable {
  var sheet: String
  var minRow: Int
  var minCol: Int
  var maxRow: Int
  var maxCol: Int

  init(sheet: String?, row: Int, col: Int, rows: Int, cols: Int) {
    self.sheet = (sheet ?? "").lowercased()
    self.minRow = row
    self.minCol = col
    self.maxRow = row + rows - 1
    self.maxCol = col + cols - 1
  }

  func contains(address: CellAddress) -> Bool {
    address.row >= minRow && address.row <= maxRow && address.col >= minCol && address.col <= maxCol
  }
}

/// One scan per criteria range per recalc batch; invalidated when a source cell in that range changes.
final class FormulaAggregateRangeCache {
  private var snapshots: [AggregateRangeKey: [CellValue]] = [:]

  func invalidateAll() {
    snapshots.removeAll(keepingCapacity: true)
  }

  func invalidate(sheetName: String, address: CellAddress) {
    let sheet = sheetName.lowercased()
    snapshots = snapshots.filter { key, _ in
      key.sheet != sheet || !key.contains(address: address)
    }
  }

  func rowMajorValues(
    key: AggregateRangeKey,
    count: Int,
    fill: (Int) -> CellValue
  ) -> [CellValue] {
    if let cached = snapshots[key] {
      return cached
    }
    var values = [CellValue]()
    values.reserveCapacity(count)
    for index in 0..<count {
      values.append(fill(index))
    }
    snapshots[key] = values
    return values
  }
}
