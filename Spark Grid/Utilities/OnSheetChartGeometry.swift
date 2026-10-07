import CoreGraphics

/// Cell-anchored frame for a chart drawn on the sheet grid.
enum OnSheetChartGeometry {
  static func frame(
    anchorRow: Int,
    anchorCol: Int,
    rowSpan: Int,
    colSpan: Int,
    rowCount: Int,
    columnCount: Int,
    xForColumn: (Int) -> CGFloat,
    yForRow: (Int) -> CGFloat,
    columnWidth: (Int) -> CGFloat,
    rowHeight: (Int) -> CGFloat
  ) -> CGRect {
    guard rowCount > 0, columnCount > 0, rowSpan > 0, colSpan > 0 else { return .zero }
    let row = min(max(0, anchorRow), rowCount - 1)
    let col = min(max(0, anchorCol), columnCount - 1)
    let rowEnd = min(rowCount, row + rowSpan)
    let colEnd = min(columnCount, col + colSpan)
    guard rowEnd > row, colEnd > col else { return .zero }
    var width: CGFloat = 0
    for column in col..<colEnd {
      width += columnWidth(column)
    }
    var height: CGFloat = 0
    for rowIndex in row..<rowEnd {
      height += rowHeight(rowIndex)
    }
    return CGRect(x: xForColumn(col), y: yForRow(row), width: width, height: height)
  }
}
