import CoreGraphics

/// Cell-anchored frame for a chart drawn on the sheet grid.
enum OnSheetChartGeometry {
  /// Height for a view that runs from `top` to `bottom`.
  /// `bottom - top` is negative when those edges are reversed (a scrolled or
  /// frozen row, or a row span that adds up below zero). SwiftUI traps on
  /// that value ("Invalid view geometry: height is negative"), so callers
  /// must skip the view instead of passing it through.
  static func placedHeight(top: CGFloat, bottom: CGFloat) -> CGFloat? {
    let height = bottom - top
    guard height.isFinite, height >= 1 else { return nil }
    return height
  }

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
    let top = yForRow(row)
    var bottom = top
    for rowIndex in row..<rowEnd {
      bottom += rowHeight(rowIndex)
    }
    guard width.isFinite, width >= 1, let height = placedHeight(top: top, bottom: bottom) else {
      return .zero
    }
    return CGRect(x: xForColumn(col), y: top, width: width, height: height)
  }
}
