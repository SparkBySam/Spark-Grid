import Foundation

enum SheetStructureMutation {
  static func insertRows(into sheet: inout Sheet, at index: Int, count: Int = 1) {
    guard count > 0, index >= 0 else { return }

    var newCells: [CellAddress: Cell] = [:]
    newCells.reserveCapacity(sheet.cells.count)
    for (address, cell) in sheet.cells {
      if address.row >= index {
        newCells[CellAddress(row: address.row + count, col: address.col)] = cell
      } else {
        newCells[address] = cell
      }
    }
    sheet.cells = newCells
    sheet.rowHeights = shiftKeyedValues(sheet.rowHeights, threshold: index, delta: count)
    if sheet.frozenRows > index {
      sheet.frozenRows += count
    }
    shiftSheetAnnotations(&sheet, axis: .row, index: index, delta: count)
  }

  static func deleteRows(in sheet: inout Sheet, at index: Int, count: Int = 1) {
    guard count > 0, index >= 0 else { return }

    var newCells: [CellAddress: Cell] = [:]
    for (address, cell) in sheet.cells {
      if address.row >= index && address.row < index + count {
        continue
      }
      if address.row >= index + count {
        newCells[CellAddress(row: address.row - count, col: address.col)] = cell
      } else {
        newCells[address] = cell
      }
    }
    sheet.cells = newCells
    sheet.rowHeights = deleteKeyedValues(sheet.rowHeights, range: index..<(index + count))
    sheet.rowHeights = shiftKeyedValues(sheet.rowHeights, threshold: index + count, delta: -count)
    sheet.frozenRows = max(0, min(sheet.frozenRows, index))
    shiftSheetAnnotations(&sheet, axis: .row, index: index, delta: -count, deleteCount: count)
  }

  static func insertColumns(into sheet: inout Sheet, at index: Int, count: Int = 1) {
    guard count > 0, index >= 0 else { return }

    var newCells: [CellAddress: Cell] = [:]
    newCells.reserveCapacity(sheet.cells.count)
    for (address, cell) in sheet.cells {
      if address.col >= index {
        newCells[CellAddress(row: address.row, col: address.col + count)] = cell
      } else {
        newCells[address] = cell
      }
    }
    sheet.cells = newCells
    sheet.columnWidths = shiftKeyedValues(sheet.columnWidths, threshold: index, delta: count)
    if sheet.frozenColumns > index {
      sheet.frozenColumns += count
    }
    shiftSheetAnnotations(&sheet, axis: .column, index: index, delta: count)
  }

  static func deleteColumns(in sheet: inout Sheet, at index: Int, count: Int = 1) {
    guard count > 0, index >= 0 else { return }

    var newCells: [CellAddress: Cell] = [:]
    for (address, cell) in sheet.cells {
      if address.col >= index && address.col < index + count {
        continue
      }
      if address.col >= index + count {
        newCells[CellAddress(row: address.row, col: address.col - count)] = cell
      } else {
        newCells[address] = cell
      }
    }
    sheet.cells = newCells
    sheet.columnWidths = deleteKeyedValues(sheet.columnWidths, range: index..<(index + count))
    sheet.columnWidths = shiftKeyedValues(sheet.columnWidths, threshold: index + count, delta: -count)
    sheet.frozenColumns = max(0, min(sheet.frozenColumns, index))
    shiftSheetAnnotations(&sheet, axis: .column, index: index, delta: -count, deleteCount: count)
  }

  private enum Axis { case row, column }

  private static func shiftSheetAnnotations(
    _ sheet: inout Sheet,
    axis: Axis,
    index: Int,
    delta: Int,
    deleteCount: Int = 0
  ) {
    sheet.mergedRanges = sheet.mergedRanges.compactMap {
      shiftRange($0, axis: axis, index: index, delta: delta, deleteCount: deleteCount)
    }
    sheet.conditionalFormats = sheet.conditionalFormats.compactMap { rule in
      guard let range = shiftRange(rule.range, axis: axis, index: index, delta: delta, deleteCount: deleteCount)
      else { return nil }
      var next = rule
      next.range = range
      return next
    }
    if var filter = sheet.autoFilter {
      if let range = shiftRange(filter.range, axis: axis, index: index, delta: delta, deleteCount: deleteCount) {
        filter.range = range
        if axis == .column {
          filter.selectedValuesByColumn = shiftColumnMap(
            filter.selectedValuesByColumn,
            index: index,
            delta: delta,
            deleteCount: deleteCount
          )
          filter.excludedColumns = Set(
            filter.excludedColumns.compactMap { col -> Int? in
              shiftIndex(col, index: index, delta: delta, deleteCount: deleteCount)
            }
          )
        }
        sheet.autoFilter = filter
      } else {
        sheet.autoFilter = nil
      }
    }
    sheet.charts = sheet.charts.compactMap { chart in
      guard let range = shiftRange(chart.dataRange, axis: axis, index: index, delta: delta, deleteCount: deleteCount)
      else { return nil }
      var next = chart
      next.dataRange = range
      switch axis {
      case .row:
        if let anchor = shiftIndex(chart.anchorRow, index: index, delta: delta, deleteCount: deleteCount) {
          next.anchorRow = anchor
        } else {
          return nil
        }
      case .column:
        if let anchor = shiftIndex(chart.anchorCol, index: index, delta: delta, deleteCount: deleteCount) {
          next.anchorCol = anchor
        } else {
          return nil
        }
      }
      return next
    }
  }

  private static func shiftRange(
    _ range: CellRange,
    axis: Axis,
    index: Int,
    delta: Int,
    deleteCount: Int
  ) -> CellRange? {
    let n = range.normalized
    switch axis {
    case .row:
      guard let minRow = shiftIndex(n.minRow, index: index, delta: delta, deleteCount: deleteCount),
            let maxRow = shiftIndex(n.maxRow, index: index, delta: delta, deleteCount: deleteCount)
      else { return nil }
      return CellRange(
        start: CellAddress(row: minRow, col: n.minCol),
        end: CellAddress(row: maxRow, col: n.maxCol)
      )
    case .column:
      guard let minCol = shiftIndex(n.minCol, index: index, delta: delta, deleteCount: deleteCount),
            let maxCol = shiftIndex(n.maxCol, index: index, delta: delta, deleteCount: deleteCount)
      else { return nil }
      return CellRange(
        start: CellAddress(row: n.minRow, col: minCol),
        end: CellAddress(row: n.maxRow, col: maxCol)
      )
    }
  }

  private static func shiftIndex(_ value: Int, index: Int, delta: Int, deleteCount: Int) -> Int? {
    if delta < 0 {
      let end = index + deleteCount
      if value >= index && value < end { return nil }
      if value >= end { return value + delta }
      return value
    }
    if value >= index { return value + delta }
    return value
  }

  private static func shiftColumnMap(
    _ map: [Int: Set<String>],
    index: Int,
    delta: Int,
    deleteCount: Int
  ) -> [Int: Set<String>] {
    var result: [Int: Set<String>] = [:]
    for (key, value) in map {
      if let next = shiftIndex(key, index: index, delta: delta, deleteCount: deleteCount) {
        result[next] = value
      }
    }
    return result
  }

  private static func shiftKeyedValues(_ values: [Int: CGFloat], threshold: Int, delta: Int) -> [Int: CGFloat] {
    var result: [Int: CGFloat] = [:]
    for (key, value) in values {
      if key >= threshold {
        result[key + delta] = value
      } else {
        result[key] = value
      }
    }
    return result
  }

  private static func deleteKeyedValues(_ values: [Int: CGFloat], range: Range<Int>) -> [Int: CGFloat] {
    values.filter { !range.contains($0.key) }
  }
}
