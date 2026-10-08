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

  /// Chart frame inside a layer that uses the grid's flipped viewport.
  /// `chartRect` is already in viewport coordinates: `yForRow` has applied
  /// scroll once. Subtract only the layer origin. A second scroll shift
  /// would slide the chart with the gesture instead of with its cells.
  static func hostFrame(chartRect: CGRect, layerFrame: CGRect) -> CGRect {
    CGRect(
      x: chartRect.minX - layerFrame.minX,
      y: chartRect.minY - layerFrame.minY,
      width: chartRect.width,
      height: chartRect.height
    )
  }

  /// Edge or corner of a selected chart. `body` is the interior, used to move it.
  enum ChartFrameHandle: Equatable {
    case body
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight
  }

  struct ChartFrameAnchor: Equatable {
    var anchorRow: Int
    var anchorCol: Int
    var rowSpan: Int
    var colSpan: Int
  }

  /// Which handle `point` lands on. Nil when it misses the frame, including the
  /// thin band just outside the border where a corner handle still counts.
  static func frameHandle(at point: CGPoint, in rect: CGRect, thickness: CGFloat) -> ChartFrameHandle? {
    guard rect.width >= 1, rect.height >= 1, thickness > 0 else { return nil }
    let hit = rect.insetBy(dx: -thickness / 2, dy: -thickness / 2)
    guard hit.contains(point) else { return nil }
    let nearLeft = abs(point.x - rect.minX) <= thickness
    let nearRight = abs(point.x - rect.maxX) <= thickness
    let nearTop = abs(point.y - rect.minY) <= thickness
    let nearBottom = abs(point.y - rect.maxY) <= thickness
    if nearTop && nearLeft { return .topLeft }
    if nearTop && nearRight { return .topRight }
    if nearBottom && nearLeft { return .bottomLeft }
    if nearBottom && nearRight { return .bottomRight }
    if nearLeft { return .left }
    if nearRight { return .right }
    if nearTop { return .top }
    if nearBottom { return .bottom }
    return rect.contains(point) ? .body : nil
  }

  /// New cell anchor after dragging `handle` by `translation`.
  /// Move keeps the span. Resize moves one edge, or both for a corner, and
  /// never shrinks below `minimumSpan`. Indexes come from the same column/row
  /// lookup the grid uses, so variable column widths still snap on cell borders.
  static func anchorAfterDrag(
    start: ChartFrameAnchor,
    handle: ChartFrameHandle,
    startRect: CGRect,
    translation: CGSize,
    minimumSpan: Int,
    rowLimit: Int,
    columnLimit: Int,
    columnAt: (CGFloat) -> Int,
    rowAt: (CGFloat) -> Int
  ) -> ChartFrameAnchor {
    let span = max(1, minimumSpan)
    if handle == .body {
      let originCol = columnAt(startRect.minX)
      let originRow = rowAt(startRect.minY)
      let nextCol = columnAt(startRect.minX + translation.width)
      let nextRow = rowAt(startRect.minY + translation.height)
      return ChartFrameAnchor(
        anchorRow: clampIndex(start.anchorRow + (nextRow - originRow), count: rowLimit),
        anchorCol: clampIndex(start.anchorCol + (nextCol - originCol), count: columnLimit),
        rowSpan: start.rowSpan,
        colSpan: start.colSpan
      )
    }

    var anchorCol = start.anchorCol
    var anchorRow = start.anchorRow
    var colSpan = start.colSpan
    var rowSpan = start.rowSpan
    let endCol = start.anchorCol + start.colSpan - 1
    let endRow = start.anchorRow + start.rowSpan - 1

    switch handle {
    case .left, .topLeft, .bottomLeft:
      let origin = columnAt(startRect.minX)
      let next = columnAt(startRect.minX + translation.width)
      let proposed = start.anchorCol + (next - origin)
      let maxAnchor = endCol - span + 1
      anchorCol = min(max(0, proposed), max(0, maxAnchor))
      colSpan = endCol - anchorCol + 1
    case .right, .topRight, .bottomRight:
      let edge = max(startRect.minX, startRect.maxX - 1)
      let origin = columnAt(edge)
      let next = columnAt(edge + translation.width)
      let proposedEnd = endCol + (next - origin)
      let minEnd = start.anchorCol + span - 1
      colSpan = max(minEnd, proposedEnd) - start.anchorCol + 1
    case .body, .top, .bottom:
      break
    }

    switch handle {
    case .top, .topLeft, .topRight:
      let origin = rowAt(startRect.minY)
      let next = rowAt(startRect.minY + translation.height)
      let proposed = start.anchorRow + (next - origin)
      let maxAnchor = endRow - span + 1
      anchorRow = min(max(0, proposed), max(0, maxAnchor))
      rowSpan = endRow - anchorRow + 1
    case .bottom, .bottomLeft, .bottomRight:
      let edge = max(startRect.minY, startRect.maxY - 1)
      let origin = rowAt(edge)
      let next = rowAt(edge + translation.height)
      let proposedEnd = endRow + (next - origin)
      let minEnd = start.anchorRow + span - 1
      rowSpan = max(minEnd, proposedEnd) - start.anchorRow + 1
    case .body, .left, .right:
      break
    }

    return ChartFrameAnchor(
      anchorRow: anchorRow,
      anchorCol: anchorCol,
      rowSpan: max(span, rowSpan),
      colSpan: max(span, colSpan)
    )
  }

  /// Preview height that follows the chart's column and row span.
  /// A wider chart is shorter; a taller chart is taller, inside the clamps.
  static func previewHeight(
    colSpan: Int,
    rowSpan: Int,
    width: CGFloat,
    minHeight: CGFloat = 140,
    maxHeight: CGFloat = 280
  ) -> CGFloat {
    let aspect = (CGFloat(max(1, colSpan)) * 80) / (CGFloat(max(1, rowSpan)) * 22)
    let raw = width / max(aspect, 0.25)
    return min(maxHeight, max(minHeight, raw))
  }

  private static func clampIndex(_ value: Int, count: Int) -> Int {
    guard count > 0 else { return 0 }
    return min(max(0, value), count - 1)
  }
}
