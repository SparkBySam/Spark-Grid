import Foundation

/// Phase timings for `recalculateEntireWorkbook` (Bug Bash / diagnostics).
final class FormulaRecalcProfile {
  var ingestSeconds: Double = 0
  var ingestParseSeconds: Double = 0
  var ingestDependencySeconds: Double = 0
  /// Fill-follower `adjustedFormulaText` vs stored raw (includes serialize).
  var ingestFillVerifySeconds: Double = 0
  /// `adjustExpression` on successful fill followers.
  var ingestFillAdjustSeconds: Double = 0
  /// `shapeAnchorKey` during bulk ingest (parse misses / fallback).
  var ingestShapeKeySeconds: Double = 0
  /// Sum: scan cells + bucket by column (across all sheet ingests).
  var ingestEntryScanSeconds: Double = 0
  /// Sum: wall inside `concurrentPerform` column ingest (overlaps across cores per sheet).
  var ingestColumnParallelWallSeconds: Double = 0
  /// Sum: merge `formulaAST` / `dependencies` / `dependents` after column ingest.
  var ingestGraphBuildSeconds: Double = 0
  /// Max per-sheet `bulkIngestFormulas` wall (serial config + slowest month + serial YTD).
  var ingestBulkSheetWallPeakSeconds: Double = 0
  var ingestTemplateCacheHits: Int = 0
  /// `buildShapeStripPlans` (AST anchor keys + fill validation); runs at eval start, not in `ingestSeconds`.
  var shapeStripPlanSeconds: Double = 0
  var aggregateIndexBuildSeconds: Double = 0
  var lookupIndexBuildSeconds: Double = 0
  var evalSeconds: Double = 0
  var evalByFunctionSeconds: [String: Double] = [:]
  var countifsHistogramLookups: Int = 0
  /// `COUNTIFS` reused a composite histogram built earlier in this recalc (skipped `supplyColumns`).
  var countifsHistogramIndexHits: Int = 0
  /// First `COUNTIFS` for a composite range key in this recalc (built histogram via `supplyColumns`).
  var countifsHistogramIndexBuilds: Int = 0
  var countifsRowScanCells: Int = 0
  var foreignFormulaEvaluations: Int = 0
  /// `IF(Cn="","",…)` KPI guard: skipped heavy false branch on blank rows.
  var ifBlankEqualityFastHits: Int = 0
  /// `IFERROR(VLOOKUP(…),…)` without nested `evalCall` dispatch.
  var iferrorVlookupFastHits: Int = 0
  /// Column strip: exact VLOOKUP table cache hit.
  var ifStripHits: Int = 0
  /// VLOOKUP kernel used IFERROR fallback expr (#N/A), not full branch tree.
  var ifStripVlkNA: Int = 0
  /// Full `evaluate` on IF false branch (kernel plan miss).
  var ifStripBranchTree: Int = 0
  /// Non-blank rows via IF-blank + COUNTIFS column kernel (one snapshot per strip).
  var ifStripCountifsRows: Int = 0
  var ifStripPlanMiss: [String: Int] = [:]

  func recordIfStripPlanMiss(_ reason: String) {
    ifStripPlanMiss[reason, default: 0] += 1
  }
  /// `SUMPRODUCT` boolean-product fast path (masked histogram / column snapshots).
  var sumproductBooleanHits: Int = 0
  /// Boolean-shaped `SUMPRODUCT` that did not use the fast path (parse miss or unsupported shape).
  var sumproductBooleanFallbacks: Int = 0

  struct SheetPhaseWalls: Sendable {
    var name: String
    var ingestWall: Double
    var evalWall: Double
    /// CPU time in aggregate index builds during this sheet's eval (Σ attribution, may overlap).
    var aggIdxCPU: Double
  }

  var sheetPhaseWalls: [SheetPhaseWalls] = []

  func recordSheetPhaseWalls(name: String, ingestWall: Double, evalWall: Double, aggIdxCPU: Double) {
    sheetPhaseWalls.append(
      SheetPhaseWalls(name: name, ingestWall: ingestWall, evalWall: evalWall, aggIdxCPU: aggIdxCPU)
    )
  }

  func recordEval(function: String, seconds: Double) {
    evalSeconds += seconds
    evalByFunctionSeconds[function, default: 0] += seconds
  }

  func mergeFrom(_ other: FormulaRecalcProfile) {
    ingestSeconds += other.ingestSeconds
    ingestParseSeconds += other.ingestParseSeconds
    ingestDependencySeconds += other.ingestDependencySeconds
    ingestFillVerifySeconds += other.ingestFillVerifySeconds
    ingestFillAdjustSeconds += other.ingestFillAdjustSeconds
    ingestShapeKeySeconds += other.ingestShapeKeySeconds
    ingestEntryScanSeconds += other.ingestEntryScanSeconds
    ingestColumnParallelWallSeconds += other.ingestColumnParallelWallSeconds
    ingestGraphBuildSeconds += other.ingestGraphBuildSeconds
    ingestBulkSheetWallPeakSeconds = max(
      ingestBulkSheetWallPeakSeconds,
      other.ingestBulkSheetWallPeakSeconds
    )
    ingestTemplateCacheHits += other.ingestTemplateCacheHits
    shapeStripPlanSeconds += other.shapeStripPlanSeconds
    aggregateIndexBuildSeconds += other.aggregateIndexBuildSeconds
    lookupIndexBuildSeconds += other.lookupIndexBuildSeconds
    evalSeconds += other.evalSeconds
    countifsHistogramLookups += other.countifsHistogramLookups
    countifsHistogramIndexHits += other.countifsHistogramIndexHits
    countifsHistogramIndexBuilds += other.countifsHistogramIndexBuilds
    countifsRowScanCells += other.countifsRowScanCells
    foreignFormulaEvaluations += other.foreignFormulaEvaluations
    ifBlankEqualityFastHits += other.ifBlankEqualityFastHits
    iferrorVlookupFastHits += other.iferrorVlookupFastHits
    ifStripHits += other.ifStripHits
    ifStripVlkNA += other.ifStripVlkNA
    ifStripBranchTree += other.ifStripBranchTree
    ifStripCountifsRows += other.ifStripCountifsRows
    for (reason, count) in other.ifStripPlanMiss {
      ifStripPlanMiss[reason, default: 0] += count
    }
    sumproductBooleanHits += other.sumproductBooleanHits
    sumproductBooleanFallbacks += other.sumproductBooleanFallbacks
    sheetPhaseWalls.append(contentsOf: other.sheetPhaseWalls)
    for (name, seconds) in other.evalByFunctionSeconds {
      evalByFunctionSeconds[name, default: 0] += seconds
    }
  }

  private func ifStripMissSummary() -> String {
    var parts: [String] = []
    if ifStripVlkNA > 0 { parts.append(String(format: "vlkNA %d", ifStripVlkNA)) }
    if ifStripBranchTree > 0 { parts.append(String(format: "branchTree %d", ifStripBranchTree)) }
    if !ifStripPlanMiss.isEmpty {
      let miss = ifStripPlanMiss.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: " ")
      parts.append("planMiss \(miss)")
    }
    guard !parts.isEmpty else { return "" }
    return " | stripFB " + parts.joined(separator: " ")
  }

  private func sheetPhaseWallSummary() -> String {
    guard !sheetPhaseWalls.isEmpty else { return "" }
    let parts = sheetPhaseWalls.map {
      String(
        format: "%@ in%.2f ev%.2f ag%.2f",
        $0.name,
        $0.ingestWall,
        $0.evalWall,
        $0.aggIdxCPU
      )
    }
    return " | sheets " + parts.joined(separator: " ")
  }

  func detailSummary(totalSeconds: Double) -> String {
    let topEval = evalByFunctionSeconds.sorted { $0.value > $1.value }.prefix(4)
      .map { String(format: "%@ %.2fs", $0.key, $0.value) }
      .joined(separator: ", ")
    return String(
      format: "total %.2fs | ingest %.2fs wallPeak %.2fs (parseΣ %.2fs depsΣ %.2fs fillVerifyΣ %.2fs fillAdjustΣ %.2fs shapeKeyΣ %.2fs entryScanΣ %.2fs colWallΣ %.2fs graphΣ %.2fs tmplHit %d) shapePlan %.2fs | aggIdx %.2fs lookupIdx %.2fs eval %.2fs | COUNTIFS hit %d idxHit %d idxBuild %d scanCells %d foreignEval %d | sumProdBool hit %d fallback %d | ifBlank %d | iferrVlk %d | ifStripHit %d cntifsStrip %d | eval %@",
      totalSeconds,
      ingestSeconds,
      ingestBulkSheetWallPeakSeconds,
      ingestParseSeconds,
      ingestDependencySeconds,
      ingestFillVerifySeconds,
      ingestFillAdjustSeconds,
      ingestShapeKeySeconds,
      ingestEntryScanSeconds,
      ingestColumnParallelWallSeconds,
      ingestGraphBuildSeconds,
      ingestTemplateCacheHits,
      shapeStripPlanSeconds,
      aggregateIndexBuildSeconds,
      lookupIndexBuildSeconds,
      evalSeconds,
      countifsHistogramLookups,
      countifsHistogramIndexHits,
      countifsHistogramIndexBuilds,
      countifsRowScanCells,
      foreignFormulaEvaluations,
      sumproductBooleanHits,
      sumproductBooleanFallbacks,
      ifBlankEqualityFastHits,
      iferrorVlookupFastHits,
      ifStripHits,
      ifStripCountifsRows,
      topEval.isEmpty ? "—" : topEval
    ) + ifStripMissSummary() + sheetPhaseWallSummary()
  }
}
