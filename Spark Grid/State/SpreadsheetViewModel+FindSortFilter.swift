import AppKit
import Foundation

extension SpreadsheetViewModel {
  // MARK: - Find / Replace

  func showFindBar(replace: Bool) {
    isFindReplaceMode = replace
    isFindBarVisible = true
    refreshFindMatches(selectCurrent: true)
  }

  func hideFindBar() {
    isFindBarVisible = false
    findMatches = []
    findMatchIndex = -1
  }

  func refreshFindMatches(selectCurrent: Bool = false) {
    findMatches = collectFindMatches()
    if findMatches.isEmpty {
      findMatchIndex = -1
      return
    }
    if selectCurrent {
      // Prefer a match at/after the selection.
      let start = selectionAnchor
      if let idx = findMatches.firstIndex(where: { $0 >= start }) {
        findMatchIndex = idx
      } else {
        findMatchIndex = 0
      }
      jumpToCurrentFindMatch()
    } else if findMatchIndex >= findMatches.count {
      findMatchIndex = findMatches.count - 1
    } else if findMatchIndex < 0 {
      findMatchIndex = 0
    }
  }

  func findNext() {
    guard !findQuery.isEmpty else {
      showFindBar(replace: isFindReplaceMode)
      return
    }
    if findMatches.isEmpty { refreshFindMatches() }
    guard !findMatches.isEmpty else { return }
    findMatchIndex = (findMatchIndex + 1) % findMatches.count
    jumpToCurrentFindMatch()
  }

  func findPrevious() {
    guard !findQuery.isEmpty else {
      showFindBar(replace: isFindReplaceMode)
      return
    }
    if findMatches.isEmpty { refreshFindMatches() }
    guard !findMatches.isEmpty else { return }
    findMatchIndex = (findMatchIndex - 1 + findMatches.count) % findMatches.count
    jumpToCurrentFindMatch()
  }

  @discardableResult
  func replaceCurrent() -> Bool {
    refreshFindMatches()
    guard findMatchIndex >= 0, findMatchIndex < findMatches.count else { return false }
    let address = findMatches[findMatchIndex]
    guard replaceMatch(at: address) else { return false }
    refreshFindMatches()
    if findMatches.isEmpty {
      findMatchIndex = -1
      return true
    }
    findMatchIndex = min(findMatchIndex, findMatches.count - 1)
    jumpToCurrentFindMatch()
    return true
  }

  func replaceAll() -> Int {
    let matches = collectFindMatches()
    guard !matches.isEmpty else { return 0 }
    undoManager?.beginUndoGrouping()
    var count = 0
    for address in matches {
      if replaceMatch(at: address) { count += 1 }
    }
    undoManager?.endUndoGrouping()
    undoManager?.setActionName("Replace All")
    refreshFindMatches()
    return count
  }

  private func jumpToCurrentFindMatch() {
    guard findMatchIndex >= 0, findMatchIndex < findMatches.count else { return }
    let address = findMatches[findMatchIndex]
    select(address)
    requestScrollSelectionIntoView()
  }

  func requestScrollSelectionIntoView() {
    scrollRequestToken &+= 1
  }

  private func collectFindMatches() -> [CellAddress] {
    let query = findQuery
    guard !query.isEmpty else { return [] }
    let range: CellRange
    switch findScope {
    case .sheet:
      range = activeSheet.populatedRangeFromOrigin
    case .selection:
      range = selectionRange.normalizedRange
    }
    let n = range.normalized
    var matches: [CellAddress] = []
    for row in n.minRow...n.maxRow {
      if isRowHiddenByFilter(row) { continue }
      for col in n.minCol...n.maxCol {
        let address = CellAddress(row: row, col: col)
        if cellMatchesFind(at: address) {
          matches.append(address)
        }
      }
    }
    return matches
  }

  private func cellMatchesFind(at address: CellAddress) -> Bool {
    let query = findQuery
    guard !query.isEmpty else { return false }
    let haystack = displayString(at: address)
    if findEntireCell {
      if findMatchCase {
        return haystack == query
      }
      return haystack.caseInsensitiveCompare(query) == .orderedSame
    }
    if findMatchCase {
      return haystack.contains(query)
    }
    return haystack.range(of: query, options: .caseInsensitive) != nil
  }

  private func replaceMatch(at address: CellAddress) -> Bool {
    let cell = activeSheet.cell(at: address)
    let display = displayString(at: address)
    guard cellMatchesFind(at: address) else { return false }

    if FormulaSyntax.isFormula(cell.raw) {
      // Prefer replacing inside raw formula text when the query appears there;
      // otherwise leave formulas alone when the match came only from computed display.
      let raw = cell.raw
      if let replaced = replacing(in: raw, query: findQuery, replacement: findReplaceText) {
        setCellValue(replaced, at: address)
        return true
      }
      return false
    }

    if findEntireCell {
      setCellValue(findReplaceText, at: address)
      return true
    }
    if let replaced = replacing(in: display, query: findQuery, replacement: findReplaceText) {
      setCellValue(replaced, at: address)
      return true
    }
    return false
  }

  private func replacing(in text: String, query: String, replacement: String) -> String? {
    guard !query.isEmpty else { return nil }
    if findMatchCase {
      guard text.contains(query) else { return nil }
      return text.replacingOccurrences(of: query, with: replacement)
    }
    guard let range = text.range(of: query, options: .caseInsensitive) else { return nil }
    var result = text
    result.replaceSubrange(range, with: replacement)
    // Replace remaining case-insensitive occurrences.
    while let next = result.range(of: query, options: .caseInsensitive) {
      result.replaceSubrange(next, with: replacement)
    }
    return result
  }

  // MARK: - Sort

  func sortRange(
    column: Int,
    direction: SortDirection,
    hasHeader: Bool
  ) {
    commitEditIfNeeded()
    let range = effectiveSortRange()
    let n = range.normalized
    guard n.maxRow >= n.minRow, n.maxCol >= n.minCol else { return }
    guard column >= n.minCol, column <= n.maxCol else { return }

    let snapshot = workbook
    let headerOffset = hasHeader ? 1 : 0
    let firstDataRow = n.minRow + headerOffset
    guard firstDataRow <= n.maxRow else { return }

    struct RowPack {
      var rowIndex: Int
      var cells: [Int: Cell]
      var height: CGFloat?
      var sortKey: String
    }

    var packs: [RowPack] = []
    for row in firstDataRow...n.maxRow {
      var cells: [Int: Cell] = [:]
      for col in n.minCol...n.maxCol {
        let address = CellAddress(row: row, col: col)
        if let cell = activeSheet.cells[address] {
          cells[col] = cell
        }
      }
      let key = displayString(at: CellAddress(row: row, col: column))
      packs.append(RowPack(
        rowIndex: row,
        cells: cells,
        height: activeSheet.rowHeights[row],
        sortKey: key
      ))
    }

    packs.sort { lhs, rhs in
      let cmp = lhs.sortKey.localizedStandardCompare(rhs.sortKey)
      if cmp == .orderedSame {
        return lhs.rowIndex < rhs.rowIndex
      }
      return direction == .ascending ? cmp == .orderedAscending : cmp == .orderedDescending
    }

    var sheet = activeSheet
    // Clear old cells in data rows.
    for row in firstDataRow...n.maxRow {
      for col in n.minCol...n.maxCol {
        sheet.cells.removeValue(forKey: CellAddress(row: row, col: col))
      }
      sheet.rowHeights.removeValue(forKey: row)
    }

    for (offset, pack) in packs.enumerated() {
      let newRow = firstDataRow + offset
      let rowDelta = newRow - pack.rowIndex
      for (col, cell) in pack.cells {
        var next = cell
        if rowDelta != 0 {
          next.raw = FormulaRewriter.adjust(cell.raw, rowDelta: rowDelta, colDelta: 0)
        }
        sheet.cells[CellAddress(row: newRow, col: col)] = next
      }
      if let height = pack.height {
        sheet.rowHeights[newRow] = height
      }
    }

    activeSheet = sheet
    registerWorkbookStructureUndo(before: snapshot, action: "Sort Range")
    notifyGridRefresh()
  }

  func effectiveSortRange() -> CellRange {
    let range = selectionRange
    if range.isSingleCell {
      return activeSheet.populatedBounds ?? .singleOrigin
    }
    return range
  }

  // MARK: - Filter

  func createFilter() {
    commitEditIfNeeded()
    var range = selectionRange
    if range.isSingleCell {
      range = filterRangeForSingleCell(selectionAnchor)
    }
    var n = range.normalized
    // If the block starts below row 1 and the row above looks like headers, include it.
    if n.minRow > 0 {
      let headerRow = n.minRow - 1
      var headerHasContent = false
      for col in n.minCol...n.maxCol {
        if !activeSheet.cell(at: CellAddress(row: headerRow, col: col)).raw.isEmpty {
          headerHasContent = true
          break
        }
      }
      if headerHasContent {
        range = CellRange(
          start: CellAddress(row: headerRow, col: n.minCol),
          end: CellAddress(row: n.maxRow, col: n.maxCol)
        )
        n = range.normalized
      }
    }
    guard n.maxRow > n.minRow else { return }
    filterState = SheetFilterState(range: range, selectedValuesByColumn: [:])
    notifyGridRefresh()
  }

  /// Range used when Create Filter is invoked from a single selected cell.
  private func filterRangeForSingleCell(_ seed: CellAddress) -> CellRange {
    if let region = contiguousRegion(around: seed), region.normalized.maxRow > region.normalized.minRow {
      return region
    }
    // Only fall back to the used range when the selection sits inside it.
    if let bounds = activeSheet.populatedBounds, bounds.contains(seed) {
      return bounds
    }
    return .singleOrigin
  }

  /// Expands from `seed` to the largest filled rectangle (no empty border gaps).
  func contiguousRegion(around seed: CellAddress) -> CellRange? {
    let sheet = activeSheet
    func hasContent(row: Int, col: Int) -> Bool {
      !sheet.cell(at: CellAddress(row: row, col: col)).raw.isEmpty
    }

    // Empty seed outside any table → no region (do not silently grab distant used range).
    guard hasContent(row: seed.row, col: seed.col) else {
      if let bounds = sheet.populatedBounds, bounds.contains(seed) {
        return bounds
      }
      return nil
    }

    var minRow = seed.row
    var maxRow = seed.row
    var minCol = seed.col
    var maxCol = seed.col
    var expanded = true
    let rowLimit = sheet.effectiveRowCount - 1
    let colLimit = sheet.effectiveColumnCount - 1

    while expanded {
      expanded = false
      if minRow > 0 {
        let row = minRow - 1
        if (minCol...maxCol).contains(where: { hasContent(row: row, col: $0) }) {
          minRow = row
          expanded = true
        }
      }
      if maxRow < rowLimit {
        let row = maxRow + 1
        if (minCol...maxCol).contains(where: { hasContent(row: row, col: $0) }) {
          maxRow = row
          expanded = true
        }
      }
      if minCol > 0 {
        let col = minCol - 1
        if (minRow...maxRow).contains(where: { hasContent(row: $0, col: col) }) {
          minCol = col
          expanded = true
        }
      }
      if maxCol < colLimit {
        let col = maxCol + 1
        if (minRow...maxRow).contains(where: { hasContent(row: $0, col: col) }) {
          maxCol = col
          expanded = true
        }
      }
    }

    return CellRange(
      start: CellAddress(row: minRow, col: minCol),
      end: CellAddress(row: maxRow, col: maxCol)
    )
  }

  func clearFilter() {
    guard filterState != nil else { return }
    filterState = nil
    notifyGridRefresh()
  }

  /// Clears criteria for one column and removes its filter affordance.
  func clearColumnFilter(_ column: Int) {
    guard var state = filterState, state.isColumnActive(column) else { return }
    state.selectedValuesByColumn.removeValue(forKey: column)
    state.excludedColumns.insert(column)
    let n = state.range.normalized
    let remaining = (n.minCol...n.maxCol).filter { state.isColumnActive($0) }
    if remaining.isEmpty {
      filterState = nil
    } else {
      filterState = state
    }
    notifyGridRefresh()
  }

  func setFilterValues(column: Int, values: Set<String>?) {
    guard var state = filterState else { return }
    state.excludedColumns.remove(column)
    if let values {
      state.selectedValuesByColumn[column] = values
    } else {
      state.selectedValuesByColumn.removeValue(forKey: column)
    }
    filterState = state
    notifyGridRefresh()
  }

  func isRowHiddenByFilter(_ row: Int) -> Bool {
    guard filterState != nil else { return false }
    if hiddenRowsCache == nil {
      hiddenRowsCache = rebuildHiddenRowsCache()
    }
    return hiddenRowsCache?.contains(row) ?? false
  }

  private func rebuildHiddenRowsCache() -> Set<Int> {
    guard let filterState else { return [] }
    let n = filterState.range.normalized
    guard n.maxRow > n.minRow else { return [] }
    var hidden = Set<Int>()
    for row in (n.minRow + 1)...n.maxRow {
      if filterState.isRowHidden(row, sheet: activeSheet, displayString: { [weak self] address in
        self?.displayString(at: address) ?? ""
      }) {
        hidden.insert(row)
      }
    }
    return hidden
  }

  func isFilterHeaderCell(row: Int, col: Int) -> Bool {
    guard let filterState else { return false }
    let n = filterState.range.normalized
    return row == n.minRow && filterState.isColumnActive(col)
  }

  func isFilterColumn(_ col: Int) -> Bool {
    filterState?.isColumnActive(col) ?? false
  }

  /// Last sheet row that currently has non-zero height (skips filter-hidden rows).
  func lastVisibleRowIndex() -> Int {
    let last = activeSheet.effectiveRowCount - 1
    guard last >= 0 else { return 0 }
    for row in stride(from: last, through: 0, by: -1) {
      if !isRowHiddenByFilter(row) { return row }
    }
    return 0
  }

  // MARK: - Zoom

  func zoomIn() {
    zoomScale = min(2.0, (zoomScale * 1.25 * 100).rounded() / 100)
  }

  func zoomOut() {
    zoomScale = max(0.5, (zoomScale / 1.25 * 100).rounded() / 100)
  }

  func zoomActualSize() {
    zoomScale = 1.0
  }
}

private extension CellRange {
  var normalizedRange: CellRange {
    let n = normalized
    return CellRange(
      start: CellAddress(row: n.minRow, col: n.minCol),
      end: CellAddress(row: n.maxRow, col: n.maxCol)
    )
  }
}
