import Foundation
import Observation

/// UI state and mutations for the active workbook. Undo integrates with the document undo manager.
@Observable
@MainActor
final class SpreadsheetViewModel {
  /// When true, `workbook` didSet skips a full formula rebuild (format-only / batched edits).
  private var suspendFormulaRebuild = false

  var workbook: Workbook {
    didSet {
      contentRevision &+= 1
      hiddenRowsCache = nil
      conditionalFormatCache.removeAll(keepingCapacity: true)
      conditionalFormatCacheRevision = -1
      if !suspendFormulaRebuild {
        formulaEngine.rebuild(workbook: workbook)
      }
    }
  }
  var selectionAnchor: CellAddress = .origin
  var selectionEnd: CellAddress = .origin
  /// All selected regions. The last entry is the active range (matches anchor/end).
  private(set) var selectionRanges: [CellRange] = [.singleOrigin]
  var isEditing = false
  var editText = ""
  /// Bumps when formula edit text / focus changes so the grid can redraw ref highlights.
  private(set) var formulaHighlightRevision = 0
  /// Which formula reference token is focused (clicked in the formula bar).
  var focusedFormulaHighlightIndex: Int? = nil
  private(set) var contentRevision = 0
  private(set) var gridRefreshToken = 0
  private(set) var selectionRevision = 0
  /// Bumped when find/navigation wants the grid to scroll the selection into view.
  var scrollRequestToken = 0
  /// Selected embedded picture on the active sheet, if any.
  var selectedImageID: UUID?

  /// Insert Chart sheet presentation.
  var isInsertChartPresented = false
  var pendingChartKind: SheetChart.Kind = .bar

  // MARK: - Find / Replace
  var isFindBarVisible = false
  var isFindReplaceMode = false
  var findQuery = ""
  var findReplaceText = ""
  var findMatchCase = false
  var findEntireCell = false
  var findScope: FindScope = .sheet
  /// Stable range for Find-in-Selection so jumping to a match does not shrink search scope.
  var findScopeRange: CellRange?
  var findMatches: [CellAddress] = []
  var findMatchIndex: Int = -1

  // MARK: - Filter / Zoom
  var filterState: SheetFilterState? {
    didSet {
      hiddenRowsCache = nil
      // Keep sheet-backed AutoFilter in sync for save / xlsx export.
      if !isRestoringFilterFromSheet {
        syncAutoFilterToActiveSheet()
      }
      // Chevrons / hidden rows are grid-visual — always refresh when filter changes.
      if oldValue != filterState {
        notifyGridRefresh()
      }
    }
  }
  /// Cached rows hidden by the active filter (invalidated on filter/content changes).
  var hiddenRowsCache: Set<Int>?
  /// Avoid write-back loops when restoring filter from the sheet.
  var isRestoringFilterFromSheet = false
  /// Cache for conditional-format overlays (invalidated with contentRevision).
  var conditionalFormatCache: [CellAddress: ConditionalPaint] = [:]
  var conditionalFormatCacheRevision: Int = -1
  /// View zoom (0.5…2.0). Scales cell geometry in the grid.
  var zoomScale: CGFloat = 1.0 {
    didSet {
      let clamped = min(2.0, max(0.5, zoomScale))
      if abs(clamped - zoomScale) > 0.0001 {
        zoomScale = clamped
        return
      }
      if oldValue != zoomScale {
        notifyGridRefresh()
      }
    }
  }

  weak var undoManager: UndoManager?

  /// Evaluates `=` formulas; display helpers use this cache.
  let formulaEngine = FormulaEngine()

  /// Colored references for the formula being edited, or the selected cell's formula (preview).
  var formulaReferenceHighlights: [FormulaRefHighlight] {
    let raw = formulaTextForReferenceHighlights
    guard FormulaSyntax.isFormula(raw) else { return [] }
    let sheet = activeSheet
    return FormulaReferenceScanner.highlights(
      in: raw,
      maxRow: sheet.effectiveRowCount - 1,
      maxCol: sheet.effectiveColumnCount - 1
    )
  }

  /// Formula text that drives grid/formula-bar reference coloring.
  private var formulaTextForReferenceHighlights: String {
    if isEditing { return editText }
    return selectedCell.raw
  }

  func noteFormulaEditTextChanged() {
    // Grid ref overlays only matter for formulas (or clearing a prior focus chip).
    guard FormulaSyntax.isFormula(editText) || focusedFormulaHighlightIndex != nil else { return }
    formulaHighlightRevision &+= 1
  }

  func updateFormulaHighlightFocus(atUTF16 location: Int) {
    let raw = formulaTextForReferenceHighlights
    guard FormulaSyntax.isFormula(raw) else {
      if focusedFormulaHighlightIndex != nil {
        focusedFormulaHighlightIndex = nil
        formulaHighlightRevision &+= 1
      }
      return
    }
    // Allow caret focus while editing; when only selected, keep a stable preview.
    guard isEditing else { return }
    let newIndex = FormulaReferenceScanner.highlightIndex(
      atUTF16: location,
      in: formulaReferenceHighlights
    )
    guard newIndex != focusedFormulaHighlightIndex else { return }
    focusedFormulaHighlightIndex = newIndex
    formulaHighlightRevision &+= 1
  }

  func focusFormulaHighlight(atUTF16 location: Int) {
    updateFormulaHighlightFocus(atUTF16: location)
  }

  func notifyGridRefresh() {
    gridRefreshToken &+= 1
  }

  private func noteSelectionChanged() {
    selectionRevision &+= 1
    focusedFormulaHighlightIndex = nil
    // Keep dashed formula overlays in sync when leaving/entering formula cells.
    formulaHighlightRevision &+= 1
  }

  init(workbook: Workbook) {
    self.workbook = workbook
    formulaEngine.rebuild(workbook: workbook)
    syncEditTextFromSelection()
    // Pull AutoFilter from the sheet so Excel header-row filters appear immediately.
    isRestoringFilterFromSheet = true
    filterState = workbook.activeSheet.autoFilter
    isRestoringFilterFromSheet = false
  }

  func displayValue(at address: CellAddress) -> CellValue {
    formulaEngine.displayValue(at: address, sheet: activeSheet)
  }

  func displayString(at address: CellAddress) -> String {
    let cell = activeSheet.cell(at: address)
    return formulaEngine.displayString(at: address, sheet: activeSheet, format: cell.format)
  }

  /// Sheets-style explanation when the selected cell evaluates to a formula error.
  var selectedFormulaErrorExplanation: String? {
    guard !isEditing else { return nil }
    let value = displayValue(at: selectionAnchor)
    guard let error = value.formulaError else { return nil }
    return "\(error.displayCode) — \(error.explanation)"
  }

  var selection: CellAddress {
    get { selectionAnchor }
    set {
      replaceSelection(with: CellRange(start: newValue, end: newValue))
    }
  }

  var selectionRange: CellRange {
    CellRange(start: selectionAnchor, end: selectionEnd)
  }

  enum SelectionAxis: Equatable {
    case cells
    case row
    case column
    case sheet
  }

  var selectionAxis: SelectionAxis {
    let ranges = selectionRanges
    guard !ranges.isEmpty else { return .cells }
    let sheet = activeSheet
    let allSheet = ranges.allSatisfy { range in
      let n = range.normalized
      return n.minRow == 0 && n.maxRow >= sheet.effectiveRowCount - 1
        && n.minCol == 0 && n.maxCol >= sheet.effectiveColumnCount - 1
    }
    if allSheet { return .sheet }
    let allColumns = ranges.allSatisfy { range in
      let n = range.normalized
      return n.minRow == 0 && n.maxRow >= sheet.effectiveRowCount - 1
    }
    if allColumns { return .column }
    let allRows = ranges.allSatisfy { range in
      let n = range.normalized
      return n.minCol == 0 && n.maxCol >= sheet.effectiveColumnCount - 1
    }
    if allRows { return .row }
    return .cells
  }

  var hasMultipleSelectionRanges: Bool { selectionRanges.count > 1 }

  func isAddressSelected(_ address: CellAddress) -> Bool {
    selectionRanges.contains { $0.contains(address) }
  }

  func isColumnInSelection(_ col: Int) -> Bool {
    selectionRanges.contains { range in
      let n = range.normalized
      return col >= n.minCol && col <= n.maxCol
    }
  }

  func isRowInSelection(_ row: Int) -> Bool {
    selectionRanges.contains { range in
      let n = range.normalized
      return row >= n.minRow && row <= n.maxRow
    }
  }

  private func replaceSelection(with range: CellRange) {
    let clamped = CellRange(start: clamp(range.start), end: clamp(range.end))
    selectionAnchor = clamped.start
    selectionEnd = clamped.end
    selectionRanges = [clamped]
    noteSelectionChanged()
  }

  private func setPrimaryRange(from start: CellAddress, to end: CellAddress) {
    let clamped = CellRange(start: clamp(start), end: clamp(end))
    selectionAnchor = clamped.start
    selectionEnd = clamped.end
    if selectionRanges.isEmpty {
      selectionRanges = [clamped]
    } else {
      selectionRanges[selectionRanges.count - 1] = clamped
    }
    noteSelectionChanged()
  }

  var activeSheet: Sheet {
    get { workbook.activeSheet }
    set {
      workbook.activeSheet = newValue
    }
  }

  /// Format-only sheet writes — avoids re-parsing every formula on the sheet.
  func setActiveSheetPreservingFormulas(_ sheet: Sheet) {
    suspendFormulaRebuild = true
    workbook.activeSheet = sheet
    suspendFormulaRebuild = false
  }

  /// Value edits — incremental formula update instead of a full rebuild.
  private func setActiveSheet(_ sheet: Sheet, formulaCellsChanged addresses: [CellAddress]) {
    suspendFormulaRebuild = true
    workbook.activeSheet = sheet
    suspendFormulaRebuild = false
    if !addresses.isEmpty {
      formulaEngine.cellsDidChange(addresses, sheet: sheet)
    }
  }

  var selectedCell: Cell {
    activeSheet.cell(at: selectionAnchor)
  }

  var formulaBarText: String {
    get { isEditing ? editText : selectedCell.raw }
    set {
      editText = newValue
      if !isEditing { isEditing = true }
      noteFormulaEditTextChanged()
    }
  }

  func syncEditTextFromSelection() {
    editText = selectedCell.raw
  }

  func selectRange(from start: CellAddress, to end: CellAddress) {
    commitEditIfNeeded()
    let expanded = activeSheet.selectionExpandedForMerges(CellRange(start: start, end: end))
    replaceSelection(with: expanded)
    syncEditTextFromSelection()
    isEditing = false
  }

  func extendSelection(to end: CellAddress) {
    let tip = clamp(end)
    selectionEnd = tip
    // Expand for merges in the painted range only — never move the drag origin
    // to the normalized top-left (that breaks right→left / bottom→top drags).
    let expanded = activeSheet.selectionExpandedForMerges(
      CellRange(start: selectionAnchor, end: tip)
    )
    let painted = CellRange(start: clamp(expanded.start), end: clamp(expanded.end))
    if selectionRanges.isEmpty {
      selectionRanges = [painted]
    } else {
      selectionRanges[selectionRanges.count - 1] = painted
    }
    noteSelectionChanged()
  }

  /// ⌘-click a cell to add/remove it from a discontinuous selection.
  func commandClickCell(_ address: CellAddress) {
    commitEditIfNeeded()
    let target = clamp(address)
    let single = CellRange(start: target, end: target)

    if let index = selectionRanges.firstIndex(where: { range in
      let n = range.normalized
      return n.minRow == target.row && n.maxRow == target.row
        && n.minCol == target.col && n.maxCol == target.col
    }) {
      if selectionRanges.count == 1 {
        replaceSelection(with: single)
      } else {
        selectionRanges.remove(at: index)
        let active = selectionRanges.last ?? single
        selectionAnchor = active.start
        selectionEnd = active.end
        noteSelectionChanged()
      }
    } else {
      selectionRanges.append(single)
      selectionAnchor = target
      selectionEnd = target
      noteSelectionChanged()
    }
    syncEditTextFromSelection()
    isEditing = false
  }

  /// ⌘-click a column header to add/remove that column.
  func commandClickColumn(_ col: Int) {
    commitEditIfNeeded()
    let sheet = activeSheet
    let clampedCol = max(0, min(sheet.effectiveColumnCount - 1, col))
    let columnRange = CellRange(
      start: CellAddress(row: 0, col: clampedCol),
      end: CellAddress(row: sheet.effectiveRowCount - 1, col: clampedCol)
    )

    if let index = selectionRanges.firstIndex(where: { range in
      let n = range.normalized
      return n.minCol == clampedCol && n.maxCol == clampedCol
        && n.minRow == 0 && n.maxRow >= sheet.effectiveRowCount - 1
    }) {
      if selectionRanges.count == 1 {
        replaceSelection(with: columnRange)
      } else {
        selectionRanges.remove(at: index)
        let active = selectionRanges.last ?? columnRange
        selectionAnchor = active.start
        selectionEnd = active.end
        noteSelectionChanged()
      }
    } else {
      selectionRanges.append(columnRange)
      selectionAnchor = columnRange.start
      selectionEnd = columnRange.end
      noteSelectionChanged()
    }
    syncEditTextFromSelection()
    isEditing = false
  }

  /// ⌘-click a row header to add/remove that row.
  func commandClickRow(_ row: Int) {
    commitEditIfNeeded()
    let sheet = activeSheet
    let clampedRow = max(0, min(sheet.effectiveRowCount - 1, row))
    let rowRange = CellRange(
      start: CellAddress(row: clampedRow, col: 0),
      end: CellAddress(row: clampedRow, col: sheet.effectiveColumnCount - 1)
    )

    if let index = selectionRanges.firstIndex(where: { range in
      let n = range.normalized
      return n.minRow == clampedRow && n.maxRow == clampedRow
        && n.minCol == 0 && n.maxCol >= sheet.effectiveColumnCount - 1
    }) {
      if selectionRanges.count == 1 {
        replaceSelection(with: rowRange)
      } else {
        selectionRanges.remove(at: index)
        let active = selectionRanges.last ?? rowRange
        selectionAnchor = active.start
        selectionEnd = active.end
        noteSelectionChanged()
      }
    } else {
      selectionRanges.append(rowRange)
      selectionAnchor = rowRange.start
      selectionEnd = rowRange.end
      noteSelectionChanged()
    }
    syncEditTextFromSelection()
    isEditing = false
  }

  /// ⌘A / Edit → Select All: always the entire sheet.
  func selectAll() {
    commitEditIfNeeded()
    let sheet = activeSheet
    let wholeEnd = CellAddress(
      row: sheet.effectiveRowCount - 1,
      col: sheet.effectiveColumnCount - 1
    )
    replaceSelection(with: CellRange(start: .origin, end: wholeEnd))
    syncEditTextFromSelection()
    isEditing = false
  }

  /// Corner-header click: used range first, then whole sheet (Excel-style).
  func selectUsedRangeOrAll() {
    commitEditIfNeeded()
    let sheet = activeSheet
    let wholeEnd = CellAddress(
      row: sheet.effectiveRowCount - 1,
      col: sheet.effectiveColumnCount - 1
    )

    if let used = sheet.populatedBounds {
      let usedNorm = used.normalized
      let current = selectionRange.normalized
      let alreadyUsed =
        !hasMultipleSelectionRanges
        && current.minRow == usedNorm.minRow
        && current.maxRow == usedNorm.maxRow
        && current.minCol == usedNorm.minCol
        && current.maxCol == usedNorm.maxCol
      if alreadyUsed {
        replaceSelection(with: CellRange(start: .origin, end: wholeEnd))
      } else {
        replaceSelection(with: CellRange(
          start: CellAddress(row: usedNorm.minRow, col: usedNorm.minCol),
          end: CellAddress(row: usedNorm.maxRow, col: usedNorm.maxCol)
        ))
      }
    } else {
      replaceSelection(with: CellRange(start: .origin, end: wholeEnd))
    }
    syncEditTextFromSelection()
    isEditing = false
  }

  func toggleSelectAll() {
    if selectionAxis == .sheet {
      select(.origin)
    } else {
      selectUsedRangeOrAll()
    }
  }

  func moveSelection(rowDelta: Int, colDelta: Int, extending: Bool = false) {
    commitEditIfNeeded()
    if extending {
      var endRow = selectionEnd.row + rowDelta
      var endCol = selectionEnd.col + colDelta
      endRow = max(0, min(activeSheet.effectiveRowCount - 1, endRow))
      endCol = max(0, min(activeSheet.effectiveColumnCount - 1, endCol))
      if rowDelta != 0 {
        endRow = nextVisibleRow(from: selectionEnd.row, delta: rowDelta) ?? endRow
      }
      selectionEnd = CellAddress(row: endRow, col: endCol)
      setPrimaryRange(from: selectionAnchor, to: selectionEnd)
    } else {
      var nextRow = selectionAnchor.row + rowDelta
      var nextCol = selectionAnchor.col + colDelta
      nextRow = max(0, min(activeSheet.effectiveRowCount - 1, nextRow))
      nextCol = max(0, min(activeSheet.effectiveColumnCount - 1, nextCol))
      if rowDelta != 0 {
        nextRow = nextVisibleRow(from: selectionAnchor.row, delta: rowDelta) ?? nextRow
      }
      let next = CellAddress(row: nextRow, col: nextCol)
      replaceSelection(with: CellRange(start: next, end: next))
    }
    syncEditTextFromSelection()
    isEditing = false
  }

  private func nextVisibleRow(from row: Int, delta: Int) -> Int? {
    guard delta != 0 else { return row }
    let step = delta > 0 ? 1 : -1
    var remaining = abs(delta)
    var current = row
    let maxRow = activeSheet.effectiveRowCount - 1
    while remaining > 0 {
      current += step
      if current < 0 || current > maxRow { return nil }
      if !isRowHiddenByFilter(current) {
        remaining -= 1
      }
    }
    return current
  }

  func select(_ address: CellAddress) {
    selectRange(from: address, to: address)
  }

  func selectColumn(_ col: Int) {
    selectColumns(from: col, to: col)
  }

  func selectColumns(from startCol: Int, to endCol: Int) {
    commitEditIfNeeded()
    let sheet = activeSheet
    let a = max(0, min(sheet.effectiveColumnCount - 1, startCol))
    let b = max(0, min(sheet.effectiveColumnCount - 1, endCol))
    replaceSelection(with: CellRange(
      start: CellAddress(row: 0, col: a),
      end: CellAddress(row: sheet.effectiveRowCount - 1, col: b)
    ))
    syncEditTextFromSelection()
    isEditing = false
  }

  func toggleColumnSelection(_ col: Int) {
    let clampedCol = max(0, min(activeSheet.effectiveColumnCount - 1, col))
    let range = selectionRange.normalized
    if !hasMultipleSelectionRanges,
       selectionAxis == .column,
       range.minCol == clampedCol,
       range.maxCol == clampedCol
    {
      select(CellAddress(row: 0, col: clampedCol))
    } else {
      selectColumn(clampedCol)
    }
  }

  func selectRow(_ row: Int) {
    selectRows(from: row, to: row)
  }

  func selectRows(from startRow: Int, to endRow: Int) {
    commitEditIfNeeded()
    let sheet = activeSheet
    let a = max(0, min(sheet.effectiveRowCount - 1, startRow))
    let b = max(0, min(sheet.effectiveRowCount - 1, endRow))
    replaceSelection(with: CellRange(
      start: CellAddress(row: a, col: 0),
      end: CellAddress(row: b, col: sheet.effectiveColumnCount - 1)
    ))
    syncEditTextFromSelection()
    isEditing = false
  }

  func toggleRowSelection(_ row: Int) {
    let clampedRow = max(0, min(activeSheet.effectiveRowCount - 1, row))
    let range = selectionRange.normalized
    if !hasMultipleSelectionRanges,
       selectionAxis == .row,
       range.minRow == clampedRow,
       range.maxRow == clampedRow
    {
      select(CellAddress(row: clampedRow, col: 0))
    } else {
      selectRow(clampedRow)
    }
  }

  func beginEditing(preserveSelection: Bool = true) {
    if !preserveSelection { return }
    editText = selectedCell.raw
    isEditing = true
    focusedFormulaHighlightIndex = nil
    noteFormulaEditTextChanged()
  }

  func commitEdit() {
    let address = selectionAnchor
    let newValue = editText
    let oldValue = activeSheet.cell(at: address).raw
    guard newValue != oldValue else {
      isEditing = false
      noteFormulaEditTextChanged()
      return
    }
    registerUndo(address: address, oldValue: oldValue, newValue: newValue)
    var sheet = activeSheet
    var cell = sheet.cell(at: address)
    cell.raw = newValue
    applyInferredNumberFormatIfNeeded(to: &cell, raw: newValue)
    sheet.setCell(cell, at: address)
    setActiveSheet(sheet, formulaCellsChanged: [address])
    isEditing = false
    noteFormulaEditTextChanged()
  }

  func cancelEdit() {
    syncEditTextFromSelection()
    isEditing = false
    noteFormulaEditTextChanged()
  }

  func commitEditIfNeeded() {
    guard isEditing else { return }
    commitEdit()
  }

  func setCellValue(_ value: String, at address: CellAddress) {
    let oldValue = activeSheet.cell(at: address).raw
    guard value != oldValue else { return }
    registerUndo(address: address, oldValue: oldValue, newValue: value)
    var sheet = activeSheet
    var cell = sheet.cell(at: address)
    cell.raw = value
    applyInferredNumberFormatIfNeeded(to: &cell, raw: value)
    sheet.setCell(cell, at: address)
    setActiveSheet(sheet, formulaCellsChanged: [address])
    if address == selectionAnchor && !isEditing {
      editText = value
    }
    // Clearing/changing a value can change which filter rows are hidden.
    if filterState != nil {
      hiddenRowsCache = nil
      notifyGridRefresh()
    }
  }

  /// When the user types/imports `50%`, keep the raw text for the formula bar and mark percent format
  /// so the grid shows a percentage instead of the fractional evaluated value.
  private func applyInferredNumberFormatIfNeeded(to cell: inout Cell, raw: String) {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasSuffix("%"),
          !FormulaSyntax.isFormula(trimmed),
          Double(String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")) != nil
    else { return }
    var format = cell.format ?? CellFormat()
    if format.numberFormat == .general {
      format.numberFormat = .percent
      if format.decimalPlaces == nil {
        format.decimalPlaces = defaultDecimalPlaces(for: .percent)
      }
      cell.format = format
    }
  }

  func applyFormulaBar() {
    commitEdit()
  }

  /// Commits whatever is currently in the formula bar (source of truth = field text).
  func commitFormulaBarText(_ text: String) {
    editText = text
    isEditing = true
    commitEdit()
  }

  func autoFitColumn(_ col: Int, recordUndo: Bool = true) {
    var sheet = activeSheet
    let oldWidth = sheet.columnWidth(for: col, default: Workbook.defaultColumnWidth)
    var maxWidth = Workbook.defaultColumnWidth
    let lastRow = max(sheet.maxPopulatedRow, 0)
    for row in 0...min(lastRow, activeSheet.effectiveRowCount - 1) {
      let address = CellAddress(row: row, col: col)
      let cell = sheet.cell(at: address)
      let text = displayString(at: address)
      guard !text.isEmpty else { continue }
      let width = CellFormatRenderer.measuredWidth(for: text, format: cell.format) + 16
      maxWidth = max(maxWidth, width)
    }
    let newWidth = min(max(maxWidth, 48), 420)
    guard abs(oldWidth - newWidth) > 0.5 else { return }
    sheet.columnWidths[col] = newWidth
    setActiveSheetPreservingFormulas(sheet)
    if recordUndo {
      registerColumnWidthUndo(col: col, oldWidth: oldWidth, newWidth: newWidth, actionName: "Auto Fit Column")
    }
  }

  func autoFitRow(_ row: Int, recordUndo: Bool = true) {
    var sheet = activeSheet
    let oldHeight = sheet.rowHeight(for: row, default: Workbook.defaultRowHeight)
    var maxHeight = Workbook.defaultRowHeight
    let lastCol = max(sheet.maxPopulatedColumn, 0)
    for col in 0...min(lastCol, activeSheet.effectiveColumnCount - 1) {
      let address = CellAddress(row: row, col: col)
      let cell = sheet.cell(at: address)
      let text = displayString(at: address)
      guard !text.isEmpty else { continue }
      let height = CellFormatRenderer.measuredHeight(for: text, format: cell.format) + 8
      maxHeight = max(maxHeight, height)
    }
    let newHeight = min(max(maxHeight, 22), 200)
    guard abs(oldHeight - newHeight) > 0.5 else { return }
    sheet.rowHeights[row] = newHeight
    setActiveSheetPreservingFormulas(sheet)
    if recordUndo {
      registerRowHeightUndo(row: row, oldHeight: oldHeight, newHeight: newHeight, actionName: "Auto Fit Row")
    }
  }

  func autoFitAllColumns() {
    let before = activeSheet.columnWidths
    let lastCol = max(activeSheet.maxPopulatedColumn, activeSheet.effectiveColumnCount - 1)
    for col in 0...lastCol {
      autoFitColumn(col, recordUndo: false)
    }
    registerColumnWidthsUndo(before: before, after: activeSheet.columnWidths, actionName: "Auto Fit Columns")
  }

  func autoFitAllRows() {
    let before = activeSheet.rowHeights
    let lastRow = max(activeSheet.maxPopulatedRow, activeSheet.effectiveRowCount - 1)
    for row in 0...lastRow where !isRowHiddenByFilter(row) {
      autoFitRow(row, recordUndo: false)
    }
    registerRowHeightsUndo(before: before, after: activeSheet.rowHeights, actionName: "Auto Fit Rows")
  }

  func columnWidth(for col: Int) -> CGFloat {
    activeSheet.columnWidth(for: col, default: Workbook.defaultColumnWidth)
  }

  func rowHeight(for row: Int) -> CGFloat {
    activeSheet.rowHeight(for: row, default: Workbook.defaultRowHeight)
  }

  func setColumnWidth(_ col: Int, width: CGFloat, recordUndo: Bool = true) {
    var sheet = activeSheet
    let oldWidth = sheet.columnWidth(for: col, default: Workbook.defaultColumnWidth)
    let newWidth = min(max(width, 24), 600)
    guard abs(oldWidth - newWidth) > 0.5 else { return }
    sheet.columnWidths[col] = newWidth
    setActiveSheetPreservingFormulas(sheet)
    if recordUndo {
      registerColumnWidthUndo(col: col, oldWidth: oldWidth, newWidth: newWidth, actionName: "Resize Column")
    }
  }

  func setRowHeight(_ row: Int, height: CGFloat, recordUndo: Bool = true) {
    var sheet = activeSheet
    let oldHeight = sheet.rowHeight(for: row, default: Workbook.defaultRowHeight)
    let newHeight = min(max(height, 16), 400)
    guard abs(oldHeight - newHeight) > 0.5 else { return }
    sheet.rowHeights[row] = newHeight
    setActiveSheetPreservingFormulas(sheet)
    if recordUndo {
      registerRowHeightUndo(row: row, oldHeight: oldHeight, newHeight: newHeight, actionName: "Resize Row")
    }
  }

  /// Call once after a drag-resize gesture (undo is deferred until mouse up).
  func commitColumnWidthResize(col: Int, from oldWidth: CGFloat) {
    registerColumnWidthUndo(
      col: col,
      oldWidth: oldWidth,
      newWidth: columnWidth(for: col),
      actionName: "Resize Column"
    )
  }

  func commitRowHeightResize(row: Int, from oldHeight: CGFloat) {
    registerRowHeightUndo(
      row: row,
      oldHeight: oldHeight,
      newHeight: rowHeight(for: row),
      actionName: "Resize Row"
    )
  }

  private func registerColumnWidthUndo(
    col: Int,
    oldWidth: CGFloat,
    newWidth: CGFloat,
    actionName: String
  ) {
    guard abs(oldWidth - newWidth) > 0.5 else { return }
    undoManager?.registerUndo(withTarget: self) { target in
      target.setColumnWidth(col, width: oldWidth, recordUndo: false)
      target.notifyGridRefresh()
      target.undoManager?.registerUndo(withTarget: target) { inner in
        inner.setColumnWidth(col, width: newWidth, recordUndo: false)
        inner.notifyGridRefresh()
      }
    }
    undoManager?.setActionName(actionName)
  }

  private func registerRowHeightUndo(
    row: Int,
    oldHeight: CGFloat,
    newHeight: CGFloat,
    actionName: String
  ) {
    guard abs(oldHeight - newHeight) > 0.5 else { return }
    undoManager?.registerUndo(withTarget: self) { target in
      target.setRowHeight(row, height: oldHeight, recordUndo: false)
      target.notifyGridRefresh()
      target.undoManager?.registerUndo(withTarget: target) { inner in
        inner.setRowHeight(row, height: newHeight, recordUndo: false)
        inner.notifyGridRefresh()
      }
    }
    undoManager?.setActionName(actionName)
  }

  private func registerColumnWidthsUndo(
    before: [Int: CGFloat],
    after: [Int: CGFloat],
    actionName: String
  ) {
    guard before != after else { return }
    undoManager?.registerUndo(withTarget: self) { target in
      var workbook = target.workbook
      var sheet = workbook.activeSheet
      sheet.columnWidths = before
      workbook.activeSheet = sheet
      target.workbook = workbook
      target.notifyGridRefresh()
      target.undoManager?.registerUndo(withTarget: target) { inner in
        var workbook = inner.workbook
        var sheet = workbook.activeSheet
        sheet.columnWidths = after
        workbook.activeSheet = sheet
        inner.workbook = workbook
        inner.notifyGridRefresh()
      }
    }
    undoManager?.setActionName(actionName)
  }

  private func registerRowHeightsUndo(
    before: [Int: CGFloat],
    after: [Int: CGFloat],
    actionName: String
  ) {
    guard before != after else { return }
    undoManager?.registerUndo(withTarget: self) { target in
      var workbook = target.workbook
      var sheet = workbook.activeSheet
      sheet.rowHeights = before
      workbook.activeSheet = sheet
      target.workbook = workbook
      target.notifyGridRefresh()
      target.undoManager?.registerUndo(withTarget: target) { inner in
        var workbook = inner.workbook
        var sheet = workbook.activeSheet
        sheet.rowHeights = after
        workbook.activeSheet = sheet
        inner.workbook = workbook
        inner.notifyGridRefresh()
      }
    }
    undoManager?.setActionName(actionName)
  }

  // MARK: - Sheets

  func addSheet() {
    commitEditIfNeeded()
    var wb = workbook
    let index = wb.sheets.count + 1
    wb.sheets.append(Sheet(name: "Sheet\(index)"))
    wb.activeSheetIndex = wb.sheets.count - 1
    workbook = wb
    selection = .origin
    syncEditTextFromSelection()
    isEditing = false
  }

  func selectSheet(at index: Int) {
    commitEditIfNeeded()
    guard index >= 0, index < workbook.sheets.count else { return }
    workbook.activeSheetIndex = index
    restoreFilterFromActiveSheet()
    invalidateFindMatches()
    selection = .origin
    syncEditTextFromSelection()
    isEditing = false
  }

  func deleteSheet(at index: Int) {
    commitEditIfNeeded()
    guard workbook.sheets.count > 1 else { return }
    guard index >= 0, index < workbook.sheets.count else { return }

    let wasActive = index == workbook.activeSheetIndex
    workbook.sheets.remove(at: index)
    if wasActive {
      workbook.activeSheetIndex = min(index, workbook.sheets.count - 1)
      restoreFilterFromActiveSheet()
    } else if index < workbook.activeSheetIndex {
      workbook.activeSheetIndex -= 1
    }
    contentRevision &+= 1
    invalidateFindMatches()
    selection = .origin
    syncEditTextFromSelection()
    isEditing = false
  }

  func renameSheet(at index: Int, to name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard index >= 0, index < workbook.sheets.count else { return }
    workbook.sheets[index].name = trimmed
  }

  // MARK: - Formatting

  var selectedFormat: CellFormat {
    selectedCell.format ?? CellFormat()
  }

  func toggleBold() { updateSelectedFormat { $0.bold.toggle() } }
  func toggleItalic() { updateSelectedFormat { $0.italic.toggle() } }
  func toggleUnderline() { updateSelectedFormat { $0.underline.toggle() } }
  func toggleStrikethrough() { updateSelectedFormat { $0.strikethrough.toggle() } }
  func toggleWrapText() { updateSelectedFormat { $0.wrapText.toggle() } }

  func setFontFamily(_ family: String) {
    updateSelectedFormat { $0.fontFamily = family }
  }

  func setFontSize(_ size: CGFloat) {
    let clamped = min(max(size, 6), 72)
    updateSelectedFormat { $0.fontSize = clamped }
  }

  func adjustFontSize(by delta: CGFloat) {
    let current = selectedFormat.fontSize ?? CellFormatRenderer.defaultFontSize
    setFontSize(current + delta)
  }

  func setTextColor(_ color: CodableColor?) {
    updateSelectedFormat { $0.textColor = color }
  }

  func setFillColor(_ color: CodableColor?) {
    updateSelectedFormat { $0.fillColor = color }
  }

  /// Banded rows: even data rows get `bandColor`, odd rows clear fill. Header row is skipped when requested.
  func applyAlternatingRowColors(bandColor: CodableColor, hasHeader: Bool) {
    commitEditIfNeeded()
    undoManager?.beginUndoGrouping()
    for range in selectionRanges {
      applyAlternatingRowColors(bandColor: bandColor, hasHeader: hasHeader, to: range)
    }
    undoManager?.endUndoGrouping()
    undoManager?.setActionName("Alternating Row Colors")
    notifyGridRefresh()
  }

  private func applyAlternatingRowColors(
    bandColor: CodableColor,
    hasHeader: Bool,
    to range: CellRange
  ) {
    let n = range.normalized
    guard n.maxRow >= n.minRow else { return }
    for row in n.minRow...n.maxRow {
      if hasHeader, row == n.minRow { continue }
      let relativeIndex = hasHeader ? row - n.minRow - 1 : row - n.minRow
      let isBand = relativeIndex % 2 == 0
      let rowRange = CellRange(
        start: CellAddress(row: row, col: n.minCol),
        end: CellAddress(row: row, col: n.maxCol)
      )
      applyFormat(to: rowRange) { format in
        format.fillColor = isBand ? bandColor : nil
      }
    }
  }

  func setHorizontalAlign(_ align: CellFormat.HorizontalAlign) {
    updateSelectedFormat { $0.horizontalAlign = align }
  }

  func setVerticalAlign(_ align: CellFormat.VerticalAlign) {
    updateSelectedFormat { $0.verticalAlign = align }
  }

  func setTextRotation(_ degrees: Int) {
    updateSelectedFormat { $0.textRotation = degrees }
  }

  func setNumberFormat(_ numberFormat: CellFormat.NumberFormat) {
    updateSelectedFormat { format in
      format.numberFormat = numberFormat
      if format.decimalPlaces == nil {
        format.decimalPlaces = defaultDecimalPlaces(for: numberFormat)
      }
    }
  }

  /// Default color used when applying border presets from the toolbar.
  var borderColor: CodableColor?
  /// Line style used when applying border presets (thin, dashed, dotted, …).
  var borderStyle: BorderStyle = .thin

  func setBorderColor(_ color: CodableColor?) {
    borderColor = color
  }

  func setBorderStyle(_ style: BorderStyle) {
    borderStyle = style
  }

  func applyBorderPreset(_ preset: BorderPreset) {
    commitEditIfNeeded()
    let edge = BorderEdge.styled(borderStyle, color: borderColor)
    let thickEdge = BorderEdge.styled(.thick, color: borderColor)
    undoManager?.beginUndoGrouping()
    for range in selectionRanges {
      applyBorderPreset(preset, to: range, edge: edge, thickEdge: thickEdge)
    }
    undoManager?.endUndoGrouping()
    undoManager?.setActionName("Format Cells")
  }

  private func applyBorderPreset(
    _ preset: BorderPreset,
    to range: CellRange,
    edge: BorderEdge,
    thickEdge: BorderEdge
  ) {
    let n = range.normalized
    switch preset {
    case .none:
      applyBorderMutation(in: range) { _, borders in
        borders = .none
      }
    case .all:
      applyBorderMutation(in: range) { _, borders in
        borders = CellBorders(top: edge, bottom: edge, left: edge, right: edge)
      }
    case .outside:
      applyBorderMutation(in: range) { address, borders in
        if address.row == n.minRow { borders.top = edge }
        if address.row == n.maxRow { borders.bottom = edge }
        if address.col == n.minCol { borders.left = edge }
        if address.col == n.maxCol { borders.right = edge }
      }
    case .inside:
      applyBorderMutation(in: range) { address, borders in
        if address.row > n.minRow { borders.top = edge }
        if address.row < n.maxRow { borders.bottom = edge }
        if address.col > n.minCol { borders.left = edge }
        if address.col < n.maxCol { borders.right = edge }
      }
    case .top:
      applyBorderMutation(in: range) { address, borders in
        if address.row == n.minRow { borders.top = edge }
      }
    case .bottom:
      applyBorderMutation(in: range) { address, borders in
        if address.row == n.maxRow { borders.bottom = edge }
      }
    case .left:
      applyBorderMutation(in: range) { address, borders in
        if address.col == n.minCol { borders.left = edge }
      }
    case .right:
      applyBorderMutation(in: range) { address, borders in
        if address.col == n.maxCol { borders.right = edge }
      }
    case .thickOutside:
      applyBorderMutation(in: range) { address, borders in
        if address.row == n.minRow { borders.top = thickEdge }
        if address.row == n.maxRow { borders.bottom = thickEdge }
        if address.col == n.minCol { borders.left = thickEdge }
        if address.col == n.maxCol { borders.right = thickEdge }
      }
    }
  }

  /// Address-aware border edits in one sheet write (no per-cell formula rebuild).
  private func applyBorderMutation(
    in range: CellRange,
    mutate: (CellAddress, inout CellBorders) -> Void
  ) {
    var sheet = activeSheet
    var changed = false

    func mutateAddress(_ address: CellAddress) {
      var cell = sheet.cell(at: address)
      var format = cell.format ?? CellFormat()
      let oldFormat = format
      mutate(address, &format.borders)
      guard format != oldFormat else { return }
      cell.format = format.isDefault ? nil : format
      registerFormatUndo(address: address, oldFormat: oldFormat, newFormat: format)
      sheet.setCell(cell, at: address)
      changed = true
    }

    // Always visit every address so empty cells get outside/all borders.
    for address in range.allAddresses() {
      mutateAddress(address)
    }

    if changed {
      setActiveSheetPreservingFormulas(sheet)
    }
  }

  private func updateFormat(in range: CellRange, mutate: (inout CellFormat) -> Void) {
    applyFormat(to: range, mutate: mutate)
  }

  private func mutateBorders(at address: CellAddress, mutate: (inout CellBorders) -> Void) {
    applyFormatMutation(at: address) { format in
      mutate(&format.borders)
    }
  }

  func increaseDecimalPlaces() {
    updateSelectedFormat { format in
      let current = format.decimalPlaces ?? defaultDecimalPlaces(for: format.numberFormat)
      format.decimalPlaces = min(current + 1, 10)
      format.numberFormat = format.numberFormat == .general ? .number : format.numberFormat
    }
  }

  func decreaseDecimalPlaces() {
    updateSelectedFormat { format in
      let current = format.decimalPlaces ?? defaultDecimalPlaces(for: format.numberFormat)
      format.decimalPlaces = max(current - 1, 0)
    }
  }

  private func defaultDecimalPlaces(for format: CellFormat.NumberFormat) -> Int {
    switch format {
    case .general: return 0
    case .number, .currency, .percent, .scientific: return 2
    case .date, .time: return 0
    }
  }

  private func updateSelectedFormat(_ mutate: (inout CellFormat) -> Void) {
    commitEditIfNeeded()
    undoManager?.beginUndoGrouping()
    for range in selectionRanges {
      applyFormat(to: range, mutate: mutate)
    }
    undoManager?.endUndoGrouping()
    undoManager?.setActionName("Format Cells")
  }

  private func applyFormat(to range: CellRange, mutate: (inout CellFormat) -> Void) {
    let n = range.normalized
    let cellCount = (n.maxRow - n.minRow + 1) * (n.maxCol - n.minCol + 1)
    let groupLarge = cellCount > 2_000
    if groupLarge {
      undoManager?.beginUndoGrouping()
    }

    var sheet = activeSheet
    var changed = false

    func mutateAddress(_ address: CellAddress) {
      var cell = sheet.cell(at: address)
      var format = cell.format ?? CellFormat()
      let oldFormat = format
      mutate(&format)
      guard format != oldFormat else { return }
      cell.format = format.isDefault ? nil : format
      registerFormatUndo(address: address, oldFormat: oldFormat, newFormat: format)
      sheet.setCell(cell, at: address)
      changed = true
    }

    // Always visit every address so empty cells receive fill/font/etc.
    for address in range.allAddresses() {
      mutateAddress(address)
    }

    if changed {
      setActiveSheetPreservingFormulas(sheet)
      notifyGridRefresh()
    }
    if groupLarge {
      undoManager?.endUndoGrouping()
      undoManager?.setActionName("Format Cells")
    }
  }

  private func applyFormatMutation(at address: CellAddress, mutate: (inout CellFormat) -> Void) {
    applyFormat(to: CellRange(start: address, end: address), mutate: mutate)
  }

  private func registerFormatUndo(address: CellAddress, oldFormat: CellFormat, newFormat: CellFormat) {
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyFormat(oldFormat, at: address, skipUndo: true)
      target.undoManager?.registerUndo(withTarget: target) { inner in
        inner.applyFormat(newFormat, at: address, skipUndo: true)
      }
    }
    // Action name is set once by the caller after undo grouping when possible.
  }

  private func applyFormat(_ format: CellFormat, at address: CellAddress, skipUndo: Bool) {
    var sheet = activeSheet
    var cell = sheet.cell(at: address)
    cell.format = format.isDefault ? nil : format
    sheet.setCell(cell, at: address)
    setActiveSheetPreservingFormulas(sheet)
  }

  private func clamp(_ address: CellAddress) -> CellAddress {
    let sheet = activeSheet
    return CellAddress(
      row: max(0, min(sheet.effectiveRowCount - 1, address.row)),
      col: max(0, min(sheet.effectiveColumnCount - 1, address.col))
    )
  }

  func clearSelection() {
    commitEditIfNeeded()
    for range in selectionRanges {
      clearRange(range, actionName: "Clear")
    }
    syncEditTextFromSelection()
  }

  // MARK: - Structure

  func insertRowsAbove(count: Int = 1) {
    insertRows(at: selectionRange.normalized.minRow, count: count)
  }

  func insertRowsBelow(count: Int = 1) {
    insertRows(at: selectionRange.normalized.maxRow + 1, count: count)
  }

  func insertColumnsLeft(count: Int = 1) {
    insertColumns(at: selectionRange.normalized.minCol, count: count)
  }

  func insertColumnsRight(count: Int = 1) {
    let n = selectionRange.normalized
    let insertAt = n.maxCol + 1
    insertColumns(at: insertAt, count: count)
    let newEndCol = insertAt + count - 1
    if selectionAxis == .column {
      selectColumns(from: insertAt, to: newEndCol)
    } else {
      selectRange(
        from: CellAddress(row: n.minRow, col: insertAt),
        to: CellAddress(row: n.maxRow, col: newEndCol)
      )
    }
    scrollRequestToken &+= 1
  }

  func deleteSelectedRows() {
    let range = selectionRange.normalized
    let sheet = activeSheet
    let spansFullWidth = range.minCol == 0 && range.maxCol >= sheet.effectiveColumnCount - 1
    if spansFullWidth {
      deleteRows(at: range.minRow, count: range.maxRow - range.minRow + 1)
    } else {
      deleteRows(at: selectionAnchor.row, count: 1)
    }
  }

  func deleteSelectedColumns() {
    let range = selectionRange.normalized
    let sheet = activeSheet
    let spansFullHeight = range.minRow == 0 && range.maxRow >= sheet.effectiveRowCount - 1
    if spansFullHeight {
      deleteColumns(at: range.minCol, count: range.maxCol - range.minCol + 1)
    } else {
      deleteColumns(at: selectionAnchor.col, count: 1)
    }
  }

  @discardableResult
  func freezePanesAtSelection() -> Bool {
    commitEditIfNeeded()
    // Freeze the selected row/column and everything above/to the left (inclusive).
    let rows = selectionAnchor.row + 1
    let cols = selectionAnchor.col + 1
    guard rows > 0 || cols > 0 else { return false }
    return applyFreeze(rows: rows, cols: cols)
  }

  @discardableResult
  func freezeRowsAtSelection() -> Bool {
    commitEditIfNeeded()
    let rows = selectionRange.normalized.minRow + 1
    guard rows > 0 else { return false }
    return applyFreeze(rows: rows, cols: activeSheet.frozenColumns)
  }

  @discardableResult
  func freezeColumnsAtSelection() -> Bool {
    commitEditIfNeeded()
    let cols = selectionRange.normalized.minCol + 1
    guard cols > 0 else { return false }
    return applyFreeze(rows: activeSheet.frozenRows, cols: cols)
  }

  func unfreezePanes() {
    commitEditIfNeeded()
    guard activeSheet.frozenRows > 0 || activeSheet.frozenColumns > 0 else { return }
    applyFreeze(rows: 0, cols: 0)
  }

  @discardableResult
  private func applyFreeze(rows: Int, cols: Int) -> Bool {
    var updatedWorkbook = workbook
    var sheet = updatedWorkbook.activeSheet
    let oldFrozenRows = sheet.frozenRows
    let oldFrozenColumns = sheet.frozenColumns
    sheet.frozenRows = rows
    sheet.frozenColumns = cols
    updatedWorkbook.activeSheet = sheet
    suspendFormulaRebuild = true
    workbook = updatedWorkbook
    suspendFormulaRebuild = false
    notifyGridRefresh()
    registerFreezeUndo(
      oldRows: oldFrozenRows,
      oldCols: oldFrozenColumns,
      newRows: sheet.frozenRows,
      newCols: sheet.frozenColumns
    )
    return true
  }

  func fillSelection(from source: CellRange? = nil, to end: CellAddress) {
    commitEditIfNeeded()
    let sourceRange = (source ?? selectionRange).normalized
    let fillRange = CellRange(
      start: CellAddress(row: sourceRange.minRow, col: sourceRange.minCol),
      end: clamp(end)
    ).normalized

    let srcRowCount = sourceRange.maxRow - sourceRange.minRow + 1
    let srcColCount = sourceRange.maxCol - sourceRange.minCol + 1
    guard srcRowCount > 0, srcColCount > 0 else { return }

    undoManager?.beginUndoGrouping()
    for row in fillRange.minRow...fillRange.maxRow {
      for col in fillRange.minCol...fillRange.maxCol {
        if row >= sourceRange.minRow && row <= sourceRange.maxRow && col >= sourceRange.minCol && col <= sourceRange.maxCol {
          continue
        }
        let srcRow = sourceRange.minRow + positiveMod(row - sourceRange.minRow, srcRowCount)
        let srcCol = sourceRange.minCol + positiveMod(col - sourceRange.minCol, srcColCount)
        let srcAddress = CellAddress(row: srcRow, col: srcCol)
        let srcCell = activeSheet.cell(at: srcAddress)
        let destAddress = CellAddress(row: row, col: col)
        let rowDelta = destAddress.row - srcAddress.row
        let colDelta = destAddress.col - srcAddress.col
        let value = FormulaRewriter.adjust(srcCell.raw, rowDelta: rowDelta, colDelta: colDelta)
        setCellValue(value, at: destAddress)
        if let format = srcCell.format {
          applyFormat(format, at: destAddress, skipUndo: true)
        }
      }
    }
    undoManager?.endUndoGrouping()
    undoManager?.setActionName("Fill")

    selectionEnd = CellAddress(row: fillRange.maxRow, col: fillRange.maxCol)
    setPrimaryRange(from: selectionAnchor, to: selectionEnd)
    syncEditTextFromSelection()
  }

  private func insertRows(at index: Int, count: Int) {
    commitEditIfNeeded()
    let snapshot = workbook
    var wb = workbook
    let sheetName = wb.activeSheet.name
    rewriteFormulas(
      in: &wb,
      mutatedSheetName: sheetName,
      axis: .row,
      change: .insert(at: index, count: count)
    )
    shiftNamedRanges(
      in: &wb,
      mutatedSheetName: sheetName,
      axis: .row,
      change: .insert(at: index, count: count)
    )
    SheetStructureMutation.insertRows(into: &wb.activeSheet, at: index, count: count)
    workbook = wb
    registerWorkbookStructureUndo(before: snapshot, action: "Insert Rows")
  }

  private func deleteRows(at index: Int, count: Int) {
    commitEditIfNeeded()
    let snapshot = workbook
    var wb = workbook
    let sheetName = wb.activeSheet.name
    rewriteFormulas(
      in: &wb,
      mutatedSheetName: sheetName,
      axis: .row,
      change: .delete(at: index, count: count)
    )
    shiftNamedRanges(
      in: &wb,
      mutatedSheetName: sheetName,
      axis: .row,
      change: .delete(at: index, count: count)
    )
    SheetStructureMutation.deleteRows(in: &wb.activeSheet, at: index, count: count)
    workbook = wb
    registerWorkbookStructureUndo(before: snapshot, action: "Delete Rows")
    clampSelectionToSheet()
  }

  private func insertColumns(at index: Int, count: Int) {
    commitEditIfNeeded()
    let snapshot = workbook
    var wb = workbook
    let sheetName = wb.activeSheet.name
    rewriteFormulas(
      in: &wb,
      mutatedSheetName: sheetName,
      axis: .column,
      change: .insert(at: index, count: count)
    )
    shiftNamedRanges(
      in: &wb,
      mutatedSheetName: sheetName,
      axis: .column,
      change: .insert(at: index, count: count)
    )
    SheetStructureMutation.insertColumns(into: &wb.activeSheet, at: index, count: count)
    workbook = wb
    registerWorkbookStructureUndo(before: snapshot, action: "Insert Columns")
  }

  private func deleteColumns(at index: Int, count: Int) {
    commitEditIfNeeded()
    let snapshot = workbook
    var wb = workbook
    let sheetName = wb.activeSheet.name
    rewriteFormulas(
      in: &wb,
      mutatedSheetName: sheetName,
      axis: .column,
      change: .delete(at: index, count: count)
    )
    shiftNamedRanges(
      in: &wb,
      mutatedSheetName: sheetName,
      axis: .column,
      change: .delete(at: index, count: count)
    )
    SheetStructureMutation.deleteColumns(in: &wb.activeSheet, at: index, count: count)
    workbook = wb
    registerWorkbookStructureUndo(before: snapshot, action: "Delete Columns")
    clampSelectionToSheet()
  }

  private func rewriteFormulas(
    in workbook: inout Workbook,
    mutatedSheetName: String,
    axis: FormulaRewriter.Axis,
    change: FormulaRewriter.StructureChange
  ) {
    for sheetIndex in workbook.sheets.indices {
      let sheetName = workbook.sheets[sheetIndex].name
      var cells = workbook.sheets[sheetIndex].cells
      var changed = false
      for (address, cell) in cells where FormulaSyntax.isFormula(cell.raw) {
        let next = FormulaRewriter.shiftForStructure(
          cell.raw,
          formulaSheetName: sheetName,
          mutatedSheetName: mutatedSheetName,
          axis: axis,
          change: change
        )
        if next != cell.raw {
          var updated = cell
          updated.raw = next
          cells[address] = updated
          changed = true
        }
      }
      if changed {
        // Same addresses — populated extents stay valid.
        workbook.sheets[sheetIndex].cells = cells
      }
    }
  }

  private func shiftNamedRanges(
    in workbook: inout Workbook,
    mutatedSheetName: String,
    axis: FormulaRewriter.Axis,
    change: FormulaRewriter.StructureChange
  ) {
    var next: [String: NamedRange] = [:]
    for (key, named) in workbook.namedRanges {
      guard named.sheetName.caseInsensitiveCompare(mutatedSheetName) == .orderedSame else {
        next[key] = named
        continue
      }
      let start = FormulaRef(
        sheet: named.sheetName,
        row: named.startRow,
        col: named.startCol,
        absRow: false,
        absCol: false
      )
      let end = FormulaRef(
        sheet: named.sheetName,
        row: named.endRow,
        col: named.endCol,
        absRow: false,
        absCol: false
      )
      let shifted = FormulaRewriter.shiftForStructure(
        "=\(A1Reference.formatRange(start: start, end: end))",
        formulaSheetName: named.sheetName,
        mutatedSheetName: mutatedSheetName,
        axis: axis,
        change: change
      )
      if shifted == "=#REF!" { continue }
      let body = shifted.hasPrefix("=") ? String(shifted.dropFirst()) : shifted
      guard let (s, e) = A1Reference.parseFormulaRange(body) else { continue }
      next[key] = NamedRange(
        name: named.name,
        sheetName: named.sheetName,
        range: CellRange(start: s.address, end: e.address)
      )
    }
    workbook.namedRanges = next
  }

  func registerWorkbookStructureUndo(before: Workbook, action: String) {
    let after = workbook
    undoManager?.registerUndo(withTarget: self) { target in
      target.workbook = before
      target.clampSelectionToSheet()
      target.undoManager?.registerUndo(withTarget: target) { inner in
        inner.workbook = after
        inner.clampSelectionToSheet()
      }
    }
    undoManager?.setActionName(action)
  }

  func clampSelectionToSheet() {
    selectionRanges = selectionRanges.map { range in
      CellRange(start: clamp(range.start), end: clamp(range.end))
    }
    if selectionRanges.isEmpty {
      replaceSelection(with: .singleOrigin)
    } else {
      let active = selectionRanges[selectionRanges.count - 1]
      selectionAnchor = active.start
      selectionEnd = active.end
      noteSelectionChanged()
    }
    syncEditTextFromSelection()
  }

  private func positiveMod(_ value: Int, _ modulus: Int) -> Int {
    let remainder = value % modulus
    return remainder >= 0 ? remainder : remainder + modulus
  }

  private func registerFreezeUndo(oldRows: Int, oldCols: Int, newRows: Int, newCols: Int) {
    undoManager?.registerUndo(withTarget: self) { target in
      var workbook = target.workbook
      var sheet = workbook.activeSheet
      sheet.frozenRows = oldRows
      sheet.frozenColumns = oldCols
      workbook.activeSheet = sheet
      target.workbook = workbook
      target.notifyGridRefresh()
      target.undoManager?.registerUndo(withTarget: target) { inner in
        var workbook = inner.workbook
        var sheet = workbook.activeSheet
        sheet.frozenRows = newRows
        sheet.frozenColumns = newCols
        workbook.activeSheet = sheet
        inner.workbook = workbook
        inner.notifyGridRefresh()
      }
    }
    undoManager?.setActionName("Freeze Panes")
  }

  /// Replaces formulas in the selection with their evaluated display values.
  func convertSelectionToValues() {
    commitEditIfNeeded()
    undoManager?.beginUndoGrouping()
    var changed = false
    for range in selectionRanges {
      let n = range.normalized
      for row in n.minRow...n.maxRow {
        for col in n.minCol...n.maxCol {
          let address = CellAddress(row: row, col: col)
          let raw = activeSheet.cell(at: address).raw
          guard FormulaSyntax.isFormula(raw) else { continue }
          let literal = literalString(from: displayValue(at: address))
          setCellValue(literal, at: address)
          changed = true
        }
      }
    }
    undoManager?.endUndoGrouping()
    if changed {
      undoManager?.setActionName("Convert to Values")
    }
    syncEditTextFromSelection()
  }

  /// Defines a workbook named range covering the primary selection.
  func defineNamedRange(name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let upper = trimmed.uppercased()
    guard upper.first?.isLetter == true,
          upper.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
    else { return }

    let snapshot = workbook
    var wb = workbook
    wb.setNamedRange(
      NamedRange(name: trimmed, sheetName: activeSheet.name, range: selectionRange)
    )
    workbook = wb

    undoManager?.registerUndo(withTarget: self) { target in
      target.workbook = snapshot
      target.undoManager?.registerUndo(withTarget: target) { inner in
        inner.workbook = wb
      }
    }
    undoManager?.setActionName("Define Named Range")
  }

  private func literalString(from value: CellValue) -> String {
    switch value {
    case .blank:
      return ""
    case .error(let error):
      return error.displayCode
    case .bool(let flag):
      return flag ? "TRUE" : "FALSE"
    case .number, .string:
      return value.displayString
    }
  }

  // MARK: - Clipboard

  func copySelection() -> String? {
    guard selectionRanges.contains(where: { rangeHasContent($0) }) else { return nil }
    if selectionRanges.count == 1 {
      return SpreadsheetClipboard.copyText(from: activeSheet, range: selectionRange)
    }
    let blocks = selectionRanges.map {
      SpreadsheetClipboard.copyText(from: activeSheet, range: $0)
    }
    return blocks.joined(separator: "\n\n")
  }

  /// Copies cell raw values (including formulas) and records origin for relative paste.
  func copyFormulas() {
    guard selectionRanges.contains(where: { rangeHasContent($0) }) else { return }
    let range = selectionRange.normalized
    let origin = CellAddress(row: range.minRow, col: range.minCol)
    let grid = SpreadsheetClipboard.grid(from: activeSheet, range: selectionRange)
    let tsv = SpreadsheetClipboard.copyText(from: activeSheet, range: selectionRange)
    SpreadsheetClipboard.writeFormulaGrid(
      .init(originRow: origin.row, originCol: origin.col, grid: grid),
      tsv: tsv
    )
  }

  private func selectionRangeHasContent() -> Bool {
    selectionRanges.contains { rangeHasContent($0) }
  }

  private func rangeHasContent(_ range: CellRange) -> Bool {
    let n = range.normalized
    for (address, cell) in activeSheet.cells {
      guard !cell.raw.isEmpty else { continue }
      if address.row >= n.minRow, address.row <= n.maxRow,
         address.col >= n.minCol, address.col <= n.maxCol {
        return true
      }
    }
    return false
  }

  func cutSelection() {
    guard let text = copySelection() else { return }
    for range in selectionRanges {
      clearRange(range, actionName: "Cut")
    }
    writeToPasteboard(text)
  }

  func pasteFromPasteboard() {
    if pasteImageFromPasteboard() {
      syncEditTextFromSelection()
      return
    }
    guard let text = NSPasteboard.general.string(forType: .string) else { return }
    let grid = SpreadsheetClipboard.parseGrid(text)
    if grid.isEmpty {
      setCellValue(text, at: selectionAnchor)
    } else {
      pasteGrid(grid, at: selectionAnchor, adjustFormulas: false)
    }
    syncEditTextFromSelection()
  }

  /// Pastes formulas with relative references adjusted from the copy origin.
  func pasteFormulasFromPasteboard() {
    if let payload = SpreadsheetClipboard.readFormulaGrid() {
      let origin = CellAddress(row: payload.originRow, col: payload.originCol)
      pasteGrid(
        payload.grid,
        at: selectionAnchor,
        adjustFormulas: true,
        sourceOrigin: origin,
        actionName: "Paste Formulas"
      )
      syncEditTextFromSelection()
      return
    }

    guard let text = NSPasteboard.general.string(forType: .string) else { return }
    let grid = SpreadsheetClipboard.parseGrid(text)
    if grid.isEmpty {
      let adjusted = FormulaRewriter.adjust(text, rowDelta: 0, colDelta: 0)
      setCellValue(adjusted, at: selectionAnchor)
    } else {
      // External paste: treat clipboard top-left as if it came from the destination (no shift),
      // but still rewrite if user copied via ⌘C then pastes with ⌘⇧V from same sheet — without
      // origin we paste verbatim like normal paste.
      pasteGrid(grid, at: selectionAnchor, adjustFormulas: false, actionName: "Paste Formulas")
    }
    syncEditTextFromSelection()
  }

  private func pasteGrid(
    _ grid: [[String]],
    at origin: CellAddress,
    adjustFormulas: Bool,
    sourceOrigin: CellAddress? = nil,
    actionName: String = "Paste"
  ) {
    let rowDelta = adjustFormulas ? origin.row - (sourceOrigin?.row ?? origin.row) : 0
    let colDelta = adjustFormulas ? origin.col - (sourceOrigin?.col ?? origin.col) : 0

    undoManager?.beginUndoGrouping()
    for (rowOffset, row) in grid.enumerated() {
      for (colOffset, value) in row.enumerated() {
        let address = CellAddress(row: origin.row + rowOffset, col: origin.col + colOffset)
        guard address.row < activeSheet.effectiveRowCount, address.col < activeSheet.effectiveColumnCount else { continue }
        let nextValue = adjustFormulas
          ? FormulaRewriter.adjust(value, rowDelta: rowDelta, colDelta: colDelta)
          : value
        setCellValue(nextValue, at: address)
      }
    }
    undoManager?.endUndoGrouping()
    undoManager?.setActionName(actionName)

    if let lastRow = grid.indices.last, let lastCol = grid[lastRow].indices.last {
      selectionEnd = CellAddress(row: origin.row + lastRow, col: origin.col + lastCol)
      setPrimaryRange(from: selectionAnchor, to: selectionEnd)
    }
  }

  private func clearRange(_ range: CellRange, actionName: String = "Clear") {
    undoManager?.beginUndoGrouping()
    let addresses = activeSheet.cells.keys.filter { range.contains($0) }
    for address in addresses {
      let oldValue = activeSheet.cell(at: address).raw
      guard !oldValue.isEmpty else { continue }
      setCellValue("", at: address)
    }
    undoManager?.endUndoGrouping()
    undoManager?.setActionName(actionName)
  }

  private func writeToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  // MARK: - Undo

  private func registerUndo(address: CellAddress, oldValue: String, newValue: String) {
    undoManager?.registerUndo(withTarget: self) { target in
      target.setCellValue(oldValue, at: address, skipUndo: true)
      target.undoManager?.registerUndo(withTarget: target) { inner in
        inner.setCellValue(newValue, at: address, skipUndo: true)
      }
    }
    undoManager?.setActionName("Edit Cell")
  }

  private func setCellValue(_ value: String, at address: CellAddress, skipUndo: Bool) {
    if skipUndo {
      var sheet = activeSheet
      var cell = sheet.cell(at: address)
      cell.raw = value
      applyInferredNumberFormatIfNeeded(to: &cell, raw: value)
      sheet.setCell(cell, at: address)
      setActiveSheet(sheet, formulaCellsChanged: [address])
      if address == selectionAnchor {
        syncEditTextFromSelection()
      }
      if filterState != nil {
        hiddenRowsCache = nil
        notifyGridRefresh()
      }
    } else {
      setCellValue(value, at: address)
    }
  }
}

import AppKit
