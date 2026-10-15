import Foundation
import GridCore
import NumberFormat
import Formula
import Functions
import Model

/// Evaluates formulas on the active sheet, with cross-sheet lookups into the workbook.
public final class FormulaEngine {
  public init() {}

  private var valueCache: [CellAddress: CellValue] = [:]
  /// Computed values for sheets other than the one currently in `valueCache`.
  /// `activateSheet` swaps this with the working cache so a tab switch does not
  /// throw away results that were already calculated.
  private var valuesBySheet: [String: [CellAddress: CellValue]] = [:]
  private var formulaAST: [CellAddress: FormulaExpr] = [:]
  private var dependencies: [CellAddress: Set<CellAddress>] = [:] // formula -> local refs
  private var dependencyRanges: [CellAddress: [CellRange]] = [:] // formula -> ranges read at eval
  private var dependents: [CellAddress: Set<CellAddress>] = [:] // cell -> formulas that use it
  private var revision: Int = 0
  private let aggregateRangeCache = FormulaAggregateRangeCache()
  private let lookupTableCache = FormulaLookupTableCache()
  private struct IngestedFormulaTemplate {
    public var expr: FormulaExpr
    public var deps: Set<CellAddress>
    public var ranges: [CellRange]
  }
  private var ingestTemplateCache: [String: IngestedFormulaTemplate] = [:]
  /// Fill-shape keys recorded during bulk ingest (avoids re-serializing at shape-plan time).
  private var sheetShapeAnchorKeys: [CellAddress: String] = [:]
  /// Column fill strips verified during bulk ingest (`master`-relative adjust, not origin shift).
  private var ingestShapeStripPlans: [ShapeStripPlan] = []
  /// Results from `recalculateEntireWorkbook` (and incremental edits), keyed by sheet name.
  private var recalculatedSheetValues: [String: [CellAddress: CellValue]] = [:]
  /// Whole-workbook precedents. Built off the main thread; sheet switches do not rebuild it.
  private var dependencyGraph: WorkbookDependencyGraph?
  private var dependencyGraphToken: UInt64 = 0
  /// Cross-sheet results scheduled after the viewed sheet's own dependents.
  public var onExternalValues: (() -> Void)?
  private var crossSheetToken: UInt64 = 0
  private var crossSheetPublishedToken: UInt64 = 0
  private var crossSheetHasResults = false
  private var crossSheetReadySheets: Set<String> = []
  private var pendingCrossSheet: CrossSheetBackground.Request?
  /// Token of a sheet-switch calculation already running off the current frame.
  private var crossSheetSheetFinishToken: [String: UInt64] = [:]

  private var workbook = Workbook.empty
  private var activeSheetName = "Sheet1"
  private var foreignCache: [ForeignKey: CellValue] = [:]
  private var foreignVisiting: Set<ForeignKey> = []

  private struct ForeignKey: Hashable {
    public var sheet: String
    public var address: CellAddress
  }

  public var cacheRevision: Int { revision }
  public private(set) var lastWorkbookRecalcProfile: FormulaRecalcProfile?

  public func displayValue(at address: CellAddress, sheet: Sheet) -> CellValue {
    // Literals always come from the sheet being painted. The working cache holds
    // only the active sheet; other sheets live in `valuesBySheet` until activated.
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
    if FormulaSyntax.isFormula(raw), let value = sheet.cell(at: address).cachedFormulaValue {
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

  /// Value drawn on the sheet. A calculated result or imported cache is shown.
  /// The formula source is not: that text belongs in the formula bar.
  /// A reference can also surface another cell's formula source when that
  /// precedent has not been calculated yet. The sheet calculates it.
  /// `displayValue` is left as the answer-check path.
  public func sheetDisplayValue(at address: CellAddress, sheet: Sheet, cell: Cell? = nil) -> CellValue {
    let value = displayValue(at: address, sheet: sheet)
    guard case .string(let text) = value else { return value }
    let resolved = cell ?? sheet.cell(at: address)
    let formula = resolved.raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let shown = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard FormulaSyntax.isFormula(formula) else { return value }
    if shown == formula {
      if let imported = resolved.cachedFormulaValue {
        return imported
      }
      // A parsed formula may evaluate to its own source text. The unparsed
      // fallback stores that source and would otherwise paint it.
      if formulaAST[address] != nil {
        return value
      }
      return .blank
    }
    // Labels and blanks stay put. Another cell's formula source (`=SUM(...)`)
    // is calculated here; `displayValue` itself stays the answer-check path.
    guard shown.hasPrefix("=") else { return value }
    guard precedentFormulasNeedIngest(at: address, sheet: sheet) else { return value }
    return valueAfterIngestingPrecedents(at: address, sheet: sheet, cell: resolved)
  }

  /// True when a same-sheet precedent is a formula that was never parsed, so a
  /// lookup would return its source text instead of a calculated value.
  private func precedentFormulasNeedIngest(at address: CellAddress, sheet: Sheet) -> Bool {
    guard let deps = dependencies[address] else { return false }
    for dep in deps {
      if formulaAST[dep] != nil { continue }
      let raw = sheet.cell(at: dep).raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if FormulaSyntax.isFormula(raw) { return true }
    }
    return false
  }

  /// Parse uncalculated formula precedents, then evaluate this cell again.
  /// This stays off `recalculate`'s eval loop so cached sheets paint as before.
  private func valueAfterIngestingPrecedents(at address: CellAddress, sheet: Sheet, cell: Cell) -> CellValue {
    // The first pass stored the precedent's formula text. Drop it and calculate.
    valueCache.removeValue(forKey: address)
    let value = calculateWithPrecedents(at: address, sheet: sheet)
    if Self.isFormulaText(value), formulaTextMatchesStoredFormula(value, sheet: sheet, address: address) {
      if let imported = cell.cachedFormulaValue {
        valueCache[address] = imported
        return imported
      }
      valueCache[address] = .blank
      return .blank
    }
    return value
  }

  /// Evaluates `address`, calculating same-sheet formula precedents first.
  /// Range arguments are not cell dependencies, so formula cells inside those
  /// ranges are calculated before the formula itself runs.
  private func calculateWithPrecedents(at address: CellAddress, sheet: Sheet) -> CellValue {
    if let literal = literalOnSheet(at: address, sheet: sheet) {
      return literal
    }
    if let cached = valueCache[address], !Self.isFormulaText(cached) {
      return cached
    }
    let cell = sheet.cell(at: address)
    let raw = cell.raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard FormulaSyntax.isFormula(raw) else {
      let value = literalOrEmpty(raw)
      valueCache[address] = value
      return value
    }
    if !precedentVisiting.insert(address).inserted {
      let value = CellValue.error(.cycle)
      valueCache[address] = value
      return value
    }
    defer { precedentVisiting.remove(address) }

    valueCache.removeValue(forKey: address)
    ensureIngested(address: address, raw: raw, sheet: sheet)
    guard let expr = formulaAST[address] else {
      let value = unresolvedValue(cell)
      valueCache[address] = value
      return value
    }
    if let deps = dependencies[address] {
      for dep in deps {
        _ = calculateWithPrecedents(at: dep, sheet: sheet)
      }
    }
    if let ranges = dependencyRanges[address] {
      calculateFormulaCells(in: ranges, sheet: sheet)
    }
    var evaluator = FormulaEvaluator { [weak self] ref in
      guard let self else { return .blank }
      return self.resolve(ref, activeSheet: sheet, localEval: { _ in })
    }
    evaluator.evaluationOrigin = address
    evaluator.prepareForCellEvaluation(origin: address)
    evaluator.namedRangeLookup = { [weak self] name in
      self?.namedRangeExpr(named: name)
    }
    evaluator.sheetExtent = { [weak self] sheetName in
      guard let self else { return (999, 25) }
      return self.extent(for: sheetName ?? self.activeSheetName)
    }
    evaluator.aggregateRangeCache = aggregateRangeCache
    evaluator.lookupTableCache = lookupTableCache
    let value = evaluator.evaluate(expr)
    valueCache[address] = value
    return value
  }

  private var precedentVisiting: Set<CellAddress> = []

  private func calculateFormulaCells(in ranges: [CellRange], sheet: Sheet) {
    for range in ranges {
      let bounds = range.normalized
      let rows = bounds.maxRow - bounds.minRow + 1
      let cols = bounds.maxCol - bounds.minCol + 1
      guard rows > 0, cols > 0 else { continue }
      if rows * cols > 512 {
        for (dep, cell) in sheet.cells {
          guard dep.row >= bounds.minRow, dep.row <= bounds.maxRow,
                dep.col >= bounds.minCol, dep.col <= bounds.maxCol,
                FormulaSyntax.isFormula(cell.raw)
          else { continue }
          _ = calculateWithPrecedents(at: dep, sheet: sheet)
        }
        continue
      }
      for row in bounds.minRow...bounds.maxRow {
        for col in bounds.minCol...bounds.maxCol {
          let dep = CellAddress(row: row, col: col)
          guard FormulaSyntax.isFormula(sheet.cell(at: dep).raw) else { continue }
          _ = calculateWithPrecedents(at: dep, sheet: sheet)
        }
      }
    }
  }

  private func formulaTextMatchesStoredFormula(
    _ value: CellValue,
    sheet: Sheet,
    address: CellAddress
  ) -> Bool {
    guard case .string(let text) = value else { return false }
    let shown = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if sheet.cell(at: address).raw.trimmingCharacters(in: .whitespacesAndNewlines) == shown {
      return true
    }
    guard let deps = dependencies[address] else { return false }
    for dep in deps {
      if sheet.cell(at: dep).raw.trimmingCharacters(in: .whitespacesAndNewlines) == shown {
        return true
      }
    }
    return false
  }

  private static func isFormulaText(_ value: CellValue) -> Bool {
    if case .string(let text) = value {
      return FormulaSyntax.isFormula(text)
    }
    return false
  }

  /// Evaluates a conditional-formatting formula relative to `origin` as if entered at `address`.
  public func evaluateConditionalFormula(
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
  public func recalculateEntireWorkbook(_ workbook: Workbook, profile: Bool = true) -> TimeInterval {
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
  public func rebuild(workbook: Workbook, recalculate: Bool = false) {
    cancelCrossSheetWork()
    valuesBySheet.removeValue(forKey: sheetKey(activeSheetName))
    clearFormulaGraph()
    aggregateRangeCache.invalidateAll()
    lookupTableCache.invalidateAll()
    self.workbook = workbook
    let sheet = workbook.activeSheet
    activeSheetName = sheet.name
    // Imported results are copied when that cell is drawn. Walking the sheet
    // here stalls the frame that opens the file.
    if recalculate {
      for (address, cell) in sheet.cells where FormulaSyntax.isFormula(cell.raw) {
        ingest(address: address, raw: cell.raw, sheet: sheet, recalculate: false)
      }
      recalculateAll(sheet: sheet)
    }
    scheduleWorkbookDependencyGraph()
  }

  /// Convenience when only a single sheet is available (e.g. isolated print of one sheet).
  public func rebuild(sheet: Sheet, recalculate: Bool = true) {
    rebuild(workbook: Workbook(sheets: [sheet], activeSheetIndex: 0), recalculate: recalculate)
  }

  /// Switch the active sheet once. Keeps calculated values for every sheet.
  public func activateSheet(_ workbook: Workbook) {
    let previous = sheetKey(activeSheetName)
    valuesBySheet[previous] = valueCache
    clearFormulaGraph()
    aggregateRangeCache.invalidateAll()
    lookupTableCache.invalidateAll()
    self.workbook = workbook
    let sheet = workbook.activeSheet
    activeSheetName = sheet.name
    valueCache = valuesBySheet[sheetKey(sheet.name)] ?? [:]
    // A later paint reads imported results for the cells on screen.
    finishCrossSheetIfNeeded(for: sheet)
  }

  /// Update after one or more cells change on the active sheet.
  public func cellsDidChange(_ addresses: [CellAddress], sheet: Sheet) {
    guard !addresses.isEmpty else { return }
    // Other sheets may read these cells. Drop their saved results so the next
    // visit calculates again. The active sheet is updated below.
    valuesBySheet.removeAll(keepingCapacity: true)
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
    scheduleCrossSheetUpdate(editedAddresses: addresses, recalculated: seen, sheet: sheet)
  }

  public func clear() {
    cancelCrossSheetWork()
    dependencyGraphToken &+= 1
    dependencyGraph = nil
    clearFormulaGraph()
    valuesBySheet.removeAll(keepingCapacity: true)
    aggregateRangeCache.invalidateAll()
    lookupTableCache.invalidateAll()
    ingestTemplateCache.removeAll(keepingCapacity: true)
    recalculatedSheetValues.removeAll(keepingCapacity: true)
    revision &+= 1
  }

  private func sheetKey(_ name: String) -> String {
    name.lowercased()
  }

  /// Parse every sheet's formulas into one graph. The open frame does not build the input.
  private func scheduleWorkbookDependencyGraph() {
    dependencyGraphToken &+= 1
    dependencyGraph = nil
    let token = dependencyGraphToken
    let source = workbook
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let input = CrossSheetBackground.graphInput(for: source)
      let graph = WorkbookDependencyGraph.build(input)
      Task { @MainActor [weak self] in
        guard let self, self.dependencyGraphToken == token else { return }
        self.dependencyGraph = graph
      }
    }
  }

  /// The viewed sheet is already up to date. Other sheets catch up off the main thread.
  private func scheduleCrossSheetUpdate(
    editedAddresses: [CellAddress],
    recalculated: Set<CellAddress>,
    sheet: Sheet
  ) {
    crossSheetToken &+= 1
    let token = crossSheetToken
    crossSheetHasResults = false
    crossSheetReadySheets.removeAll(keepingCapacity: true)
    let activeKey = sheetKey(sheet.name)
    if recalculatedSheetValues.keys.contains(where: { $0 != activeKey }) {
      recalculatedSheetValues = recalculatedSheetValues.filter { $0.key == activeKey }
    }
    var calculated: [CellAddress: CellValue] = [:]
    calculated.reserveCapacity(recalculated.count)
    for address in recalculated where formulaAST[address] != nil {
      if let value = valueCache[address] {
        calculated[address] = value
      }
    }
    let request = CrossSheetBackground.Request(
      token: token,
      workbook: workbook,
      editedSheetName: sheet.name,
      editedSheet: sheet,
      editedAddresses: editedAddresses,
      calculatedEdits: calculated,
      graph: dependencyGraph,
      onlySheetName: nil
    )
    pendingCrossSheet = request
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let outcome = CrossSheetBackground.compute(request)
      Task { @MainActor [weak self] in
        guard let self, self.crossSheetToken == token else { return }
        self.applyCrossSheetOutcome(outcome)
        self.crossSheetPublishedToken = token
        self.crossSheetHasResults = true
        self.pendingCrossSheet = nil
        self.crossSheetReadySheets.removeAll(keepingCapacity: true)
      }
    }
  }

  /// Show the sheet now. A pending cross-sheet calculation finishes off this frame.
  private func finishCrossSheetIfNeeded(for sheet: Sheet) {
    let key = sheetKey(sheet.name)
    if crossSheetHasResults, crossSheetPublishedToken == crossSheetToken {
      overlayStoredCrossSheetValues(forKey: key)
      return
    }
    if crossSheetReadySheets.contains(key) {
      overlayStoredCrossSheetValues(forKey: key)
      return
    }
    guard var request = pendingCrossSheet, request.token == crossSheetToken else { return }
    if crossSheetSheetFinishToken[key] == request.token { return }
    crossSheetSheetFinishToken[key] = request.token
    request.onlySheetName = sheet.name
    let token = request.token
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let outcome = CrossSheetBackground.compute(request)
      Task { @MainActor [weak self] in
        guard let self else { return }
        guard self.crossSheetSheetFinishToken[key] == token else { return }
        self.crossSheetSheetFinishToken[key] = nil
        guard self.crossSheetToken == token else { return }
        self.applyCrossSheetOutcome(outcome)
        self.crossSheetReadySheets.insert(key)
      }
    }
  }

  private func applyCrossSheetOutcome(_ outcome: CrossSheetBackground.Outcome) {
    let activeKey = sheetKey(activeSheetName)
    var activeChanged = false
    for (key, values) in outcome.valuesBySheet {
      var merged = recalculatedSheetValues[key] ?? [:]
      for (address, value) in values {
        merged[address] = value
      }
      if !merged.isEmpty {
        recalculatedSheetValues[key] = merged
      }
      if key == activeKey {
        for (address, value) in values {
          valueCache[address] = value
        }
        if !values.isEmpty { activeChanged = true }
      }
    }
    if activeChanged {
      revision &+= 1
      onExternalValues?()
    }
  }

  private func overlayStoredCrossSheetValues(forKey key: String) {
    guard let values = recalculatedSheetValues[key] else { return }
    for (address, value) in values {
      valueCache[address] = value
    }
  }

  private func cancelCrossSheetWork() {
    crossSheetToken &+= 1
    crossSheetPublishedToken = crossSheetToken
    crossSheetHasResults = false
    pendingCrossSheet = nil
    crossSheetReadySheets.removeAll(keepingCapacity: true)
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
    sheetShapeAnchorKeys.removeAll(keepingCapacity: true)
    ingestShapeStripPlans.removeAll(keepingCapacity: true)
  }

  private func shiftDependencies(
    _ deps: Set<CellAddress>,
    rowDelta: Int,
    colDelta: Int
  ) -> Set<CellAddress> {
    guard rowDelta != 0 || colDelta != 0 else { return deps }
    return Set(deps.map { CellAddress(row: $0.row + rowDelta, col: $0.col + colDelta) })
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
        if let value = sheet.cell(at: address).cachedFormulaValue {
          valueCache[address] = value
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

  /// Imported cache when a formula has one. Otherwise the same literal the
  /// formula source used to become, so cells with no cache still calculate
  /// the way they did.
  private func unresolvedValue(_ cell: Cell) -> CellValue {
    if FormulaSyntax.isFormula(cell.raw), let imported = cell.cachedFormulaValue {
      return imported
    }
    return literalOrEmpty(cell.raw)
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
        if let imported = cell.cachedFormulaValue {
          values.append(imported)
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
    public var master: CellAddress
    /// Sorted by row then column (ingest time).
    public var members: [CellAddress]
    public var isColumnStrip: Bool
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
    let ingestWall = CFAbsoluteTimeGetCurrent() - ingestStart
    profile?.ingestSeconds += ingestWall
    if let profile {
      profile.ingestBulkSheetWallPeakSeconds = max(profile.ingestBulkSheetWallPeakSeconds, ingestWall)
    }
    let aggIdxBefore = profile?.aggregateIndexBuildSeconds ?? 0
    let evalStart = CFAbsoluteTimeGetCurrent()
    recalculateAll(sheet: sheet, profile: profile, useShapeStrips: useShapeStrips)
    let evalWall = CFAbsoluteTimeGetCurrent() - evalStart
    let aggIdxCPU = (profile?.aggregateIndexBuildSeconds ?? 0) - aggIdxBefore
    profile?.recordSheetPhaseWalls(
      name: sheet.name,
      ingestWall: ingestWall,
      evalWall: evalWall,
      aggIdxCPU: aggIdxCPU
    )
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
    let ingestWall = CFAbsoluteTimeGetCurrent() - ingestStart
    profile?.ingestSeconds += ingestWall
    if let profile {
      profile.ingestBulkSheetWallPeakSeconds = max(profile.ingestBulkSheetWallPeakSeconds, ingestWall)
    }
    let aggIdxBefore = profile?.aggregateIndexBuildSeconds ?? 0
    let evalStart = CFAbsoluteTimeGetCurrent()
    recalculateAll(sheet: sheet, profile: profile, useShapeStrips: useShapeStrips)
    let evalWall = CFAbsoluteTimeGetCurrent() - evalStart
    let aggIdxCPU = (profile?.aggregateIndexBuildSeconds ?? 0) - aggIdxBefore
    profile?.recordSheetPhaseWalls(
      name: sheet.name,
      ingestWall: ingestWall,
      evalWall: evalWall,
      aggIdxCPU: aggIdxCPU
    )
    var values: [CellAddress: CellValue] = [:]
    for address in formulaAST.keys {
      if let value = valueCache[address] {
        values[address] = value
      }
    }
    return values
  }

  /// KPI YTD `IFERROR(Σ SUMPRODUCT…)` row ribbon (R–Y); must not steal column strips from S onward.
  private static let ytdSumproductRibbonFirstCol = 18

  private func buildShapeStripPlans(sheet: Sheet, profile: FormulaRecalcProfile?) -> [ShapeStripPlan] {
    let planStart = CFAbsoluteTimeGetCurrent()
    defer {
      profile?.shapeStripPlanSeconds += CFAbsoluteTimeGetCurrent() - planStart
    }
    var plans = ingestShapeStripPlans
    let ingestMembers = Set(plans.flatMap(\.members))
    plans.append(contentsOf: groupedShapeStripPlans(excludingMembers: ingestMembers))
    return plans
  }

  private func groupedShapeStripPlans(excludingMembers: Set<CellAddress>) -> [ShapeStripPlan] {
    var grouped: [String: [CellAddress]] = [:]
    for address in formulaAST.keys {
      let key = sheetShapeAnchorKeys[address]
        ?? {
          guard let expr = formulaAST[address] else { return "" }
          return FormulaRewriter.shapeAnchorKey(expr: expr, anchor: address)
        }()
      guard !key.isEmpty else { continue }
      grouped[key, default: []].append(address)
    }
    let minimumMembers = 8
    var plans: [ShapeStripPlan] = []
    for (_, members) in grouped where members.count >= minimumMembers {
      guard membersFormFillStrip(members) else { continue }
      // Column strips own S–Y; horizontal R5 ribbon only hijacks memberToMaster (see stripByMaster[S5] miss).
      if isYtdSumproductRowRibbon(members) { continue }
      guard let master = members.min(by: {
        if $0.row != $1.row { return $0.row < $1.row }
        return $0.col < $1.col
      }) else { continue }
      guard formulaAST[master] != nil else { continue }
      let sorted = members.sorted {
        if $0.row != $1.row { return $0.row < $1.row }
        return $0.col < $1.col
      }
      let columnStrip = Set(sorted.map(\.col)).count == 1 && sorted.allSatisfy { $0.col == master.col }
      plans.append(ShapeStripPlan(master: master, members: sorted, isColumnStrip: columnStrip))
    }
    return plans
  }

  private func isYtdSumproductRowRibbon(_ members: [CellAddress]) -> Bool {
    guard members.count >= 8 else { return false }
    let rows = Set(members.map(\.row))
    guard rows.count == 1 else { return false }
    let cols = members.map(\.col).sorted()
    guard cols.count == 8, cols.first == 17, cols.last == 24 else { return false }
    return zip(cols, 17...24).allSatisfy { $0.0 == $0.1 }
  }

  /// True when `members` share one row or one column and cover consecutive indices (Excel fill strip).
  private func membersFormFillStrip(_ members: [CellAddress]) -> Bool {
    guard members.count >= 8 else { return false }
    let cols = Set(members.map(\.col))
    if cols.count == 1 {
      let rows = members.map(\.row).sorted()
      guard let first = rows.first, let last = rows.last else { return false }
      return last - first + 1 == members.count
    }
    let rows = Set(members.map(\.row))
    if rows.count == 1 {
      let cols = members.map(\.col).sorted()
      guard let first = cols.first, let last = cols.last else { return false }
      return last - first + 1 == members.count
    }
    return false
  }

  /// Full-sheet ingest after `clearFormulaGraph`: parallel parse/deps, no watched ranges, no stale cleanup.
  private func bulkIngestFormulas(on sheet: Sheet, profile: FormulaRecalcProfile?) {
    let maxRow = sheet.effectiveRowCount - 1
    let maxCol = sheet.effectiveColumnCount - 1
    let sheetName = sheet.name
    sheetShapeAnchorKeys.removeAll(keepingCapacity: true)
    ingestShapeStripPlans.removeAll(keepingCapacity: true)
    let entryScanStart = CFAbsoluteTimeGetCurrent()
    let columnBuckets = sheet.formulaIngestByColumn
    guard !columnBuckets.isEmpty else { return }
    profile?.ingestEntryScanSeconds += CFAbsoluteTimeGetCurrent() - entryScanStart

    let columnIndices = Array(columnBuckets.keys)
    var columnOutputs: [ColumnIngestOutput?] = Array(repeating: nil, count: columnIndices.count)
    let cacheLock = NSLock()
    let metricsLock = NSLock()
    let stripLock = NSLock()

    let columnParallelWallStart = CFAbsoluteTimeGetCurrent()
    DispatchQueue.concurrentPerform(iterations: columnIndices.count) { columnIndex in
      var columnMetrics = BulkIngestColumnMetrics()
      let col = columnIndices[columnIndex]
      let columnEntries = columnBuckets[col] ?? []
      var templatesByAddress: [CellAddress: IngestedFormulaTemplate] = [:]
      templatesByAddress.reserveCapacity(columnEntries.count)
      var shapeKeysByAddress: [CellAddress: String] = [:]
      shapeKeysByAddress.reserveCapacity(columnEntries.count)
      var errorAddresses: [CellAddress] = []
      var localStripPlans: [ShapeStripPlan] = []
      var runMaster: CellAddress?
      var runMasterExpr: FormulaExpr?
      var runMasterDeps: Set<CellAddress>?
      var runMasterShapeKey: String?
      var runMembers: [CellAddress] = []
      var lastRow: Int?

      func flushRun() {
        if let master = runMaster, membersFormFillStrip(runMembers) {
          let sorted = runMembers.sorted {
            if $0.row != $1.row { return $0.row < $1.row }
            return $0.col < $1.col
          }
          let columnStrip = Set(sorted.map(\.col)).count == 1 && sorted.allSatisfy { $0.col == master.col }
          localStripPlans.append(ShapeStripPlan(master: master, members: sorted, isColumnStrip: columnStrip))
        }
        runMaster = nil
        runMasterExpr = nil
        runMasterDeps = nil
        runMasterShapeKey = nil
        runMembers = []
      }

      for (address, trimmed) in columnEntries {
        var resolved: BulkIngestMasterParse?

        if let master = runMaster,
           let masterExpr = runMasterExpr,
           let masterDeps = runMasterDeps,
           let previousRow = lastRow,
           address.row == previousRow + 1 {
          let rowDelta = address.row - master.row
          let colDelta = address.col - master.col
          let verifyStart = CFAbsoluteTimeGetCurrent()
          let expected = FormulaRewriter.adjustedFormulaText(
            expr: masterExpr,
            rowDelta: rowDelta,
            colDelta: colDelta
          )
          columnMetrics.fillVerifySeconds += CFAbsoluteTimeGetCurrent() - verifyStart
          if expected == trimmed {
            let adjustStart = CFAbsoluteTimeGetCurrent()
            let expr = FormulaRewriter.adjustExpression(masterExpr, rowDelta: rowDelta, colDelta: colDelta)
            columnMetrics.fillAdjustSeconds += CFAbsoluteTimeGetCurrent() - adjustStart
            let deps = self.shiftDependencies(masterDeps, rowDelta: rowDelta, colDelta: colDelta)
            let shapeKey: String
            if let cachedShapeKey = runMasterShapeKey {
              shapeKey = cachedShapeKey
            } else {
              let shapeStart = CFAbsoluteTimeGetCurrent()
              shapeKey = FormulaRewriter.shapeAnchorKey(expr: expr, anchor: address)
              columnMetrics.shapeKeySeconds += CFAbsoluteTimeGetCurrent() - shapeStart
            }
            columnMetrics.templateCacheHits += 1
            runMembers.append(address)
            resolved = BulkIngestMasterParse(expr: expr, deps: deps, shapeKey: shapeKey)
            lastRow = address.row
          } else {
            flushRun()
            if let parsed = self.parseBulkIngestMaster(
              trimmed: trimmed,
              address: address,
              sheetName: sheetName,
              maxRow: maxRow,
              maxCol: maxCol,
              cacheLock: cacheLock,
              metrics: &columnMetrics
            ) {
              runMaster = address
              runMasterExpr = parsed.expr
              runMasterDeps = parsed.deps
              runMasterShapeKey = parsed.shapeKey
              runMembers = [address]
              resolved = parsed
              lastRow = address.row
            }
          }
        } else {
          if runMaster != nil {
            flushRun()
          }
          if let parsed = self.parseBulkIngestMaster(
            trimmed: trimmed,
            address: address,
            sheetName: sheetName,
            maxRow: maxRow,
            maxCol: maxCol,
            cacheLock: cacheLock,
            metrics: &columnMetrics
          ) {
            runMaster = address
            runMasterExpr = parsed.expr
            runMasterDeps = parsed.deps
            runMasterShapeKey = parsed.shapeKey
            runMembers = [address]
            resolved = parsed
            lastRow = address.row
          }
        }

        guard let resolved else {
          errorAddresses.append(address)
          lastRow = address.row
          continue
        }
        shapeKeysByAddress[address] = resolved.shapeKey
        templatesByAddress[address] = IngestedFormulaTemplate(
          expr: resolved.expr,
          deps: resolved.deps,
          ranges: []
        )
      }
      flushRun()
      columnOutputs[columnIndex] = ColumnIngestOutput(
        templatesByAddress: templatesByAddress,
        shapeKeysByAddress: shapeKeysByAddress,
        errorAddresses: errorAddresses,
        stripPlans: localStripPlans,
        metrics: columnMetrics
      )
      if !localStripPlans.isEmpty {
        stripLock.lock()
        ingestShapeStripPlans.append(contentsOf: localStripPlans)
        stripLock.unlock()
      }
      metricsLock.lock()
      profile?.ingestParseSeconds += columnMetrics.parseSeconds
      profile?.ingestDependencySeconds += columnMetrics.dependencySeconds
      profile?.ingestFillVerifySeconds += columnMetrics.fillVerifySeconds
      profile?.ingestFillAdjustSeconds += columnMetrics.fillAdjustSeconds
      profile?.ingestShapeKeySeconds += columnMetrics.shapeKeySeconds
      profile?.ingestTemplateCacheHits += columnMetrics.templateCacheHits
      metricsLock.unlock()
    }
    profile?.ingestColumnParallelWallSeconds += CFAbsoluteTimeGetCurrent() - columnParallelWallStart

    let graphStart = CFAbsoluteTimeGetCurrent()
    formulaAST.reserveCapacity(formulaAST.count + sheet.cells.count / 4)
    dependencies.reserveCapacity(dependencies.count + sheet.cells.count / 4)
    for output in columnOutputs {
      guard let output else { continue }
      for address in output.errorAddresses {
        valueCache[address] = .error(.error)
      }
      for (address, template) in output.templatesByAddress {
        formulaAST[address] = template.expr
        dependencies[address] = template.deps
        if let shapeKey = output.shapeKeysByAddress[address] {
          sheetShapeAnchorKeys[address] = shapeKey
        }
        if let value = sheet.cell(at: address).cachedFormulaValue {
          valueCache[address] = value
        }
      }
    }
    dependents.removeAll(keepingCapacity: true)
    for (formula, deps) in dependencies {
      for dep in deps {
        dependents[dep, default: []].insert(formula)
      }
    }
    profile?.ingestGraphBuildSeconds += CFAbsoluteTimeGetCurrent() - graphStart
  }

  private struct ColumnIngestOutput {
    public var templatesByAddress: [CellAddress: IngestedFormulaTemplate]
    public var shapeKeysByAddress: [CellAddress: String]
    public var errorAddresses: [CellAddress]
    public var stripPlans: [ShapeStripPlan]
    public var metrics: BulkIngestColumnMetrics
  }

  private struct BulkIngestColumnMetrics {
    public var parseSeconds: Double = 0
    public var dependencySeconds: Double = 0
    public var fillVerifySeconds: Double = 0
    public var fillAdjustSeconds: Double = 0
    public var shapeKeySeconds: Double = 0
    public var templateCacheHits: Int = 0
  }

  private struct BulkIngestMasterParse {
    public var expr: FormulaExpr
    public var deps: Set<CellAddress>
    public var shapeKey: String
  }

  private func parseBulkIngestMaster(
    trimmed: String,
    address: CellAddress,
    sheetName: String,
    maxRow: Int,
    maxCol: Int,
    cacheLock: NSLock,
    metrics: inout BulkIngestColumnMetrics
  ) -> BulkIngestMasterParse? {
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
      metrics.templateCacheHits += 1
      let shapeStart = CFAbsoluteTimeGetCurrent()
      let shapeKey = FormulaRewriter.shapeAnchorKey(expr: cached.expr, anchor: address)
      metrics.shapeKeySeconds += CFAbsoluteTimeGetCurrent() - shapeStart
      return BulkIngestMasterParse(expr: cached.expr, deps: cached.deps, shapeKey: shapeKey)
    }

    do {
      let parseStart = CFAbsoluteTimeGetCurrent()
      let expr = try FormulaParser.parse(trimmed)
      metrics.parseSeconds += CFAbsoluteTimeGetCurrent() - parseStart
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
      metrics.dependencySeconds += CFAbsoluteTimeGetCurrent() - depStart
      let shapeStart = CFAbsoluteTimeGetCurrent()
      let shapeKey = FormulaRewriter.shapeAnchorKey(expr: expr, anchor: address)
      metrics.shapeKeySeconds += CFAbsoluteTimeGetCurrent() - shapeStart
      let template = IngestedFormulaTemplate(
        expr: expr,
        deps: collected.deps,
        ranges: []
      )
      cacheLock.lock()
      ingestTemplateCache[templateKey] = template
      cacheLock.unlock()
      return BulkIngestMasterParse(expr: expr, deps: collected.deps, shapeKey: shapeKey)
    } catch {
      return nil
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
      let plans = buildShapeStripPlans(sheet: sheet, profile: profile)
      let rowPlans = plans.filter { !$0.isColumnStrip }
      let columnPlans = plans.filter(\.isColumnStrip)
      for plan in rowPlans {
        stripByMaster[plan.master] = plan
        for member in plan.members {
          memberToMaster[member] = plan.master
        }
      }
      for plan in columnPlans {
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
          valueCache[dep] = unresolvedValue(sheet.cell(at: dep))
        }
      }
    }

    func evalShapeStrip(_ plan: ShapeStripPlan) {
      let orderedMembers = plan.members
      let memberSet = Set(orderedMembers)
      for address in orderedMembers {
        guard let deps = dependencies[address] else { continue }
        for dep in deps where !memberSet.contains(dep) {
          eval(dep)
        }
      }

      func evalStripCell(_ address: CellAddress) {
        if visited.contains(address) { return }
        guard let expr = formulaAST[address] else { return }
        evaluator.prepareForCellEvaluation(origin: address)
        valueCache[address] = evaluator.evaluate(expr)
        visited.insert(address)
      }

      func stripSink(_ address: CellAddress, _ value: CellValue) {
        valueCache[address] = value
        visited.insert(address)
      }

      guard let masterExpr = formulaAST[plan.master] else { return }
      #if DEBUG
      if evaluator.recalcProfile != nil {
        let masterRaw = sheet.cell(at: plan.master).raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let masterFormulaText = masterRaw.hasPrefix("=") ? String(masterRaw.dropFirst()) : masterRaw
        evaluator.stripPlanDiagnosticContext = FormulaEvaluator.StripPlanDiagnosticContext(
          sheetName: sheet.name,
          masterFormulaText: masterFormulaText
        )
      }
      defer { evaluator.stripPlanDiagnosticContext = nil }
      #endif

      if plan.isColumnStrip,
         sheet.name.caseInsensitiveCompare("YTD Summary") == .orderedSame,
         plan.master.col >= Self.ytdSumproductRibbonFirstCol,
         let ytdStrip = ytdSumproductColumnStripAnchor(
           plan: plan,
           masterExpr: masterExpr,
           formulaAST: formulaAST,
           evaluator: evaluator
         ),
         evaluator.evaluateColumnYtdSumproductQuotientStrip(
           master: ytdStrip.master,
           members: ytdStrip.members,
           expr: ytdStrip.expr,
           sink: stripSink
         ) {
        return
      }

      if plan.isColumnStrip,
         evaluator.evaluateColumnShapeStrip(
           master: plan.master,
           members: orderedMembers,
           masterExpr: masterExpr,
           sink: stripSink
         ) {
        return
      }
      for address in orderedMembers {
        if visited.contains(address) { continue }
        let rowDelta = address.row - plan.master.row
        let colDelta = address.col - plan.master.col
        let expr = formulaAST[address]
          ?? FormulaRewriter.adjustExpression(masterExpr, rowDelta: rowDelta, colDelta: colDelta)
        evaluator.prepareForCellEvaluation(origin: address)
        valueCache[address] = evaluator.evaluate(expr)
        visited.insert(address)
      }
    }

    func ytdSumproductColumnStripAnchor(
      plan: ShapeStripPlan,
      masterExpr: FormulaExpr,
      formulaAST: [CellAddress: FormulaExpr],
      evaluator: FormulaEvaluator
    ) -> (master: CellAddress, members: [CellAddress], expr: FormulaExpr)? {
      var master = plan.master
      var expr = masterExpr
      var members = plan.members.sorted {
        if $0.row != $1.row { return $0.row < $1.row }
        return $0.col < $1.col
      }
      while master.row > 0 {
        let above = CellAddress(row: master.row - 1, col: master.col)
        guard let aboveExpr = formulaAST[above], !members.contains(above) else { break }
        guard evaluator.canPlanColumnYtdSumproductQuotient(expr: aboveExpr, master: above) else { break }
        members.insert(above, at: 0)
        master = above
        expr = aboveExpr
      }
      guard evaluator.canPlanColumnYtdSumproductQuotient(expr: expr, master: master) else { return nil }
      return (master, members, expr)
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
        if visited.contains(address) { return }
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
          valueCache[address] = unresolvedValue(sheet.cell(at: address))
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
      let value = unresolvedValue(activeSheet.cell(at: address))
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
       let value = sheet.cell(at: address).cachedFormulaValue {
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
