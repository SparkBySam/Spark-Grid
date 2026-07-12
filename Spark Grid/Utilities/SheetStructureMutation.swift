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
