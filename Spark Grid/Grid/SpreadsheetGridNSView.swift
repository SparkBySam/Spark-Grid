import AppKit

/// AppKit spreadsheet grid with sticky row/column headers, selection, editing, and keyboard navigation.
final class SpreadsheetGridNSView: NSView {
  static let baseHeaderSize: CGFloat = 28
  static let headerSize: CGFloat = 28 // unscaled; prefer instance `headerSize` for layout
  static let defaultColumnWidth = Workbook.defaultColumnWidth
  static let defaultRowHeight = Workbook.defaultRowHeight
  /// Mid-contrast hairline that reads on both dark empty cells and light fills.
  private static let darkModeGridLine = NSColor(calibratedWhite: 0.54, alpha: 0.30)
  private static let lightModeGridLine = NSColor(white: 0, alpha: 0.24)

  var viewModel: SpreadsheetViewModel? {
    didSet {
      guard viewModel !== oldValue else { return }
      invalidateLayoutCache()
      needsDisplay = true
    }
  }

  private var zoomScale: CGFloat { max(0.5, min(2.0, viewModel?.zoomScale ?? 1)) }

  /// Zoom-scaled header band size.
  private var headerSize: CGFloat { Self.baseHeaderSize * zoomScale }

  private var scrollOrigin = CGPoint.zero
  private var cachedColumnOffsets: [CGFloat]?
  private var cachedRowOffsets: [CGFloat]?
  private var cachedColumnCount = 0
  private var cachedRowCount = 0
  /// Previous selection dirty region — avoids full-grid redraws on click/drag.
  private var lastSelectionDirtyRect: NSRect = .null
  private let editor = NSTextField()
  private var isEditorActive = false

  private enum EditorEntryMode {
  /// Started by typing over a selected cell — arrow keys save and move selection.
    case replaceOnType
  /// Started by double-click or Enter — arrow keys move the text cursor.
    case inCellEdit
  }

  private var editorEntryMode: EditorEntryMode = .inCellEdit
  private var isDraggingSelection = false
  private var isDraggingFill = false
  private enum ImageResizeCorner { case bottomRight }
  private struct ImageDragState {
    enum Mode {
      case move
      case resize(ImageResizeCorner)
    }
    let imageID: UUID
    let mode: Mode
    let startPoint: NSPoint
    let startImage: SheetImage
  }
  private var activeImageDrag: ImageDragState?
  private var fillSourceRange: CellRange?
  private var headerDrag: HeaderDrag?
  private let resizeHandleThickness: CGFloat = 6
  private let fillHandleSize: CGFloat = 9
  private var editorCaretObserver: NSObjectProtocol?
  private var isApplyingFormulaAttributes = false
  private var lastAppliedFormulaHighlightKey = ""

  private enum HeaderDrag {
    case columns(anchor: Int)
    case rows(anchor: Int)
  }

  private enum ResizeTarget {
    case column(Int, startWidth: CGFloat, startX: CGFloat)
    case row(Int, startHeight: CGFloat, startY: CGFloat)
  }

  private var activeResize: ResizeTarget?

  private enum HeaderHit {
    case corner
    case column(Int)
    case row(Int)
    case content
  }

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  private var contentRect: NSRect {
    NSRect(
      x: headerSize,
      y: headerSize,
      width: max(0, bounds.width - headerSize),
      height: max(0, bounds.height - headerSize)
    )
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  private func gridLineColor() -> NSColor {
    switch effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
    case .darkAqua:
      return Self.darkModeGridLine
    default:
      return Self.lightModeGridLine
    }
  }

  private func headerLineColor() -> NSColor {
    switch effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
    case .darkAqua:
      return Self.darkModeGridLine
    default:
      return NSColor.separatorColor.withAlphaComponent(0.92)
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    configureEditor()
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas {
      removeTrackingArea(area)
    }
    let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseMoved, .inVisibleRect, .enabledDuringMouseDrag]
    addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
  }

  override func resetCursorRects() {
    super.resetCursorRects()
    updateCursorRects()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func resetScrollPosition() {
    scrollOrigin = .zero
    needsDisplay = true
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard window != nil else {
      claimedInitialFocus = false
      return
    }
    claimInitialFocusIfNeeded()
  }

  private var claimedInitialFocus = false

  func claimInitialFocusIfNeeded() {
    guard !claimedInitialFocus, window != nil else { return }
    claimedInitialFocus = true
    DispatchQueue.main.async { [weak self] in
      DispatchQueue.main.async {
        guard let self, let window = self.window else { return }
        window.makeFirstResponder(self)
      }
    }
  }

  private func configureEditor() {
    editor.isBordered = false
    editor.isBezeled = false
    editor.focusRingType = .none
    editor.drawsBackground = false
    editor.backgroundColor = .clear
    editor.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    editor.delegate = self
    editor.isHidden = true
    addSubview(editor)

    editorCaretObserver = NotificationCenter.default.addObserver(
      forName: NSTextView.didChangeSelectionNotification,
      object: nil,
      queue: .main
    ) { [weak self] note in
      guard let self, self.isEditorActive, !self.isApplyingFormulaAttributes,
            let textView = note.object as? NSTextView,
            self.editor.currentEditor() === textView
      else { return }
      // Only update which ref is focused for grid borders — do not rewrite
      // attributed text here (that retriggers selection and freezes the app).
      self.viewModel?.updateFormulaHighlightFocus(atUTF16: textView.selectedRange.location)
    }
  }

  // MARK: - Layout helpers

  private func columnWidth(at col: Int) -> CGFloat {
    guard let sheet = viewModel?.activeSheet else { return Self.defaultColumnWidth * zoomScale }
    return sheet.columnWidth(for: col, default: Self.defaultColumnWidth) * zoomScale
  }

  private func rowHeight(at row: Int) -> CGFloat {
    if viewModel?.isRowHiddenByFilter(row) == true { return 0 }
    guard let sheet = viewModel?.activeSheet else { return Self.defaultRowHeight * zoomScale }
    return sheet.rowHeight(for: row, default: Self.defaultRowHeight) * zoomScale
  }

  private func frozenColumnCount() -> Int {
    viewModel?.activeSheet.frozenColumns ?? 0
  }

  private func frozenRowCount() -> Int {
    viewModel?.activeSheet.frozenRows ?? 0
  }

  private func frozenColumnBoundaryX() -> CGFloat {
    let frozen = frozenColumnCount()
    guard frozen > 0 else { return headerSize }
    return headerSize + columnOffsets()[frozen]
  }

  private func frozenRowBoundaryY() -> CGFloat {
    let frozen = frozenRowCount()
    guard frozen > 0 else { return headerSize }
    return headerSize + rowOffsets()[frozen]
  }

  private func headerColumnIndices() -> [Int] {
    let frozen = frozenColumnCount()
    var columns: [Int] = []
    if frozen > 0 {
      for col in 0..<frozen where shouldDrawColumnHeader(col) {
        columns.append(col)
      }
    }
    for col in visibleColumnRange() where col >= frozen && shouldDrawColumnHeader(col) {
      columns.append(col)
    }
    return columns
  }

  private func headerRowIndices() -> [Int] {
    let frozen = frozenRowCount()
    var rows: [Int] = []
    if frozen > 0 {
      for row in 0..<frozen where shouldDrawRowHeader(row) {
        rows.append(row)
      }
    }
    for row in visibleRowRange() where row >= frozen && shouldDrawRowHeader(row) {
      rows.append(row)
    }
    return rows
  }

  private func invalidateLayoutCache() {
    cachedColumnOffsets = nil
    cachedRowOffsets = nil
    cachedColumnCount = 0
    cachedRowCount = 0
  }

  private func columnOffsets() -> [CGFloat] {
    let count = columnCount()
    if let cached = cachedColumnOffsets, cachedColumnCount == count {
      return cached
    }
    var offsets = [CGFloat](repeating: 0, count: count + 1)
    for col in 0..<count {
      offsets[col + 1] = offsets[col] + columnWidth(at: col)
    }
    cachedColumnOffsets = offsets
    cachedColumnCount = count
    return offsets
  }

  private func rowOffsets() -> [CGFloat] {
    let count = rowCount()
    if let cached = cachedRowOffsets, cachedRowCount == count {
      return cached
    }
    var offsets = [CGFloat](repeating: 0, count: count + 1)
    for row in 0..<count {
      offsets[row + 1] = offsets[row] + rowHeight(at: row)
    }
    cachedRowOffsets = offsets
    cachedRowCount = count
    return offsets
  }

  private func indexAtOffset(_ offsets: [CGFloat], position: CGFloat, lowerBound: Int, upperBound: Int) -> Int {
    guard upperBound > lowerBound else { return lowerBound }
    var lo = lowerBound
    var hi = upperBound - 1
    while lo < hi {
      let mid = (lo + hi + 1) / 2
      if offsets[mid] <= position {
        lo = mid
      } else {
        hi = mid - 1
      }
    }
    return lo
  }

  private func widthOfColumns(from: Int, to: Int) -> CGFloat {
    guard to > from else { return 0 }
    let offsets = columnOffsets()
    return offsets[to] - offsets[from]
  }

  private func heightOfRows(from: Int, to: Int) -> CGFloat {
    guard to > from else { return 0 }
    let offsets = rowOffsets()
    return offsets[to] - offsets[from]
  }

  private func xForColumn(_ col: Int) -> CGFloat {
    let offsets = columnOffsets()
    let modelX = offsets[col]
    if col < frozenColumnCount() {
      return headerSize + modelX
    }
    return headerSize + modelX - scrollOrigin.x
  }

  private func yForRow(_ row: Int) -> CGFloat {
    let offsets = rowOffsets()
    let modelY = offsets[row]
    if row < frozenRowCount() {
      return headerSize + modelY
    }
    return headerSize + modelY - scrollOrigin.y
  }

  private func rowCount() -> Int {
    viewModel?.activeSheet.effectiveRowCount ?? Workbook.defaultRowCount
  }

  private func columnCount() -> Int {
    viewModel?.activeSheet.effectiveColumnCount ?? Workbook.defaultColumnCount
  }

  private func columnAtContent(x: CGFloat) -> Int {
    let count = columnCount()
    let offsets = columnOffsets()
    let frozen = frozenColumnCount()
    let frozenEndX = frozenColumnBoundaryX()

    if x < frozenEndX {
      let position = max(0, x - headerSize)
      return indexAtOffset(offsets, position: position, lowerBound: 0, upperBound: frozen)
    }

    let position = max(0, x - headerSize + scrollOrigin.x)
    return indexAtOffset(offsets, position: position, lowerBound: frozen, upperBound: count)
  }

  private func rowAtContent(y: CGFloat) -> Int {
    let count = rowCount()
    let offsets = rowOffsets()
    let frozen = frozenRowCount()
    let frozenEndY = frozenRowBoundaryY()
    let totalHeight = offsets[count]

    let position: CGFloat
    let lower: Int
    let upper: Int
    if y < frozenEndY {
      position = max(0, y - headerSize)
      lower = 0
      upper = max(frozen, 1)
    } else {
      position = max(0, y - headerSize + scrollOrigin.y)
      lower = frozen
      upper = count
    }

    // Clicking in empty space below all laid-out rows used to land on the last
    // zero-height (filter-hidden) index — e.g. row 1000. Clamp to content.
    if totalHeight <= 0 {
      return lower
    }
    if position >= totalHeight {
      return lastVisibleRow(in: lower..<(upper == 0 ? 1 : upper)) ?? max(lower, upper - 1)
    }

    var row = indexAtOffset(offsets, position: min(position, totalHeight - 0.001), lowerBound: lower, upperBound: upper)
    if rowHeight(at: row) == 0 {
      row = nearestVisibleRow(from: row, lowerBound: lower, upperBound: upper) ?? row
    }
    return row
  }

  private func lastVisibleRow(in range: Range<Int>) -> Int? {
    for row in stride(from: range.upperBound - 1, through: range.lowerBound, by: -1) {
      if rowHeight(at: row) > 0 { return row }
    }
    return nil
  }

  private func nearestVisibleRow(from row: Int, lowerBound: Int, upperBound: Int) -> Int? {
    if rowHeight(at: row) > 0 { return row }
    var down = row + 1
    var up = row - 1
    while down < upperBound || up >= lowerBound {
      if down < upperBound {
        if rowHeight(at: down) > 0 { return down }
        down += 1
      }
      if up >= lowerBound {
        if rowHeight(at: up) > 0 { return up }
        up -= 1
      }
    }
    return nil
  }

  /// Bottom Y of the laid-out sheet content inside the scrollable area (not the viewport bottom).
  private func contentBottomY() -> CGFloat {
    let offsets = rowOffsets()
    let total = offsets[rowCount()]
    return headerSize + total - scrollOrigin.y
  }

  private func rectForCell(row: Int, col: Int) -> NSRect {
    NSRect(
      x: xForColumn(col),
      y: yForRow(row),
      width: columnWidth(at: col),
      height: rowHeight(at: row)
    )
  }

  /// Paint rect for a cell, spanning merges at the anchor. Returns nil for covered (non-anchor) cells.
  private func paintRect(for address: CellAddress, sheet: Sheet) -> NSRect? {
    if sheet.isCoveredByMerge(address) { return nil }
    if let merge = sheet.mergeContaining(address) {
      let n = merge.normalized
      let topLeft = rectForCell(row: n.minRow, col: n.minCol)
      let bottomRight = rectForCell(row: n.maxRow, col: n.maxCol)
      return topLeft.union(bottomRight)
    }
    return rectForCell(row: address.row, col: address.col)
  }

  private func fillHandleRect() -> NSRect? {
    guard let viewModel, !viewModel.isEditing, !isEditorActive else { return nil }
    guard !viewModel.hasMultipleSelectionRanges else { return nil }
    let range = (viewModel.selectionRanges.last ?? viewModel.selectionRange).normalized
    // Filter chip owns the SE corner on header cells — hide the handle so they don't fight.
    if viewModel.isFilterHeaderCell(row: range.maxRow, col: range.maxCol) { return nil }
    guard visibleRowRange().contains(range.maxRow),
          visibleColumnRange().contains(range.maxCol) else { return nil }
    let cell = rectForCell(row: range.maxRow, col: range.maxCol)
    guard isCellRectInContentArea(cell) else { return nil }
    let size = fillHandleSize
    return NSRect(
      x: cell.maxX - size / 2,
      y: cell.maxY - size / 2,
      width: size,
      height: size
    )
  }

  private func isPointInFillHandle(_ point: NSPoint) -> Bool {
    guard let rect = fillHandleRect() else { return false }
    return rect.insetBy(dx: -2, dy: -2).contains(point)
  }

  private func isCellRectInContentArea(_ rect: NSRect) -> Bool {
    rect.maxX > headerSize
      && rect.maxY > headerSize
      && rect.minX < bounds.width
      && rect.minY < bounds.height
  }

  private func visibleColumnRange() -> ClosedRange<Int> {
    let content = contentRect
    let first = max(0, columnAtContent(x: content.minX))
    let last = min(columnCount() - 1, columnAtContent(x: content.maxX))
    return first...last
  }

  private func visibleRowRange() -> ClosedRange<Int> {
    let content = contentRect
    let first = max(0, rowAtContent(y: content.minY))
    let last = min(rowCount() - 1, rowAtContent(y: content.maxY))
    return first...last
  }

  private func totalContentSize() -> NSSize {
    let colOffsets = columnOffsets()
    let rowOff = rowOffsets()
    return NSSize(
      width: headerSize + colOffsets[columnCount()],
      height: headerSize + rowOff[rowCount()]
    )
  }

  private func clampScrollOrigin() {
    let frozenCols = frozenColumnCount()
    let frozenRows = frozenRowCount()
    let scrollableWidth = widthOfColumns(from: frozenCols, to: columnCount())
    let scrollableHeight = heightOfRows(from: frozenRows, to: rowCount())
    let visibleScrollableWidth = max(0, contentRect.width - widthOfColumns(from: 0, to: frozenCols))
    let visibleScrollableHeight = max(0, contentRect.height - heightOfRows(from: 0, to: frozenRows))
    let maxX = max(0, scrollableWidth - visibleScrollableWidth)
    let maxY = max(0, scrollableHeight - visibleScrollableHeight)
    scrollOrigin.x = min(max(0, scrollOrigin.x), maxX)
    scrollOrigin.y = min(max(0, scrollOrigin.y), maxY)
  }

  private func ensureSelectionVisible() {
    guard let viewModel else { return }
    let anchor = rectForCell(row: viewModel.selectionAnchor.row, col: viewModel.selectionAnchor.col)
    let visible = contentRect
    if anchor.minX < visible.minX {
      scrollOrigin.x -= visible.minX - anchor.minX
    } else if anchor.maxX > visible.maxX {
      scrollOrigin.x += anchor.maxX - visible.maxX
    }
    if anchor.minY < visible.minY {
      scrollOrigin.y -= visible.minY - anchor.minY
    } else if anchor.maxY > visible.maxY {
      scrollOrigin.y += anchor.maxY - visible.maxY
    }
    clampScrollOrigin()
  }

  private func headerHit(at point: NSPoint) -> HeaderHit {
    if point.x < headerSize && point.y < headerSize { return .corner }
    if point.y < headerSize && point.x >= headerSize {
      return .column(columnAtContent(x: point.x))
    }
    if point.x < headerSize && point.y >= headerSize {
      return .row(rowAtContent(y: point.y))
    }
    if contentRect.contains(point) { return .content }
    return .content
  }

  private func addressAtContent(point: NSPoint) -> CellAddress {
    CellAddress(
      row: rowAtContent(y: point.y),
      col: columnAtContent(x: point.x)
    )
  }

  private func columnHeaderRect(for col: Int) -> NSRect {
    NSRect(
      x: xForColumn(col),
      y: 0,
      width: columnWidth(at: col),
      height: headerSize
    )
  }

  private func rowHeaderRect(for row: Int) -> NSRect {
    NSRect(
      x: 0,
      y: yForRow(row),
      width: headerSize,
      height: rowHeight(at: row)
    )
  }

  private func shouldDrawColumnHeader(_ col: Int) -> Bool {
    let rect = columnHeaderRect(for: col)
    let leftClip = frozenColumnCount() > 0 ? frozenColumnBoundaryX() : headerSize
    // Keep partially scrolled headers visible (clip draws the visible sliver).
    if col < frozenColumnCount() {
      return rect.maxX > headerSize && rect.minX < bounds.width
    }
    return rect.maxX > leftClip && rect.minX < bounds.width
  }

  private func shouldDrawRowHeader(_ row: Int) -> Bool {
    guard rowHeight(at: row) > 0.5 else { return false }
    let rect = rowHeaderRect(for: row)
    let topClip = frozenRowCount() > 0 ? frozenRowBoundaryY() : headerSize
    if row < frozenRowCount() {
      return rect.maxY > headerSize && rect.minY < bounds.height
    }
    return rect.maxY > topClip && rect.minY < bounds.height
  }

  private func resizeTarget(at point: NSPoint) -> ResizeTarget? {
    // Double-click zone: left edge of column A (against the corner) → auto-fit all columns.
    // Top edge of row 1 (against the corner) → auto-fit all rows.
    if point.y < headerSize, point.x >= headerSize {
      let col = columnAtContent(x: point.x)
      let rect = columnHeaderRect(for: col)

      if col == 0, abs(point.x - headerSize) <= resizeHandleThickness {
        return .column(0, startWidth: columnWidth(at: 0), startX: point.x)
      }

      if col > 0 {
        let leftBorder = rect.minX
        if abs(point.x - leftBorder) <= resizeHandleThickness {
          let previous = col - 1
          return .column(previous, startWidth: columnWidth(at: previous), startX: point.x)
        }
      }

      if abs(point.x - rect.maxX) <= resizeHandleThickness {
        return .column(col, startWidth: rect.width, startX: point.x)
      }
    }

    if point.x < headerSize, point.y >= headerSize {
      let row = rowAtContent(y: point.y)
      let rect = rowHeaderRect(for: row)

      if row == 0, abs(point.y - headerSize) <= resizeHandleThickness {
        return .row(0, startHeight: rowHeight(at: 0), startY: point.y)
      }

      if row > 0 {
        let topBorder = rect.minY
        if abs(point.y - topBorder) <= resizeHandleThickness {
          let previous = row - 1
          return .row(previous, startHeight: rowHeight(at: previous), startY: point.y)
        }
      }

      if abs(point.y - rect.maxY) <= resizeHandleThickness {
        return .row(row, startHeight: rect.height, startY: point.y)
      }
    }

    return nil
  }

  private func updateCursor(for point: NSPoint) {
    guard activeResize == nil else { return }
    if isPointInFillHandle(point) {
      NSCursor.crosshair.set()
      return
    }
    switch resizeTarget(at: point) {
    case .column:
      NSCursor.resizeLeftRight.set()
    case .row:
      NSCursor.resizeUpDown.set()
    default:
      NSCursor.arrow.set()
    }
  }

  private func updateCursorRects() {
    discardCursorRects()
    let colRange = visibleColumnRange()
    for col in colRange {
      let rect = columnHeaderRect(for: col)
      let rightHandle = NSRect(
        x: rect.maxX - resizeHandleThickness / 2,
        y: rect.minY,
        width: resizeHandleThickness,
        height: rect.height
      )
      if rightHandle.maxX > headerSize {
        addCursorRect(rightHandle, cursor: .resizeLeftRight)
      }

      if col > 0 {
        let leftHandle = NSRect(
          x: rect.minX - resizeHandleThickness / 2,
          y: rect.minY,
          width: resizeHandleThickness,
          height: rect.height
        )
        if leftHandle.maxX > headerSize {
          addCursorRect(leftHandle, cursor: .resizeLeftRight)
        }
      }
    }

    let rowRange = visibleRowRange()
    for row in rowRange {
      let rect = rowHeaderRect(for: row)
      let bottomHandle = NSRect(
        x: rect.minX,
        y: rect.maxY - resizeHandleThickness / 2,
        width: rect.width,
        height: resizeHandleThickness
      )
      if bottomHandle.maxY > headerSize {
        addCursorRect(bottomHandle, cursor: .resizeUpDown)
      }

      if row > 0 {
        let topHandle = NSRect(
          x: rect.minX,
          y: rect.minY - resizeHandleThickness / 2,
          width: rect.width,
          height: resizeHandleThickness
        )
        if topHandle.maxY > headerSize {
          addCursorRect(topHandle, cursor: .resizeUpDown)
        }
      }
    }
  }

  // MARK: - Drawing

  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    dirtyRect.fill()

  // 1. Cells first, then gridlines on top so hairlines stay even over fills.
    let skipGridlines = visibleRegionIsMostlyBordered()
    if let ctx = NSGraphicsContext.current {
      ctx.saveGraphicsState()
      NSBezierPath(rect: contentRect).addClip()
      drawCells(in: dirtyRect)
      drawImages(in: dirtyRect)
      if !skipGridlines {
        drawGridLines(in: dirtyRect)
      }
      drawSelection(in: dirtyRect)
      drawFormulaReferenceHighlights(in: dirtyRect)
      ctx.restoreGraphicsState()
    }

    // 2. Frozen panes redrawn on top so scrolled content cannot bleed through.
    if frozenRowCount() > 0 || frozenColumnCount() > 0 {
      if let ctx = NSGraphicsContext.current {
        ctx.saveGraphicsState()
        NSBezierPath(rect: contentRect).addClip()
        drawFrozenCells(in: dirtyRect)
        if !skipGridlines {
          drawFrozenGridLines(in: dirtyRect)
        }
        ctx.restoreGraphicsState()
      }
    }

    // 2.5 Opaque header gutters so scrolled cells cannot bleed into labels.
    NSColor.controlBackgroundColor.setFill()
    if dirtyRect.intersects(NSRect(x: 0, y: 0, width: bounds.width, height: headerSize)) {
      NSRect(x: 0, y: 0, width: bounds.width, height: headerSize).fill()
    }
    if dirtyRect.intersects(NSRect(x: 0, y: 0, width: headerSize, height: bounds.height)) {
      NSRect(x: 0, y: 0, width: headerSize, height: bounds.height).fill()
    }

    // 3. Sticky headers drawn on top so scrolled cell text cannot bleed through.
    drawStickyHeaders(in: dirtyRect)
    drawFreezeDividers(in: dirtyRect)
    drawHeaderCorner(in: dirtyRect)
  }

  private enum GridLineRegion {
    case scrollable
    case frozenCorner
    case frozenTop
    case frozenLeft
  }

  private func columnIncludedInGridLines(_ col: Int, region: GridLineRegion, frozenCols: Int) -> Bool {
    switch region {
    case .scrollable: col >= frozenCols
    case .frozenCorner, .frozenLeft: col < frozenCols
    case .frozenTop: col >= frozenCols
    }
  }

  private func rowIncludedInGridLines(_ row: Int, region: GridLineRegion, frozenRows: Int) -> Bool {
    switch region {
    case .scrollable: row >= frozenRows
    case .frozenCorner, .frozenTop: row < frozenRows
    case .frozenLeft: row >= frozenRows
    }
  }

  private func scrollableCellsClipRect() -> NSRect {
    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()
    let top = frozenRows > 0 ? frozenRowBoundaryY() : contentRect.minY
    let left = frozenCols > 0 ? frozenColumnBoundaryX() : contentRect.minX
    return NSRect(
      x: max(contentRect.minX, left),
      y: max(contentRect.minY, top),
      width: max(0, contentRect.maxX - max(contentRect.minX, left)),
      height: max(0, contentRect.maxY - max(contentRect.minY, top))
    )
  }

  private func frozenCellsClipRect() -> NSRect {
    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()
    guard frozenRows > 0, frozenCols > 0 else { return .zero }
    return NSRect(
      x: contentRect.minX,
      y: contentRect.minY,
      width: max(0, frozenColumnBoundaryX() - contentRect.minX),
      height: max(0, frozenRowBoundaryY() - contentRect.minY)
    )
  }

  private func frozenTopStripClipRect() -> NSRect {
    let frozenRows = frozenRowCount()
    guard frozenRows > 0 else { return .zero }
    let left = frozenColumnCount() > 0 ? frozenColumnBoundaryX() : contentRect.minX
    return NSRect(
      x: max(contentRect.minX, left),
      y: contentRect.minY,
      width: max(0, contentRect.maxX - max(contentRect.minX, left)),
      height: max(0, frozenRowBoundaryY() - contentRect.minY)
    )
  }

  private func frozenLeftStripClipRect() -> NSRect {
    let frozenCols = frozenColumnCount()
    guard frozenCols > 0 else { return .zero }
    let top = frozenRowCount() > 0 ? frozenRowBoundaryY() : contentRect.minY
    return NSRect(
      x: contentRect.minX,
      y: max(contentRect.minY, top),
      width: max(0, frozenColumnBoundaryX() - contentRect.minX),
      height: max(0, contentRect.maxY - max(contentRect.minY, top))
    )
  }

  private func drawStickyHeaders(in dirtyRect: NSRect) {
    let headerFill = NSColor.controlBackgroundColor
    let headerText = NSColor.secondaryLabelColor
    let selectionFill = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.12)
    let accent = NSColor.controlAccentColor
    let gridLine = headerLineColor()
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11, weight: .medium),
      .foregroundColor: headerText,
    ]
    let isSheetSelection = viewModel?.selectionAxis == .sheet
    let isColumnSelected: (Int) -> Bool = { [self] col in
      self.viewModel?.isColumnInSelection(col) ?? false
    }
    let isRowSelected: (Int) -> Bool = { [self] row in
      self.viewModel?.isRowInSelection(row) ?? false
    }

    // Opaque header bands (cover any scrolled cell text underneath).
    let topBand = NSRect(x: 0, y: 0, width: bounds.width, height: headerSize)
    if dirtyRect.intersects(topBand) {
      headerFill.setFill()
      topBand.fill()
    }
    let leftBand = NSRect(x: 0, y: 0, width: headerSize, height: bounds.height)
    if dirtyRect.intersects(leftBand) {
      headerFill.setFill()
      leftBand.fill()
    }

    // Column headers (fixed vertically, scroll horizontally).
    NSGraphicsContext.saveGraphicsState()
    let columnHeaderClip = NSRect(
      x: headerSize,
      y: 0,
      width: max(0, bounds.width - headerSize),
      height: headerSize
    )
    NSBezierPath(rect: columnHeaderClip).addClip()
    if frozenColumnCount() > 0 {
      let frozenHeaderBand = NSRect(
        x: headerSize,
        y: 0,
        width: max(0, frozenColumnBoundaryX() - headerSize),
        height: headerSize
      )
      headerFill.setFill()
      frozenHeaderBand.fill()
      let scrollableHeaderBand = NSRect(
        x: frozenColumnBoundaryX(),
        y: 0,
        width: max(0, bounds.width - frozenColumnBoundaryX()),
        height: headerSize
      )
      scrollableHeaderBand.fill()
    }
    if isSheetSelection, dirtyRect.intersects(columnHeaderClip) {
      selectionFill.setFill()
      columnHeaderClip.fill()
      accent.setStroke()
      let border = NSBezierPath()
      border.lineWidth = 2
      border.move(to: NSPoint(x: columnHeaderClip.minX, y: columnHeaderClip.maxY - 1))
      border.line(to: NSPoint(x: columnHeaderClip.maxX, y: columnHeaderClip.maxY - 1))
      border.stroke()
    }
    let colRange = headerColumnIndices()
    for col in colRange {
      let rect = columnHeaderRect(for: col)
      let drawRect = rect.intersection(columnHeaderClip)
      guard !drawRect.isEmpty, dirtyRect.intersects(drawRect) else { continue }
      if !isSheetSelection {
        let isSelected = isColumnSelected(col)
        (isSelected ? selectionFill : headerFill).setFill()
        drawRect.fill()
      }
      let label = A1Notation.columnLabel(for: col) as NSString
      let size = label.size(withAttributes: attrs)
      label.draw(
        at: NSPoint(x: drawRect.midX - size.width / 2, y: drawRect.midY - size.height / 2),
        withAttributes: attrs
      )
      if !isSheetSelection {
        let isSelected = isColumnSelected(col)
        if isSelected {
          accent.setStroke()
          let border = NSBezierPath()
          border.lineWidth = 2
          border.move(to: NSPoint(x: drawRect.minX + 0.5, y: drawRect.maxY - 1))
          border.line(to: NSPoint(x: drawRect.maxX - 0.5, y: drawRect.maxY - 1))
          border.stroke()
        }
      }
      gridLine.setStroke()
      let boundaryX = frozenColumnBoundaryX()
      if abs(rect.maxX - boundaryX) > 0.5 {
        NSBezierPath.strokeLine(from: NSPoint(x: rect.maxX, y: 0), to: NSPoint(x: rect.maxX, y: headerSize))
      }
    }
    NSGraphicsContext.restoreGraphicsState()

    // Row headers (fixed horizontally, scroll vertically).
    NSGraphicsContext.saveGraphicsState()
    let rowHeaderClip = NSRect(
      x: 0,
      y: headerSize,
      width: headerSize,
      height: max(0, bounds.height - headerSize)
    )
    NSBezierPath(rect: rowHeaderClip).addClip()
    if frozenRowCount() > 0 {
      let frozenHeaderBand = NSRect(
        x: 0,
        y: headerSize,
        width: headerSize,
        height: max(0, frozenRowBoundaryY() - headerSize)
      )
      headerFill.setFill()
      frozenHeaderBand.fill()
      let scrollableHeaderBand = NSRect(
        x: 0,
        y: frozenRowBoundaryY(),
        width: headerSize,
        height: max(0, bounds.height - frozenRowBoundaryY())
      )
      scrollableHeaderBand.fill()
    }
    if isSheetSelection, dirtyRect.intersects(rowHeaderClip) {
      selectionFill.setFill()
      rowHeaderClip.fill()
      accent.setStroke()
      let border = NSBezierPath()
      border.lineWidth = 2
      border.move(to: NSPoint(x: rowHeaderClip.maxX - 1, y: rowHeaderClip.minY))
      border.line(to: NSPoint(x: rowHeaderClip.maxX - 1, y: rowHeaderClip.maxY))
      border.stroke()
    }
    let rowRange = headerRowIndices()
    for row in rowRange {
      let rect = rowHeaderRect(for: row)
      let drawRect = rect.intersection(rowHeaderClip)
      guard !drawRect.isEmpty, dirtyRect.intersects(drawRect) else { continue }
      if !isSheetSelection {
        let isSelected = isRowSelected(row)
        (isSelected ? selectionFill : headerFill).setFill()
        drawRect.fill()
      }
      let label = "\(row + 1)" as NSString
      let size = label.size(withAttributes: attrs)
      label.draw(
        at: NSPoint(x: drawRect.midX - size.width / 2, y: drawRect.midY - size.height / 2),
        withAttributes: attrs
      )
      if !isSheetSelection {
        let isSelected = isRowSelected(row)
        if isSelected {
          accent.setStroke()
          let border = NSBezierPath()
          border.lineWidth = 2
          border.move(to: NSPoint(x: drawRect.maxX - 1, y: drawRect.minY + 0.5))
          border.line(to: NSPoint(x: drawRect.maxX - 1, y: drawRect.maxY - 0.5))
          border.stroke()
        }
      }
      gridLine.setStroke()
      let boundaryY = frozenRowBoundaryY()
      if abs(rect.maxY - boundaryY) > 0.5 {
        NSBezierPath.strokeLine(from: NSPoint(x: 0, y: rect.maxY), to: NSPoint(x: headerSize, y: rect.maxY))
      }
    }
    NSGraphicsContext.restoreGraphicsState()
  }

  private func drawHeaderCorner(in dirtyRect: NSRect) {
    let headerFill = NSColor.controlBackgroundColor
    let selectionFill = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.12)
    let isSheetSelection = viewModel?.selectionAxis == .sheet
    let gridLine = headerLineColor()

    let corner = NSRect(x: 0, y: 0, width: headerSize, height: headerSize)
    guard dirtyRect.intersects(corner) else { return }
    (isSheetSelection ? selectionFill : headerFill).setFill()
    corner.fill()
    gridLine.setStroke()
    NSBezierPath.strokeLine(from: NSPoint(x: corner.maxX, y: 0), to: NSPoint(x: corner.maxX, y: corner.maxY))
    NSBezierPath.strokeLine(from: NSPoint(x: 0, y: corner.maxY), to: NSPoint(x: corner.maxX, y: corner.maxY))
  }

  private func drawGridLinesInClip(
    dirtyRect: NSRect,
    region: GridLineRegion,
    clipRect: NSRect
  ) {
    guard !clipRect.isEmpty else { return }

    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()
    let frozenBoundaryX = frozenColumnBoundaryX()
    let frozenBoundaryY = frozenRowBoundaryY()

    gridLineColor().setStroke()
    let path = NSBezierPath()
    path.lineWidth = 0.5
    let content = contentRect
    // Don't extend gridlines into empty viewport below the last laid-out row
    // (important when filter-hidden rows collapse height).
    let sheetBottom = min(content.maxY, max(content.minY, contentBottomY()))
    let gridBounds = NSRect(
      x: content.minX,
      y: content.minY,
      width: content.width,
      height: max(0, sheetBottom - content.minY)
    )
    guard gridBounds.height > 0.5 else { return }

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: clipRect.intersection(gridBounds)).addClip()

    // Fast full-span lines — one stroke per unique grid line (avoid painting shared edges twice).
    let colRange = visibleColumnRange()
    for col in colRange {
      guard columnIncludedInGridLines(col, region: region, frozenCols: frozenCols) else { continue }
      let x = xForColumn(col)
      let maxX = x + columnWidth(at: col)
      if region == .scrollable, x < frozenBoundaryX - 0.5 { continue }
      if region == .frozenCorner || region == .frozenLeft, maxX > frozenBoundaryX + 0.5 { continue }
      path.move(to: NSPoint(x: x, y: gridBounds.minY))
      path.line(to: NSPoint(x: x, y: gridBounds.maxY))
      if col == colRange.upperBound {
        path.move(to: NSPoint(x: maxX, y: gridBounds.minY))
        path.line(to: NSPoint(x: maxX, y: gridBounds.maxY))
      }
    }

    let rowRange = visibleRowRange()
    for row in rowRange {
      guard rowIncludedInGridLines(row, region: region, frozenRows: frozenRows) else { continue }
      let height = rowHeight(at: row)
      guard height > 0.5 else { continue }
      let y = yForRow(row)
      let maxY = y + height
      if region == .scrollable, y < frozenBoundaryY - 0.5 { continue }
      if region == .frozenCorner || region == .frozenTop, maxY > frozenBoundaryY + 0.5 { continue }
      if maxY < gridBounds.minY || y > gridBounds.maxY { continue }
      path.move(to: NSPoint(x: gridBounds.minX, y: y))
      path.line(to: NSPoint(x: gridBounds.maxX, y: y))
      if row == rowRange.upperBound {
        path.move(to: NSPoint(x: gridBounds.minX, y: maxY))
        path.line(to: NSPoint(x: gridBounds.maxX, y: maxY))
      }
    }
    path.stroke()
    NSGraphicsContext.restoreGraphicsState()
  }

  private func drawGridLines(in dirtyRect: NSRect) {
    drawGridLinesInClip(
      dirtyRect: dirtyRect,
      region: .scrollable,
      clipRect: scrollableCellsClipRect()
    )
  }

  private func drawFrozenGridLines(in dirtyRect: NSRect) {
    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()
    guard frozenRows > 0 || frozenCols > 0 else { return }

    if frozenRows > 0 && frozenCols > 0 {
      drawGridLinesInClip(dirtyRect: dirtyRect, region: .frozenCorner, clipRect: frozenCellsClipRect())
    }
    if frozenRows > 0 {
      drawGridLinesInClip(dirtyRect: dirtyRect, region: .frozenTop, clipRect: frozenTopStripClipRect())
    }
    if frozenCols > 0 {
      drawGridLinesInClip(dirtyRect: dirtyRect, region: .frozenLeft, clipRect: frozenLeftStripClipRect())
    }
  }

  /// When most on-screen cells already have custom borders, default gridlines are pure overdraw.
  private func visibleRegionIsMostlyBordered() -> Bool {
    guard let sheet = viewModel?.activeSheet else { return false }
    let rows = visibleRowRange()
    let cols = visibleColumnRange()
    var bordered = 0
    var populated = 0
    // Sample up to ~200 cells so this stays cheap on huge views.
    var sampled = 0
    rowLoop: for row in rows {
      for col in cols {
        guard let cell = sheet.cells[CellAddress(row: row, col: col)] else { continue }
        populated += 1
        if cell.format?.borders.hasAny == true { bordered += 1 }
        sampled += 1
        if sampled >= 200 { break rowLoop }
      }
    }
    guard populated > 0 else { return false }
    return bordered * 2 >= populated
  }

  private func drawCell(
    _ cell: Cell,
    at address: CellAddress,
    in dirtyRect: NSRect,
    viewModel: SpreadsheetViewModel,
    drawBorders: Bool = true
  ) {
    let rect = rectForCell(row: address.row, col: address.col)
    guard isCellRectInContentArea(rect), dirtyRect.intersects(rect) else { return }
    let paintFormat = viewModel.resolvedFormat(at: address)
    let hasBorders = paintFormat?.borders.hasAny == true || cell.format?.borders.hasAny == true
    let hasFill = paintFormat?.fillColor != nil
    if cell.raw.isEmpty && !hasFill && !hasBorders { return }
    if viewModel.isEditing && address == viewModel.selectionAnchor && isEditorActive {
      if drawBorders, let borders = paintFormat?.borders ?? cell.format?.borders, borders.hasAny {
        CellFormatRenderer.drawBorders(borders, in: rect, scale: zoomScale)
      }
      return
    }

    if let fill = CellFormatRenderer.fillColor(for: paintFormat) {
      fill.setFill()
      rect.fill()
    }

    if !cell.raw.isEmpty {
      let value = viewModel.displayValue(at: address)
      let text = viewModel.displayString(at: address)
      let insetX = 4 * zoomScale
      let insetY = 2 * zoomScale
      let textRect = rect.insetBy(dx: insetX, dy: insetY)
      if textRect.width > 1, textRect.height > 1 {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        var drawFormat = paintFormat ?? CellFormat()
        let baseSize = drawFormat.fontSize ?? CellFormatRenderer.defaultFontSize
        drawFormat.fontSize = baseSize * zoomScale
        if value.isError {
          drawFormat.textColor = CellFormatRenderer.codableColor(from: .systemRed)
          CellFormatRenderer.drawText(text, in: textRect, format: drawFormat)
        } else {
          CellFormatRenderer.drawText(text, in: textRect, format: drawFormat)
        }
        NSGraphicsContext.restoreGraphicsState()
      }
    }

    if drawBorders, let borders = paintFormat?.borders, borders.hasAny {
      CellFormatRenderer.drawBorders(borders, in: rect, scale: zoomScale)
    }
  }

  private func drawFilterAffordance(in rect: NSRect, over background: NSColor?) {
    let size = 10 * zoomScale
    let gap = 5 * zoomScale
    let boxWidth = size + 2 * zoomScale
    let boxHeight = size
    let box = NSRect(
      x: rect.maxX - boxWidth - gap,
      y: rect.maxY - boxHeight - gap,
      width: boxWidth,
      height: boxHeight
    )

    let base = (background ?? NSColor.windowBackgroundColor)
      .usingColorSpace(.deviceRGB) ?? background ?? .windowBackgroundColor
    let luminance =
      0.2126 * base.redComponent
      + 0.7152 * base.greenComponent
      + 0.0722 * base.blueComponent
    let onLight = luminance > 0.55
    let chipFill = onLight
      ? NSColor.black.withAlphaComponent(0.12)
      : NSColor.white.withAlphaComponent(0.22)
    let glyphFill = onLight
      ? NSColor.black.withAlphaComponent(0.72)
      : NSColor.white.withAlphaComponent(0.92)

    chipFill.setFill()
    NSBezierPath(roundedRect: box, xRadius: 2 * zoomScale, yRadius: 2 * zoomScale).fill()

    let tri = NSBezierPath()
    let origin = NSPoint(x: box.midX - size / 2, y: box.midY - size / 4)
    tri.move(to: origin)
    tri.line(to: NSPoint(x: origin.x + size, y: origin.y))
    tri.line(to: NSPoint(x: origin.x + size / 2, y: origin.y + size * 0.65))
    tri.close()
    glyphFill.setFill()
    tri.fill()
  }

  /// Effective background after the selection wash that will be drawn under text.
  private static func selectedCellBackground(over fill: NSColor?, isDarkMode: Bool) -> NSColor {
    let base = (fill ?? NSColor.windowBackgroundColor)
      .usingColorSpace(.deviceRGB) ?? fill ?? .windowBackgroundColor
    let washAlpha: CGFloat = isDarkMode ? 0.4 : 0.12
    return blendedColor(
      base,
      overlay: NSColor.selectedContentBackgroundColor,
      overlayFraction: washAlpha
    )
  }

  private static func selectedCellTextColor(over fill: NSColor?, isDarkMode: Bool) -> NSColor {
    let washed = selectedCellBackground(over: fill, isDarkMode: isDarkMode)
    // Pick contrast against the washed fill — not labelColor (white in dark mode on white fills).
    return luminance(of: washed) < 0.58 ? .white : .black
  }

  private static func luminance(of color: NSColor) -> CGFloat {
    let c = color.usingColorSpace(.deviceRGB) ?? color
    return 0.2126 * c.redComponent
      + 0.7152 * c.greenComponent
      + 0.0722 * c.blueComponent
  }

  private static func blendedColor(
    _ base: NSColor,
    overlay: NSColor,
    overlayFraction: CGFloat
  ) -> NSColor {
    let b = base.usingColorSpace(.deviceRGB) ?? base
    let o = overlay.usingColorSpace(.deviceRGB) ?? overlay
    let t = min(max(overlayFraction, 0), 1)
    return NSColor(
      red: o.redComponent * t + b.redComponent * (1 - t),
      green: o.greenComponent * t + b.greenComponent * (1 - t),
      blue: o.blueComponent * t + b.blueComponent * (1 - t),
      alpha: 1
    )
  }

  private func filterAffordanceRect(forCell rect: NSRect) -> NSRect {
    let size = 10 * zoomScale
    let gap = 5 * zoomScale
    let boxWidth = size + 2 * zoomScale
    let boxHeight = size
    // Slightly larger hit target than the drawn chip.
    return NSRect(
      x: rect.maxX - boxWidth - gap - 2 * zoomScale,
      y: rect.maxY - boxHeight - gap - 2 * zoomScale,
      width: boxWidth + 4 * zoomScale,
      height: boxHeight + 4 * zoomScale
    )
  }

  private func drawImages(in dirtyRect: NSRect) {
    guard let sheet = viewModel?.activeSheet, !sheet.images.isEmpty else { return }
    let selectedID = viewModel?.selectedImageID
    for image in sheet.images {
      guard let nsImage = NSImage(data: image.imageData) else { continue }
      let rect = imageRect(for: image)
      guard dirtyRect.intersects(rect), isCellRectInContentArea(rect) else { continue }
      nsImage.draw(
        in: rect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: nil
      )
      if image.id == selectedID {
        drawImageSelectionChrome(in: rect)
      }
    }
  }

  private func imageRect(for image: SheetImage) -> NSRect {
    let x = xForColumn(image.anchorCol) + SheetImage.points(fromEMU: image.colOffsetEMU)
    let y = yForRow(image.anchorRow) + SheetImage.points(fromEMU: image.rowOffsetEMU)
    let width = SheetImage.points(fromEMU: image.widthEMU)
    let height = SheetImage.points(fromEMU: image.heightEMU)
    return NSRect(x: x, y: y, width: width, height: height)
  }

  private func drawImageSelectionChrome(in rect: NSRect) {
    let accent = NSColor.controlAccentColor
    accent.setStroke()
    let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
    border.lineWidth = 2
    border.stroke()
    let handle = NSRect(
      x: rect.maxX - 6,
      y: rect.maxY - 6,
      width: 8,
      height: 8
    )
    accent.setFill()
    handle.fill()
  }

  private func imageHitTest(at point: NSPoint) -> SheetImage? {
    guard let sheet = viewModel?.activeSheet else { return nil }
    for image in sheet.images.reversed() {
      if imageRect(for: image).contains(point) { return image }
    }
    return nil
  }

  private func imageResizeHandleHit(at point: NSPoint, image: SheetImage) -> ImageResizeCorner? {
    let rect = imageRect(for: image)
    let handle = NSRect(x: rect.maxX - 8, y: rect.maxY - 8, width: 12, height: 12)
    return handle.contains(point) ? .bottomRight : nil
  }

  private func normalizeImagePlacement(
    row: Int,
    col: Int,
    rowOffsetEMU: Int,
    colOffsetEMU: Int
  ) -> (row: Int, col: Int, rowOffsetEMU: Int, colOffsetEMU: Int) {
    var r = max(0, row)
    var c = max(0, col)
    var rowPts = SheetImage.points(fromEMU: rowOffsetEMU)
    var colPts = SheetImage.points(fromEMU: colOffsetEMU)
    while colPts < -0.5, c > 0 {
      c -= 1
      colPts += columnWidth(at: c)
    }
    let maxCol = columnCount() - 1
    while colPts >= columnWidth(at: c) - 0.5, c < maxCol {
      colPts -= columnWidth(at: c)
      c += 1
    }
    while rowPts < -0.5, r > 0 {
      r -= 1
      rowPts += rowHeight(at: r)
    }
    let maxRow = rowCount() - 1
    while rowPts >= rowHeight(at: r) - 0.5, r < maxRow {
      rowPts -= rowHeight(at: r)
      r += 1
    }
    return (
      r,
      c,
      SheetImage.emu(fromPoints: max(0, rowPts)),
      SheetImage.emu(fromPoints: max(0, colPts))
    )
  }

  private func placementForImageTopLeft(x: CGFloat, y: CGFloat) -> (row: Int, col: Int, rowOffsetEMU: Int, colOffsetEMU: Int) {
    let col = columnAtContent(x: max(headerSize, min(x, bounds.width - 1)))
    let row = rowAtContent(y: max(headerSize, min(y, bounds.height - 1)))
    let colPts = x - xForColumn(col)
    let rowPts = y - yForRow(row)
    return normalizeImagePlacement(
      row: row,
      col: col,
      rowOffsetEMU: SheetImage.emu(fromPoints: rowPts),
      colOffsetEMU: SheetImage.emu(fromPoints: colPts)
    )
  }

  @discardableResult
  private func handleImageMouseDown(at point: NSPoint, event: NSEvent) -> Bool {
    guard let viewModel else { return false }
    if let selectedID = viewModel.selectedImageID,
       let selected = viewModel.image(with: selectedID),
       imageResizeHandleHit(at: point, image: selected) != nil
    {
      viewModel.selectImage(id: selectedID)
      activeImageDrag = ImageDragState(
        imageID: selectedID,
        mode: .resize(.bottomRight),
        startPoint: point,
        startImage: selected
      )
      isDraggingSelection = false
      return true
    }
    if let hit = imageHitTest(at: point) {
      viewModel.selectImage(id: hit.id)
      activeImageDrag = ImageDragState(
        imageID: hit.id,
        mode: .move,
        startPoint: point,
        startImage: hit
      )
      isDraggingSelection = false
      return true
    }
    return false
  }

  private func applyImageDrag(to point: NSPoint) {
    guard let drag = activeImageDrag, let viewModel else { return }
    let deltaX = point.x - drag.startPoint.x
    let deltaY = point.y - drag.startPoint.y
    let startRect = imageRect(for: drag.startImage)
    switch drag.mode {
    case .move:
      let placement = placementForImageTopLeft(
        x: startRect.minX + deltaX,
        y: startRect.minY + deltaY
      )
      viewModel.setImagePlacement(
        id: drag.imageID,
        anchorRow: placement.row,
        anchorCol: placement.col,
        rowOffsetEMU: placement.rowOffsetEMU,
        colOffsetEMU: placement.colOffsetEMU
      )
    case .resize(.bottomRight):
      let newWidth = max(12, startRect.width + deltaX)
      let newHeight = max(12, startRect.height + deltaY)
      viewModel.setImagePlacement(
        id: drag.imageID,
        anchorRow: drag.startImage.anchorRow,
        anchorCol: drag.startImage.anchorCol,
        rowOffsetEMU: drag.startImage.rowOffsetEMU,
        colOffsetEMU: drag.startImage.colOffsetEMU,
        widthEMU: SheetImage.emu(fromPoints: newWidth),
        heightEMU: SheetImage.emu(fromPoints: newHeight)
      )
    }
    needsDisplay = true
  }

  private func finishImageDragIfNeeded() {
    guard let drag = activeImageDrag, let viewModel else {
      activeImageDrag = nil
      return
    }
    viewModel.commitImagePlacement(id: drag.imageID, before: drag.startImage)
    activeImageDrag = nil
  }

  private func drawCells(in dirtyRect: NSRect) {
    guard let viewModel else { return }
    let sheet = viewModel.activeSheet
    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()

    let colRange = visibleColumnRange()
    let rowRange = visibleRowRange()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: scrollableCellsClipRect()).addClip()
    var borderItems: [(CellBorders, NSRect)] = []
    borderItems.reserveCapacity(256)
    for row in rowRange where row >= frozenRows {
      for col in colRange where col >= frozenCols {
        let address = CellAddress(row: row, col: col)
        if sheet.isCoveredByMerge(address) { continue }
        let hasCell = sheet.cells[address] != nil
        let isMergeAnchor = sheet.mergeContaining(address) != nil
        guard hasCell || isMergeAnchor else { continue }
        let cell = sheet.cell(at: address)
        guard let rect = paintRect(for: address, sheet: sheet) else { continue }
        guard isCellRectInContentArea(rect), dirtyRect.intersects(rect) else { continue }
        drawCellContent(cell, at: address, rect: rect, viewModel: viewModel)
        if let borders = viewModel.resolvedFormat(at: address)?.borders ?? cell.format?.borders,
           borders.hasAny
        {
          borderItems.append((borders, rect))
        }
      }
    }
    CellFormatRenderer.drawBordersBatch(borderItems, scale: zoomScale)
    drawSelectionWash(
      in: dirtyRect,
      rowRange: rowRange,
      colRange: colRange,
      viewModel: viewModel,
      sheet: sheet
    )
    NSGraphicsContext.restoreGraphicsState()
  }

  private func drawFrozenRegionCells(
    in dirtyRect: NSRect,
    rowRange: ClosedRange<Int>,
    colRange: ClosedRange<Int>,
    clipRect: NSRect,
    viewModel: SpreadsheetViewModel,
    sheet: Sheet
  ) {
    guard !clipRect.isEmpty, !rowRange.isEmpty, !colRange.isEmpty else { return }

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: clipRect).addClip()
    var borderItems: [(CellBorders, NSRect)] = []
    borderItems.reserveCapacity(64)
    for row in rowRange {
      for col in colRange {
        let address = CellAddress(row: row, col: col)
        if sheet.isCoveredByMerge(address) { continue }
        let hasCell = sheet.cells[address] != nil
        let isMergeAnchor = sheet.mergeContaining(address) != nil
        guard hasCell || isMergeAnchor else { continue }
        let cell = sheet.cell(at: address)
        guard let rect = paintRect(for: address, sheet: sheet) else { continue }
        guard dirtyRect.intersects(rect) else { continue }
        drawCellContent(cell, at: address, rect: rect, viewModel: viewModel)
        if let borders = viewModel.resolvedFormat(at: address)?.borders ?? cell.format?.borders,
           borders.hasAny
        {
          borderItems.append((borders, rect))
        }
      }
    }
    CellFormatRenderer.drawBordersBatch(borderItems, scale: zoomScale)
    drawSelectionWash(
      in: dirtyRect,
      rowRange: rowRange,
      colRange: colRange,
      viewModel: viewModel,
      sheet: sheet
    )
    NSGraphicsContext.restoreGraphicsState()
  }

  /// Selection fill for every cell in the range — not only cells still stored after clearing text.
  private func drawSelectionWash(
    in dirtyRect: NSRect,
    rowRange: ClosedRange<Int>,
    colRange: ClosedRange<Int>,
    viewModel: SpreadsheetViewModel,
    sheet: Sheet
  ) {
    guard !rowRange.isEmpty, !colRange.isEmpty else { return }
    let isDarkMode = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let washAlpha: CGFloat = isDarkMode ? 0.4 : 0.12
    let washColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(washAlpha)
    washColor.setFill()

    for range in viewModel.selectionRanges {
      let n = range.normalized
      let rowLower = max(n.minRow, rowRange.lowerBound)
      let rowUpper = min(n.maxRow, rowRange.upperBound)
      let colLower = max(n.minCol, colRange.lowerBound)
      let colUpper = min(n.maxCol, colRange.upperBound)
      guard rowLower <= rowUpper, colLower <= colUpper else { continue }
      for row in rowLower...rowUpper {
        for col in colLower...colUpper {
          let address = CellAddress(row: row, col: col)
          if sheet.isCoveredByMerge(address) { continue }
          let rect = rectForCell(row: row, col: col)
          guard isCellRectInContentArea(rect), dirtyRect.intersects(rect) else { continue }
          rect.fill()
        }
      }
    }
  }

  /// Fill + text only. Borders are painted in a later coalesced pass.
  private func drawCellContent(
    _ cell: Cell,
    at address: CellAddress,
    rect: NSRect,
    viewModel: SpreadsheetViewModel
  ) {
    if viewModel.isEditing && address == viewModel.selectionAnchor && isEditorActive {
      return
    }

    let paint = viewModel.resolvedPaint(at: address)
    let paintFormat = paint.format
    let fillColor = CellFormatRenderer.fillColor(for: paintFormat)
    if let fill = fillColor {
      fill.setFill()
      rect.fill()
    }

    let isSelected = viewModel.isAddressSelected(address)
    let isDarkMode = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

    if let fraction = paint.dataBarFraction, let color = paint.dataBarColor {
      drawDataBar(fraction: fraction, color: color, in: rect)
    }
    if let icon = paint.icon {
      drawIconSetGlyph(icon, in: rect)
    }

    let isFilterHeader = viewModel.isFilterHeaderCell(row: address.row, col: address.col)
    let hideValue = paint.dataBarFraction != nil && paint.dataBarShowValue == false
    if !hideValue, !cell.raw.isEmpty {
      let value = viewModel.displayValue(at: address)
      let text = viewModel.displayString(at: address)
      if !text.isEmpty {
        let insetX = 4 * zoomScale
        let insetY = 2 * zoomScale
        var textRect = rect.insetBy(dx: insetX, dy: insetY)
        if paint.icon != nil {
          textRect.origin.x += 14 * zoomScale
          textRect.size.width = max(0, textRect.width - 14 * zoomScale)
        }
        if isFilterHeader {
          // Keep wrapped text clear of the bottom-right filter chip.
          textRect.size.width = max(0, textRect.width - 14 * zoomScale)
          textRect.size.height = max(0, textRect.height - 14 * zoomScale)
        }
        if textRect.width > 1, textRect.height > 1 {
          NSGraphicsContext.saveGraphicsState()
          NSBezierPath(rect: rect).addClip()
          var drawFormat = paintFormat ?? CellFormat()
          let baseSize = drawFormat.fontSize ?? CellFormatRenderer.defaultFontSize
          drawFormat.fontSize = baseSize * zoomScale
          if value.isError {
            drawFormat.textColor = CellFormatRenderer.codableColor(from: .systemRed)
          } else if isSelected {
            drawFormat.textColor = CellFormatRenderer.codableColor(
              from: Self.selectedCellTextColor(over: fillColor, isDarkMode: isDarkMode)
            )
          }
          CellFormatRenderer.drawText(text, in: textRect, format: drawFormat)
          NSGraphicsContext.restoreGraphicsState()
        }
      }
    }

    if isFilterHeader {
      drawFilterAffordance(in: rect, over: fillColor)
    }
  }

  private func drawDataBar(fraction: Double, color: CodableColor, in rect: NSRect) {
    let pad = 2 * zoomScale
    let height = max(4 * zoomScale, rect.height - pad * 2)
    let maxWidth = max(0, rect.width - pad * 2)
    let width = maxWidth * CGFloat(min(1, max(0, fraction)))
    guard width > 0.5 else { return }
    let bar = NSRect(
      x: rect.minX + pad,
      y: rect.midY - height / 2,
      width: width,
      height: height
    )
    NSColor(
      calibratedRed: color.red,
      green: color.green,
      blue: color.blue,
      alpha: 0.72
    ).setFill()
    NSBezierPath(roundedRect: bar, xRadius: 2 * zoomScale, yRadius: 2 * zoomScale).fill()
  }

  private func drawIconSetGlyph(_ glyph: IconSetGlyph, in rect: NSRect) {
    let size = min(12 * zoomScale, rect.height - 4 * zoomScale)
    guard size > 4 else { return }
    let origin = NSPoint(x: rect.minX + 3 * zoomScale, y: rect.midY - size / 2)
    let box = NSRect(origin: origin, size: NSSize(width: size, height: size))
    switch glyph {
    case .greenCircle, .yellowCircle, .redCircle:
      let color: NSColor = {
        switch glyph {
        case .greenCircle: return .systemGreen
        case .yellowCircle: return .systemYellow
        default: return .systemRed
        }
      }()
      color.setFill()
      NSBezierPath(ovalIn: box.insetBy(dx: 1, dy: 1)).fill()
    case .greenArrow, .yellowArrow, .redArrow:
      let color: NSColor = {
        switch glyph {
        case .greenArrow: return .systemGreen
        case .yellowArrow: return .systemYellow
        default: return .systemRed
        }
      }()
      color.setFill()
      let path = NSBezierPath()
      if glyph == .yellowArrow {
        path.move(to: NSPoint(x: box.minX, y: box.midY))
        path.line(to: NSPoint(x: box.maxX, y: box.midY))
        path.line(to: NSPoint(x: box.maxX - size * 0.25, y: box.midY - size * 0.25))
        path.move(to: NSPoint(x: box.maxX, y: box.midY))
        path.line(to: NSPoint(x: box.maxX - size * 0.25, y: box.midY + size * 0.25))
        path.lineWidth = 1.5 * zoomScale
        color.setStroke()
        path.stroke()
      } else if glyph == .greenArrow {
        path.move(to: NSPoint(x: box.midX, y: box.maxY))
        path.line(to: NSPoint(x: box.minX + 1, y: box.minY + size * 0.35))
        path.line(to: NSPoint(x: box.maxX - 1, y: box.minY + size * 0.35))
        path.close()
        path.fill()
      } else {
        path.move(to: NSPoint(x: box.midX, y: box.minY))
        path.line(to: NSPoint(x: box.minX + 1, y: box.maxY - size * 0.35))
        path.line(to: NSPoint(x: box.maxX - 1, y: box.maxY - size * 0.35))
        path.close()
        path.fill()
      }
    case .greenCheck, .yellowDash, .redX:
      let color: NSColor = {
        switch glyph {
        case .greenCheck: return .systemGreen
        case .yellowDash: return .systemYellow
        default: return .systemRed
        }
      }()
      let path = NSBezierPath()
      path.lineWidth = 1.6 * zoomScale
      path.lineCapStyle = .round
      color.setStroke()
      switch glyph {
      case .greenCheck:
        path.move(to: NSPoint(x: box.minX + size * 0.15, y: box.midY))
        path.line(to: NSPoint(x: box.midX - size * 0.05, y: box.minY + size * 0.2))
        path.line(to: NSPoint(x: box.maxX - size * 0.1, y: box.maxY - size * 0.15))
      case .yellowDash:
        path.move(to: NSPoint(x: box.minX + size * 0.15, y: box.midY))
        path.line(to: NSPoint(x: box.maxX - size * 0.15, y: box.midY))
      default:
        path.move(to: NSPoint(x: box.minX + size * 0.2, y: box.minY + size * 0.2))
        path.line(to: NSPoint(x: box.maxX - size * 0.2, y: box.maxY - size * 0.2))
        path.move(to: NSPoint(x: box.maxX - size * 0.2, y: box.minY + size * 0.2))
        path.line(to: NSPoint(x: box.minX + size * 0.2, y: box.maxY - size * 0.2))
      }
      path.stroke()
    }
  }

  private func drawFrozenCells(in dirtyRect: NSRect) {
    guard let viewModel else { return }
    let sheet = viewModel.activeSheet
    let frozenRows = frozenRowCount()
    let frozenCols = frozenColumnCount()
    let visibleRows = visibleRowRange()
    let visibleCols = visibleColumnRange()

    if frozenRows > 0 && frozenCols > 0 {
      drawFrozenRegionCells(
        in: dirtyRect,
        rowRange: 0...(frozenRows - 1),
        colRange: 0...(frozenCols - 1),
        clipRect: frozenCellsClipRect(),
        viewModel: viewModel,
        sheet: sheet
      )
    }
    if frozenRows > 0 {
      let colLower = max(visibleCols.lowerBound, frozenCols)
      if colLower <= visibleCols.upperBound {
        drawFrozenRegionCells(
          in: dirtyRect,
          rowRange: 0...(frozenRows - 1),
          colRange: colLower...visibleCols.upperBound,
          clipRect: frozenTopStripClipRect(),
          viewModel: viewModel,
          sheet: sheet
        )
      }
    }
    if frozenCols > 0 {
      let rowLower = max(visibleRows.lowerBound, frozenRows)
      if rowLower <= visibleRows.upperBound {
        drawFrozenRegionCells(
          in: dirtyRect,
          rowRange: rowLower...visibleRows.upperBound,
          colRange: 0...(frozenCols - 1),
          clipRect: frozenLeftStripClipRect(),
          viewModel: viewModel,
          sheet: sheet
        )
      }
    }
  }

  private func drawSelection(in dirtyRect: NSRect) {
    guard let viewModel else { return }
    let ranges = viewModel.selectionRanges
    let isMulti = ranges.count > 1

    for (index, range) in ranges.enumerated() {
      let n = range.normalized
      let fullTopLeft = rectForCell(row: n.minRow, col: n.minCol)
      let fullBottomRight = rectForCell(row: n.maxRow, col: n.maxCol)
      let fullRect = NSRect(
        x: fullTopLeft.minX,
        y: fullTopLeft.minY,
        width: fullBottomRight.maxX - fullTopLeft.minX,
        height: fullBottomRight.maxY - fullTopLeft.minY
      )

      // Full selection outline (Excel-familiar), not an L-anchor on the active cell.
      if isCellRectInContentArea(fullRect), dirtyRect.intersects(fullRect) {
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: fullRect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = index == ranges.count - 1 ? 2 : 1.5
        border.stroke()
      }
    }

    if !isMulti {
      drawFillHandle(in: dirtyRect)
    }
  }

  private func drawFillHandle(in dirtyRect: NSRect) {
    guard let rect = fillHandleRect(), dirtyRect.intersects(rect) else { return }
    NSColor.controlAccentColor.setFill()
    NSBezierPath(rect: rect).fill()
    NSColor.white.setStroke()
    let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
    border.lineWidth = 1.5
    border.stroke()
  }

  private func drawFormulaReferenceHighlights(in dirtyRect: NSRect) {
    guard let viewModel else { return }
    let highlights = viewModel.formulaReferenceHighlights
    guard !highlights.isEmpty else { return }

    let activeSheetName = viewModel.activeSheet.name
    let visibleRows = visibleRowRange()
    let visibleCols = visibleColumnRange()
    let focused = viewModel.focusedFormulaHighlightIndex

    for (index, highlight) in highlights.enumerated() {
      if let sheet = highlight.sheet,
         sheet.caseInsensitiveCompare(activeSheetName) != .orderedSame
      {
        continue
      }
      let n = highlight.cellRange.normalized
      let startRow = max(n.minRow, visibleRows.lowerBound)
      let endRow = min(n.maxRow, visibleRows.upperBound)
      let startCol = max(n.minCol, visibleCols.lowerBound)
      let endCol = min(n.maxCol, visibleCols.upperBound)
      guard startRow <= endRow, startCol <= endCol else { continue }

      let topLeft = rectForCell(row: startRow, col: startCol)
      let bottomRight = rectForCell(row: endRow, col: endCol)
      let fillRect = NSRect(
        x: topLeft.minX,
        y: topLeft.minY,
        width: bottomRight.maxX - topLeft.minX,
        height: bottomRight.maxY - topLeft.minY
      )
      guard isCellRectInContentArea(fillRect), dirtyRect.intersects(fillRect) else { continue }

      let color = highlight.color
      let isFocused = focused == index || (focused == nil && highlights.count == 1)
      color.withAlphaComponent(isFocused ? 0.16 : 0.08).setFill()
      fillRect.fill()

      color.setStroke()
      let border = NSBezierPath(rect: fillRect.insetBy(dx: 0.5, dy: 0.5))
      border.lineWidth = isFocused ? 2 : 1.5
      // Sheets-style dashed range outline
      border.setLineDash([4, 3], count: 2, phase: 0)
      border.stroke()
    }
  }

  private func drawFreezeDividers(in dirtyRect: NSRect) {
    guard let sheet = viewModel?.activeSheet else { return }
    let frozenCols = sheet.frozenColumns
    let frozenRows = sheet.frozenRows
    guard frozenCols > 0 || frozenRows > 0 else { return }

    let content = contentRect
    NSColor.separatorColor.withAlphaComponent(0.92).setStroke()
    if frozenCols > 0 {
      let x = frozenColumnBoundaryX()
      let line = NSBezierPath()
      line.move(to: NSPoint(x: x, y: content.minY))
      line.line(to: NSPoint(x: x, y: content.maxY))
      line.lineWidth = 1.5
      line.stroke()
    }
    if frozenRows > 0 {
      let y = frozenRowBoundaryY()
      let line = NSBezierPath()
      line.move(to: NSPoint(x: content.minX, y: y))
      line.line(to: NSPoint(x: content.maxX, y: y))
      line.lineWidth = 1.5
      line.stroke()
    }
  }

  // MARK: - Editor

  func showEditor(selectAll: Bool = false) {
    guard let viewModel else { return }
    let rect = rectForCell(row: viewModel.selectionAnchor.row, col: viewModel.selectionAnchor.col)
    guard isCellRectInContentArea(rect) else { return }
    isEditorActive = true
    lastAppliedFormulaHighlightKey = ""
    editor.stringValue = viewModel.editText
    applyEditorFormat(from: viewModel.selectedCell.format)
    styleFieldEditor(for: viewModel.selectedCell.format)
    updateEditorFrame()
    editor.isHidden = false
    window?.makeFirstResponder(editor)
    guard let fieldEditor = editor.currentEditor() else { return }
    if selectAll {
      fieldEditor.selectAll(nil)
    } else {
      let length = editor.stringValue.utf16.count
      fieldEditor.selectedRange = NSRange(location: length, length: 0)
    }
    applyInCellFormulaAttributes(preserveSelection: true)
    if let textView = editor.currentEditor() as? NSTextView {
      viewModel.updateFormulaHighlightFocus(atUTF16: textView.selectedRange.location)
      // Focus update may arrive before highlights exist; refresh once more next turn.
      DispatchQueue.main.async { [weak self] in
        guard let self, self.isEditorActive else { return }
        self.lastAppliedFormulaHighlightKey = ""
        self.applyInCellFormulaAttributes(preserveSelection: true)
        if let textView = self.editor.currentEditor() as? NSTextView {
          self.viewModel?.updateFormulaHighlightFocus(atUTF16: textView.selectedRange.location)
        }
        self.needsDisplay = true
      }
    }
  }

  private func applyEditorFormat(from format: CellFormat?) {
    var scaledFormat = format ?? CellFormat()
    let baseSize = scaledFormat.fontSize ?? CellFormatRenderer.defaultFontSize
    scaledFormat.fontSize = baseSize * zoomScale
    editor.font = CellFormatRenderer.font(for: scaledFormat)
    let colors = editorColors(for: format)
    editor.textColor = colors.foreground
    styleFieldEditor(for: format)
  }

  /// Match the in-cell editor surface to the cell fill with readable text/selection colors.
  private func editorColors(for format: CellFormat?) -> (background: NSColor, foreground: NSColor) {
    let background = CellFormatRenderer.fillColor(for: format) ?? NSColor.textBackgroundColor
    let bgRGB = background.usingColorSpace(.deviceRGB) ?? background
    if let explicit = CellFormatRenderer.nsColor(format?.textColor) {
      return (background, explicit)
    }
    let fg = Self.luminance(of: bgRGB) > 0.65 ? NSColor.black : NSColor.white
    return (background, fg)
  }

  private func styleFieldEditor(for format: CellFormat?) {
    guard let textView = editor.currentEditor() as? NSTextView else { return }
    let colors = editorColors(for: format)
    textView.drawsBackground = true
    textView.backgroundColor = colors.background
    textView.textColor = colors.foreground
    textView.insertionPointColor = colors.foreground
    let selectionForeground = Self.luminance(of: colors.background.usingColorSpace(.deviceRGB) ?? colors.background) > 0.65
      ? NSColor.black
      : NSColor.white
    textView.selectedTextAttributes = [
      .backgroundColor: NSColor.selectedTextBackgroundColor,
      .foregroundColor: selectionForeground,
    ]
    textView.typingAttributes = [
      .font: editor.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
      .foregroundColor: colors.foreground,
      .backgroundColor: NSColor.clear,
    ]
  }

  private func applyInCellFormulaAttributes(preserveSelection: Bool) {
    guard !isApplyingFormulaAttributes else { return }
    guard let viewModel, FormulaSyntax.isFormula(editor.stringValue) else {
      lastAppliedFormulaHighlightKey = ""
      return
    }

    let key = "\(editor.stringValue)|\(viewModel.focusedFormulaHighlightIndex ?? -1)|\(viewModel.formulaHighlightRevision)"
    guard key != lastAppliedFormulaHighlightKey else { return }
    lastAppliedFormulaHighlightKey = key

    isApplyingFormulaAttributes = true
    defer { isApplyingFormulaAttributes = false }

    let font = editor.font ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
    let colors = editorColors(for: viewModel.selectedCell.format)
    let attributed = FormulaReferenceScanner.attributedFormula(
      editor.stringValue,
      highlights: viewModel.formulaReferenceHighlights,
      focusedIndex: viewModel.focusedFormulaHighlightIndex,
      baseFont: font,
      baseColor: colors.foreground
    )
    var selected: NSRange?
    if preserveSelection, let textView = editor.currentEditor() as? NSTextView {
      selected = textView.selectedRange
    }
    editor.attributedStringValue = attributed
    if let selected, let textView = editor.currentEditor() as? NSTextView {
      let maxLen = (editor.stringValue as NSString).length
      let loc = min(selected.location, maxLen)
      let len = min(selected.length, max(0, maxLen - loc))
      textView.setSelectedRange(NSRange(location: loc, length: len))
    }
  }

  func hideEditor(commit: Bool) {
    guard isEditorActive else { return }
    isEditorActive = false
    if commit, let viewModel {
      viewModel.editText = editor.stringValue
      viewModel.commitEdit()
    } else {
      viewModel?.cancelEdit()
    }
    editor.isHidden = true
    window?.makeFirstResponder(self)
    needsDisplay = true
  }

  private func commitEditorAndMove(rowDelta: Int, colDelta: Int) {
    guard let viewModel else { return }
    viewModel.editText = editor.stringValue
    hideEditor(commit: true)
    viewModel.moveSelection(rowDelta: rowDelta, colDelta: colDelta)
    scrollSelectionIntoView()
  }

  private func updateEditorFrame() {
    guard let viewModel else { return }
    let sheet = viewModel.activeSheet
    let anchor = viewModel.selectionAnchor
    let rect = (paintRect(for: anchor, sheet: sheet) ?? rectForCell(row: anchor.row, col: anchor.col))
      .insetBy(dx: 1, dy: 1)
    guard rect.width > 4, rect.height > 4 else {
      editor.isHidden = true
      return
    }
    editor.frame = rect
  }

  func syncDisplay() {
    // Filter visibility depends on cell values — rebuild row heights when content changes.
    if viewModel?.filterState != nil {
      invalidateLayoutCache()
    }
    clampScrollOrigin()
    updateEditorFrame()
    window?.invalidateCursorRects(for: self)
    needsDisplay = true
  }

  func applyFreezePanesLayout() {
    invalidateLayoutCache()
    syncDisplay()
  }

  func refreshSelectionDisplay() {
    updateEditorFrame()
    let next = selectionDirtyRect().insetBy(dx: -4, dy: -4)
    var dirty = next
    if !lastSelectionDirtyRect.isNull {
      dirty = dirty.union(lastSelectionDirtyRect)
    }
    lastSelectionDirtyRect = next
    if dirty.isNull || dirty.isEmpty {
      needsDisplay = true
    } else {
      setNeedsDisplay(dirty.intersection(bounds))
    }
  }

  private func selectionDirtyRect() -> NSRect {
    guard let viewModel else { return .null }
    var rect = NSRect.null
    for range in viewModel.selectionRanges {
      let n = range.normalized
      let topLeft = rectForCell(row: n.minRow, col: n.minCol)
      let bottomRight = rectForCell(row: n.maxRow, col: n.maxCol)
      let r = NSRect(
        x: topLeft.minX,
        y: topLeft.minY,
        width: bottomRight.maxX - topLeft.minX,
        height: bottomRight.maxY - topLeft.minY
      )
      rect = rect.union(r)
    }
    if let handle = fillHandleRect() {
      rect = rect.union(handle)
    }
    // Header highlights track selection too.
    rect = rect.union(NSRect(x: 0, y: 0, width: bounds.width, height: headerSize))
    rect = rect.union(NSRect(x: 0, y: 0, width: headerSize, height: bounds.height))
    return rect
  }

  func refreshFormulaHighlights() {
    needsDisplay = true
    guard isEditorActive else { return }
    applyInCellFormulaAttributes(preserveSelection: true)
  }

  func scrollFocusedFormulaHighlightIntoViewIfNeeded() {
    guard let viewModel,
          let index = viewModel.focusedFormulaHighlightIndex,
          viewModel.formulaReferenceHighlights.indices.contains(index)
    else { return }
    let highlight = viewModel.formulaReferenceHighlights[index]
    if let sheet = highlight.sheet,
       sheet.caseInsensitiveCompare(viewModel.activeSheet.name) != .orderedSame
    {
      return
    }
    let address = highlight.start
    let rect = rectForCell(row: address.row, col: address.col)
    scrollToVisible(rect.insetBy(dx: -40, dy: -40))
  }

  func reloadContent(resetScrollPosition shouldReset: Bool = false) {
    if shouldReset { scrollOrigin = .zero }
    invalidateLayoutCache()
    updateEditorFrame()
    window?.invalidateCursorRects(for: self)
    needsDisplay = true
  }

  func scrollSelectionIntoView() {
    ensureSelectionVisible()
    updateEditorFrame()
    needsDisplay = true
  }

  // MARK: - Mouse

  override func mouseMoved(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    updateCursor(for: point)
    updateErrorToolTip(at: point)
  }

  private func updateErrorToolTip(at point: NSPoint) {
    guard let viewModel, contentRect.contains(point) else {
      toolTip = nil
      return
    }
    let address = addressAtContent(point: point)
    if let error = viewModel.displayValue(at: address).formulaError {
      toolTip = "\(error.displayCode) — \(error.explanation)"
    } else {
      toolTip = nil
    }
  }

  override func cursorUpdate(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    updateCursor(for: point)
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let point = convert(event.locationInWindow, from: nil)

    if isEditorActive { hideEditor(commit: true) }

    if isPointInFillHandle(point) {
      fillSourceRange = viewModel?.selectionRange
      isDraggingFill = true
      return
    }

    if let target = resizeTarget(at: point) {
      if event.clickCount >= 2 {
        switch target {
        case .column(let col, _, _):
          // Double-click the left edge of column A (against the corner) fits every column.
          if col == 0, abs(point.x - headerSize) <= resizeHandleThickness {
            viewModel?.autoFitAllColumns()
          } else {
            viewModel?.autoFitColumn(col)
          }
        case .row(let row, _, _):
          // Double-click the top edge of row 1 (against the corner) fits every row.
          if row == 0, abs(point.y - headerSize) <= resizeHandleThickness {
            viewModel?.autoFitAllRows()
          } else {
            viewModel?.autoFitRow(row)
          }
        }
        invalidateLayoutCache()
        updateEditorFrame()
        needsDisplay = true
        return
      }
      activeResize = target
      return
    }

    switch headerHit(at: point) {
    case .corner:
      viewModel?.toggleSelectAll()
      window?.makeFirstResponder(self)
      needsDisplay = true
      return
    case .column(let col):
      if event.modifierFlags.contains(.command) {
        viewModel?.commandClickColumn(col)
      } else {
        viewModel?.selectColumn(col)
        headerDrag = .columns(anchor: col)
      }
      needsDisplay = true
      return
    case .row(let row):
      if event.modifierFlags.contains(.command) {
        viewModel?.commandClickRow(row)
      } else {
        viewModel?.selectRow(row)
        headerDrag = .rows(anchor: row)
      }
      needsDisplay = true
      return
    case .content:
      break
    }

    guard contentRect.contains(point) else { return }
    // Ignore clicks in the empty band below collapsed/filter-hidden content.
    if point.y > contentBottomY() + 1 {
      return
    }

    if handleImageMouseDown(at: point, event: event) {
      needsDisplay = true
      return
    }
    viewModel?.selectImage(id: nil)

    let rawAddress = addressAtContent(point: point)
    let address = viewModel?.activeSheet.mergeAnchor(for: rawAddress) ?? rawAddress
    if rowHeight(at: address.row) <= 0 {
      return
    }
    if viewModel?.isFilterHeaderCell(row: address.row, col: address.col) == true,
       isInFilterAffordance(point: point, address: address)
    {
      presentFilterMenu(for: address.col, at: point)
      window?.makeFirstResponder(self)
      return
    }
    if event.modifierFlags.contains(.command) {
      viewModel?.commandClickCell(address)
      needsDisplay = true
      return
    }

    isDraggingSelection = true
    viewModel?.selectRange(from: address, to: address)

    if event.clickCount >= 2 {
      isDraggingSelection = false
      editorEntryMode = .inCellEdit
      viewModel?.beginEditing()
      showEditor(selectAll: false)
    } else {
      scrollSelectionIntoView()
    }
  }

  private func isInFilterAffordance(point: NSPoint, address: CellAddress) -> Bool {
    let rect = rectForCell(row: address.row, col: address.col)
    return filterAffordanceRect(forCell: rect).contains(point)
  }

  private func presentFilterMenu(for column: Int, at point: NSPoint) {
    guard let viewModel, let filter = viewModel.filterState else { return }
    let values = filter.uniqueValues(
      forColumn: column,
      sheet: viewModel.activeSheet,
      displayString: { viewModel.displayString(at: $0) }
    )
    let selected = filter.selectedValuesByColumn[column]
    let allSelected = selected == nil

    let menu = NSMenu()
    let clearFilterItem = NSMenuItem(
      title: "Clear Filter for Column",
      action: #selector(clearColumnFilter(_:)),
      keyEquivalent: ""
    )
    clearFilterItem.target = self
    clearFilterItem.representedObject = column
    clearFilterItem.isEnabled = true
    menu.addItem(clearFilterItem)
    menu.addItem(.separator())

    let allItem = NSMenuItem(title: "Select All", action: #selector(selectAllFilterValues(_:)), keyEquivalent: "")
    allItem.target = self
    allItem.representedObject = column
    allItem.state = allSelected ? .on : .off
    menu.addItem(allItem)

    let clearAllItem = NSMenuItem(title: "Clear All", action: #selector(clearAllFilterValues(_:)), keyEquivalent: "")
    clearAllItem.target = self
    clearAllItem.representedObject = column
    clearAllItem.state = (selected?.isEmpty == true) ? .on : .off
    menu.addItem(clearAllItem)
    menu.addItem(.separator())

    for value in values {
      let title = value.isEmpty ? "(Blanks)" : value
      let item = NSMenuItem(title: title, action: #selector(toggleFilterValue(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = FilterValuePayload(column: column, value: value)
      let isOn = selected?.contains(value) ?? true
      item.state = isOn ? .on : .off
      menu.addItem(item)
    }

    menu.popUp(positioning: nil, at: point, in: self)
  }

  @objc private func clearColumnFilter(_ sender: NSMenuItem) {
    guard let column = sender.representedObject as? Int else { return }
    viewModel?.clearColumnFilter(column)
    invalidateLayoutCache()
    needsDisplay = true
  }

  @objc private func selectAllFilterValues(_ sender: NSMenuItem) {
    guard let column = sender.representedObject as? Int else { return }
    viewModel?.setFilterValues(column: column, values: nil)
    invalidateLayoutCache()
    needsDisplay = true
  }

  @objc private func clearAllFilterValues(_ sender: NSMenuItem) {
    guard let column = sender.representedObject as? Int else { return }
    viewModel?.setFilterValues(column: column, values: [])
    invalidateLayoutCache()
    needsDisplay = true
  }

  @objc private func toggleFilterValue(_ sender: NSMenuItem) {
    guard let payload = sender.representedObject as? FilterValuePayload,
          let viewModel,
          let filter = viewModel.filterState
    else { return }
    let all = Set(filter.uniqueValues(
      forColumn: payload.column,
      sheet: viewModel.activeSheet,
      displayString: { viewModel.displayString(at: $0) }
    ))
    var selected = filter.selectedValuesByColumn[payload.column] ?? all
    if selected.contains(payload.value) {
      selected.remove(payload.value)
    } else {
      selected.insert(payload.value)
    }
    if selected == all {
      viewModel.setFilterValues(column: payload.column, values: nil)
    } else {
      viewModel.setFilterValues(column: payload.column, values: selected)
    }
    invalidateLayoutCache()
    needsDisplay = true
  }

  private final class FilterValuePayload: NSObject {
    let column: Int
    let value: String
    init(column: Int, value: String) {
      self.column = column
      self.value = value
    }
  }

  override func mouseDragged(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)

    if let resize = activeResize {
      switch resize {
      case .column(let col, let startWidth, let startX):
        let delta = point.x - startX
        viewModel?.setColumnWidth(col, width: (startWidth + delta) / zoomScale, recordUndo: false)
      case .row(let row, let startHeight, let startY):
        let delta = point.y - startY
        viewModel?.setRowHeight(row, height: (startHeight + delta) / zoomScale, recordUndo: false)
      }
      invalidateLayoutCache()
      window?.invalidateCursorRects(for: self)
      updateEditorFrame()
      needsDisplay = true
      return
    }

    if activeImageDrag != nil {
      applyImageDrag(to: point)
      return
    }

    if let headerDrag {
      switch headerDrag {
      case .columns(let anchor):
        let col: Int
        if point.y < headerSize, point.x >= headerSize {
          col = columnAtContent(x: max(headerSize, min(point.x, bounds.width - 1)))
        } else if contentRect.contains(point) {
          col = addressAtContent(point: point).col
        } else {
          col = columnAtContent(x: max(headerSize, min(point.x, bounds.width - 1)))
        }
        viewModel?.selectColumns(from: anchor, to: col)
        needsDisplay = true
        return
      case .rows(let anchor):
        let row: Int
        if point.x < headerSize, point.y >= headerSize {
          row = rowAtContent(y: max(headerSize, min(point.y, bounds.height - 1)))
        } else if contentRect.contains(point) {
          row = addressAtContent(point: point).row
        } else {
          row = rowAtContent(y: max(headerSize, min(point.y, bounds.height - 1)))
        }
        viewModel?.selectRows(from: anchor, to: row)
        needsDisplay = true
        return
      }
    }

    if isDraggingFill, let viewModel, let source = fillSourceRange {
      let clamped = NSPoint(
        x: max(contentRect.minX, min(point.x, contentRect.maxX - 1)),
        y: max(contentRect.minY, min(point.y, contentRect.maxY - 1))
      )
      let end = addressAtContent(point: clamped)
      let normalized = source.normalized
      let fillEnd = CellAddress(
        row: max(normalized.maxRow, end.row),
        col: max(normalized.maxCol, end.col)
      )
      viewModel.extendSelection(to: fillEnd)
      scrollSelectionIntoView()
      return
    }

    guard isDraggingSelection, let viewModel else { return }
    let clamped = NSPoint(
      x: max(contentRect.minX, min(point.x, contentRect.maxX - 1)),
      y: max(contentRect.minY, min(point.y, contentRect.maxY - 1))
    )
    viewModel.extendSelection(to: addressAtContent(point: clamped))
    scrollSelectionIntoView()
  }

  override func mouseUp(with event: NSEvent) {
    if activeImageDrag != nil {
      finishImageDragIfNeeded()
      needsDisplay = true
    }

    if isDraggingFill, let viewModel, let source = fillSourceRange {
      let point = convert(event.locationInWindow, from: nil)
      let clamped = NSPoint(
        x: max(contentRect.minX, min(point.x, contentRect.maxX - 1)),
        y: max(contentRect.minY, min(point.y, contentRect.maxY - 1))
      )
      let end = addressAtContent(point: clamped)
      let normalized = source.normalized
      if end.row > normalized.maxRow || end.col > normalized.maxCol {
        viewModel.fillSelection(from: source, to: end)
      } else {
        viewModel.selectRange(from: source.start, to: source.end)
      }
      isDraggingFill = false
      fillSourceRange = nil
      syncDisplay()
      return
    }

    if let resize = activeResize {
      switch resize {
      case .column(let col, let startWidth, _):
        viewModel?.commitColumnWidthResize(col: col, from: startWidth / zoomScale)
      case .row(let row, let startHeight, _):
        viewModel?.commitRowHeightResize(row: row, from: startHeight / zoomScale)
      }
      activeResize = nil
      window?.invalidateCursorRects(for: self)
      let point = convert(event.locationInWindow, from: nil)
      updateCursor(for: point)
    }
    headerDrag = nil
    isDraggingSelection = false
  }

  override func scrollWheel(with event: NSEvent) {
    let invert = AppSettings.shared.invertScrollDirection
    scrollOrigin.x += event.scrollingDeltaX
    scrollOrigin.y += event.scrollingDeltaY * (invert ? -1 : 1)
    clampScrollOrigin()
    updateEditorFrame()
    needsDisplay = true
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    let point = convert(event.locationInWindow, from: nil)

    if let viewModel {
      switch headerHit(at: point) {
      case .row(let row):
        viewModel.selectRow(row)
        needsDisplay = true
      case .column(let col):
        viewModel.selectColumn(col)
        needsDisplay = true
      case .content:
        let address = addressAtContent(point: point)
        if !viewModel.isAddressSelected(address) {
          viewModel.selectRange(from: address, to: address)
          needsDisplay = true
        }
      case .corner:
        break
      }
    }

    let menu = NSMenu()
    let cut = menu.addItem(withTitle: "Cut", action: #selector(handleMenuCut(_:)), keyEquivalent: "")
    cut.target = self
    let copy = menu.addItem(withTitle: "Copy", action: #selector(handleMenuCopy(_:)), keyEquivalent: "")
    copy.target = self
    let paste = menu.addItem(withTitle: "Paste", action: #selector(handleMenuPaste(_:)), keyEquivalent: "")
    paste.target = self
    menu.addItem(.separator())
    addPrimaryContextActions(to: menu)
    menu.addItem(.separator())
    addStructureSubmenus(to: menu)
    return menu
  }

  private func addPrimaryContextActions(to menu: NSMenu) {
    guard let viewModel else { return }

    addMenuItem(menu, "Create a Filter", #selector(handleMenuCreateFilter(_:)))
    let clearFilter = addMenuItem(menu, "Clear Filter", #selector(handleMenuClearFilter(_:)))
    clearFilter.isEnabled = viewModel.filterState != nil
    let clearColumn = addMenuItem(
      menu,
      "Clear Filter for Column",
      #selector(handleMenuClearColumnFilter(_:))
    )
    clearColumn.isEnabled = viewModel.isFilterColumn(viewModel.selectionAnchor.col)

    menu.addItem(.separator())

    let merge = NSMenu(title: "Merge")
    let mergeAll = addMenuItem(merge, "Merge All", #selector(handleMenuMergeAll(_:)))
    mergeAll.isEnabled = viewModel.canMergeSelection
    let mergeAcross = addMenuItem(merge, "Merge Across", #selector(handleMenuMergeAcross(_:)))
    mergeAcross.isEnabled = viewModel.canMergeHorizontally
    let mergeVertical = addMenuItem(merge, "Merge Vertically", #selector(handleMenuMergeVertical(_:)))
    mergeVertical.isEnabled = viewModel.canMergeVertically
    merge.addItem(.separator())
    let unmerge = addMenuItem(merge, "Unmerge Cells", #selector(handleMenuUnmerge(_:)))
    unmerge.isEnabled = viewModel.canUnmergeSelection
    let mergeItem = NSMenuItem(title: "Merge", action: nil, keyEquivalent: "")
    mergeItem.submenu = merge
    menu.addItem(mergeItem)
  }

  private func addStructureSubmenus(to menu: NSMenu) {
    guard let viewModel else { return }
    let axis = viewModel.selectionAxis
    let showRows = axis != .column
    let showCols = axis != .row

    if showRows || showCols {
      if showRows {
        addMenuItem(menu, "Insert Row Above", #selector(handleMenuInsertRowAbove(_:)))
        addMenuItem(menu, "Insert Row Below", #selector(handleMenuInsertRowBelow(_:)))
        addMenuItem(menu, "Delete Row(s)", #selector(handleMenuDeleteRows(_:)))
      }
      if showRows && showCols {
        menu.addItem(.separator())
      }
      if showCols {
        addMenuItem(menu, "Insert Column Left", #selector(handleMenuInsertColumnLeft(_:)))
        addMenuItem(menu, "Insert Column Right", #selector(handleMenuInsertColumnRight(_:)))
        addMenuItem(menu, "Delete Column(s)", #selector(handleMenuDeleteColumns(_:)))
      }
      menu.addItem(.separator())
    }

    let borders = NSMenu(title: "Borders")
    addMenuItem(borders, "All Borders", #selector(handleMenuBorderAll(_:)))
    addMenuItem(borders, "Outside Borders", #selector(handleMenuBorderOutside(_:)))
    addMenuItem(borders, "Bottom Border", #selector(handleMenuBorderBottom(_:)))
    addMenuItem(borders, "No Border", #selector(handleMenuBorderNone(_:)))
    let bordersItem = NSMenuItem(title: "Borders", action: nil, keyEquivalent: "")
    bordersItem.submenu = borders
    menu.addItem(bordersItem)

    let freeze = NSMenu(title: "Freeze")
    addMenuItem(freeze, "Freeze Panes", #selector(handleMenuFreezePanes(_:)))
    addMenuItem(freeze, "Freeze Rows", #selector(handleMenuFreezeRows(_:)))
    addMenuItem(freeze, "Freeze Columns", #selector(handleMenuFreezeColumns(_:)))
    freeze.addItem(.separator())
    addMenuItem(freeze, "Unfreeze Panes", #selector(handleMenuUnfreezePanes(_:)))
    let freezeItem = NSMenuItem(title: "Freeze", action: nil, keyEquivalent: "")
    freezeItem.submenu = freeze
    menu.addItem(freezeItem)
  }

  @discardableResult
  private func addMenuItem(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
    let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }

  private func addStructureMenuItems(to menu: NSMenu) {
    addStructureSubmenus(to: menu)
  }

  @objc private func handleMenuCut(_ sender: Any?) {
    viewModel?.cutSelection()
    syncDisplay()
  }

  @objc private func handleMenuCopy(_ sender: Any?) {
    guard let text = viewModel?.copySelection() else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  @objc private func handleMenuPaste(_ sender: Any?) {
    viewModel?.pasteFromPasteboard()
    syncDisplay()
  }

  @objc private func handleMenuInsertRowAbove(_ sender: Any?) {
    viewModel?.insertRowsAbove()
    syncDisplay()
  }

  @objc private func handleMenuInsertRowBelow(_ sender: Any?) {
    viewModel?.insertRowsBelow()
    syncDisplay()
  }

  @objc private func handleMenuDeleteRows(_ sender: Any?) {
    viewModel?.deleteSelectedRows()
    syncDisplay()
  }

  @objc private func handleMenuInsertColumnLeft(_ sender: Any?) {
    viewModel?.insertColumnsLeft()
    syncDisplay()
  }

  @objc private func handleMenuInsertColumnRight(_ sender: Any?) {
    viewModel?.insertColumnsRight()
    syncDisplay()
  }

  @objc private func handleMenuDeleteColumns(_ sender: Any?) {
    viewModel?.deleteSelectedColumns()
    syncDisplay()
  }

  @objc private func handleMenuFreezePanes(_ sender: Any?) {
    guard viewModel?.freezePanesAtSelection() == true else {
      Self.presentFreezeRequiresOffsetAlert(axis: .both)
      return
    }
    applyFreezePanesLayout()
  }

  @objc private func handleMenuFreezeRows(_ sender: Any?) {
    guard viewModel?.freezeRowsAtSelection() == true else {
      Self.presentFreezeRequiresOffsetAlert(axis: .rows)
      return
    }
    applyFreezePanesLayout()
  }

  @objc private func handleMenuFreezeColumns(_ sender: Any?) {
    guard viewModel?.freezeColumnsAtSelection() == true else {
      Self.presentFreezeRequiresOffsetAlert(axis: .columns)
      return
    }
    applyFreezePanesLayout()
  }

  @objc private func handleMenuUnfreezePanes(_ sender: Any?) {
    viewModel?.unfreezePanes()
    applyFreezePanesLayout()
  }

  @objc private func handleMenuMergeAll(_ sender: Any?) {
    viewModel?.mergeSelection(axis: .all)
    syncDisplay()
  }

  @objc private func handleMenuMergeAcross(_ sender: Any?) {
    viewModel?.mergeSelection(axis: .horizontal)
    syncDisplay()
  }

  @objc private func handleMenuMergeVertical(_ sender: Any?) {
    viewModel?.mergeSelection(axis: .vertical)
    syncDisplay()
  }

  @objc private func handleMenuUnmerge(_ sender: Any?) {
    viewModel?.unmergeSelection()
    syncDisplay()
  }

  @objc private func handleMenuBorderAll(_ sender: Any?) {
    viewModel?.applyBorderPreset(.all)
    syncDisplay()
  }

  @objc private func handleMenuBorderOutside(_ sender: Any?) {
    viewModel?.applyBorderPreset(.outside)
    syncDisplay()
  }

  @objc private func handleMenuBorderBottom(_ sender: Any?) {
    viewModel?.applyBorderPreset(.bottom)
    syncDisplay()
  }

  @objc private func handleMenuBorderNone(_ sender: Any?) {
    viewModel?.applyBorderPreset(.none)
    syncDisplay()
  }

  @objc private func handleMenuCreateFilter(_ sender: Any?) {
    viewModel?.createFilter()
    syncDisplay()
  }

  @objc private func handleMenuClearFilter(_ sender: Any?) {
    viewModel?.clearFilter()
    syncDisplay()
  }

  @objc private func handleMenuClearColumnFilter(_ sender: Any?) {
    guard let viewModel else { return }
    viewModel.clearColumnFilter(viewModel.selectionAnchor.col)
    syncDisplay()
  }

  enum FreezeAlertAxis {
    case both
    case rows
    case columns
  }

  static func presentFreezeRequiresOffsetAlert(axis: FreezeAlertAxis) {
    let alert = NSAlert()
    alert.messageText = "Can’t Freeze Panes"
    switch axis {
    case .both:
      alert.informativeText = "Select the bottom-right cell of the area you want to keep visible, then try again. For example, select B2 to freeze row 1 and column A."
    case .rows:
      alert.informativeText = "Select the last row you want to keep frozen. For example, select row 3 to freeze rows 1–3."
    case .columns:
      alert.informativeText = "Select the last column you want to keep frozen. For example, select column C to freeze columns A–C."
    }
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  // MARK: - Keyboard

  @objc override func selectAll(_ sender: Any?) {
    viewModel?.selectAll()
    needsDisplay = true
  }

  override func keyDown(with event: NSEvent) {
    guard let viewModel, !isEditorActive else {
      super.keyDown(with: event)
      return
    }

    switch event.keyCode {
    case 51, 117:
      if viewModel.selectedImageID != nil {
        viewModel.deleteSelectedImage()
        needsDisplay = true
        return
      }
      viewModel.clearSelection()
    case 123: viewModel.moveSelection(rowDelta: 0, colDelta: -1, extending: event.modifierFlags.contains(.shift))
    case 124: viewModel.moveSelection(rowDelta: 0, colDelta: 1, extending: event.modifierFlags.contains(.shift))
    case 125: viewModel.moveSelection(rowDelta: 1, colDelta: 0, extending: event.modifierFlags.contains(.shift))
    case 126: viewModel.moveSelection(rowDelta: -1, colDelta: 0, extending: event.modifierFlags.contains(.shift))
    case 36:
      editorEntryMode = .inCellEdit
      viewModel.beginEditing()
      showEditor(selectAll: false)
      return
    case 48:
      viewModel.moveSelection(rowDelta: 0, colDelta: event.modifierFlags.contains(.shift) ? -1 : 1, extending: event.modifierFlags.contains(.shift))
    default:
      if let chars = event.characters, chars.count == 1, let scalar = chars.unicodeScalars.first {
        let isPrintable = CharacterSet.alphanumerics.contains(scalar)
          || CharacterSet.punctuationCharacters.contains(scalar)
          || CharacterSet.symbols.contains(scalar)
          || scalar == " "
        if isPrintable {
          editorEntryMode = .replaceOnType
          viewModel.editText = chars
          viewModel.isEditing = true
          showEditor(selectAll: false)
          return
        }
      }
      super.keyDown(with: event)
    }
    scrollSelectionIntoView()
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let settings = AppSettings.shared
    let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
    if event.charactersIgnoringModifiers?.lowercased() == "a", mods == .command {
      viewModel?.selectAll()
      needsDisplay = true
      return true
    }
    if settings.matches(.copy, event: event) {
      if let text = viewModel?.copySelection() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return true
      }
    }
    if settings.matches(.cut, event: event) {
      viewModel?.cutSelection()
      syncDisplay()
      return true
    }
    if settings.matches(.paste, event: event) {
      viewModel?.pasteFromPasteboard()
      syncDisplay()
      return true
    }
    if settings.matches(.copyFormulas, event: event) {
      viewModel?.copyFormulas()
      return true
    }
    if settings.matches(.pasteFormulas, event: event) {
      viewModel?.pasteFormulasFromPasteboard()
      syncDisplay()
      return true
    }
    if settings.matches(.convertToValues, event: event) {
      viewModel?.convertSelectionToValues()
      syncDisplay()
      return true
    }
    if settings.matches(.bold, event: event) {
      viewModel?.toggleBold()
      syncDisplay()
      return true
    }
    if settings.matches(.italic, event: event) {
      viewModel?.toggleItalic()
      syncDisplay()
      return true
    }
    if settings.matches(.underline, event: event) {
      viewModel?.toggleUnderline()
      syncDisplay()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}

extension SpreadsheetGridNSView: NSTextFieldDelegate {
  func control(
    _ control: NSControl,
    textView: NSTextView,
    doCommandBy commandSelector: Selector
  ) -> Bool {
    guard isEditorActive else { return false }

    if editorEntryMode == .replaceOnType {
      switch commandSelector {
      case #selector(NSResponder.insertNewline(_:)):
        commitEditorAndMove(rowDelta: 1, colDelta: 0)
        return true
      case #selector(NSResponder.moveUp(_:)):
        commitEditorAndMove(rowDelta: -1, colDelta: 0)
        return true
      case #selector(NSResponder.moveDown(_:)):
        commitEditorAndMove(rowDelta: 1, colDelta: 0)
        return true
      case #selector(NSResponder.moveLeft(_:)):
        commitEditorAndMove(rowDelta: 0, colDelta: -1)
        return true
      case #selector(NSResponder.moveRight(_:)):
        commitEditorAndMove(rowDelta: 0, colDelta: 1)
        return true
      default:
        return false
      }
    }

    if commandSelector == #selector(NSResponder.insertTab(_:)) {
      return applyFormulaTabCompletion(in: textView)
    }

    if commandSelector == #selector(NSResponder.insertNewline(_:)) {
      commitEditorAndMove(rowDelta: 1, colDelta: 0)
      return true
    }

    return false
  }

  private var namedRangeNames: [String] {
    guard let keys = viewModel?.workbook.namedRanges.keys else { return [] }
    return Array(keys)
  }

  @discardableResult
  private func applyFormulaTabCompletion(in textView: NSTextView) -> Bool {
    let cursor = textView.selectedRange.location
    guard let result = FormulaAutocomplete.tabComplete(
      text: textView.string,
      utf16Cursor: cursor,
      namedRanges: namedRangeNames
    ) else { return false }
    textView.string = result.text
    textView.setSelectedRange(NSRange(location: result.cursor, length: 0))
    editor.stringValue = result.text
    viewModel?.editText = result.text
    viewModel?.noteFormulaEditTextChanged()
    return true
  }

  func controlTextDidEndEditing(_ obj: Notification) {
    guard isEditorActive else { return }
    hideEditor(commit: true)
  }

  func controlTextDidChange(_ obj: Notification) {
    guard !isApplyingFormulaAttributes else { return }
    viewModel?.editText = editor.stringValue
    viewModel?.noteFormulaEditTextChanged()
    if let fieldEditor = editor.currentEditor() as? NSTextView {
      viewModel?.updateFormulaHighlightFocus(atUTF16: fieldEditor.selectedRange.location)
    }
    applyInCellFormulaAttributes(preserveSelection: true)
    maybeOfferFormulaCompletions()
  }

  func control(
    _ control: NSControl,
    textView: NSTextView,
    completions words: [String],
    forPartialWordRange charRange: NSRange,
    indexOfSelectedItem index: UnsafeMutablePointer<Int>
  ) -> [String] {
    guard editor.stringValue.hasPrefix("=") else { return [] }
    guard FormulaAutocomplete.shouldOfferPopup(
      in: textView.string,
      utf16Cursor: charRange.location + charRange.length,
      namedRanges: namedRangeNames
    ) else { return [] }
    let partial = (textView.string as NSString).substring(with: charRange)
    index.pointee = 0
    return FormulaAutocomplete.suggestions(
      matching: partial,
      namedRanges: namedRangeNames
    )
  }

  private func maybeOfferFormulaCompletions() {
    guard let window = window,
          let fieldEditor = window.fieldEditor(false, for: editor) as? NSTextView
    else { return }

    let cursor = fieldEditor.selectedRange.location
    guard FormulaAutocomplete.shouldOfferPopup(
      in: fieldEditor.string,
      utf16Cursor: cursor,
      namedRanges: namedRangeNames
    ) else {
      NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(triggerFormulaComplete), object: nil)
      return
    }

    NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(triggerFormulaComplete), object: nil)
    perform(#selector(triggerFormulaComplete), with: nil, afterDelay: 0.12)
  }

  @objc private func triggerFormulaComplete() {
    guard isEditorActive,
          !isApplyingFormulaAttributes,
          let window = window,
          let fieldEditor = window.fieldEditor(false, for: editor) as? NSTextView
    else { return }
    fieldEditor.complete(nil)
  }
}
