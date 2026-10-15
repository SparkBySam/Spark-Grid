import Foundation

/// General filled-column evaluation: warm range snapshots once, then range-kernel column eval.
enum FormulaColumnEvaluator {
  /// Expand a column strip upward over consecutive ingested rows (e.g. S5 when ingest master is S6).
  static func columnBatchAnchor(
    planMaster: CellAddress,
    members: [CellAddress],
    masterExpr: FormulaExpr,
    formulaAST: [CellAddress: FormulaExpr]
  ) -> (master: CellAddress, members: [CellAddress], expr: FormulaExpr) {
    var master = planMaster
    var expr = masterExpr
    var sorted = members.sorted {
      if $0.row != $1.row { return $0.row < $1.row }
      return $0.col < $1.col
    }
    while let first = sorted.first, first.row > 0 {
      let above = CellAddress(row: first.row - 1, col: master.col)
      guard let aboveExpr = formulaAST[above], !sorted.contains(above) else { break }
      sorted.insert(above, at: 0)
      master = above
      expr = aboveExpr
    }
    return (master, sorted, expr)
  }

  /// One compiled column: pin ranges, run fused range kernels when available, else scalar fill with warm cache.
  @discardableResult
  static func evaluateFilledColumn(
    planMaster: CellAddress,
    members: [CellAddress],
    masterExpr: FormulaExpr,
    formulaAST: [CellAddress: FormulaExpr],
    evaluator: FormulaEvaluator,
    sink: (CellAddress, CellValue) -> Void
  ) -> Bool {
    guard members.count >= 2 else { return false }
    guard members.allSatisfy({ $0.col == planMaster.col }) else { return false }
    let rows = members.map(\.row)
    guard let firstRow = rows.first, let lastRow = rows.last else { return false }
    guard lastRow - firstRow + 1 == members.count, rows == rows.sorted() else { return false }

    let batch = columnBatchAnchor(
      planMaster: planMaster,
      members: members,
      masterExpr: masterExpr,
      formulaAST: formulaAST
    )
    evaluator.warmColumnRangeSnapshots(for: batch.expr, at: batch.master)

    guard evaluator.evaluateColumnShapeStrip(
      master: batch.master,
      members: batch.members,
      masterExpr: batch.expr,
      sink: sink
    ) else {
      return false
    }
    evaluator.recalcProfile?.columnBatchKernelRows += batch.members.count
    return true
  }
}
