import Foundation

struct FormulaEvaluator {
  /// Resolves a cell reference (local or cross-sheet).
  typealias ValueLookup = (FormulaRef) -> CellValue
  /// Resolves a named range to a sheet-qualified range expression, if defined.
  typealias NamedRangeLookup = (String) -> FormulaExpr?
  /// Last usable row/col index for open-ended ranges (`A2:A`, `A:A`, `2:2`).
  typealias SheetExtentLookup = (_ sheetName: String?) -> (maxRow: Int, maxCol: Int)

  let lookup: ValueLookup
  var namedRangeLookup: NamedRangeLookup = { _ in nil }
  /// Defaults to a modest grid so open ranges don't explode when extent isn't wired.
  var sheetExtent: SheetExtentLookup = { _ in (maxRow: 999, maxCol: 25) }

  func evaluate(_ expr: FormulaExpr) -> CellValue {
    switch expr {
    case .number(let n):
      return .number(n)
    case .string(let s):
      return .string(s)
    case .boolean(let b):
      return .bool(b)
    case .error(let e):
      return .error(e)
    case .namedRange(let name):
      guard let resolved = namedRangeLookup(name) else { return .error(.name) }
      return evaluate(resolved)
    case .cellRef(let ref):
      return lookup(ref)
    case .range:
      // Bare ranges are multi-valued; scalar context matches Sheets `#VALUE!`.
      return .error(.arrayResult)
    case .unary(let op, let expr):
      return evalUnary(op, expr)
    case .binary(let op, let lhs, let rhs):
      return evalBinary(op, lhs, rhs)
    case .call(let name, let args):
      return evalCall(name, args)
    }
  }

  private func evalUnary(_ op: UnaryOp, _ expr: FormulaExpr) -> CellValue {
    let values = arrayEvaluate(expr)
    if values.count == 1 {
      return applyUnary(op, to: values[0])
    }
    if values.isEmpty { return .blank }
    return .error(.arrayResult)
  }

  private func evalBinary(_ op: BinaryOp, _ lhsExpr: FormulaExpr, _ rhsExpr: FormulaExpr) -> CellValue {
    let values = arrayBinary(op, lhsExpr, rhsExpr)
    if values.count == 1 { return values[0] }
    if values.isEmpty { return .blank }
    // Sheets/Excel: multi-value result in one cell is not silently collapsed.
    return .error(.arrayResult)
  }

  private func applyUnary(_ op: UnaryOp, to value: CellValue) -> CellValue {
    if case .error = value { return value }
    guard let number = value.asNumber else { return .error(.value) }
    switch op {
    case .negate: return .number(-number)
    case .plus: return .number(number)
    }
  }

  private func applyBinary(_ op: BinaryOp, lhs: CellValue, rhs: CellValue) -> CellValue {
    if case .error = lhs { return lhs }
    if case .error = rhs { return rhs }

    switch op {
    case .concat:
      return .string(lhs.asString + rhs.asString)
    case .add, .subtract, .multiply, .divide, .power:
      guard let a = lhs.asNumber, let b = rhs.asNumber else { return .error(.value) }
      switch op {
      case .add: return .number(a + b)
      case .subtract: return .number(a - b)
      case .multiply: return .number(a * b)
      case .divide:
        guard b != 0 else { return .error(.divZero) }
        return .number(a / b)
      case .power: return .number(pow(a, b))
      default: return .error(.value)
      }
    case .eq, .ne, .lt, .gt, .le, .ge:
      return compare(op, lhs, rhs)
    }
  }

  /// Evaluates an expression to one or more values (ranges / broadcast arithmetic).
  private func arrayEvaluate(_ expr: FormulaExpr) -> [CellValue] {
    switch expr {
    case .number, .string, .boolean, .error, .cellRef:
      return [evaluate(expr)]
    case .namedRange(let name):
      guard let resolved = namedRangeLookup(name) else { return [.error(.name)] }
      return arrayEvaluate(resolved)
    case .range(let start, let end):
      return rangeCellValues(start: start, end: end)
    case .unary(let op, let inner):
      return arrayEvaluate(inner).map { applyUnary(op, to: $0) }
    case .binary(let op, let lhs, let rhs):
      return arrayBinary(op, lhs, rhs)
    case .call:
      return [evaluate(expr)]
    }
  }

  private func arrayBinary(_ op: BinaryOp, _ lhsExpr: FormulaExpr, _ rhsExpr: FormulaExpr) -> [CellValue] {
    let lhs = arrayEvaluate(lhsExpr)
    let rhs = arrayEvaluate(rhsExpr)
    if let err = lhs.first(where: \.isError) { return [err] }
    if let err = rhs.first(where: \.isError) { return [err] }

    if lhs.count == 1, rhs.count == 1 {
      return [applyBinary(op, lhs: lhs[0], rhs: rhs[0])]
    }
    // Broadcast scalar × range (and vice versa), e.g. `(A2+A6+A7)*(B3:B5)`.
    if lhs.count == 1 {
      return rhs.map { applyBinary(op, lhs: lhs[0], rhs: $0) }
    }
    if rhs.count == 1 {
      return lhs.map { applyBinary(op, lhs: $0, rhs: rhs[0]) }
    }
    guard lhs.count == rhs.count else { return [.error(.value)] }
    return zip(lhs, rhs).map { applyBinary(op, lhs: $0, rhs: $1) }
  }

  private func rangeCellValues(start: FormulaRef, end: FormulaRef) -> [CellValue] {
    let n = normalizedBounds(start: start, end: end)
    var values: [CellValue] = []
    values.reserveCapacity((n.maxRow - n.minRow + 1) * (n.maxCol - n.minCol + 1))
    for row in n.minRow...n.maxRow {
      for col in n.minCol...n.maxCol {
        var ref = FormulaRef(sheet: start.sheet, row: row, col: col, absRow: false, absCol: false)
        if ref.sheet == nil { ref.sheet = end.sheet }
        values.append(lookup(ref))
      }
    }
    return values
  }

  private func compare(_ op: BinaryOp, _ lhs: CellValue, _ rhs: CellValue) -> CellValue {
    if let a = lhs.asNumber, let b = rhs.asNumber {
      switch op {
      case .eq: return .bool(a == b)
      case .ne: return .bool(a != b)
      case .lt: return .bool(a < b)
      case .gt: return .bool(a > b)
      case .le: return .bool(a <= b)
      case .ge: return .bool(a >= b)
      default: return .error(.value)
      }
    }
    let a = lhs.asString
    let b = rhs.asString
    switch op {
    case .eq: return .bool(a == b)
    case .ne: return .bool(a != b)
    case .lt: return .bool(a < b)
    case .gt: return .bool(a > b)
    case .le: return .bool(a <= b)
    case .ge: return .bool(a >= b)
    default: return .error(.value)
    }
  }

  private func evalCall(_ name: String, _ args: [FormulaExpr]) -> CellValue {
    switch name {
    case "SUM": return aggregate(args, skipNonNumeric: true) { $0 + $1 }
    case "AVERAGE":
      var sum = 0.0
      var count = 0
      for value in flatten(args) {
        if case .error = value { return value }
        if let n = numericForStats(value) {
          sum += n
          count += 1
        }
      }
      guard count > 0 else { return .error(.divZero) }
      return .number(sum / Double(count))
    case "COUNT":
      var count = 0
      for value in flatten(args) {
        if case .error = value { return value }
        if numericForStats(value) != nil { count += 1 }
      }
      return .number(Double(count))
    case "COUNTA":
      var count = 0
      for value in flatten(args) {
        if case .error = value { return value }
        if case .blank = value { continue }
        count += 1
      }
      return .number(Double(count))
    case "MIN": return extreme(args, pickMin: true)
    case "MAX": return extreme(args, pickMin: false)
    case "IF":
      guard args.count >= 2, args.count <= 3 else { return .error(.value) }
      let condition = evaluate(args[0])
      if case .error = condition { return condition }
      guard let flag = condition.asBool else { return .error(.value) }
      if flag {
        return evaluate(args[1])
      }
      if args.count == 3 {
        return evaluate(args[2])
      }
      return .bool(false)
    case "IFERROR":
      guard args.count == 2 else { return .error(.value) }
      let value = evaluate(args[0])
      if case .error = value {
        return evaluate(args[1])
      }
      return value
    case "AND":
      return logicalJoin(args, requireAll: true)
    case "OR":
      return logicalJoin(args, requireAll: false)
    case "ABS":
      guard args.count == 1 else { return .error(.value) }
      let value = evaluate(args[0])
      if case .error = value { return value }
      guard let n = value.asNumber else { return .error(.value) }
      return .number(abs(n))
    case "ROUND":
      guard args.count == 1 || args.count == 2 else { return .error(.value) }
      let value = evaluate(args[0])
      if case .error = value { return value }
      guard let n = value.asNumber else { return .error(.value) }
      var digits = 0.0
      if args.count == 2 {
        let d = evaluate(args[1])
        if case .error = d { return d }
        guard let dn = d.asNumber else { return .error(.value) }
        digits = dn
      }
      let factor = pow(10.0, digits.rounded())
      return .number((n * factor).rounded() / factor)
    case "LEN":
      guard args.count == 1 else { return .error(.value) }
      let value = evaluate(args[0])
      if case .error = value { return value }
      return .number(Double(value.asString.count))
    case "LEFT":
      return substring(args, fromStart: true)
    case "RIGHT":
      return substring(args, fromStart: false)
    case "TRIM":
      guard args.count == 1 else { return .error(.value) }
      let value = evaluate(args[0])
      if case .error = value { return value }
      let collapsed = value.asString
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
      return .string(collapsed)
    case "CONCAT", "CONCATENATE":
      var result = ""
      for value in flatten(args) {
        if case .error = value { return value }
        result += value.asString
      }
      return .string(result)
    case "TEXT":
      return evalTEXT(args)
    case "XLOOKUP":
      return evalXLOOKUP(args)
    case "VLOOKUP":
      return evalVLOOKUP(args)
    case "INDEX":
      return evalINDEX(args)
    case "MATCH":
      return evalMATCH(args)
    case "TODAY":
      guard args.isEmpty else { return .error(.value) }
      return .number(ExcelDate.serial(from: Date()))
    case "DATE":
      return evalDATE(args)
    case "YEAR":
      return evalDatePart(args) { Calendar.current.component(.year, from: $0) }
    case "MONTH":
      return evalDatePart(args) { Calendar.current.component(.month, from: $0) }
    case "DAY":
      return evalDatePart(args) { Calendar.current.component(.day, from: $0) }
    default:
      return .error(.name)
    }
  }

  private func logicalJoin(_ args: [FormulaExpr], requireAll: Bool) -> CellValue {
    guard !args.isEmpty else { return .error(.value) }
    var sawValue = false
    for value in flatten(args) {
      if case .error = value { return value }
      if case .blank = value { continue }
      guard let flag = value.asBool else { return .error(.value) }
      sawValue = true
      if requireAll {
        if !flag { return .bool(false) }
      } else if flag {
        return .bool(true)
      }
    }
    guard sawValue else { return .error(.value) }
    return .bool(requireAll)
  }

  private func evalTEXT(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    let formatValue = evaluate(args[1])
    if case .error = formatValue { return formatValue }
    let pattern = formatValue.asString.uppercased()

    if let number = value.asNumber {
      if pattern.contains("Y") || pattern.contains("M") || pattern.contains("D") {
        guard let date = ExcelDate.date(from: number) else { return .error(.value) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        switch pattern {
        case "YYYY-MM-DD", "YYYY/MM/DD":
          formatter.dateFormat = "yyyy-MM-dd"
        case "M/D/YYYY", "M/D/YY":
          formatter.dateFormat = "M/d/yyyy"
        case "MMMM D, YYYY":
          formatter.dateFormat = "MMMM d, yyyy"
        default:
          formatter.dateFormat = "yyyy-MM-dd"
        }
        return .string(formatter.string(from: date))
      }
      if pattern == "0" { return .string(String(Int(number.rounded()))) }
      if pattern == "0.0" { return .string(String(format: "%.1f", number)) }
      if pattern == "0.00" { return .string(String(format: "%.2f", number)) }
      if pattern == "0%" || pattern == "0.00%" {
        return .string(String(format: "%.0f%%", number * 100))
      }
      return .string(value.displayString)
    }
    return .string(value.asString)
  }

  private func evalINDEX(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 || args.count == 3 else { return .error(.value) }
    guard case .range(let start, let end) = resolveToRange(args[0]) else {
      return .error(.value)
    }
    let rowValue = evaluate(args[1])
    if case .error = rowValue { return rowValue }
    guard let rowNumber = rowValue.asNumber else { return .error(.value) }
    let rowIndex = Int(rowNumber.rounded(.down))

    var colIndex = 1
    if args.count == 3 {
      let colValue = evaluate(args[2])
      if case .error = colValue { return colValue }
      guard let colNumber = colValue.asNumber else { return .error(.value) }
      colIndex = Int(colNumber.rounded(.down))
    }

    let n = normalizedBounds(start: start, end: end)
    let height = n.maxRow - n.minRow + 1
    let width = n.maxCol - n.minCol + 1
    guard rowIndex >= 1, rowIndex <= height, colIndex >= 1, colIndex <= width else {
      return .error(.ref)
    }
    let ref = FormulaRef(
      sheet: start.sheet ?? end.sheet,
      row: n.minRow + rowIndex - 1,
      col: n.minCol + colIndex - 1,
      absRow: false,
      absCol: false
    )
    return lookup(ref)
  }

  private func evalMATCH(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 || args.count == 3 else { return .error(.value) }
    let needle = evaluate(args[0])
    if case .error = needle { return needle }
    guard let values = rangeValues(resolveToRangeExpr(args[1]) ?? args[1]) else {
      return .error(.value)
    }

    var matchType = 1
    if args.count == 3 {
      let typeValue = evaluate(args[2])
      if case .error = typeValue { return typeValue }
      guard let typeNumber = typeValue.asNumber else { return .error(.value) }
      matchType = Int(typeNumber.rounded(.down))
    }

    if matchType == 0 {
      for (index, value) in values.enumerated() {
        if case .error = value { return value }
        if valuesEqual(needle, value) {
          return .number(Double(index + 1))
        }
      }
      return .error(.na)
    }

    // Approximate: largest value ≤ needle (match_type 1) or smallest ≥ needle (-1)
    guard let needleNum = needle.asNumber else { return .error(.na) }
    var best: (index: Int, key: Double)?
    for (index, value) in values.enumerated() {
      if case .error = value { return value }
      guard let key = value.asNumber else { continue }
      if matchType > 0 {
        if key <= needleNum, best == nil || key >= best!.key {
          best = (index, key)
        }
      } else if key >= needleNum, best == nil || key <= best!.key {
        best = (index, key)
      }
    }
    guard let best else { return .error(.na) }
    return .number(Double(best.index + 1))
  }

  private func evalDATE(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 3 else { return .error(.value) }
    let y = evaluate(args[0])
    let m = evaluate(args[1])
    let d = evaluate(args[2])
    if case .error = y { return y }
    if case .error = m { return m }
    if case .error = d { return d }
    guard let year = y.asNumber, let month = m.asNumber, let day = d.asNumber else {
      return .error(.value)
    }
    var components = DateComponents()
    components.year = Int(year.rounded(.down))
    components.month = Int(month.rounded(.down))
    components.day = Int(day.rounded(.down))
    guard let date = Calendar.current.date(from: components) else { return .error(.value) }
    return .number(ExcelDate.serial(from: date))
  }

  private func evalDatePart(_ args: [FormulaExpr], _ part: (Date) -> Int) -> CellValue {
    guard args.count == 1 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    guard let serial = value.asNumber, let date = ExcelDate.date(from: serial) else {
      return .error(.value)
    }
    return .number(Double(part(date)))
  }

  private func resolveToRange(_ expr: FormulaExpr) -> FormulaExpr? {
    switch expr {
    case .range:
      return expr
    case .namedRange(let name):
      return namedRangeLookup(name)
    default:
      return nil
    }
  }

  private func resolveToRangeExpr(_ expr: FormulaExpr) -> FormulaExpr? {
    resolveToRange(expr)
  }

  private func evalXLOOKUP(_ args: [FormulaExpr]) -> CellValue {
    guard args.count >= 3, args.count <= 4 else { return .error(.value) }
    let needle = evaluate(args[0])
    if case .error = needle { return needle }

    let lookupValues = rangeValues(args[1])
    let returnValues = rangeValues(args[2])
    guard let lookupValues, let returnValues else { return .error(.value) }
    guard lookupValues.count == returnValues.count, !lookupValues.isEmpty else {
      return .error(.value)
    }

    for (index, value) in lookupValues.enumerated() {
      if case .error = value { return value }
      if valuesEqual(needle, value) {
        let result = returnValues[index]
        if case .error = result { return result }
        return result
      }
    }

    if args.count == 4 {
      return evaluate(args[3])
    }
    return .error(.na)
  }

  private func evalVLOOKUP(_ args: [FormulaExpr]) -> CellValue {
    guard args.count >= 3, args.count <= 4 else { return .error(.value) }
    let needle = evaluate(args[0])
    if case .error = needle { return needle }

    guard case .range(let start, let end) = resolveToRange(args[1]) else { return .error(.value) }
    let colIndexValue = evaluate(args[2])
    if case .error = colIndexValue { return colIndexValue }
    guard let colIndexNumber = colIndexValue.asNumber else { return .error(.value) }
    let colIndex = Int(colIndexNumber.rounded(.down))

    var exact = false // Excel default: approximate match
    if args.count == 4 {
      let flag = evaluate(args[3])
      if case .error = flag { return flag }
      // FALSE → exact; TRUE/omitted → approximate
      exact = !(flag.asBool ?? true)
    }

    let n = normalizedBounds(start: start, end: end)
    let width = n.maxCol - n.minCol + 1
    guard colIndex >= 1, colIndex <= width else { return .error(.ref) }

    let resultCol = n.minCol + colIndex - 1
    var approximate: (key: Double, value: CellValue)?

    for row in n.minRow...n.maxRow {
      let keyRef = FormulaRef(
        sheet: start.sheet,
        row: row,
        col: n.minCol,
        absRow: false,
        absCol: false
      )
      let key = lookup(keyRef)
      if case .error = key { return key }

      let resultRef = FormulaRef(
        sheet: start.sheet,
        row: row,
        col: resultCol,
        absRow: false,
        absCol: false
      )
      let result = lookup(resultRef)

      if exact {
        if valuesEqual(needle, key) {
          return result
        }
      } else {
        guard let needleNum = needle.asNumber, let keyNum = key.asNumber else { continue }
        if keyNum <= needleNum {
          if approximate == nil || keyNum >= approximate!.key {
            approximate = (keyNum, result)
          }
        }
      }
    }

    if exact {
      return .error(.na)
    }
    return approximate?.value ?? .error(.na)
  }

  private func valuesEqual(_ lhs: CellValue, _ rhs: CellValue) -> Bool {
    if let a = lhs.asNumber, let b = rhs.asNumber {
      return a == b
    }
    return lhs.asString.caseInsensitiveCompare(rhs.asString) == .orderedSame
  }

  private func rangeValues(_ expr: FormulaExpr) -> [CellValue]? {
    let resolved: FormulaExpr
    if case .namedRange(let name) = expr, let rangeExpr = namedRangeLookup(name) {
      resolved = rangeExpr
    } else {
      resolved = expr
    }
    switch resolved {
    case .range(let start, let end):
      let n = normalizedBounds(start: start, end: end)
      var values: [CellValue] = []
      for row in n.minRow...n.maxRow {
        for col in n.minCol...n.maxCol {
          var ref = FormulaRef(sheet: start.sheet, row: row, col: col, absRow: false, absCol: false)
          if ref.sheet == nil { ref.sheet = end.sheet }
          values.append(lookup(ref))
        }
      }
      return values
    default:
      return [evaluate(resolved)]
    }
  }

  private func normalizedBounds(start: FormulaRef, end: FormulaRef) -> (
    minRow: Int, maxRow: Int, minCol: Int, maxCol: Int
  ) {
    let sheet = start.sheet ?? end.sheet
    let extent = sheetExtent(sheet)
    return A1Reference.resolvedBounds(
      start: start,
      end: end,
      maxRow: extent.maxRow,
      maxCol: extent.maxCol
    )
  }

  private func substring(_ args: [FormulaExpr], fromStart: Bool) -> CellValue {
    guard args.count == 1 || args.count == 2 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    var count = 1.0
    if args.count == 2 {
      let c = evaluate(args[1])
      if case .error = c { return c }
      guard let cn = c.asNumber else { return .error(.value) }
      count = cn
    }
    let n = max(0, Int(count.rounded(.down)))
    let chars = Array(value.asString)
    if fromStart {
      return .string(String(chars.prefix(n)))
    }
    return .string(String(chars.suffix(n)))
  }

  private func extreme(_ args: [FormulaExpr], pickMin: Bool) -> CellValue {
    var current: Double?
    for value in flatten(args) {
      if case .error = value { return value }
      guard let n = numericForStats(value) else { continue }
      if let c = current {
        current = pickMin ? min(c, n) : max(c, n)
      } else {
        current = n
      }
    }
    guard let current else { return .error(.value) }
    return .number(current)
  }

  private func aggregate(
    _ args: [FormulaExpr],
    skipNonNumeric: Bool,
    combine: (Double, Double) -> Double
  ) -> CellValue {
    var total = 0.0
    var saw = false
    for value in flatten(args) {
      if case .error = value { return value }
      if let n = value.asNumber {
        total = saw ? combine(total, n) : n
        saw = true
      } else if !skipNonNumeric {
        return .error(.value)
      }
    }
    return .number(total)
  }

  private func numericForStats(_ value: CellValue) -> Double? {
    switch value {
    case .number(let n): return n
    case .bool(let b): return b ? 1 : 0
    case .blank, .string, .error: return nil
    }
  }

  private func flatten(_ args: [FormulaExpr]) -> [CellValue] {
    var values: [CellValue] = []
    for arg in args {
      let resolved: FormulaExpr
      if case .namedRange(let name) = arg, let rangeExpr = namedRangeLookup(name) {
        resolved = rangeExpr
      } else {
        resolved = arg
      }
      // Expands ranges and broadcast arithmetic like `(A2+A6+A7)*(B3:B5)`.
      values.append(contentsOf: arrayEvaluate(resolved))
    }
    return values
  }
}

enum FormulaDependencies {
  /// Local (same-sheet) dependencies for the active sheet's dependency graph.
  static func collect(
    from expr: FormulaExpr,
    activeSheetName: String,
    maxRow: Int,
    maxCol: Int,
    namedRangeLookup: (String) -> FormulaExpr? = { _ in nil }
  ) -> Set<CellAddress> {
    var deps: Set<CellAddress> = []
    collect(
      expr,
      activeSheetName: activeSheetName,
      maxRow: maxRow,
      maxCol: maxCol,
      namedRangeLookup: namedRangeLookup,
      into: &deps
    )
    return deps
  }

  private static func collect(
    _ expr: FormulaExpr,
    activeSheetName: String,
    maxRow: Int,
    maxCol: Int,
    namedRangeLookup: (String) -> FormulaExpr?,
    into deps: inout Set<CellAddress>
  ) {
    switch expr {
    case .number, .string, .boolean, .error:
      break
    case .namedRange(let name):
      if let resolved = namedRangeLookup(name) {
        collect(
          resolved,
          activeSheetName: activeSheetName,
          maxRow: maxRow,
          maxCol: maxCol,
          namedRangeLookup: namedRangeLookup,
          into: &deps
        )
      }
    case .cellRef(let ref):
      if ref.isOnSheet(activeSheetName), !ref.isRowOpen, !ref.isColOpen {
        deps.insert(ref.address)
      }
    case .range(let start, let end):
      if start.isOnSheet(activeSheetName) {
        let n = A1Reference.resolvedBounds(
          start: start,
          end: end,
          maxRow: maxRow,
          maxCol: maxCol
        )
        for row in n.minRow...n.maxRow {
          for col in n.minCol...n.maxCol {
            deps.insert(CellAddress(row: row, col: col))
          }
        }
      }
    case .unary(_, let expr):
      collect(
        expr,
        activeSheetName: activeSheetName,
        maxRow: maxRow,
        maxCol: maxCol,
        namedRangeLookup: namedRangeLookup,
        into: &deps
      )
    case .binary(_, let lhs, let rhs):
      collect(
        lhs,
        activeSheetName: activeSheetName,
        maxRow: maxRow,
        maxCol: maxCol,
        namedRangeLookup: namedRangeLookup,
        into: &deps
      )
      collect(
        rhs,
        activeSheetName: activeSheetName,
        maxRow: maxRow,
        maxCol: maxCol,
        namedRangeLookup: namedRangeLookup,
        into: &deps
      )
    case .call(_, let args):
      for arg in args {
        collect(
          arg,
          activeSheetName: activeSheetName,
          maxRow: maxRow,
          maxCol: maxCol,
          namedRangeLookup: namedRangeLookup,
          into: &deps
        )
      }
    }
  }
}
