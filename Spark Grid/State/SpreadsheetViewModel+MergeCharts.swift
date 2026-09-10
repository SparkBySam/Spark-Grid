import AppKit
import Foundation

enum MergeAxis: Sendable {
  /// One rectangle covering the whole selection.
  case all
  /// Merge each row across selected columns (Excel “Merge Across”).
  case horizontal
  /// Merge each column down selected rows.
  case vertical
}

extension SpreadsheetViewModel {
  enum MergeOutcome: Equatable {
    case cancelled
    case merged(count: Int)
    case nothingToMerge
  }

  /// Merges the selection. Warns when other cells have values that will be cleared
  /// (keeps the top-left cell of each merge, Excel-style).
  @discardableResult
  func mergeSelection(axis: MergeAxis = .all, confirmDiscard: Bool = true) -> MergeOutcome {
    commitEditIfNeeded()
    let range = selectionRange
    let n = range.normalized
    guard n.minRow != n.maxRow || n.minCol != n.maxCol else { return .nothingToMerge }

    let planned = plannedMerges(for: range, axis: axis)
    guard !planned.isEmpty else { return .nothingToMerge }

    if confirmDiscard, let warning = mergeWarningText(for: planned) {
      let alert = NSAlert()
      alert.messageText = "Merge Cells?"
      alert.informativeText = warning
      alert.alertStyle = .warning
      alert.addButton(withTitle: "Merge")
      alert.addButton(withTitle: "Cancel")
      guard alert.runModal() == .alertFirstButtonReturn else { return .cancelled }
    }

    var sheet = activeSheet
    let beforeMerges = sheet.mergedRanges
    let beforeCells = sheet.cells

    for plan in planned {
      let pn = plan.normalized
      sheet.mergedRanges.removeAll { merge in
        let m = merge.normalized
        return pn.minRow <= m.maxRow && pn.maxRow >= m.minRow
          && pn.minCol <= m.maxCol && pn.maxCol >= m.minCol
      }
    }
    sheet.mergedRanges.append(contentsOf: planned)

    for plan in planned {
      let pn = plan.normalized
      let topLeft = CellAddress(row: pn.minRow, col: pn.minCol)
      for row in pn.minRow...pn.maxRow {
        for col in pn.minCol...pn.maxCol {
          let address = CellAddress(row: row, col: col)
          guard address != topLeft else { continue }
          var cell = sheet.cell(at: address)
          if !cell.raw.isEmpty {
            cell.raw = ""
            sheet.setCell(cell, at: address)
          }
        }
      }
    }

    applyMergeMutation(
      sheet: sheet,
      undoMerges: beforeMerges,
      undoCells: beforeCells,
      actionName: mergeActionName(axis)
    )
    selectRange(
      from: CellAddress(row: n.minRow, col: n.minCol),
      to: CellAddress(row: n.maxRow, col: n.maxCol)
    )
    return .merged(count: planned.count)
  }

  func unmergeSelection() {
    commitEditIfNeeded()
    let range = selectionRange.normalized
    var sheet = activeSheet
    let before = sheet.mergedRanges
    sheet.mergedRanges.removeAll { merge in
      let m = merge.normalized
      return range.minRow <= m.maxRow && range.maxRow >= m.minRow
        && range.minCol <= m.maxCol && range.maxCol >= m.minCol
    }
    guard sheet.mergedRanges != before else { return }
    applyMergedRanges(sheet.mergedRanges, undoBefore: before, actionName: "Unmerge Cells")
  }

  var canMergeSelection: Bool {
    let n = selectionRange.normalized
    return n.minRow != n.maxRow || n.minCol != n.maxCol
  }

  var canMergeHorizontally: Bool {
    let n = selectionRange.normalized
    return n.minCol != n.maxCol
  }

  var canMergeVertically: Bool {
    let n = selectionRange.normalized
    return n.minRow != n.maxRow
  }

  var canUnmergeSelection: Bool {
    let range = selectionRange.normalized
    return activeSheet.mergedRanges.contains { merge in
      let m = merge.normalized
      return range.minRow <= m.maxRow && range.maxRow >= m.minRow
        && range.minCol <= m.maxCol && range.maxCol >= m.minCol
    }
  }

  func insertChart(kind: SheetChart.Kind) {
    beginInsertChart(preferredKind: kind)
  }

  func beginInsertChart(preferredKind: SheetChart.Kind = .bar) {
    commitEditIfNeeded()
    let n = selectionRange.normalized
    guard n.minRow != n.maxRow || n.minCol != n.maxCol else { return }
    pendingChartKind = preferredKind
    isInsertChartPresented = true
  }

  func insertChart(_ chart: SheetChart) {
    commitEditIfNeeded()
    var sheet = activeSheet
    let before = sheet.charts
    var next = chart
    if next.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      next.title = "\(next.kind.title) Chart"
    }
    sheet.charts.append(next)
    applyCharts(sheet.charts, undoBefore: before, actionName: "Insert Chart")
    isInsertChartPresented = false
  }

  func removeChart(id: UUID) {
    var sheet = activeSheet
    let before = sheet.charts
    sheet.charts.removeAll { $0.id == id }
    guard sheet.charts != before else { return }
    applyCharts(sheet.charts, undoBefore: before, actionName: "Delete Chart")
  }

  // MARK: - Private

  private func plannedMerges(for range: CellRange, axis: MergeAxis) -> [CellRange] {
    let n = range.normalized
    switch axis {
    case .all:
      return [
        CellRange(
          start: CellAddress(row: n.minRow, col: n.minCol),
          end: CellAddress(row: n.maxRow, col: n.maxCol)
        ),
      ]
    case .horizontal:
      guard n.minCol != n.maxCol else { return [] }
      return (n.minRow...n.maxRow).map { row in
        CellRange(
          start: CellAddress(row: row, col: n.minCol),
          end: CellAddress(row: row, col: n.maxCol)
        )
      }
    case .vertical:
      guard n.minRow != n.maxRow else { return [] }
      return (n.minCol...n.maxCol).map { col in
        CellRange(
          start: CellAddress(row: n.minRow, col: col),
          end: CellAddress(row: n.maxRow, col: col)
        )
      }
    }
  }

  private func mergeWarningText(for merges: [CellRange]) -> String? {
    var keptLines: [String] = []
    var clearedLines: [String] = []

    for merge in merges {
      let n = merge.normalized
      let topLeft = CellAddress(row: n.minRow, col: n.minCol)
      let keptRaw = activeSheet.cell(at: topLeft).raw
      if !keptRaw.isEmpty {
        keptLines.append("• \(topLeft.a1): \(preview(keptRaw))")
      } else {
        keptLines.append("• \(topLeft.a1): (empty)")
      }
      for row in n.minRow...n.maxRow {
        for col in n.minCol...n.maxCol {
          let address = CellAddress(row: row, col: col)
          guard address != topLeft else { continue }
          let raw = activeSheet.cell(at: address).raw
          guard !raw.isEmpty else { continue }
          clearedLines.append("• \(address.a1): \(preview(raw))")
          if clearedLines.count >= 8 {
            clearedLines.append("• …")
            break
          }
        }
        if clearedLines.count >= 8 { break }
      }
    }

    guard !clearedLines.isEmpty else { return nil }
    return """
    The top-left cell is kept; other values are cleared.

    Kept:
    \(keptLines.joined(separator: "\n"))

    Cleared:
    \(clearedLines.joined(separator: "\n"))
    """
  }

  private func preview(_ raw: String) -> String {
    raw.count > 40 ? String(raw.prefix(37)) + "…" : raw
  }

  private func mergeActionName(_ axis: MergeAxis) -> String {
    switch axis {
    case .all: return "Merge Cells"
    case .horizontal: return "Merge Across"
    case .vertical: return "Merge Vertically"
    }
  }

  private func applyMergeMutation(
    sheet: Sheet,
    undoMerges: [CellRange],
    undoCells: [CellAddress: Cell],
    actionName: String
  ) {
    let afterMerges = sheet.mergedRanges
    let afterCells = sheet.cells
    setActiveSheetPreservingFormulas(sheet)
    undoManager?.registerUndo(withTarget: self) { target in
      var restored = target.activeSheet
      restored.mergedRanges = undoMerges
      restored.replaceCells(undoCells)
      target.applyMergeMutation(
        sheet: restored,
        undoMerges: afterMerges,
        undoCells: afterCells,
        actionName: actionName
      )
    }
    undoManager?.setActionName(actionName)
    notifyGridRefresh()
  }

  private func applyMergedRanges(
    _ ranges: [CellRange],
    undoBefore: [CellRange],
    actionName: String
  ) {
    var sheet = activeSheet
    sheet.mergedRanges = ranges
    setActiveSheetPreservingFormulas(sheet)
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyMergedRanges(undoBefore, undoBefore: ranges, actionName: actionName)
    }
    undoManager?.setActionName(actionName)
    notifyGridRefresh()
  }

  private func applyCharts(
    _ charts: [SheetChart],
    undoBefore: [SheetChart],
    actionName: String
  ) {
    var sheet = activeSheet
    sheet.charts = charts
    setActiveSheetPreservingFormulas(sheet)
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyCharts(undoBefore, undoBefore: charts, actionName: actionName)
    }
    undoManager?.setActionName(actionName)
    notifyGridRefresh()
  }
}
