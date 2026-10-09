import Foundation

/// Evaluates formulas on the active sheet, with cross-sheet lookups into the workbook.
final class FormulaEngine {
  private var valueCache: [CellAddress: CellValue] = [:]
  private var formulaAST: [CellAddress: FormulaExpr] = [:]
  private var dependencies: [CellAddress: Set<CellAddress>] = [:] // formula -> local refs
  private var dependencyRanges: [CellAddress: [CellRange]] = [:] // formula -> ranges read at eval
  private var dependents: [CellAddress: Set<CellAddress>] = [:] // cell -> formulas that use it
  private var revision: Int = 0

  private var workbook = Workbook.empty
  private var activeSheetName = "Sheet1"
  private var foreignCache: [ForeignKey: CellValue] = [:]
  private var foreignVisiting: Set<ForeignKey> = []

  private struct ForeignKey: Hashable {
    var sheet: String
    var address: CellAddress
  }

  var cacheRevision: Int { revision }

  func displayValue(at address: CellAddress, sheet: Sheet) -> CellValue {
    // Literals always come from the sheet being painted. The address cache is not
    // sheet-scoped, so a hit can still be another sheet's value, or a blank cached
    // before a cross-sheet paste wrote this cell.
    if let literal = literalOnSheet(at: address, sheet: sheet) {
      return literal
    }
    if let cached = valueCache[address] {
      return cached
    }
    if formulaAST[address] != nil {
      recalculate(addresses: [address], sheet: sheet)
      if let cached = valueCache[address] {
        return cached
      }
    }
    let value = literalOrEmpty(sheet.cell(at: address).raw)
    valueCache[address] = value
    return value
  }

  func displayString(at address: CellAddress, sheet: Sheet, format: CellFormat?) -> String {
    let value = displayValue(at: address, sheet: sheet)
    return CellFormatRenderer.displayText(for: value, format: format, fallbackRaw: sheet.cell(at: address).raw)
  }

  /// Evaluates a conditional-formatting formula relative to `origin` as if entered at `address`.
  func evaluateConditionalFormula(
    _ raw: String,
    at address: CellAddress,
    relativeTo origin: CellAddress,
    sheet: Sheet
  ) -> CellValue {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .blank }
    let withEquals = trimmed.hasPrefix("=") ? trimmed : "=\(trimmed)"
    let adjusted = FormulaRewriter.adjust(
      withEquals,
      rowDelta: address.row - origin.row,
      colDelta: address.col - origin.col
    )
    guard let expr = try? FormulaParser.parse(adjusted) else { return .error(.error) }

    var evaluator = FormulaEvaluator { [weak self] ref in
      guard let self else { return .blank }
      return self.resolve(ref, activeSheet: sheet, localEval: { addr in
        _ = self.displayValue(at: addr, sheet: sheet)
      })
    }
    evaluator.evaluationOrigin = address
    evaluator.namedRangeLookup = { [weak self] name in
      self?.namedRangeExpr(named: name)
    }
    evaluator.sheetExtent = { [weak self] sheetName in
      guard let self else { return (999, 25) }
      return self.extent(for: sheetName ?? self.activeSheetName)
    }
    return evaluator.evaluate(expr)
  }

  /// Full rebuild for the workbook's active sheet (also enables cross-sheet lookups).
  /// When `recalculate` is false, formulas evaluate on demand via `displayValue` (faster open / sheet switch).
  func rebuild(workbook: Workbook, recalculate: Bool = false) {
    clear()
    self.workbook = workbook
    let sheet = workbook.activeSheet
    activeSheetName = sheet.name
    for (address, cell) in sheet.cells where FormulaSyntax.isFormula(cell.raw) {
      ingest(address: address, raw: cell.raw, sheet: sheet, recalculate: false)
    }
    if recalculate {
      recalculateAll(sheet: sheet)
    }
  }

  /// Convenience when only a single sheet is available (e.g. isolated print of one sheet).
  func rebuild(sheet: Sheet, recalculate: Bool = true) {
    rebuild(workbook: Workbook(sheets: [sheet], activeSheetIndex: 0), recalculate: recalculate)
  }

  /// Update after one or more cells change on the active sheet.
  func cellsDidChange(_ addresses: [CellAddress], sheet: Sheet) {
    guard !addresses.isEmpty else { return }
    foreignCache.removeAll(keepingCapacity: true)
    var dirty: Set<CellAddress> = []
    for address in addresses {
      ingest(address: address, raw: sheet.cell(at: address).raw, sheet: sheet, recalculate: false)
      dirty.insert(address)
      if let deps = dependents[address] {
        dirty.formUnion(deps)
      }
      for (formulaAddr, ranges) in dependencyRanges {
        if ranges.contains(where: { $0.contains(address) }) {
          dirty.insert(formulaAddr)
        }
      }
    }
    var queue = Array(dirty)
    var seen = dirty
    while let next = queue.popLast() {
      guard let kids = dependents[next] else { continue }
      for kid in kids where !seen.contains(kid) {
        seen.insert(kid)
        queue.append(kid)
      }
    }
    recalculate(addresses: seen, sheet: sheet)
  }

  func clear() {
    valueCache.removeAll(keepingCapacity: true)
    formulaAST.removeAll(keepingCapacity: true)
    dependencies.removeAll(keepingCapacity: true)
    dependencyRanges.removeAll(keepingCapacity: true)
    dependents.removeAll(keepingCapacity: true)
    foreignCache.removeAll(keepingCapacity: true)
    foreignVisiting.removeAll(keepingCapacity: true)
    revision &+= 1
  }

  // MARK: - Private

  private func ingest(address: CellAddress, raw: String, sheet: Sheet, recalculate: Bool) {
    if let oldDeps = dependencies.removeValue(forKey: address) {
      for dep in oldDeps {
        dependents[dep]?.remove(address)
        if dependents[dep]?.isEmpty == true {
          dependents.removeValue(forKey: dep)
        }
      }
    }
    formulaAST.removeValue(forKey: address)
    dependencyRanges.removeValue(forKey: address)
    valueCache.removeValue(forKey: address)

    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if FormulaSyntax.isFormula(trimmed) {
      do {
        let expr = try FormulaParser.parse(trimmed)
        formulaAST[address] = expr
        let maxRow = sheet.effectiveRowCount - 1
        let maxCol = sheet.effectiveColumnCount - 1
        let deps = FormulaDependencies.collect(
          from: expr,
          activeSheetName: activeSheetName,
          maxRow: maxRow,
          maxCol: maxCol,
          namedRangeLookup: { [weak self] name in
            self?.namedRangeExpr(named: name)
          }
        )
        dependencies[address] = deps
        dependencyRanges[address] = FormulaDependencies.collectWatchedRanges(
          from: expr,
          activeSheetName: activeSheetName,
          maxRow: maxRow,
          maxCol: maxCol,
          namedRangeLookup: { [weak self] name in
            self?.namedRangeExpr(named: name)
          }
        )
        for dep in deps {
          dependents[dep, default: []].insert(address)
        }
        if let snapshot = sheet.cell(at: address).importedFormulaResult {
          valueCache[address] = CellValue.fromImportedExcel(snapshot)
        }
      } catch {
        valueCache[address] = .error(.error)
      }
    } else {
      valueCache[address] = literalOrEmpty(trimmed)
    }

    if recalculate {
      cellsDidChange([address], sheet: sheet)
    }
  }

  private func literalOrEmpty(_ raw: String) -> CellValue {
    CellValue.fromLiteralRaw(raw)
  }

  /// Non-formula cells are read from `sheet` and refreshed in the cache.
  /// Returns nil when the cell holds a formula and the caller should use the cache.
  private func literalOnSheet(at address: CellAddress, sheet: Sheet) -> CellValue? {
    let raw = sheet.cell(at: address).raw
    guard !FormulaSyntax.isFormula(raw) else { return nil }
    let value = literalOrEmpty(raw)
    valueCache[address] = value
    return value
  }

  private func recalculateAll(sheet: Sheet) {
    recalculate(addresses: Set(formulaAST.keys), sheet: sheet)
  }

  private func recalculate(addresses: Set<CellAddress>, sheet: Sheet) {
    let order = topologicalOrder(of: addresses)
    var visiting: Set<CellAddress> = []
    var visited: Set<CellAddress> = []

    func eval(_ address: CellAddress) {
      if visited.contains(address) { return }
      if visiting.contains(address) {
        valueCache[address] = .error(.cycle)
        visited.insert(address)
        return
      }
      visiting.insert(address)
      defer {
        visiting.remove(address)
        visited.insert(address)
      }

      guard let expr = formulaAST[address] else {
        if valueCache[address] == nil {
          valueCache[address] = literalOrEmpty(sheet.cell(at: address).raw)
        }
        return
      }

      if let deps = dependencies[address] {
        for dep in deps {
          if formulaAST[dep] != nil {
            eval(dep)
          } else if valueCache[dep] == nil {
            valueCache[dep] = literalOrEmpty(sheet.cell(at: dep).raw)
          }
        }
      }

      var evaluator = FormulaEvaluator { [weak self] ref in
        guard let self else { return .blank }
        return self.resolve(ref, activeSheet: sheet, localEval: eval)
      }
      evaluator.evaluationOrigin = address
      evaluator.namedRangeLookup = { [weak self] name in
        self?.namedRangeExpr(named: name)
      }
      evaluator.sheetExtent = { [weak self] sheetName in
        guard let self else { return (999, 25) }
        return self.extent(for: sheetName ?? self.activeSheetName)
      }
      valueCache[address] = evaluator.evaluate(expr)
    }

    for address in order {
      eval(address)
    }
    for address in addresses where formulaAST[address] != nil && !visited.contains(address) {
      eval(address)
    }
    revision &+= 1
  }

  private func resolve(
    _ ref: FormulaRef,
    activeSheet: Sheet,
    localEval: (CellAddress) -> Void
  ) -> CellValue {
    let sheetName = ref.sheet ?? activeSheetName
    if sheetName.caseInsensitiveCompare(activeSheetName) == .orderedSame {
      let address = ref.address
      if let literal = literalOnSheet(at: address, sheet: activeSheet) {
        return literal
      }
      if formulaAST[address] != nil {
        localEval(address)
      }
      if let cached = valueCache[address] {
        return cached
      }
      let value = literalOrEmpty(activeSheet.cell(at: address).raw)
      valueCache[address] = value
      return value
    }

    return resolveForeign(sheetName: sheetName, address: ref.address)
  }

  private func resolveForeign(sheetName: String, address: CellAddress) -> CellValue {
    guard let sheetIndex = workbook.sheets.firstIndex(where: {
      $0.name.caseInsensitiveCompare(sheetName) == .orderedSame
    }) else {
      return .error(.ref)
    }
    let sheet = workbook.sheets[sheetIndex]
    let key = ForeignKey(sheet: sheet.name, address: address)

    if let cached = foreignCache[key] {
      return cached
    }
    if foreignVisiting.contains(key) {
      return .error(.cycle)
    }

    let raw = sheet.cell(at: address).raw
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard FormulaSyntax.isFormula(trimmed) else {
      let value = literalOrEmpty(trimmed)
      foreignCache[key] = value
      return value
    }

    foreignVisiting.insert(key)
    defer { foreignVisiting.remove(key) }

    do {
      let expr = try FormulaParser.parse(trimmed)
      var evaluator = FormulaEvaluator { [weak self] ref in
        guard let self else { return .blank }
        let targetSheet = ref.sheet ?? sheet.name
        if targetSheet.caseInsensitiveCompare(self.activeSheetName) == .orderedSame {
          let addr = ref.address
          if let cached = self.valueCache[addr] {
            return cached
          }
          return self.literalOrEmpty(self.workbook.activeSheet.cell(at: addr).raw)
        }
        if targetSheet.caseInsensitiveCompare(sheet.name) == .orderedSame {
          return self.resolveForeign(sheetName: sheet.name, address: ref.address)
        }
        return self.resolveForeign(sheetName: targetSheet, address: ref.address)
      }
      evaluator.evaluationOrigin = address
      evaluator.namedRangeLookup = { [weak self] name in
        self?.namedRangeExpr(named: name)
      }
      evaluator.sheetExtent = { [weak self] sheetName in
        guard let self else { return (999, 25) }
        return self.extent(for: sheetName ?? sheet.name)
      }
      let value = evaluator.evaluate(expr)
      foreignCache[key] = value
      return value
    } catch {
      let value = CellValue.error(.error)
      foreignCache[key] = value
      return value
    }
  }

  private func extent(for sheetName: String) -> (maxRow: Int, maxCol: Int) {
    if let sheet = workbook.sheets.first(where: {
      $0.name.caseInsensitiveCompare(sheetName) == .orderedSame
    }) {
      return (sheet.effectiveRowCount - 1, sheet.effectiveColumnCount - 1)
    }
    return (Workbook.defaultRowCount - 1, Workbook.defaultColumnCount - 1)
  }

  private func namedRangeExpr(named name: String) -> FormulaExpr? {
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

  private func topologicalOrder(of addresses: Set<CellAddress>) -> [CellAddress] {
    var indegree: [CellAddress: Int] = [:]
    var graph: [CellAddress: Set<CellAddress>] = [:]
    for address in addresses where formulaAST[address] != nil {
      indegree[address] = 0
    }
    for address in addresses {
      guard let deps = dependencies[address] else { continue }
      for dep in deps where addresses.contains(dep) && formulaAST[dep] != nil {
        graph[dep, default: []].insert(address)
        indegree[address, default: 0] += 1
      }
    }
    var queue = indegree.filter { $0.value == 0 }.map(\.key)
    var order: [CellAddress] = []
    while let next = queue.popLast() {
      order.append(next)
      for kid in graph[next] ?? [] {
        indegree[kid, default: 0] -= 1
        if indegree[kid] == 0 {
          queue.append(kid)
        }
      }
    }
    for address in addresses where formulaAST[address] != nil && !order.contains(address) {
      order.append(address)
    }
    return order
  }
}
