import Foundation

/// Phase timings for `recalculateEntireWorkbook` (Bug Bash / diagnostics).
final class FormulaRecalcProfile {
  var ingestSeconds: Double = 0
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
  /// `SUMPRODUCT` boolean-product fast path (masked histogram / column snapshots).
  var sumproductBooleanHits: Int = 0
  /// Boolean-shaped `SUMPRODUCT` that did not use the fast path (parse miss or unsupported shape).
  var sumproductBooleanFallbacks: Int = 0

  func recordEval(function: String, seconds: Double) {
    evalSeconds += seconds
    evalByFunctionSeconds[function, default: 0] += seconds
  }

  func mergeFrom(_ other: FormulaRecalcProfile) {
    ingestSeconds += other.ingestSeconds
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
    sumproductBooleanHits += other.sumproductBooleanHits
    sumproductBooleanFallbacks += other.sumproductBooleanFallbacks
    for (name, seconds) in other.evalByFunctionSeconds {
      evalByFunctionSeconds[name, default: 0] += seconds
    }
  }

  func detailSummary(totalSeconds: Double) -> String {
    let topEval = evalByFunctionSeconds.sorted { $0.value > $1.value }.prefix(4)
      .map { String(format: "%@ %.2fs", $0.key, $0.value) }
      .joined(separator: ", ")
    return String(
      format: "total %.2fs | ingest %.2fs aggIdx %.2fs lookupIdx %.2fs eval %.2fs | COUNTIFS hit %d idxHit %d idxBuild %d scanCells %d foreignEval %d | sumProdBool hit %d fallback %d | ifBlank %d | iferrVlk %d | eval %@",
      totalSeconds,
      ingestSeconds,
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
      topEval.isEmpty ? "—" : topEval
    )
  }
}
