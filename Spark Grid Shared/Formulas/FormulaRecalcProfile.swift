import Foundation

/// Phase timings for `recalculateEntireWorkbook` (Bug Bash / diagnostics).
final class FormulaRecalcProfile {
  var ingestSeconds: Double = 0
  var aggregateIndexBuildSeconds: Double = 0
  var lookupIndexBuildSeconds: Double = 0
  var evalSeconds: Double = 0
  var evalByFunctionSeconds: [String: Double] = [:]
  var countifsHistogramLookups: Int = 0
  var countifsRowScanCells: Int = 0
  var foreignFormulaEvaluations: Int = 0
  /// `SUMPRODUCT` boolean-product fast path (masked histogram / column snapshots).
  var sumproductBooleanHits: Int = 0
  /// Boolean-shaped `SUMPRODUCT` that did not use the fast path (parse miss or unsupported shape).
  var sumproductBooleanFallbacks: Int = 0

  func recordEval(function: String, seconds: Double) {
    evalSeconds += seconds
    evalByFunctionSeconds[function, default: 0] += seconds
  }

  func detailSummary(totalSeconds: Double) -> String {
    let topEval = evalByFunctionSeconds.sorted { $0.value > $1.value }.prefix(4)
      .map { String(format: "%@ %.2fs", $0.key, $0.value) }
      .joined(separator: ", ")
    return String(
      format: "total %.2fs | ingest %.2fs aggIdx %.2fs lookupIdx %.2fs eval %.2fs | COUNTIFS hit %d scanCells %d foreignEval %d | sumProdBool hit %d fallback %d | eval %@",
      totalSeconds,
      ingestSeconds,
      aggregateIndexBuildSeconds,
      lookupIndexBuildSeconds,
      evalSeconds,
      countifsHistogramLookups,
      countifsRowScanCells,
      foreignFormulaEvaluations,
      sumproductBooleanHits,
      sumproductBooleanFallbacks,
      topEval.isEmpty ? "—" : topEval
    )
  }
}
