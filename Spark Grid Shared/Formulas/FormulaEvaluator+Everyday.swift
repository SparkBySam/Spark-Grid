import Foundation

extension FormulaEvaluator {
  fileprivate struct ValueMatrix {
    var rows: Int
    var cols: Int
    var values: [CellValue]
  }

  fileprivate struct RangeAnchor {
    var sheet: String?
    var row: Int
    var col: Int
    var rows: Int
    var cols: Int
  }

  fileprivate enum CriteriaOp {
    case eq, ne, lt, le, gt, ge
  }

  fileprivate struct CriteriaTest {
    var op: CriteriaOp
    var number: Double?
    var text: String
    var wildcard: Bool
    var blank: Bool
  }

  func evalSUMIF(_ args: [FormulaExpr]) -> CellValue {
    conditionalAggregate(args, kind: .sum)
  }

  func evalAVERAGEIF(_ args: [FormulaExpr]) -> CellValue {
    conditionalAggregate(args, kind: .average)
  }

  func evalCOUNTIF(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 else { return .error(.value) }
    guard let anchor = rangeAnchor(args[0]) else { return .error(.value) }
    let criterion = evaluate(args[1])
    if case .error = criterion { return criterion }
    let test = criteriaTest(from: criterion)
    var count = 0
    for row in 0..<anchor.rows {
      for col in 0..<anchor.cols {
        let value = lookup(cellRef(anchor, row: row, col: col))
        if case .error(let error) = value { return .error(error) }
        if criteriaMatch(value, test) { count += 1 }
      }
    }
    return .number(Double(count))
  }

  func evalSUMIFS(_ args: [FormulaExpr]) -> CellValue {
    multiCriteriaAggregate(args, kind: .sum)
  }

  func evalAVERAGEIFS(_ args: [FormulaExpr]) -> CellValue {
    multiCriteriaAggregate(args, kind: .average)
  }

  func evalCOUNTIFS(_ args: [FormulaExpr]) -> CellValue {
    guard args.count >= 2, args.count.isMultiple(of: 2) else { return .error(.value) }
    guard let first = rangeAnchor(args[0]) else { return .error(.value) }
    var tests: [(RangeAnchor, CriteriaTest)] = []
    var index = 0
    while index < args.count {
      guard let anchor = rangeAnchor(args[index]) else { return .error(.value) }
      if anchor.rows != first.rows || anchor.cols != first.cols { return .error(.value) }
      let criterion = evaluate(args[index + 1])
      if case .error = criterion { return criterion }
      tests.append((anchor, criteriaTest(from: criterion)))
      index += 2
    }
    var count = 0
    for row in 0..<first.rows {
      for col in 0..<first.cols {
        var matched = true
        for (anchor, test) in tests {
          let value = lookup(cellRef(anchor, row: row, col: col))
          if case .error(let error) = value { return .error(error) }
          if !criteriaMatch(value, test) {
            matched = false
            break
          }
        }
        if matched { count += 1 }
      }
    }
    return .number(Double(count))
  }

  func evalCOUNTBLANK(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 1, let anchor = rangeAnchor(args[0]) else { return .error(.value) }
    var count = 0
    for row in 0..<anchor.rows {
      for col in 0..<anchor.cols {
        let value = lookup(cellRef(anchor, row: row, col: col))
        if isBlankForCount(value) { count += 1 }
      }
    }
    return .number(Double(count))
  }

  func evalSUMPRODUCT(_ args: [FormulaExpr]) -> CellValue {
    guard !args.isEmpty else { return .error(.value) }
    var matrices: [ValueMatrix] = []
    for arg in args {
      guard let matrix = valueMatrix(arg) else { return .error(.value) }
      matrices.append(matrix)
    }
    let rows = matrices[0].rows
    let cols = matrices[0].cols
    guard matrices.allSatisfy({ $0.rows == rows && $0.cols == cols }) else { return .error(.value) }
    var total = 0.0
    let count = rows * cols
    for index in 0..<count {
      var product = 1.0
      for matrix in matrices {
        let value = matrix.values[index]
        if case .error(let error) = value { return .error(error) }
        product *= sumProductCoefficient(value)
      }
      total += product
    }
    return .number(total)
  }

  func evalIFNA(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 2 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error(.na) = value {
      return evaluate(args[1])
    }
    return value
  }

  func evalIFS(_ args: [FormulaExpr]) -> CellValue {
    guard args.count >= 2, args.count.isMultiple(of: 2) else { return .error(.value) }
    var index = 0
    while index < args.count {
      let condition = evaluate(args[index])
      if case .error = condition { return condition }
      guard let flag = condition.asBool else { return .error(.value) }
      if flag { return evaluate(args[index + 1]) }
      index += 2
    }
    return .error(.na)
  }

  func evalNOT(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 1 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    guard let flag = value.asBool else { return .error(.value) }
    return .bool(!flag)
  }

  func evalTextCase(_ args: [FormulaExpr], uppercased: Bool) -> CellValue {
    guard args.count == 1 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    let text = value.asString
    return .string(uppercased ? text.uppercased() : text.lowercased())
  }

  func evalMID(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 3 else { return .error(.value) }
    let text = evaluate(args[0])
    let start = evaluate(args[1])
    let count = evaluate(args[2])
    if case .error = text { return text }
    if case .error = start { return start }
    if case .error = count { return count }
    guard let startNumber = start.asNumber, let countNumber = count.asNumber else { return .error(.value) }
    if startNumber < 1 || countNumber < 0 { return .error(.value) }
    let startIndex = Int(startNumber.rounded(.towardZero))
    let length = Int(countNumber.rounded(.towardZero))
    let chars = Array(text.asString)
    let offset = startIndex - 1
    if offset >= chars.count || length == 0 { return .string("") }
    let end = min(chars.count, offset + length)
    return .string(String(chars[offset..<end]))
  }

  func evalSUBSTITUTE(_ args: [FormulaExpr]) -> CellValue {
    guard args.count == 3 || args.count == 4 else { return .error(.value) }
    let text = evaluate(args[0])
    let old = evaluate(args[1])
    let new = evaluate(args[2])
    if case .error = text { return text }
    if case .error = old { return old }
    if case .error = new { return new }
    let source = text.asString
    let needle = old.asString
    let replacement = new.asString
    if needle.isEmpty { return .string(source) }

    if args.count == 4 {
      let instance = evaluate(args[3])
      if case .error = instance { return instance }
      guard let instanceNumber = instance.asNumber else { return .error(.value) }
      let occurrence = Int(instanceNumber.rounded(.towardZero))
      if occurrence < 1 { return .error(.value) }
      return .string(replaceOccurrence(in: source, needle: needle, with: replacement, occurrence: occurrence))
    }
    return .string(source.replacingOccurrences(of: needle, with: replacement))
  }

  func evalTEXTJOIN(_ args: [FormulaExpr]) -> CellValue {
    guard args.count >= 3 else { return .error(.value) }
    let delimiter = evaluate(args[0])
    if case .error = delimiter { return delimiter }
    let ignore = evaluate(args[1])
    if case .error = ignore { return ignore }
    guard let ignoreEmpty = ignore.asBool else { return .error(.value) }
    var parts: [String] = []
    for value in expandedValues(Array(args.dropFirst(2))) {
      if case .error(let error) = value { return .error(error) }
      if ignoreEmpty && isBlankForCount(value) { continue }
      parts.append(value.asString)
    }
    return .string(parts.joined(separator: delimiter.asString))
  }

  func evalDirectionalRound(_ args: [FormulaExpr], mode: NSDecimalNumber.RoundingMode) -> CellValue {
    guard args.count == 1 || args.count == 2 else { return .error(.value) }
    let value = evaluate(args[0])
    if case .error = value { return value }
    guard let number = value.asNumber else { return .error(.value) }
    var places = 0
    if args.count == 2 {
      let digits = evaluate(args[1])
      if case .error = digits { return digits }
      guard let digitNumber = digits.asNumber else { return .error(.value) }
      places = Int(digitNumber.rounded())
    }
    return .number(excelRound(number, places: places, mode: mode))
  }

  // MARK: - Conditional aggregates

  fileprivate enum AggregateKind {
    case sum
    case average
  }

  private func conditionalAggregate(_ args: [FormulaExpr], kind: AggregateKind) -> CellValue {
    guard args.count == 2 || args.count == 3 else { return .error(.value) }
    guard let criteria = rangeAnchor(args[0]) else { return .error(.value) }
    let criterion = evaluate(args[1])
    if case .error = criterion { return criterion }
    let test = criteriaTest(from: criterion)
    let sumAnchor: RangeAnchor
    if args.count == 3 {
      guard let sum = rangeAnchor(args[2]) else { return .error(.value) }
      sumAnchor = RangeAnchor(sheet: sum.sheet, row: sum.row, col: sum.col, rows: criteria.rows, cols: criteria.cols)
    } else {
      sumAnchor = criteria
    }
    return reduceMatches(criteria: criteria, test: test, values: sumAnchor, kind: kind)
  }

  private func multiCriteriaAggregate(_ args: [FormulaExpr], kind: AggregateKind) -> CellValue {
    guard args.count >= 3, (args.count - 1).isMultiple(of: 2) else { return .error(.value) }
    guard let sum = rangeAnchor(args[0]) else { return .error(.value) }
    var tests: [(RangeAnchor, CriteriaTest)] = []
    var index = 1
    while index < args.count {
      guard let anchor = rangeAnchor(args[index]) else { return .error(.value) }
      if anchor.rows != sum.rows || anchor.cols != sum.cols { return .error(.value) }
      let criterion = evaluate(args[index + 1])
      if case .error = criterion { return criterion }
      tests.append((anchor, criteriaTest(from: criterion)))
      index += 2
    }
    var total = 0.0
    var count = 0
    for row in 0..<sum.rows {
      for col in 0..<sum.cols {
        var matched = true
        for (anchor, test) in tests {
          let value = lookup(cellRef(anchor, row: row, col: col))
          if case .error(let error) = value { return .error(error) }
          if !criteriaMatch(value, test) {
            matched = false
            break
          }
        }
        guard matched else { continue }
        let value = lookup(cellRef(sum, row: row, col: col))
        if case .error(let error) = value { return .error(error) }
        guard let number = numericAddend(value) else { continue }
        total += number
        count += 1
      }
    }
    switch kind {
    case .sum:
      return .number(total)
    case .average:
      guard count > 0 else { return .error(.divZero) }
      return .number(total / Double(count))
    }
  }

  private func reduceMatches(
    criteria: RangeAnchor,
    test: CriteriaTest,
    values: RangeAnchor,
    kind: AggregateKind
  ) -> CellValue {
    var total = 0.0
    var count = 0
    for row in 0..<criteria.rows {
      for col in 0..<criteria.cols {
        let candidate = lookup(cellRef(criteria, row: row, col: col))
        if case .error(let error) = candidate { return .error(error) }
        guard criteriaMatch(candidate, test) else { continue }
        let value = lookup(cellRef(values, row: row, col: col))
        if case .error(let error) = value { return .error(error) }
        guard let number = numericAddend(value) else { continue }
        total += number
        count += 1
      }
    }
    switch kind {
    case .sum:
      return .number(total)
    case .average:
      guard count > 0 else { return .error(.divZero) }
      return .number(total / Double(count))
    }
  }

  // MARK: - Criteria

  private func criteriaTest(from value: CellValue) -> CriteriaTest {
    switch value {
    case .number(let number):
      return CriteriaTest(op: .eq, number: number, text: "", wildcard: false, blank: false)
    case .bool(let flag):
      return CriteriaTest(op: .eq, number: nil, text: flag ? "TRUE" : "FALSE", wildcard: false, blank: false)
    case .blank:
      return CriteriaTest(op: .eq, number: nil, text: "", wildcard: false, blank: true)
    case .string(let text):
      return criteriaTest(from: text)
    case .error:
      return CriteriaTest(op: .eq, number: nil, text: "", wildcard: false, blank: false)
    }
  }

  private func criteriaTest(from raw: String) -> CriteriaTest {
    var op: CriteriaOp = .eq
    var rest = raw
    if rest.hasPrefix(">=") {
      op = .ge
      rest = String(rest.dropFirst(2))
    } else if rest.hasPrefix("<=") {
      op = .le
      rest = String(rest.dropFirst(2))
    } else if rest.hasPrefix("<>") {
      op = .ne
      rest = String(rest.dropFirst(2))
    } else if rest.hasPrefix(">") {
      op = .gt
      rest = String(rest.dropFirst(1))
    } else if rest.hasPrefix("<") {
      op = .lt
      rest = String(rest.dropFirst(1))
    } else if rest.hasPrefix("=") {
      op = .eq
      rest = String(rest.dropFirst(1))
    }
    if rest.isEmpty {
      return CriteriaTest(op: op, number: nil, text: "", wildcard: false, blank: true)
    }
    let wildcard = excelHasWildcard(rest)
    if !wildcard, let number = Double(rest.trimmingCharacters(in: .whitespacesAndNewlines)) {
      return CriteriaTest(op: op, number: number, text: rest, wildcard: false, blank: false)
    }
    return CriteriaTest(op: op, number: nil, text: rest, wildcard: wildcard, blank: false)
  }

  private func criteriaMatch(_ value: CellValue, _ test: CriteriaTest) -> Bool {
    let blank = isBlankForCount(value)
    if test.wildcard && (test.op == .eq || test.op == .ne) {
      if blank { return test.op == .ne }
      let matched = excelWildcardMatch(criteriaText(value), pattern: test.text)
      return test.op == .eq ? matched : !matched
    }
    if let criterion = test.number {
      if let number = criteriaNumber(value) {
        return compareCriteria(test.op, number, criterion)
      }
      return test.op == .ne
    }
    if test.blank {
      switch test.op {
      case .eq: return blank
      case .ne: return !blank
      default: return false
      }
    }
    if blank { return test.op == .ne }
    if case .number = value {
      return test.op == .ne
    }
    let comparison = criteriaText(value).caseInsensitiveCompare(test.text)
    switch test.op {
    case .eq: return comparison == .orderedSame
    case .ne: return comparison != .orderedSame
    case .lt: return comparison == .orderedAscending
    case .gt: return comparison == .orderedDescending
    case .le: return comparison != .orderedDescending
    case .ge: return comparison != .orderedAscending
    }
  }

  private func compareCriteria(_ op: CriteriaOp, _ lhs: Double, _ rhs: Double) -> Bool {
    switch op {
    case .eq: return lhs == rhs
    case .ne: return lhs != rhs
    case .lt: return lhs < rhs
    case .le: return lhs <= rhs
    case .gt: return lhs > rhs
    case .ge: return lhs >= rhs
    }
  }

  private func criteriaNumber(_ value: CellValue) -> Double? {
    switch value {
    case .number(let number):
      return number
    case .string(let text):
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { return nil }
      return Double(trimmed)
    default:
      return nil
    }
  }

  private func criteriaText(_ value: CellValue) -> String {
    switch value {
    case .number:
      return value.displayString
    case .bool(let flag):
      return flag ? "TRUE" : "FALSE"
    case .string(let text):
      return text
    case .blank, .error:
      return ""
    }
  }

  private func isBlankForCount(_ value: CellValue) -> Bool {
    switch value {
    case .blank:
      return true
    case .string(let text):
      return text.isEmpty
    default:
      return false
    }
  }

  private func numericAddend(_ value: CellValue) -> Double? {
    if case .number(let number) = value { return number }
    return nil
  }

  private func excelHasWildcard(_ text: String) -> Bool {
    let chars = Array(text)
    var index = 0
    while index < chars.count {
      if chars[index] == "~", index + 1 < chars.count {
        let next = chars[index + 1]
        if next == "*" || next == "?" || next == "~" { return true }
        index += 2
        continue
      }
      if chars[index] == "*" || chars[index] == "?" { return true }
      index += 1
    }
    return false
  }

  private func excelWildcardMatch(_ text: String, pattern: String) -> Bool {
    let haystack = Array(text.lowercased())
    let needle = Array(pattern.lowercased())
    func match(from textIndex: Int, patternIndex: Int) -> Bool {
      var ti = textIndex
      var pi = patternIndex
      while pi < needle.count {
        if needle[pi] == "~", pi + 1 < needle.count {
          guard ti < haystack.count, haystack[ti] == needle[pi + 1] else { return false }
          ti += 1
          pi += 2
          continue
        }
        if needle[pi] == "*" {
          var next = pi + 1
          while next < needle.count, needle[next] == "*" { next += 1 }
          if next == needle.count { return true }
          for start in ti...haystack.count where match(from: start, patternIndex: next) {
            return true
          }
          return false
        }
        guard ti < haystack.count, needle[pi] == "?" || haystack[ti] == needle[pi] else { return false }
        ti += 1
        pi += 1
      }
      return ti == haystack.count
    }
    return match(from: 0, patternIndex: 0)
  }

  // MARK: - Ranges and arrays

  private func resolvedExpr(_ expr: FormulaExpr) -> FormulaExpr {
    if case .namedRange(let name) = expr, let resolved = namedRangeLookup(name) {
      return resolved
    }
    return expr
  }

  private func rangeAnchor(_ expr: FormulaExpr) -> RangeAnchor? {
    switch resolvedExpr(expr) {
    case .range(let start, let end):
      let bounds = normalizedBounds(start: start, end: end)
      return RangeAnchor(
        sheet: start.sheet ?? end.sheet,
        row: bounds.minRow,
        col: bounds.minCol,
        rows: bounds.maxRow - bounds.minRow + 1,
        cols: bounds.maxCol - bounds.minCol + 1
      )
    case .cellRef(let ref):
      guard !ref.isRowOpen, !ref.isColOpen else { return nil }
      return RangeAnchor(sheet: ref.sheet, row: ref.row, col: ref.col, rows: 1, cols: 1)
    default:
      return nil
    }
  }

  private func cellRef(_ anchor: RangeAnchor, row: Int, col: Int) -> FormulaRef {
    FormulaRef(
      sheet: anchor.sheet,
      row: anchor.row + row,
      col: anchor.col + col,
      absRow: false,
      absCol: false
    )
  }

  private func valueMatrix(_ expr: FormulaExpr) -> ValueMatrix? {
    let resolved = resolvedExpr(expr)
    switch resolved {
    case .range(let start, let end):
      let bounds = normalizedBounds(start: start, end: end)
      let rows = bounds.maxRow - bounds.minRow + 1
      let cols = bounds.maxCol - bounds.minCol + 1
      guard rows > 0, cols > 0 else { return nil }
      return ValueMatrix(rows: rows, cols: cols, values: rangeCellValues(start: start, end: end))
    case .unary(let op, let inner):
      guard let matrix = valueMatrix(inner) else { return nil }
      return ValueMatrix(rows: matrix.rows, cols: matrix.cols, values: matrix.values.map { applyUnary(op, to: $0) })
    case .binary(let op, let lhs, let rhs):
      guard let left = valueMatrix(lhs), let right = valueMatrix(rhs) else { return nil }
      return combine(op, left, right)
    case .cellRef:
      return ValueMatrix(rows: 1, cols: 1, values: [evaluate(resolved)])
    default:
      return ValueMatrix(rows: 1, cols: 1, values: [evaluate(resolved)])
    }
  }

  private func combine(_ op: BinaryOp, _ lhs: ValueMatrix, _ rhs: ValueMatrix) -> ValueMatrix? {
    if lhs.rows == rhs.rows, lhs.cols == rhs.cols {
      let values = zip(lhs.values, rhs.values).map { applyBinary(op, lhs: $0, rhs: $1) }
      return ValueMatrix(rows: lhs.rows, cols: lhs.cols, values: values)
    }
    if lhs.rows == 1, lhs.cols == 1 {
      let values = rhs.values.map { applyBinary(op, lhs: lhs.values[0], rhs: $0) }
      return ValueMatrix(rows: rhs.rows, cols: rhs.cols, values: values)
    }
    if rhs.rows == 1, rhs.cols == 1 {
      let values = lhs.values.map { applyBinary(op, lhs: $0, rhs: rhs.values[0]) }
      return ValueMatrix(rows: lhs.rows, cols: lhs.cols, values: values)
    }
    return nil
  }

  private func expandedValues(_ args: [FormulaExpr]) -> [CellValue] {
    var values: [CellValue] = []
    for arg in args {
      if let matrix = valueMatrix(arg) {
        values.append(contentsOf: matrix.values)
      } else {
        values.append(evaluate(arg))
      }
    }
    return values
  }

  private func sumProductCoefficient(_ value: CellValue) -> Double {
    switch value {
    case .number(let number):
      return number
    case .bool(let flag):
      return flag ? 1 : 0
    case .blank, .string, .error:
      return 0
    }
  }

  private func replaceOccurrence(in source: String, needle: String, with replacement: String, occurrence: Int) -> String {
    var found = 0
    var search = source.startIndex
    while search < source.endIndex, let range = source.range(of: needle, range: search..<source.endIndex) {
      found += 1
      if found == occurrence {
        var result = source
        result.replaceSubrange(range, with: replacement)
        return result
      }
      search = range.upperBound
    }
    return source
  }

  private func excelRound(_ value: Double, places: Int, mode: NSDecimalNumber.RoundingMode) -> Double {
    let source = Decimal(string: String(value)) ?? Decimal(value)
    var input = source
    var output = Decimal()
    NSDecimalRound(&output, &input, places, mode)
    return NSDecimalNumber(decimal: output).doubleValue
  }
}
