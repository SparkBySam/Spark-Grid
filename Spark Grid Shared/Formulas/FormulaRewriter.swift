import Foundation

/// Shared catalog of built-in formula function names (uppercase).
enum FormulaFunctions {
  static let all: [String] = [
    "SUM", "AVERAGE", "COUNT", "COUNTA", "MIN", "MAX",
    "IF", "IFERROR", "AND", "OR",
    "ABS", "ROUND",
    "LEN", "LEFT", "RIGHT", "TRIM", "CONCAT", "CONCATENATE", "TEXT",
    "XLOOKUP", "VLOOKUP", "INDEX", "MATCH",
    "TODAY", "DATE", "YEAR", "MONTH", "DAY",
  ].sorted()

  static func suggestions(matching prefix: String) -> [String] {
    let upper = prefix.uppercased()
    guard !upper.isEmpty else { return Array(all.prefix(12)) }
    return all.filter { $0.hasPrefix(upper) }
  }
}

/// Adjusts relative references when filling or copying formulas,
/// and shifts references after insert/delete row/column.
enum FormulaRewriter {
  enum Axis {
    case row
    case column
  }

  enum StructureChange {
    case insert(at: Int, count: Int)
    case delete(at: Int, count: Int)
  }

  /// Returns adjusted formula text (including leading `=`), or the original raw if not a formula / unparseable.
  static func adjust(_ raw: String, rowDelta: Int, colDelta: Int) -> String {
    guard FormulaSyntax.isFormula(raw) else { return raw }
    guard rowDelta != 0 || colDelta != 0 else { return raw }
    do {
      let expr = try FormulaParser.parse(raw)
      let adjusted = adjustExpr(expr, rowDelta: rowDelta, colDelta: colDelta)
      return "=" + serialize(adjusted)
    } catch {
      return raw
    }
  }

  /// Shifts references that point at `mutatedSheet` after insert/delete.
  /// Absolute ($A$1) and relative refs both move — matching Excel structure edits.
  static func shiftForStructure(
    _ raw: String,
    formulaSheetName: String,
    mutatedSheetName: String,
    axis: Axis,
    change: StructureChange
  ) -> String {
    guard FormulaSyntax.isFormula(raw) else { return raw }
    do {
      let expr = try FormulaParser.parse(raw)
      let shifted = shiftExpr(
        expr,
        formulaSheetName: formulaSheetName,
        mutatedSheetName: mutatedSheetName,
        axis: axis,
        change: change
      )
      return "=" + serialize(shifted)
    } catch {
      return raw
    }
  }

  // MARK: - Fill / paste adjust

  private static func adjustExpr(_ expr: FormulaExpr, rowDelta: Int, colDelta: Int) -> FormulaExpr {
    switch expr {
    case .number, .string, .boolean, .error, .namedRange:
      return expr
    case .cellRef(let ref):
      if let next = ref.adjusted(rowDelta: rowDelta, colDelta: colDelta) {
        return .cellRef(next)
      }
      return .error(.ref)
    case .range(let start, let end):
      guard let s = start.adjusted(rowDelta: rowDelta, colDelta: colDelta),
            let e = end.adjusted(rowDelta: rowDelta, colDelta: colDelta)
      else { return .error(.ref) }
      return .range(s, e)
    case .unary(let op, let inner):
      return .unary(op, adjustExpr(inner, rowDelta: rowDelta, colDelta: colDelta))
    case .binary(let op, let lhs, let rhs):
      return .binary(
        op,
        adjustExpr(lhs, rowDelta: rowDelta, colDelta: colDelta),
        adjustExpr(rhs, rowDelta: rowDelta, colDelta: colDelta)
      )
    case .call(let name, let args):
      return .call(name, args.map { adjustExpr($0, rowDelta: rowDelta, colDelta: colDelta) })
    }
  }

  // MARK: - Structure shift

  private static func shiftExpr(
    _ expr: FormulaExpr,
    formulaSheetName: String,
    mutatedSheetName: String,
    axis: Axis,
    change: StructureChange
  ) -> FormulaExpr {
    switch expr {
    case .number, .string, .boolean, .error, .namedRange:
      return expr
    case .cellRef(let ref):
      return shiftRef(
        ref,
        formulaSheetName: formulaSheetName,
        mutatedSheetName: mutatedSheetName,
        axis: axis,
        change: change
      ).map { .cellRef($0) } ?? .error(.ref)
    case .range(let start, let end):
      guard let s = shiftRef(
        start,
        formulaSheetName: formulaSheetName,
        mutatedSheetName: mutatedSheetName,
        axis: axis,
        change: change
      ),
      let e = shiftRef(
        end,
        formulaSheetName: formulaSheetName,
        mutatedSheetName: mutatedSheetName,
        axis: axis,
        change: change
      )
      else { return .error(.ref) }
      return .range(s, e)
    case .unary(let op, let inner):
      return .unary(
        op,
        shiftExpr(
          inner,
          formulaSheetName: formulaSheetName,
          mutatedSheetName: mutatedSheetName,
          axis: axis,
          change: change
        )
      )
    case .binary(let op, let lhs, let rhs):
      return .binary(
        op,
        shiftExpr(
          lhs,
          formulaSheetName: formulaSheetName,
          mutatedSheetName: mutatedSheetName,
          axis: axis,
          change: change
        ),
        shiftExpr(
          rhs,
          formulaSheetName: formulaSheetName,
          mutatedSheetName: mutatedSheetName,
          axis: axis,
          change: change
        )
      )
    case .call(let name, let args):
      return .call(
        name,
        args.map {
          shiftExpr(
            $0,
            formulaSheetName: formulaSheetName,
            mutatedSheetName: mutatedSheetName,
            axis: axis,
            change: change
          )
        }
      )
    }
  }

  private static func shiftRef(
    _ ref: FormulaRef,
    formulaSheetName: String,
    mutatedSheetName: String,
    axis: Axis,
    change: StructureChange
  ) -> FormulaRef? {
    let target = ref.sheet ?? formulaSheetName
    guard target.caseInsensitiveCompare(mutatedSheetName) == .orderedSame else {
      return ref
    }

    switch (axis, change) {
    case (.row, .insert(let index, let count)):
      guard !ref.isRowOpen else { return ref }
      var next = ref
      if next.row >= index { next.row += count }
      return next
    case (.column, .insert(let index, let count)):
      guard !ref.isColOpen else { return ref }
      var next = ref
      if next.col >= index { next.col += count }
      return next
    case (.row, .delete(let index, let count)):
      guard !ref.isRowOpen else { return ref }
      if ref.row >= index && ref.row < index + count { return nil }
      var next = ref
      if next.row >= index + count { next.row -= count }
      return next
    case (.column, .delete(let index, let count)):
      guard !ref.isColOpen else { return ref }
      if ref.col >= index && ref.col < index + count { return nil }
      var next = ref
      if next.col >= index + count { next.col -= count }
      return next
    }
  }

  // MARK: - Serialize

  static func serialize(_ expr: FormulaExpr) -> String {
    switch expr {
    case .number(let n):
      if n.rounded() == n, abs(n) < 1e15 {
        return String(Int(n))
      }
      return String(n)
    case .string(let s):
      let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
      return "\"\(escaped)\""
    case .boolean(let b):
      return b ? "TRUE" : "FALSE"
    case .error(let e):
      return e.displayCode
    case .namedRange(let name):
      return name
    case .cellRef(let ref):
      return A1Reference.format(ref)
    case .range(let start, let end):
      return A1Reference.formatRange(start: start, end: end)
    case .unary(let op, let inner):
      let prefix = op == .negate ? "-" : "+"
      let needsParens = needsParensForUnary(inner)
      let body = serialize(inner)
      return needsParens ? "\(prefix)(\(body))" : "\(prefix)\(body)"
    case .binary(let op, let lhs, let rhs):
      return serializeBinary(op, lhs, rhs)
    case .call(let name, let args):
      let joined = args.map(serialize).joined(separator: ",")
      return "\(name)(\(joined))"
    }
  }

  private static func serializeBinary(_ op: BinaryOp, _ lhs: FormulaExpr, _ rhs: FormulaExpr) -> String {
    let symbol: String
    switch op {
    case .add: symbol = "+"
    case .subtract: symbol = "-"
    case .multiply: symbol = "*"
    case .divide: symbol = "/"
    case .power: symbol = "^"
    case .concat: symbol = "&"
    case .eq: symbol = "="
    case .ne: symbol = "<>"
    case .lt: symbol = "<"
    case .gt: symbol = ">"
    case .le: symbol = "<="
    case .ge: symbol = ">="
    }
    return "\(serialize(lhs))\(symbol)\(serialize(rhs))"
  }

  private static func needsParensForUnary(_ expr: FormulaExpr) -> Bool {
    switch expr {
    case .binary, .unary: return true
    default: return false
    }
  }
}
