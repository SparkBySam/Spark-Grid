import Foundation
import Observation

/// UI state and mutations for the active workbook. Undo integrates with the document undo manager.
@Observable
@MainActor
final class SpreadsheetViewModel {
  var workbook: Workbook
  var selectionAnchor: CellAddress = .origin
  var selectionEnd: CellAddress = .origin
  var isEditing = false
  var editText = ""

  weak var undoManager: UndoManager?

  init(workbook: Workbook) {
    self.workbook = workbook
    syncEditTextFromSelection()
  }

  var selection: CellAddress {
    get { selectionAnchor }
    set {
      selectionAnchor = newValue
      selectionEnd = newValue
    }
  }

  var selectionRange: CellRange {
    CellRange(start: selectionAnchor, end: selectionEnd)
  }

  var activeSheet: Sheet {
    get { workbook.activeSheet }
    set { workbook.activeSheet = newValue }
  }

  var selectedCell: Cell {
    activeSheet.cell(at: selectionAnchor)
  }

  var formulaBarText: String {
    get { isEditing ? editText : selectedCell.raw }
    set {
      editText = newValue
      if !isEditing { isEditing = true }
    }
  }

  func syncEditTextFromSelection() {
    editText = selectedCell.raw
  }

  func selectRange(from start: CellAddress, to end: CellAddress) {
    commitEditIfNeeded()
    selectionAnchor = clamp(start)
    selectionEnd = clamp(end)
    syncEditTextFromSelection()
    isEditing = false
  }

  func extendSelection(to end: CellAddress) {
    selectionEnd = clamp(end)
  }

  func selectAll() {
    commitEditIfNeeded()
    let sheet = activeSheet
    let maxRow = max(sheet.maxPopulatedRow, 0)
    let maxCol = max(sheet.maxPopulatedColumn, 0)
    selectionAnchor = .origin
    selectionEnd = CellAddress(
      row: min(max(maxRow, 99), Workbook.defaultRowCount - 1),
      col: min(max(maxCol, 25), Workbook.defaultColumnCount - 1)
    )
    syncEditTextFromSelection()
    isEditing = false
  }

  func moveSelection(rowDelta: Int, colDelta: Int, extending: Bool = false) {
    commitEditIfNeeded()
    if extending {
      let end = CellAddress(
        row: max(0, min(Workbook.defaultRowCount - 1, selectionEnd.row + rowDelta)),
        col: max(0, min(Workbook.defaultColumnCount - 1, selectionEnd.col + colDelta))
      )
      selectionEnd = end
    } else {
      let next = CellAddress(
        row: max(0, min(Workbook.defaultRowCount - 1, selectionAnchor.row + rowDelta)),
        col: max(0, min(Workbook.defaultColumnCount - 1, selectionAnchor.col + colDelta))
      )
      selectionAnchor = next
      selectionEnd = next
    }
    syncEditTextFromSelection()
    isEditing = false
  }

  func select(_ address: CellAddress) {
    selectRange(from: address, to: address)
  }

  func beginEditing(preserveSelection: Bool = true) {
    if !preserveSelection { return }
    editText = selectedCell.raw
    isEditing = true
  }

  func commitEdit() {
    let address = selectionAnchor
    let newValue = editText
    let oldValue = activeSheet.cell(at: address).raw
    guard newValue != oldValue else {
      isEditing = false
      return
    }
    registerUndo(address: address, oldValue: oldValue, newValue: newValue)
    var sheet = activeSheet
    var cell = sheet.cell(at: address)
    cell.raw = newValue
    sheet.setCell(cell, at: address)
    activeSheet = sheet
    isEditing = false
  }

  func cancelEdit() {
    syncEditTextFromSelection()
    isEditing = false
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
    sheet.setCell(cell, at: address)
    activeSheet = sheet
    if address == selectionAnchor && !isEditing {
      editText = value
    }
  }

  func applyFormulaBar() {
    commitEdit()
  }

  func autoFitColumn(_ col: Int) {
    var sheet = activeSheet
    var maxWidth = Workbook.defaultColumnWidth
    let lastRow = max(sheet.maxPopulatedRow, 0)
    for row in 0...min(lastRow, Workbook.defaultRowCount - 1) {
      let address = CellAddress(row: row, col: col)
      let cell = sheet.cell(at: address)
      let text = CellFormatRenderer.displayText(raw: cell.raw, format: cell.format)
      guard !text.isEmpty else { continue }
      let width = CellFormatRenderer.measuredWidth(for: text, format: cell.format) + 16
      maxWidth = max(maxWidth, width)
    }
    sheet.columnWidths[col] = min(max(maxWidth, 48), 420)
    activeSheet = sheet
  }

  func autoFitRow(_ row: Int) {
    var sheet = activeSheet
    var maxHeight = Workbook.defaultRowHeight
    let lastCol = max(sheet.maxPopulatedColumn, 0)
    for col in 0...min(lastCol, Workbook.defaultColumnCount - 1) {
      let address = CellAddress(row: row, col: col)
      let cell = sheet.cell(at: address)
      let text = CellFormatRenderer.displayText(raw: cell.raw, format: cell.format)
      guard !text.isEmpty else { continue }
      let height = CellFormatRenderer.measuredHeight(for: text, format: cell.format) + 8
      maxHeight = max(maxHeight, height)
    }
    sheet.rowHeights[row] = min(max(maxHeight, 22), 200)
    activeSheet = sheet
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

  func setHorizontalAlign(_ align: CellFormat.HorizontalAlign) {
    updateSelectedFormat { $0.horizontalAlign = align }
  }

  func setVerticalAlign(_ align: CellFormat.VerticalAlign) {
    updateSelectedFormat { $0.verticalAlign = align }
  }

  func setNumberFormat(_ numberFormat: CellFormat.NumberFormat) {
    updateSelectedFormat { format in
      format.numberFormat = numberFormat
      if format.decimalPlaces == nil {
        format.decimalPlaces = defaultDecimalPlaces(for: numberFormat)
      }
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
    for address in selectionRange.allAddresses() {
      applyFormatMutation(at: address, mutate: mutate)
    }
  }

  private func applyFormatMutation(at address: CellAddress, mutate: (inout CellFormat) -> Void) {
    var sheet = activeSheet
    var cell = sheet.cell(at: address)
    var format = cell.format ?? CellFormat()
    let oldFormat = format
    mutate(&format)
    guard format != oldFormat else { return }
    cell.format = format.isDefault ? nil : format
    registerFormatUndo(address: address, oldFormat: oldFormat, newFormat: format)
    sheet.setCell(cell, at: address)
    activeSheet = sheet
  }

  private func registerFormatUndo(address: CellAddress, oldFormat: CellFormat, newFormat: CellFormat) {
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyFormat(oldFormat, at: address, skipUndo: true)
      target.undoManager?.registerUndo(withTarget: target) { inner in
        inner.applyFormat(newFormat, at: address, skipUndo: true)
      }
    }
    undoManager?.setActionName("Format Cell")
  }

  private func applyFormat(_ format: CellFormat, at address: CellAddress, skipUndo: Bool) {
    var sheet = activeSheet
    var cell = sheet.cell(at: address)
    cell.format = format.isDefault ? nil : format
    sheet.setCell(cell, at: address)
    activeSheet = sheet
  }

  private func clamp(_ address: CellAddress) -> CellAddress {
    CellAddress(
      row: max(0, min(Workbook.defaultRowCount - 1, address.row)),
      col: max(0, min(Workbook.defaultColumnCount - 1, address.col))
    )
  }

  // MARK: - Clipboard

  func copySelection() -> String? {
    activeSheet.cell(at: selectionAnchor).raw.nilIfEmpty
  }

  func cutSelection() {
    let value = activeSheet.cell(at: selectionAnchor).raw
    guard !value.isEmpty else { return }
    setCellValue("", at: selectionAnchor)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
  }

  func pasteFromPasteboard() {
    guard let text = NSPasteboard.general.string(forType: .string) else { return }
    setCellValue(text, at: selectionAnchor)
    syncEditTextFromSelection()
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
      sheet.setCell(cell, at: address)
      activeSheet = sheet
      if address == selectionAnchor {
        syncEditTextFromSelection()
      }
    } else {
      setCellValue(value, at: address)
    }
  }
}

import AppKit

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
