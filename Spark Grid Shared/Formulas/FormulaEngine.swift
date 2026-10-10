import Foundation

/// Evaluates formulas on the active sheet, with cross-sheet lookups into the workbook.
final class FormulaEngine {
  private var valueCache: [CellAddress: CellValue] = [:]
  private var formulaAST: [CellAddress: FormulaExpr] = [:]
  private var dependencies: [CellAddress: Set<CellAddress>] = [:] // formula -> local refs
  private var dependencyRanges: [CellAddress: [CellRange]] = [:] // formula -> ranges read at eval
  private var dependents: [CellAddress: Set<CellAddress>] = [:] // cell -> formulas that use it
  private var revision: Int = 0
  private let aggregateRangeCache = FormulaAggregateRangeCache()
  private let lookupTableCache = FormulaLookupTableCache()
  private struct IngestedFormulaTemplate {
    var expr: FormulaExpr
    var deps: Set<CellAddress>
    var ranges: [CellRange]
  }
  private var ingestTemplateCache: [String: IngestedFormulaTemplate] = [:]
  /// Results from `recalculateEntireWorkbook` (and incremental edits), keyed by sheet name.
  private var recalculatedSheetValues: [String: [CellAddress: CellValue]] = [:]

  private var workbook = Workbook.empty
  private var activeSheetName = "Sheet1"
  private var foreignCache: [ForeignKey: CellValue] = [:]
  private var foreignVisiting: Set<ForeignKey> = []

  private struct ForeignKey: Hashable {
    var sheet: String
    var address: CellAddress
  }

  var cacheRevision: Int { revision }
  private(set) var lastWorkbookRecalcProfile: FormulaRecalcProfile?

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
    let raw = sheet.cell(at: address).raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if FormulaSyntax.isFormula(raw), let stored = storedRecalculatedValue(sheetName: sheet.name, at: address) {
      return stored
    }
    if FormulaSyntax.isFormula(raw), let snapshot = sheet.cell(at: address).importedFormulaResult {
      let value = CellValue.fromImportedExcel(snapshot)
      valueCache[address] = value
      return value
    }
    if FormulaSyntax.isFormula(raw) {
      ensureIngested(address: address, raw: raw, sheet: sheet)
    }
    if formulaAST[address] != nil {
      recalculate(addresses: [address], sheet: sheet)
      if let cached = valueCache[address] {
        return cached
      }
    }
    let value = literalOrEmpty(raw)
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
    evaluator.aggregateRangeCache = aggregateRangeCache
    evaluator.lookupTableCache = lookupTableCache
    return evaluator.evaluate(expr)
  }

  /// Re-evaluates every formula on every sheet (does not block open; call explicitly after import).
  @discardableResult
  func recalculateEntireWorkbook(_ workbook: Workbook, profile: Bool = true) -> TimeInterval {
    let start = CFAbsoluteTimeGetCurrent()
    self.workbook = workbook
    let prof = profile ? FormulaRecalcProfile() : nil
    lastWorkbookRecalcProfile = prof
    aggregateRangeCache.profile = prof
    lookupTableCache.profile = prof
    recalculatedSheetValues.removeAll(keepingCapacity: true)
    aggregateRangeCache.invalidateAll()
    lookupTableCache.invalidateAll()
    foreignCache.removeAll(keepingCapacity: true)
    foreignVisiting.removeAll(keepingCapacity: true)
    let ordered = workbookRecalcSheetOrder(workbook)
    let monthSheets = ordered.filter { workbookRecalcSheetRank($0.name) == 1 }
    let useParallelMonths = monthSheets.count >= 2

    for sheet in ordered where workbookRecalcSheetRank(sheet.name) == 0 {
      recalculateWorkbookSheet(sheet, profile: prof, useShapeStrips: true)
    }

    if useParallelMonths {
      let profileLock = NSLock()
      var parallelValues: [String: [CellAddress: CellValue]] = [:]
      DispatchQueue.concurrentPerform(iterations: monthSheets.count) { index in
        let sheet = monthSheets[index]
        let worker = FormulaEngine()
        let localProfile = FormulaRecalcProfile()
        let values = worker.runIsolatedSheetRecalc(
          workbook: workbook,
          sheet: sheet,
          profile: localProfile,
          useShapeStrips: true
        )
        profileLock.lock()
        prof?.mergeFrom(localProfile)
        parallelValues[sheet.name.lowercased()] = values
        profileLock.unlock()
      }
      for (key, values) in parallelValues {
        recalculatedSheetValues[key] = values
      }
    } else {
      for sheet in monthSheets {
        recalculateWorkbookSheet(sheet, profile: prof, useShapeStrips: true)
      }
    }

    for sheet in ordered where workbookRecalcSheetRank(sheet.name) == 2 {
      recalculateWorkbookSheet(sheet, profile: prof, useShapeStrips: true)
    }
    aggregateRangeCache.profile = nil
    lookupTableCache.profile = nil
    revision &+= 1
    return CFAbsoluteTimeGetCurrent() - start
  }

  /// Full rebuild for the workbook's active sheet (also enables cross-sheet lookups).
  /// When `recalculate` is false, formulas evaluate on demand via `displayValue` (faster open / sheet switch).
  func rebuild(workbook: Workbook, recalculate: Bool = false) {
    clearFormulaGraph()
    aggregateRangeCache.invalidateAll()
    lookupTableCache.invalidateAll()
    self.workbook = workbook
    let sheet = workbook.activeSheet
    activeSheetName = sheet.name
    for (address, cell) in sheet.cells where FormulaSyntax.isFormula(cell.raw) {
      if let snapshot = cell.importedFormulaResult {
        valueCache[address] = CellValue.fromImportedExcel(snapshot)
      }
    }
    if recalculate {
      for (address, cell) in sheet.cells where FormulaSyntax.isFormula(cell.raw) {
        ingest(address: address, raw: cell.raw, sheet: sheet, recalculate: false)
      }
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
    for address in addresses {
      aggregateRangeCache.invalidate(sheetName: activeSheetName, address: address)
      lookupTableCache.invalidate(sheetName: activeSheetName, address: address)
    }
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
    mergeRecalculatedValues(for: sheet)
  }

  func clear() {
    clearFormulaGraph()
    aggregateRangeCache.invalidateAll()
    lookupTableCache.invalidateAll()
    ingestTemplateCache.removeAll(keepingCapacity: true)
    recalculatedSheetValues.removeAll(keepingCapacity: true)
    revision &+= 1
  }

  private func sheetKey(_ name: String) -> String {
    name.lowercased()
  }

  private func ingestTemplateKey(sheetName: String, maxRow: Int, maxCol: Int, formula: String) -> String {
    "\(sheetName.lowercased())\u{1e}\(maxRow)\u{1e}\(maxCol)\u{1e}\(formula)"
  }

  private func storedRecalculatedValue(sheetName: String, at address: CellAddress) -> CellValue? {
    recalculatedSheetValues[sheetKey(sheetName)]?[address]
  }

  private func mergeRecalculatedValues(for sheet: Sheet) {
    let key = sheetKey(sheet.name)
    var merged = recalculatedSheetValues[key] ?? [:]
    for (address, cell) in sheet.cells where FormulaSyntax.isFormula(cell.raw) {
      if let value = valueCache[address] {
        merged[address] = value
      }
    }
    if !merged.isEmpty {
      recalculatedSheetValues[key] = merged
    }
  }

  private func clearFormulaGraph() {
    valueCache.removeAll(keepingCapacity: true)
    formulaAST.removeAll(keepingCapacity: true)
    dependencies.removeAll(keepingCapacity: true)
    dependencyRanges.removeAll(keepingCapacity: true)
    dependents.removeAll(keepingCapacity: true)
    foreignCache.removeAll(keepingCapacity: true)
    foreignVisiting.removeAll(keepingCapacity: true)
  }

  // MARK: - Private

  private func ensureIngested(address: CellAddress, raw: String, sheet: Sheet) {
    guard formulaAST[address] == nil else { return }
    ingest(address: address, raw: raw, sheet: sheet, recalculate: false)
  }

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
        let maxRow = sheet.effectiveRowCount - 1
        let maxCol = sheet.effectiveColumnCount - 1
        let templateKey = ingestTemplateKey(
          sheetName: activeSheetName,
          maxRow: maxRow,
          maxCol: maxCol,
          formula: trimmed
        )
        let template: IngestedFormulaTemplate
        if let cached = ingestTemplateCache[templateKey] {
          template = cached
          lastWorkbookRecalcProfile?.ingestTemplateCacheHits += 1
        } else {
          let parseStart = CFAbsoluteTimeGetCurrent()
          let expr = try FormulaParser.parse(trimmed)
          let parseElapsed = CFAbsoluteTimeGetCurrent() - parseStart
          let depStart = CFAbsoluteTimeGetCurrent()
          let collected = FormulaDependencies.collectForIngest(
            from: expr,
            activeSheetName: activeSheetName,
            maxRow: maxRow,
            maxCol: maxCol,
            collectWatchedRanges: true,
            namedRangeLookup: { [weak self] name in
              self?.namedRangeExpr(named: name)
            }
          )
          let depElapsed = CFAbsoluteTimeGetCurrent() - depStart
          lastWorkbookRecalcProfile?.ingestParseSeconds += parseElapsed
          lastWorkbookRecalcProfile?.ingestDependencySeconds += depElapsed
          template = IngestedFormulaTemplate(
            expr: expr,
            deps: collected.deps,
            ranges: collected.ranges
          )
          ingestTemplateCache[templateKey] = template
        }
        formulaAST[address] = template.expr
        dependencies[address] = template.deps
        dependencyRanges[address] = template.ranges
        for dep in template.deps {
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

  private func workbookLiteral(sheet: Sheet, address: CellAddress) -> CellValue? {
    let raw = sheet.cell(at: address).raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !FormulaSyntax.isFormula(raw) else { return nil }
    return literalOrEmpty(raw)
  }

  private func workbookRangeValues(for key: AggregateRangeKey) -> [CellValue] {
    guard let sheet = workbook.sheets.first(where: {
      $0.name.lowercased() == key.sheet
    }) else {
      return []
    }
    let recalculated = recalculatedSheetValues[sheetKey(sheet.name)]
    var values: [CellValue] = []
    values.reserveCapacity((key.maxRow - key.minRow + 1) * (key.maxCol - key.minCol + 1))
    for row in key.minRow...key.maxRow {
      for col in key.minCol...key.maxCol {
        let address = CellAddress(row: row, col: col)
        if let stored = recalculated?[address] {
          values.append(stored)
          continue
        }
        if let stored = storedRecalculatedValue(sheetName: sheet.name, at: address) {
          values.append(stored)
          continue
        }
        let cell = sheet.cell(at: address)
        if let literal = workbookLiteral(sheet: sheet, address: address) {
          values.append(literal)
          continue
        }
        if let imported = cell.importedFormulaResult {
          values.append(CellValue.fromImportedExcel(imported))
          continue
        }
        values.append(literalOrEmpty(cell.raw))
      }
    }
    return values
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

  private struct ShapeStripPlan {
    var master: CellAddress
    var members: [CellAddress]
  }

  private func recalculateWorkbookSheet(
    _ sheet: Sheet,
    profile: FormulaRecalcProfile?,
    useShapeStrips: Bool
  ) {
    activeSheetName = sheet.name
    clearFormulaGraph()
    let ingestStart = CFAbsoluteTimeGetCurrent()
    bulkIngestFormulas(on: sheet, profile: profile)
    profile?.ingestSeconds += CFAbsoluteTimeGetCurrent() - ingestStart
    recalculateAll(sheet: sheet, profile: profile, useShapeStrips: useShapeStrips)
    mergeRecalculatedValues(for: sheet)
  }

  /// One sheet pass for parallel month workers (does not touch caller caches).
  fileprivate func runIsolatedSheetRecalc(
    workbook: Workbook,
    sheet: Sheet,
    profile: FormulaRecalcProfile?,
    useShapeStrips: Bool
  ) -> [CellAddress: CellValue] {
    self.workbook = workbook
    activeSheetName = sheet.name
    clearFormulaGraph()
    let ingestStart = CFAbsoluteTimeGetCurrent()
    bulkIngestFormulas(on: sheet, profile: profile)
    profile?.ingestSeconds += CFAbsoluteTimeGetCurrent() - ingestStart
    recalculateAll(sheet: sheet, profile: profile, useShapeStrips: useShapeStrips)
    var values: [CellAddress: CellValue] = [:]
    for address in formulaAST.keys {
      if let value = valueCache[address] {
        values[address] = value
      }
    }
    return values
  }

  private func buildShapeStripPlans(sheet: Sheet, profile: FormulaRecalcProfile?) -> [ShapeStripPlan] {
    let planStart = CFAbsoluteTimeGetCurrent()
    defer {
      profile?.shapeStripPlanSeconds += CFAbsoluteTimeGetCurrent() - planStart
    }
    var grouped: [String: [CellAddress]] = [:]
    for address in formulaAST.keys {
      guard let expr = formulaAST[address] else { continue }
      let key = FormulaRewriter.shapeAnchorKey(expr: expr, anchor: address)
      grouped[key, default: []].append(address)
    }
    let minimumMembers = 8
    var plans: [ShapeStripPlan] = []
    for (_, members) in grouped where members.count >= minimumMembers {
      guard let master = members.min(by: {
        if $0.row != $1.row { return $0.row < $1.row }
        return $0.col < $1.col
      }) else { continue }
      guard let masterExpr = formulaAST[master] else { continue }
      let matchesFill = members.allSatisfy { addr in
        let rowDelta = addr.row - master.row
        let colDelta = addr.col - master.col
        let expected = FormulaRewriter.adjustedFormulaText(
          expr: masterExpr,
          rowDelta: rowDelta,
          colDelta: colDelta
        )
        let actual = sheet.cell(at: addr).raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return expected == actual
      }
      guard matchesFill else { continue }
      plans.append(ShapeStripPlan(master: master, members: members))
    }
    return plans
  }

  /// Full-sheet ingest after `clearFormulaGraph`: parallel parse/deps, no watched ranges, no stale cleanup.
  private func bulkIngestFormulas(on sheet: Sheet, profile: FormulaRecalcProfile?) {
    let maxRow = sheet.effectiveRowCount - 1
    let maxCol = sheet.effectiveColumnCount - 1
    let sheetName = sheet.name
    var entries: [(CellAddress, String)] = []
    entries.reserveCapacity(sheet.cells.count)
    for (address, cell) in sheet.cells {
      let trimmed = cell.raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard FormulaSyntax.isFormula(trimmed) else { continue }
      entries.append((address, trimmed))
    }
    guard !entries.isEmpty else { return }

    let count = entries.count
    var templates: [IngestedFormulaTemplate?] = Array(repeating: nil, count: count)
    let cacheLock = NSLock()
    let profileLock = NSLock()

    DispatchQueue.concurrentPerform(iterations: count) { index in
      let trimmed = entries[index].1
      let templateKey = ingestTemplateKey(
        sheetName: sheetName,
        maxRow: maxRow,
        maxCol: maxCol,
        formula: trimmed
      )
      cacheLock.lock()
      let cached = ingestTemplateCache[templateKey]
      cacheLock.unlock()
      if let cached {
        templates[index] = cached
        profileLock.lock()
        profile?.ingestTemplateCacheHits += 1
        profileLock.unlock()
        return
      }

      do {
        let parseStart = CFAbsoluteTimeGetCurrent()
        let expr = try FormulaParser.parse(trimmed)
        let parseElapsed = CFAbsoluteTimeGetCurrent() - parseStart
        let depStart = CFAbsoluteTimeGetCurrent()
        let collected = FormulaDependencies.collectForIngest(
          from: expr,
          activeSheetName: sheetName,
          maxRow: maxRow,
          maxCol: maxCol,
          collectWatchedRanges: false,
          namedRangeLookup: { [weak self] name in
            self?.namedRangeExpr(named: name)
          }
        )
        let depElapsed = CFAbsoluteTimeGetCurrent() - depStart
        let template = IngestedFormulaTemplate(
          expr: expr,
          deps: collected.deps,
          ranges: []
        )
        templates[index] = template
        cacheLock.lock()
        ingestTemplateCache[templateKey] = template
        cacheLock.unlock()
        profileLock.lock()
        profile?.ingestParseSeconds += parseElapsed
        profile?.ingestDependencySeconds += depElapsed
        profileLock.unlock()
      } catch {
        templates[index] = nil
      }
    }

    for index in 0..<count {
      let address = entries[index].0
      guard let template = templates[index] else {
        valueCache[address] = .error(.error)
        continue
      }
      formulaAST[address] = template.expr
      dependencies[address] = template.deps
      for dep in template.deps {
        dependents[dep, default: []].insert(address)
      }
      if let snapshot = sheet.cell(at: address).importedFormulaResult {
        valueCache[address] = CellValue.fromImportedExcel(snapshot)
      }
    }
  }

  private func recalculateAll(
    sheet: Sheet,
    profile: FormulaRecalcProfile? = nil,
    useShapeStrips: Bool = false
  ) {
    recalculate(addresses: Set(formulaAST.keys), sheet: sheet, profile: profile, useShapeStrips: useShapeStrips)
  }

  private func recalculate(
    addresses: Set<CellAddress>,
    sheet: Sheet,
    profile: FormulaRecalcProfile? = nil,
    useShapeStrips: Bool = false
  ) {
    aggregateRangeCache.workbookBulkLoader = { [weak self] key in
      self?.workbookRangeValues(for: key) ?? []
    }
    defer { aggregateRangeCache.workbookBulkLoader = nil }
    let order = topologicalOrder(of: addresses)
    var visiting: Set<CellAddress> = []
    var visited: Set<CellAddress> = []
    var evaluator: FormulaEvaluator!
    var stripByMaster: [CellAddress: ShapeStripPlan] = [:]
    var memberToMaster: [CellAddress: CellAddress] = [:]
    var stripExecuted: Set<CellAddress> = []
    if useShapeStrips {
      for plan in buildShapeStripPlans(sheet: sheet, profile: profile) {
        stripByMaster[plan.master] = plan
        for member in plan.members {
          memberToMaster[member] = plan.master
        }
      }
    }

    func evalDependencies(_ address: CellAddress) {
      guard let deps = dependencies[address] else { return }
      for dep in deps {
        if formulaAST[dep] != nil {
          eval(dep)
        } else if valueCache[dep] == nil {
          valueCache[dep] = literalOrEmpty(sheet.cell(at: dep).raw)
        }
      }
    }

    func evalShapeStrip(_ plan: ShapeStripPlan) {
      guard let masterExpr = formulaAST[plan.master] else { return }
      let orderedMembers = plan.members.sorted {
        if $0.row != $1.row { return $0.row < $1.row }
        return $0.col < $1.col
      }
      for address in orderedMembers {
        if visited.contains(address) { continue }
        evalDependencies(address)
        let rowDelta = address.row - plan.master.row
        let colDelta = address.col - plan.master.col
        let expr = FormulaRewriter.adjustExpression(masterExpr, rowDelta: rowDelta, colDelta: colDelta)
        evaluator.prepareForCellEvaluation(origin: address)
        valueCache[address] = evaluator.evaluate(expr)
        visited.insert(address)
      }
    }

    func eval(_ address: CellAddress) {
      if visited.contains(address) { return }
      if let master = memberToMaster[address] {
        if !stripExecuted.contains(master) {
          if let plan = stripByMaster[master] {
            evalShapeStrip(plan)
            stripExecuted.insert(master)
          }
        }
        return
      }
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

      evalDependencies(address)

      evaluator.prepareForCellEvaluation(origin: address)
      valueCache[address] = evaluator.evaluate(expr)
    }

    evaluator = FormulaEvaluator { [weak self] ref in
      guard let self else { return .blank }
      return self.resolve(ref, activeSheet: sheet, localEval: eval)
    }
    evaluator.namedRangeLookup = { [weak self] name in
      self?.namedRangeExpr(named: name)
    }
    evaluator.sheetExtent = { [weak self] sheetName in
      guard let self else { return (999, 25) }
      return self.extent(for: sheetName ?? self.activeSheetName)
    }
    evaluator.aggregateRangeCache = aggregateRangeCache
    evaluator.lookupTableCache = lookupTableCache
    evaluator.recalcProfile = profile

    for address in order {
      eval(address)
    }
    for address in addresses where formulaAST[address] != nil && !visited.contains(address) {
      eval(address)
    }
    revision &+= 1
  }

  /// Config and month data sheets before YTD/summary so cross-sheet COUNTIFS read stored values.
  private func workbookRecalcSheetRank(_ name: String) -> Int {
    let lower = name.lowercased()
    if lower == "config" { return 0 }
    if lower.contains("ytd") || lower.contains("summary") || lower == "dashboard" { return 2 }
    return 1
  }

  private func workbookRecalcSheetOrder(_ workbook: Workbook) -> [Sheet] {
    return workbook.sheets.sorted { lhs, rhs in
      let l = workbookRecalcSheetRank(lhs.name)
      let r = workbookRecalcSheetRank(rhs.name)
      if l != r { return l < r }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
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
    if let stored = storedRecalculatedValue(sheetName: sheet.name, at: address) {
      foreignCache[key] = stored
      return stored
    }
    if let literal = workbookLiteral(sheet: sheet, address: address) {
      foreignCache[key] = literal
      return literal
    }
    let rawForStored = sheet.cell(at: address).raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if FormulaSyntax.isFormula(rawForStored),
       let imported = sheet.cell(at: address).importedFormulaResult {
      let value = CellValue.fromImportedExcel(imported)
      foreignCache[key] = value
      return value
    }
    if foreignVisiting.contains(key) {
      return .error(.cycle)
    }

    let trimmed = sheet.cell(at: address).raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard FormulaSyntax.isFormula(trimmed) else {
      let value = literalOrEmpty(trimmed)
      foreignCache[key] = value
      return value
    }

    foreignVisiting.insert(key)
    defer { foreignVisiting.remove(key) }

    lastWorkbookRecalcProfile?.foreignFormulaEvaluations += 1
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
      evaluator.aggregateRangeCache = aggregateRangeCache
      evaluator.lookupTableCache = lookupTableCache
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
