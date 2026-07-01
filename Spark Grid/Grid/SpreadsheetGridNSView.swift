import AppKit

/// AppKit spreadsheet grid with sticky row/column headers, selection, editing, and keyboard navigation.
final class SpreadsheetGridNSView: NSView {
  static let headerSize: CGFloat = 28
  static let defaultColumnWidth = Workbook.defaultColumnWidth
  static let defaultRowHeight = Workbook.defaultRowHeight
  private static let darkModeGridLine = NSColor(
    calibratedRed: 53.0 / 255.0,
    green: 53.0 / 255.0,
    blue: 53.0 / 255.0,
    alpha: 1.0
  )

  var viewModel: SpreadsheetViewModel? {
    didSet { needsDisplay = true }
  }

  private var scrollOrigin = CGPoint.zero
  private let editor = NSTextField()
  private var isEditorActive = false
  private var isDraggingSelection = false

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
      x: Self.headerSize,
      y: Self.headerSize,
      width: max(0, bounds.width - Self.headerSize),
      height: max(0, bounds.height - Self.headerSize)
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
      return NSColor.gridColor
    }
  }

  private func headerLineColor() -> NSColor {
    switch effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
    case .darkAqua:
      return Self.darkModeGridLine
    default:
      return NSColor.separatorColor
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    configureEditor()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func resetScroll() {
    scrollOrigin = .zero
    needsDisplay = true
  }

  private func configureEditor() {
    editor.isBordered = true
    editor.isBezeled = true
    editor.bezelStyle = .squareBezel
    editor.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    editor.delegate = self
    editor.isHidden = true
    addSubview(editor)
  }

  // MARK: - Layout helpers

  private func columnWidth(at col: Int) -> CGFloat {
    guard let sheet = viewModel?.activeSheet else { return Self.defaultColumnWidth }
    return sheet.columnWidth(for: col, default: Self.defaultColumnWidth)
  }

  private func rowHeight(at row: Int) -> CGFloat {
    guard let sheet = viewModel?.activeSheet else { return Self.defaultRowHeight }
    return sheet.rowHeight(for: row, default: Self.defaultRowHeight)
  }

  private func xForColumn(_ col: Int) -> CGFloat {
    var x = Self.headerSize
    for c in 0..<col { x += columnWidth(at: c) }
    return x
  }

  private func yForRow(_ row: Int) -> CGFloat {
    var y = Self.headerSize
    for r in 0..<row { y += rowHeight(at: r) }
    return y
  }

  private func columnAtContent(x: CGFloat) -> Int {
    var remaining = x - Self.headerSize + scrollOrigin.x
    guard remaining >= 0 else { return 0 }
    var col = 0
    while col < Workbook.defaultColumnCount {
      let width = columnWidth(at: col)
      if remaining < width { return col }
      remaining -= width
      col += 1
    }
    return Workbook.defaultColumnCount - 1
  }

  private func rowAtContent(y: CGFloat) -> Int {
    var remaining = y - Self.headerSize + scrollOrigin.y
    guard remaining >= 0 else { return 0 }
    var row = 0
    while row < Workbook.defaultRowCount {
      let height = rowHeight(at: row)
      if remaining < height { return row }
      remaining -= height
      row += 1
    }
    return Workbook.defaultRowCount - 1
  }

  private func rectForCell(row: Int, col: Int) -> NSRect {
    NSRect(
      x: xForColumn(col) - scrollOrigin.x,
      y: yForRow(row) - scrollOrigin.y,
      width: columnWidth(at: col),
      height: rowHeight(at: row)
    )
  }

  private func isCellRectInContentArea(_ rect: NSRect) -> Bool {
    rect.maxX > Self.headerSize
      && rect.maxY > Self.headerSize
      && rect.minX < bounds.width
      && rect.minY < bounds.height
  }

  private func visibleColumnRange() -> ClosedRange<Int> {
    let content = contentRect
    let first = max(0, columnAtContent(x: content.minX))
    let last = min(Workbook.defaultColumnCount - 1, columnAtContent(x: content.maxX))
    return first...last
  }

  private func visibleRowRange() -> ClosedRange<Int> {
    let content = contentRect
    let first = max(0, rowAtContent(y: content.minY))
    let last = min(Workbook.defaultRowCount - 1, rowAtContent(y: content.maxY))
    return first...last
  }

  private func totalContentSize() -> NSSize {
    var width = Self.headerSize
    for col in 0..<Workbook.defaultColumnCount { width += columnWidth(at: col) }
    var height = Self.headerSize
    for row in 0..<Workbook.defaultRowCount { height += rowHeight(at: row) }
    return NSSize(width: width, height: height)
  }

  private func clampScrollOrigin() {
    let content = totalContentSize()
    let maxX = max(0, content.width - bounds.width)
    let maxY = max(0, content.height - bounds.height)
    scrollOrigin.x = min(max(0, scrollOrigin.x), maxX)
    scrollOrigin.y = min(max(0, scrollOrigin.y), maxY)
  }

  private func ensureSelectionVisible() {
    guard let viewModel else { return }
    let range = viewModel.selectionRange.normalized
    let topLeft = rectForCell(row: range.minRow, col: range.minCol)
    let bottomRight = rectForCell(row: range.maxRow, col: range.maxCol)
    let selectionRect = NSRect(
      x: topLeft.minX,
      y: topLeft.minY,
      width: bottomRight.maxX - topLeft.minX,
      height: bottomRight.maxY - topLeft.minY
    )
    let visible = contentRect
    if selectionRect.minX < visible.minX {
      scrollOrigin.x -= visible.minX - selectionRect.minX
    } else if selectionRect.maxX > visible.maxX {
      scrollOrigin.x += selectionRect.maxX - visible.maxX
    }
    if selectionRect.minY < visible.minY {
      scrollOrigin.y -= visible.minY - selectionRect.minY
    } else if selectionRect.maxY > visible.maxY {
      scrollOrigin.y += selectionRect.maxY - visible.maxY
    }
    clampScrollOrigin()
  }

  private func headerHit(at point: NSPoint) -> HeaderHit {
    if point.x < Self.headerSize && point.y < Self.headerSize { return .corner }
    if point.y < Self.headerSize && point.x >= Self.headerSize {
      return .column(columnAtContent(x: point.x))
    }
    if point.x < Self.headerSize && point.y >= Self.headerSize {
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

  // MARK: - Drawing

  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    dirtyRect.fill()

  // 1. Grid lines and cells in the content area (clipped).
    if let ctx = NSGraphicsContext.current {
      ctx.saveGraphicsState()
      NSBezierPath(rect: contentRect).addClip()
      drawGridLines(in: dirtyRect)
      drawCells(in: dirtyRect)
      drawSelection(in: dirtyRect)
      ctx.restoreGraphicsState()
    }

    // 2. Sticky headers drawn on top so scrolled cell text cannot bleed through.
    drawStickyHeaders(in: dirtyRect)
  }

  private func drawStickyHeaders(in dirtyRect: NSRect) {
    let headerFill = NSColor.controlBackgroundColor
    let headerText = NSColor.secondaryLabelColor
    let gridLine = headerLineColor()
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11, weight: .medium),
      .foregroundColor: headerText,
    ]

    // Opaque header bands (cover any scrolled cell text underneath).
    let topBand = NSRect(x: 0, y: 0, width: bounds.width, height: Self.headerSize)
    if dirtyRect.intersects(topBand) {
      headerFill.setFill()
      topBand.fill()
    }
    let leftBand = NSRect(x: 0, y: 0, width: Self.headerSize, height: bounds.height)
    if dirtyRect.intersects(leftBand) {
      headerFill.setFill()
      leftBand.fill()
    }

    // Column headers (fixed vertically, scroll horizontally).
    let colRange = visibleColumnRange()
    for col in colRange {
      let cellX = xForColumn(col) - scrollOrigin.x
      let rect = NSRect(x: cellX, y: 0, width: columnWidth(at: col), height: Self.headerSize)
      guard rect.maxX > Self.headerSize, dirtyRect.intersects(rect) else { continue }
      headerFill.setFill()
      rect.fill()
      let label = A1Notation.columnLabel(for: col) as NSString
      let size = label.size(withAttributes: attrs)
      label.draw(
        at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
        withAttributes: attrs
      )
      gridLine.setStroke()
      NSBezierPath.strokeLine(from: NSPoint(x: rect.maxX, y: 0), to: NSPoint(x: rect.maxX, y: rect.maxY))
    }

    // Row headers (fixed horizontally, scroll vertically).
    let rowRange = visibleRowRange()
    for row in rowRange {
      let cellY = yForRow(row) - scrollOrigin.y
      let rect = NSRect(x: 0, y: cellY, width: Self.headerSize, height: rowHeight(at: row))
      guard rect.maxY > Self.headerSize, dirtyRect.intersects(rect) else { continue }
      headerFill.setFill()
      rect.fill()
      let label = "\(row + 1)" as NSString
      let size = label.size(withAttributes: attrs)
      label.draw(
        at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
        withAttributes: attrs
      )
      gridLine.setStroke()
      NSBezierPath.strokeLine(from: NSPoint(x: 0, y: rect.maxY), to: NSPoint(x: rect.maxX, y: rect.maxY))
    }

    // Corner border.
    let corner = NSRect(x: 0, y: 0, width: Self.headerSize, height: Self.headerSize)
    if dirtyRect.intersects(corner) {
      gridLine.setStroke()
      NSBezierPath.strokeLine(from: NSPoint(x: corner.maxX, y: 0), to: NSPoint(x: corner.maxX, y: corner.maxY))
      NSBezierPath.strokeLine(from: NSPoint(x: 0, y: corner.maxY), to: NSPoint(x: corner.maxX, y: corner.maxY))
    }
  }

  private func drawGridLines(in dirtyRect: NSRect) {
    gridLineColor().setStroke()
    let path = NSBezierPath()
    path.lineWidth = 0.5
    let content = contentRect

    let colRange = visibleColumnRange()
    for col in colRange {
      let x = xForColumn(col) - scrollOrigin.x
      path.move(to: NSPoint(x: x, y: content.minY))
      path.line(to: NSPoint(x: x, y: content.maxY))
      let maxX = x + columnWidth(at: col)
      path.move(to: NSPoint(x: maxX, y: content.minY))
      path.line(to: NSPoint(x: maxX, y: content.maxY))
    }

    let rowRange = visibleRowRange()
    for row in rowRange {
      let y = yForRow(row) - scrollOrigin.y
      path.move(to: NSPoint(x: content.minX, y: y))
      path.line(to: NSPoint(x: content.maxX, y: y))
      let maxY = y + rowHeight(at: row)
      path.move(to: NSPoint(x: content.minX, y: maxY))
      path.line(to: NSPoint(x: content.maxX, y: maxY))
    }
    path.stroke()
  }

  private func drawCells(in dirtyRect: NSRect) {
    guard let viewModel else { return }
    let sheet = viewModel.activeSheet

    let colRange = visibleColumnRange()
    let rowRange = visibleRowRange()

    for (address, cell) in sheet.cells where
      rowRange.contains(address.row) &&
      colRange.contains(address.col)
    {
      let rect = rectForCell(row: address.row, col: address.col)
      guard isCellRectInContentArea(rect), dirtyRect.intersects(rect) else { continue }
      if cell.raw.isEmpty && cell.format?.fillColor == nil { continue }
      if viewModel.isEditing && address == viewModel.selectionAnchor && isEditorActive { continue }

      if let fill = CellFormatRenderer.fillColor(for: cell.format) {
        fill.setFill()
        rect.fill()
      }

      guard !cell.raw.isEmpty else { continue }

      let text = CellFormatRenderer.displayText(raw: cell.raw, format: cell.format)
      let textRect = rect.insetBy(dx: 4, dy: 2)
      guard textRect.width > 1, textRect.height > 1 else { continue }

      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: rect).addClip()
      CellFormatRenderer.drawText(text, in: textRect, format: cell.format)
      NSGraphicsContext.restoreGraphicsState()
    }
  }

  private func drawSelection(in dirtyRect: NSRect) {
    guard let viewModel else { return }
    let range = viewModel.selectionRange.normalized

    for row in range.minRow...range.maxRow {
      for col in range.minCol...range.maxCol {
        let rect = rectForCell(row: row, col: col)
        guard isCellRectInContentArea(rect), dirtyRect.intersects(rect) else { continue }
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.12).setFill()
        rect.fill()
      }
    }

    let topLeft = rectForCell(row: range.minRow, col: range.minCol)
    let bottomRight = rectForCell(row: range.maxRow, col: range.maxCol)
    let outer = NSRect(
      x: topLeft.minX,
      y: topLeft.minY,
      width: bottomRight.maxX - topLeft.minX,
      height: bottomRight.maxY - topLeft.minY
    )
    guard isCellRectInContentArea(outer), dirtyRect.intersects(outer) else { return }

    NSColor.controlAccentColor.setStroke()
    let border = NSBezierPath(rect: outer.insetBy(dx: 0.5, dy: 0.5))
    border.lineWidth = 2
    border.stroke()

    let anchor = rectForCell(row: viewModel.selectionAnchor.row, col: viewModel.selectionAnchor.col)
    if isCellRectInContentArea(anchor) {
      NSColor.controlAccentColor.setFill()
      NSRect(x: anchor.minX, y: anchor.minY, width: 2, height: anchor.height).fill()
      NSRect(x: anchor.minX, y: anchor.minY, width: anchor.width, height: 2).fill()
    }
  }

  // MARK: - Editor

  func showEditor() {
    guard let viewModel else { return }
    let rect = rectForCell(row: viewModel.selectionAnchor.row, col: viewModel.selectionAnchor.col)
    guard isCellRectInContentArea(rect) else { return }
    isEditorActive = true
    editor.stringValue = viewModel.editText
    applyEditorFormat(from: viewModel.selectedCell.format)
    updateEditorFrame()
    editor.isHidden = false
    window?.makeFirstResponder(editor)
    editor.currentEditor()?.selectAll(nil)
  }

  private func applyEditorFormat(from format: CellFormat?) {
    editor.font = CellFormatRenderer.font(for: format ?? CellFormat())
    if let color = CellFormatRenderer.nsColor(format?.textColor) {
      editor.textColor = color
    } else {
      editor.textColor = NSColor.labelColor
    }
  }

  func hideEditor(commit: Bool) {
    guard isEditorActive else { return }
    if commit, let viewModel {
      viewModel.editText = editor.stringValue
      viewModel.commitEdit()
    }
    editor.isHidden = true
    isEditorActive = false
    window?.makeFirstResponder(self)
    needsDisplay = true
  }

  private func updateEditorFrame() {
    guard let viewModel else { return }
    let rect = rectForCell(row: viewModel.selectionAnchor.row, col: viewModel.selectionAnchor.col).insetBy(dx: 1, dy: 1)
    guard rect.width > 4, rect.height > 4 else {
      editor.isHidden = true
      return
    }
    editor.frame = rect
  }

  func syncDisplay() {
    updateEditorFrame()
    needsDisplay = true
  }

  func reloadContent() {
    resetScroll()
    updateEditorFrame()
    needsDisplay = true
  }

  func scrollSelectionIntoView() {
    ensureSelectionVisible()
    updateEditorFrame()
    needsDisplay = true
  }

  // MARK: - Mouse

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let point = convert(event.locationInWindow, from: nil)

    if isEditorActive { hideEditor(commit: true) }

    switch headerHit(at: point) {
    case .corner:
      viewModel?.selectAll()
      needsDisplay = true
      return
    case .column(let col):
      if event.clickCount >= 2 {
        viewModel?.autoFitColumn(col)
        needsDisplay = true
      }
      return
    case .row(let row):
      if event.clickCount >= 2 {
        viewModel?.autoFitRow(row)
        needsDisplay = true
      }
      return
    case .content:
      break
    }

    guard contentRect.contains(point) else { return }

    let address = addressAtContent(point: point)
    isDraggingSelection = true
    viewModel?.selectRange(from: address, to: address)

    if event.clickCount >= 2 {
      isDraggingSelection = false
      viewModel?.beginEditing()
      showEditor()
    } else {
      scrollSelectionIntoView()
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard isDraggingSelection, let viewModel else { return }
    let point = convert(event.locationInWindow, from: nil)
    let clamped = NSPoint(
      x: max(contentRect.minX, min(point.x, contentRect.maxX - 1)),
      y: max(contentRect.minY, min(point.y, contentRect.maxY - 1))
    )
    viewModel.extendSelection(to: addressAtContent(point: clamped))
    scrollSelectionIntoView()
  }

  override func mouseUp(with event: NSEvent) {
    isDraggingSelection = false
  }

  override func scrollWheel(with event: NSEvent) {
    scrollOrigin.x += event.scrollingDeltaX
    scrollOrigin.y += event.scrollingDeltaY
    clampScrollOrigin()
    updateEditorFrame()
    needsDisplay = true
  }

  // MARK: - Keyboard

  override func keyDown(with event: NSEvent) {
    guard let viewModel, !isEditorActive else {
      super.keyDown(with: event)
      return
    }

    switch event.keyCode {
    case 123: viewModel.moveSelection(rowDelta: 0, colDelta: -1, extending: event.modifierFlags.contains(.shift))
    case 124: viewModel.moveSelection(rowDelta: 0, colDelta: 1, extending: event.modifierFlags.contains(.shift))
    case 125: viewModel.moveSelection(rowDelta: 1, colDelta: 0, extending: event.modifierFlags.contains(.shift))
    case 126: viewModel.moveSelection(rowDelta: -1, colDelta: 0, extending: event.modifierFlags.contains(.shift))
    case 36:
      viewModel.beginEditing()
      showEditor()
      return
    case 48:
      viewModel.moveSelection(rowDelta: 0, colDelta: event.modifierFlags.contains(.shift) ? -1 : 1, extending: event.modifierFlags.contains(.shift))
    case 51:
      viewModel.setCellValue("", at: viewModel.selectionAnchor)
      viewModel.syncEditTextFromSelection()
    default:
      if let chars = event.characters, chars.count == 1, let scalar = chars.unicodeScalars.first {
        let isPrintable = CharacterSet.alphanumerics.contains(scalar)
          || CharacterSet.punctuationCharacters.contains(scalar)
          || CharacterSet.symbols.contains(scalar)
          || scalar == " "
        if isPrintable {
          viewModel.editText = chars
          viewModel.isEditing = true
          showEditor()
          return
        }
      }
      super.keyDown(with: event)
    }
    scrollSelectionIntoView()
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard event.modifierFlags.contains(.command) else {
      return super.performKeyEquivalent(with: event)
    }
    switch event.charactersIgnoringModifiers?.lowercased() {
    case "c":
      if let text = viewModel?.copySelection() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return true
      }
    case "x":
      viewModel?.cutSelection()
      syncDisplay()
      return true
    case "v":
      viewModel?.pasteFromPasteboard()
      syncDisplay()
      return true
    default:
      break
    }
    return super.performKeyEquivalent(with: event)
  }
}

extension SpreadsheetGridNSView: NSTextFieldDelegate {
  func controlTextDidEndEditing(_ obj: Notification) {
    guard isEditorActive else { return }
    hideEditor(commit: true)
  }

  func controlTextDidChange(_ obj: Notification) {
    viewModel?.editText = editor.stringValue
  }
}
