import AppKit
import Foundation

extension SpreadsheetViewModel {
  /// Format used for painting a cell (base + conditional formatting overlays).
  func resolvedFormat(at address: CellAddress) -> CellFormat? {
    let rules = activeSheet.conditionalFormats
    guard !rules.isEmpty else {
      return activeSheet.cell(at: address).format
    }
    if conditionalFormatCacheRevision != contentRevision {
      conditionalFormatCache.removeAll(keepingCapacity: true)
      conditionalFormatCacheRevision = contentRevision
    }
    if let index = conditionalFormatCache.index(forKey: address) {
      return conditionalFormatCache[index].value
    }
    let cell = activeSheet.cell(at: address)
    let value = displayValue(at: address)
    let text = formulaEngine.displayString(at: address, sheet: activeSheet, format: cell.format)
    let resolved = ConditionalFormatEvaluator.resolvedFormat(
      at: address,
      base: cell.format,
      rules: rules,
      value: value,
      displayString: text,
      numberFormat: cell.format?.numberFormat,
      numericValuesInRange: { [weak self] range in
        guard let self else { return [] }
        return self.numericValues(in: range)
      },
      evaluateFormula: { [weak self] raw, addr, origin in
        guard let self else { return .blank }
        return self.formulaEngine.evaluateConditionalFormula(
          raw,
          at: addr,
          relativeTo: origin,
          sheet: self.activeSheet
        )
      }
    )
    conditionalFormatCache[address] = resolved
    return resolved
  }

  private func numericValues(in range: CellRange) -> [Double] {
    let n = range.normalized
    var values: [Double] = []
    for row in n.minRow...n.maxRow {
      for col in n.minCol...n.maxCol {
        if let number = displayValue(at: CellAddress(row: row, col: col)).asNumber {
          values.append(number)
        }
      }
    }
    return values
  }

  func addConditionalFormatRule(_ rule: ConditionalFormatRule) {
    commitEditIfNeeded()
    var sheet = activeSheet
    let before = sheet.conditionalFormats
    sheet.conditionalFormats.append(rule)
    applyConditionalFormats(sheet.conditionalFormats, undoBefore: before, actionName: "Add Conditional Format")
  }

  func removeConditionalFormatRules(ids: Set<UUID>) {
    guard !ids.isEmpty else { return }
    commitEditIfNeeded()
    var sheet = activeSheet
    let before = sheet.conditionalFormats
    sheet.conditionalFormats.removeAll { ids.contains($0.id) }
    guard sheet.conditionalFormats != before else { return }
    applyConditionalFormats(sheet.conditionalFormats, undoBefore: before, actionName: "Remove Conditional Format")
  }

  func clearConditionalFormats(intersecting range: CellRange) {
    commitEditIfNeeded()
    var sheet = activeSheet
    let before = sheet.conditionalFormats
    sheet.conditionalFormats.removeAll { rule in
      rangesIntersect(rule.range, range)
    }
    guard sheet.conditionalFormats != before else { return }
    applyConditionalFormats(sheet.conditionalFormats, undoBefore: before, actionName: "Clear Conditional Formats")
  }

  func replaceConditionalFormats(_ rules: [ConditionalFormatRule], actionName: String = "Conditional Format") {
    commitEditIfNeeded()
    let before = activeSheet.conditionalFormats
    guard before != rules else { return }
    applyConditionalFormats(rules, undoBefore: before, actionName: actionName)
  }

  func restoreFilterFromActiveSheet() {
    isRestoringFilterFromSheet = true
    filterState = activeSheet.autoFilter
    isRestoringFilterFromSheet = false
  }

  func syncAutoFilterToActiveSheet() {
    var sheet = activeSheet
    guard sheet.autoFilter != filterState else { return }
    sheet.autoFilter = filterState
    setActiveSheetPreservingFormulas(sheet)
  }

  private func applyConditionalFormats(
    _ rules: [ConditionalFormatRule],
    undoBefore: [ConditionalFormatRule],
    actionName: String
  ) {
    var sheet = activeSheet
    sheet.conditionalFormats = rules
    setActiveSheetPreservingFormulas(sheet)
    conditionalFormatCache.removeAll(keepingCapacity: true)
    conditionalFormatCacheRevision = -1
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyConditionalFormats(undoBefore, undoBefore: rules, actionName: actionName)
    }
    undoManager?.setActionName(actionName)
    notifyGridRefresh()
  }

  private func rangesIntersect(_ a: CellRange, _ b: CellRange) -> Bool {
    let an = a.normalized
    let bn = b.normalized
    return an.minRow <= bn.maxRow && an.maxRow >= bn.minRow
      && an.minCol <= bn.maxCol && an.maxCol >= bn.minCol
  }
}
