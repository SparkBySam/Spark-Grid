import Foundation

extension SpreadsheetViewModel {
  func mergeSelection() {
    commitEditIfNeeded()
    let range = selectionRange
    let n = range.normalized
    guard n.minRow != n.maxRow || n.minCol != n.maxCol else { return }

    var sheet = activeSheet
    let before = sheet.mergedRanges
    sheet.mergedRanges.removeAll { merge in
      let m = merge.normalized
      return n.minRow <= m.maxRow && n.maxRow >= m.minRow
        && n.minCol <= m.maxCol && n.maxCol >= m.minCol
    }
    sheet.mergedRanges.append(
      CellRange(
        start: CellAddress(row: n.minRow, col: n.minCol),
        end: CellAddress(row: n.maxRow, col: n.maxCol)
      )
    )
    applyMergedRanges(sheet.mergedRanges, undoBefore: before, actionName: "Merge Cells")
    selectRange(
      from: CellAddress(row: n.minRow, col: n.minCol),
      to: CellAddress(row: n.maxRow, col: n.maxCol)
    )
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

  var canUnmergeSelection: Bool {
    let range = selectionRange.normalized
    return activeSheet.mergedRanges.contains { merge in
      let m = merge.normalized
      return range.minRow <= m.maxRow && range.maxRow >= m.minRow
        && range.minCol <= m.maxCol && range.maxCol >= m.minCol
    }
  }

  func insertChart(kind: SheetChart.Kind) {
    commitEditIfNeeded()
    let dataRange = selectionRange
    let n = dataRange.normalized
    guard n.minRow != n.maxRow || n.minCol != n.maxCol else { return }

    let anchorRow = min(activeSheet.effectiveRowCount - 1, n.maxRow + 2)
    let anchorCol = n.minCol
    let chart = SheetChart(
      kind: kind,
      title: "\(kind.title) Chart",
      dataRange: dataRange,
      anchorRow: anchorRow,
      anchorCol: anchorCol
    )
    var sheet = activeSheet
    let before = sheet.charts
    sheet.charts.append(chart)
    applyCharts(sheet.charts, undoBefore: before, actionName: "Insert Chart")
  }

  func removeChart(id: UUID) {
    var sheet = activeSheet
    let before = sheet.charts
    sheet.charts.removeAll { $0.id == id }
    guard sheet.charts != before else { return }
    applyCharts(sheet.charts, undoBefore: before, actionName: "Delete Chart")
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
