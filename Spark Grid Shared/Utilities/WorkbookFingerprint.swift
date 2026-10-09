import CryptoKit
import Foundation

/// Stable dirty-state fingerprint without JSON-encoding every cell (large KPI workbooks
/// can hold hundreds of thousands of cells and spike memory on open).
enum WorkbookFingerprint {
  static func data(for workbook: Workbook) -> Data {
    var hasher = SHA256()
    update(hasher: &hasher, workbook: workbook)
    return Data(hasher.finalize())
  }

  private static func update(hasher: inout SHA256, workbook: Workbook) {
    hashInt(hasher: &hasher, workbook.activeSheetIndex)
    hashNamedRanges(hasher: &hasher, workbook.namedRanges)
    for sheet in workbook.sheets {
      hashSheet(hasher: &hasher, sheet)
    }
  }

  private static func hashSheet(hasher: inout SHA256, sheet: Sheet) {
    hashString(hasher: &hasher, sheet.id.uuidString)
    hashString(hasher: &hasher, sheet.name)
    hashInt(hasher: &hasher, sheet.frozenRows)
    hashInt(hasher: &hasher, sheet.frozenColumns)
    hashOptionalInt(hasher: &hasher, sheet.gridRowCount)
    hashOptionalInt(hasher: &hasher, sheet.gridColumnCount)

    for key in sheet.columnWidths.keys.sorted() {
      hashInt(hasher: &hasher, key)
      hashCGFloat(hasher: &hasher, sheet.columnWidths[key] ?? 0)
    }
    for key in sheet.rowHeights.keys.sorted() {
      hashInt(hasher: &hasher, key)
      hashCGFloat(hasher: &hasher, sheet.rowHeights[key] ?? 0)
    }

    for merge in sheet.mergedRanges {
      hashCellAddress(hasher: &hasher, merge.start)
      hashCellAddress(hasher: &hasher, merge.end)
    }

    hashConditionalFormats(hasher: &hasher, sheet.conditionalFormats)
    hashAutoFilter(hasher: &hasher, sheet.autoFilter)
    hashCharts(hasher: &hasher, sheet.charts)
    hashImages(hasher: &hasher, sheet.images)

    for address in sheet.cells.keys.sorted() {
      hashCell(hasher: &hasher, address: address, cell: sheet.cells[address] ?? Cell())
    }
  }

  private static func hashCell(hasher: inout SHA256, address: CellAddress, cell: Cell) {
    hashCellAddress(hasher: &hasher, address)
    hashString(hasher: &hasher, cell.raw)
    if let format = cell.format {
      hashCellFormat(hasher: &hasher, format)
    } else {
      hasher.update(Data([0]))
    }
  }

  private static func hashCellFormat(hasher: inout SHA256, format: CellFormat) {
    // Reuse JSON for format blobs — small compared to full-workbook encoding.
    if let encoded = try? JSONEncoder().encode(format) {
      hasher.update(encoded)
    }
  }

  private static func hashNamedRanges(hasher: inout SHA256, ranges: [String: NamedRange]) {
    for key in ranges.keys.sorted() {
      hashString(hasher: &hasher, key)
      if let encoded = try? JSONEncoder().encode(ranges[key]) {
        hasher.update(encoded)
      }
    }
  }

  private static func hashConditionalFormats(hasher: inout SHA256, rules: [ConditionalFormatRule]) {
    for rule in rules {
      if let encoded = try? JSONEncoder().encode(rule) {
        hasher.update(encoded)
      }
    }
  }

  private static func hashAutoFilter(hasher: inout SHA256, filter: SheetFilterState?) {
    guard let filter else {
      hasher.update(Data([0]))
      return
    }
    hasher.update(Data([1]))
    if let encoded = try? JSONEncoder().encode(filter) {
      hasher.update(encoded)
    }
  }

  private static func hashCharts(hasher: inout SHA256, charts: [SheetChart]) {
    for chart in charts {
      if let encoded = try? JSONEncoder().encode(chart) {
        hasher.update(encoded)
      }
    }
  }

  private static func hashImages(hasher: inout SHA256, images: [SheetImage]) {
    for image in images {
      hashInt(hasher: &hasher, image.anchorRow)
      hashInt(hasher: &hasher, image.anchorCol)
      hashInt(hasher: &hasher, image.widthEMU)
      hashInt(hasher: &hasher, image.heightEMU)
      hasher.update(image.imageData)
    }
  }

  private static func hashCellAddress(hasher: inout SHA256, address: CellAddress) {
    hashInt(hasher: &hasher, address.row)
    hashInt(hasher: &hasher, address.col)
  }

  private static func hashString(hasher: inout SHA256, value: String) {
    var length = UInt32(value.utf8.count).littleEndian
    withUnsafeBytes(of: length) { hasher.update(Data($0)) }
    hasher.update(Data(value.utf8))
  }

  private static func hashInt(hasher: inout SHA256, value: Int) {
    var little = Int64(value).littleEndian
    withUnsafeBytes(of: little) { hasher.update(Data($0)) }
  }

  private static func hashOptionalInt(hasher: inout SHA256, value: Int?) {
    guard let value else {
      hasher.update(Data([0]))
      return
    }
    hasher.update(Data([1]))
    hashInt(hasher: &hasher, value)
  }

  private static func hashCGFloat(hasher: inout SHA256, value: CGFloat) {
    var bits = Double(value).bitPattern.littleEndian
    withUnsafeBytes(of: bits) { hasher.update(Data($0)) }
  }
}
