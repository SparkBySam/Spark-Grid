import Foundation

/// Cross-sheet formula updates that run after the viewed sheet has already refreshed.
/// The edit path only schedules this. A sheet opened early is shown first; this pass
/// fills its values afterward.
nonisolated enum CrossSheetBackground {
  struct Request: Sendable {
    var token: UInt64
    var workbook: Workbook
    var editedSheetName: String
    var editedSheet: Sheet
    var editedAddresses: [CellAddress]
    var calculatedEdits: [CellAddress: CellValue]
    var graph: WorkbookDependencyGraph?
    /// Nil updates every affected formula. A name updates that sheet and the
    /// precedents required to do it.
    var onlySheetName: String?
  }

  struct Outcome: Sendable {
    var valuesBySheet: [String: [CellAddress: CellValue]]
  }

  static func graphInput(for workbook: Workbook) -> WorkbookGraphInput {
    var sheets: [WorkbookGraphInput.Sheet] = []
    var sheetIDsByName: [String: Int] = [:]
    sheets.reserveCapacity(workbook.sheets.count)
    for sheet in workbook.sheets {
      let sheetID = sheets.count
      let key = sheet.name.lowercased()
      if sheetIDsByName[key] == nil {
        sheetIDsByName[key] = sheetID
      }
      var columns: [[WorkbookGraphInput.Cell]] = []
      columns.reserveCapacity(sheet.formulaIngestByColumn.count)
      for column in sheet.formulaIngestByColumn.keys.sorted() {
        let entries = sheet.formulaIngestByColumn[column] ?? []
        var cells: [WorkbookGraphInput.Cell] = []
        cells.reserveCapacity(entries.count)
        for (address, raw) in entries {
          cells.append(WorkbookGraphInput.Cell(row: address.row, col: address.col, raw: raw))
        }
        columns.append(cells)
      }
      sheets.append(
        WorkbookGraphInput.Sheet(
          name: key,
          sheetID: sheetID,
          maxRow: max(0, sheet.effectiveRowCount - 1),
          maxCol: max(0, sheet.effectiveColumnCount - 1),
          columns: columns
        )
      )
    }
    var names: [WorkbookGraphInput.Name] = []
    for named in workbook.namedRanges.values where named.resolvesToRange {
      guard let sheetID = sheetIDsByName[named.sheetName.lowercased()] else { continue }
      names.append(
        WorkbookGraphInput.Name(
          key: named.name.uppercased(),
          sheetID: sheetID,
          minRow: min(named.startRow, named.endRow),
          maxRow: max(named.startRow, named.endRow),
          minCol: min(named.startCol, named.endCol),
          maxCol: max(named.startCol, named.endCol)
        )
      )
    }
    return WorkbookGraphInput(
      sheets: sheets,
      names: names,
      sheetIDsByName: sheetIDsByName,
      fallbackMaxRow: max(0, Workbook.defaultRowCount - 1),
      fallbackMaxCol: max(0, Workbook.defaultColumnCount - 1)
    )
  }

  static func compute(_ request: Request) -> Outcome {
    var workbook = request.workbook
    if let index = workbook.sheets.firstIndex(where: {
      $0.name.caseInsensitiveCompare(request.editedSheetName) == .orderedSame
    }) {
      workbook.sheets[index] = request.editedSheet
    }
    let graph = request.graph ?? WorkbookDependencyGraph.build(graphInput(for: workbook))
    guard let editedSheetID = graph.sheetID(for: request.editedSheetName) else {
      return Outcome(valuesBySheet: [:])
    }

    var overrides: [FormulaCoord: CellValue] = [:]
    overrides.reserveCapacity(request.calculatedEdits.count)
    for (address, value) in request.calculatedEdits {
      overrides[FormulaCoord(sheetID: editedSheetID, row: address.row, col: address.col)] = value
    }

    var sheetsByID: [Int: Sheet] = [:]
    sheetsByID.reserveCapacity(workbook.sheets.count)
    for sheet in workbook.sheets {
      if let sheetID = graph.sheetID(for: sheet.name) {
        sheetsByID[sheetID] = sheet
      }
    }

    var affected: [FormulaCoord: Int] = [:]
    var seen: Set<FormulaCoord> = []
    var queue: [FormulaCoord] = []
    func enqueue(_ coord: FormulaCoord) {
      if seen.insert(coord).inserted {
        queue.append(coord)
      }
    }
    for address in request.editedAddresses {
      enqueue(FormulaCoord(sheetID: editedSheetID, row: address.row, col: address.col))
    }
    for address in request.calculatedEdits.keys {
      enqueue(FormulaCoord(sheetID: editedSheetID, row: address.row, col: address.col))
    }

    var head = 0
    while head < queue.count {
      let coord = queue[head]
      head += 1
      for formulaID in graph.formulaIDsReading(sheetID: coord.sheetID, row: coord.row, col: coord.col) {
        guard graph.formulaCoords.indices.contains(formulaID) else { continue }
        let formulaCoord = graph.formulaCoords[formulaID]
        if overrides[formulaCoord] != nil {
          enqueue(formulaCoord)
          continue
        }
        if affected[formulaCoord] == nil {
          affected[formulaCoord] = formulaID
          enqueue(formulaCoord)
        }
      }
    }

    let context = EvaluationContext(
      workbook: workbook,
      graph: graph,
      sheetsByID: sheetsByID,
      overrides: overrides,
      affected: affected
    )
    let limitSheetID = request.onlySheetName.flatMap { graph.sheetID(for: $0) }
    if let limitSheetID, request.onlySheetName != nil {
      for (coord, formulaID) in affected where coord.sheetID == limitSheetID {
        context.evaluate(formulaID: formulaID, at: coord)
      }
    } else {
      for (coord, formulaID) in affected {
        context.evaluate(formulaID: formulaID, at: coord)
      }
    }

    var valuesBySheet: [String: [CellAddress: CellValue]] = [:]
    for (coord, value) in context.memo {
      guard graph.sheetNames.indices.contains(coord.sheetID) else { continue }
      let key = graph.sheetNames[coord.sheetID]
      var sheetValues = valuesBySheet[key] ?? [:]
      sheetValues[CellAddress(row: coord.row, col: coord.col)] = value
      valuesBySheet[key] = sheetValues
    }
    return Outcome(valuesBySheet: valuesBySheet)
  }
}

private nonisolated final class EvaluationContext {
  let workbook: Workbook
  let graph: WorkbookDependencyGraph
  let sheetsByID: [Int: Sheet]
  let overrides: [FormulaCoord: CellValue]
  let affected: [FormulaCoord: Int]
  var memo: [FormulaCoord: CellValue] = [:]
  var visiting: Set<FormulaCoord> = []
  var expressions: [FormulaCoord: FormulaExpr] = [:]
  var currentSheetID = 0
  var currentSheetName = ""

  init(
    workbook: Workbook,
    graph: WorkbookDependencyGraph,
    sheetsByID: [Int: Sheet],
    overrides: [FormulaCoord: CellValue],
    affected: [FormulaCoord: Int]
  ) {
    self.workbook = workbook
    self.graph = graph
    self.sheetsByID = sheetsByID
    self.overrides = overrides
    self.affected = affected
  }

  func evaluate(formulaID: Int, at coord: FormulaCoord) {
    _ = value(at: coord)
    if memo[coord] != nil { return }
    guard affected[coord] == formulaID else { return }
    _ = evaluateFormula(at: coord)
  }

  func value(at coord: FormulaCoord) -> CellValue {
    if let cached = memo[coord] { return cached }
    if let override = overrides[coord] { return override }
    if affected[coord] != nil {
      return evaluateFormula(at: coord)
    }
    return storedValue(sheetID: coord.sheetID, row: coord.row, col: coord.col)
  }

  func evaluateFormula(at coord: FormulaCoord) -> CellValue {
    if let cached = memo[coord] { return cached }
    if !visiting.insert(coord).inserted {
      let cycle = CellValue.error(.cycle)
      memo[coord] = cycle
      return cycle
    }
    defer { visiting.remove(coord) }

    let previousSheetID = currentSheetID
    let previousSheetName = currentSheetName
    currentSheetID = coord.sheetID
    currentSheetName = sheetsByID[coord.sheetID]?.name ?? ""
    defer {
      currentSheetID = previousSheetID
      currentSheetName = previousSheetName
    }

    let cell = sheetsByID[coord.sheetID]?.cell(at: CellAddress(row: coord.row, col: coord.col)) ?? Cell()
    let raw = cell.raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let expr: FormulaExpr
    if let parsed = expressions[coord] {
      expr = parsed
    } else if FormulaSyntax.isFormula(raw), let parsed = try? FormulaParser.parse(raw) {
      expressions[coord] = parsed
      expr = parsed
    } else {
      let unresolved = cell.cachedFormulaValue ?? CellValue.fromLiteralRaw(cell.raw)
      memo[coord] = unresolved
      return unresolved
    }

    var evaluator = FormulaEvaluator { [self] ref in
      self.lookup(ref)
    }
    evaluator.evaluationOrigin = CellAddress(row: coord.row, col: coord.col)
    evaluator.namedRangeLookup = { [self] name in
      self.namedRangeExpr(named: name)
    }
    evaluator.sheetExtent = { [self] sheetName in
      self.extent(for: sheetName)
    }
    let value = evaluator.evaluate(expr)
    memo[coord] = value
    return value
  }

  func lookup(_ ref: FormulaRef) -> CellValue {
    let sheetID: Int
    if let name = ref.sheet {
      guard let resolved = graph.sheetID(for: name) else { return .error(.ref) }
      sheetID = resolved
    } else {
      sheetID = currentSheetID
    }
    return value(at: FormulaCoord(sheetID: sheetID, row: ref.row, col: ref.col))
  }

  func storedValue(sheetID: Int, row: Int, col: Int) -> CellValue {
    guard let sheet = sheetsByID[sheetID] else { return .blank }
    let cell = sheet.cell(at: CellAddress(row: row, col: col))
    if FormulaSyntax.isFormula(cell.raw) {
      return cell.cachedFormulaValue ?? CellValue.fromLiteralRaw(cell.raw)
    }
    return CellValue.fromLiteralRaw(cell.raw)
  }

  func extent(for sheetName: String?) -> (maxRow: Int, maxCol: Int) {
    let resolved = sheetName ?? currentSheetName
    if let sheet = workbook.sheets.first(where: {
      $0.name.caseInsensitiveCompare(resolved) == .orderedSame
    }) {
      return (max(0, sheet.effectiveRowCount - 1), max(0, sheet.effectiveColumnCount - 1))
    }
    return (max(0, Workbook.defaultRowCount - 1), max(0, Workbook.defaultColumnCount - 1))
  }

  func namedRangeExpr(named name: String) -> FormulaExpr? {
    guard let named = workbook.namedRange(named: name), named.resolvesToRange else { return nil }
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
    if start.row == end.row, start.col == end.col {
      return .cellRef(start)
    }
    return .range(start, end)
  }
}
