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

  fileprivate struct LookupMemoKey: Hashable {
    var sheet: String?
    var row: Int
    var col: Int
  }

  /// Excel-style aggregates skip #VALUE! / #REF! rows instead of failing the whole formula.
  fileprivate func lookupForAggregate(_ ref: FormulaRef, memo: inout [LookupMemoKey: CellValue]) -> CellValue {
    let key = LookupMemoKey(sheet: ref.sheet, row: ref.row, col: ref.col)
    if let cached = memo[key] { return cached }
    let value = lookup(ref)
    memo[key] = value
    return value
  }

  fileprivate func aggregateRowError(_ value: CellValue) -> Bool {
    if case .error = value { return true }
    return false
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
    var memo: [LookupMemoKey: CellValue] = [:]
    let values = snapshotValues(anchor: anchor, memo: &memo)
    if let cache = aggregateRangeCache,
       criteriaSupportsIndexLookup(test),
       let lookupKey = lookupKeyForCriterion(criterion, test: test) {
      let rangeKey = aggregateRangeKey(for: anchor)
      let count = cache.countForCriteria(
        rangeKeys: [rangeKey],
        criteriaKeys: [lookupKey],
        supplyColumns: { [values] }
      )
      return .number(Double(count))
    }
    var count = 0
    for value in values {
      if aggregateRowError(value) { continue }
      if criteriaMatch(value, test) { count += 1 }
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
    switch countIFSEvalResult(args) {
    case .value(let count):
      return .number(Double(count))
    case .error(let value):
      return value
    }
  }

  /// KPI YTD: `COUNTIFS(Jan…)+COUNTIFS(Feb…)+…` with identical criterion expressions.
  func tryEvalFusedCountIFSSum(_ lhs: FormulaExpr, _ rhs: FormulaExpr) -> CellValue? {
    guard let terms = collectAddTreeCountIFS(lhs, rhs), terms.count >= 2 else { return nil }
    guard let criteriaExprs = sharedCountIFSCriteriaExprs(in: terms) else { return nil }
    var criteriaValues: [CellValue] = []
    criteriaValues.reserveCapacity(criteriaExprs.count)
    for expr in criteriaExprs {
      let value = evaluate(expr)
      if case .error = value { return value }
      criteriaValues.append(value)
    }
    let tests = criteriaValues.map { criteriaTest(from: $0) }
    guard aggregateLookupKeys(criteria: criteriaValues, tests: tests) != nil else { return nil }

    var total = 0
    for term in terms {
      guard case .call(_, let args) = term else { return nil }
      switch countIFSEvalResult(args, criteriaValues: criteriaValues, tests: tests) {
      case .value(let count):
        total += count
      case .error(let value):
        return value
      }
    }
    recalcProfile?.countifsFusedAddHits += 1
    return .number(Double(total))
  }

  private enum CountIFSOutcome {
    case value(Int)
    case error(CellValue)
  }

  private func countIFSEvalResult(
    _ args: [FormulaExpr],
    criteriaValues: [CellValue]? = nil,
    tests: [CriteriaTest]? = nil
  ) -> CountIFSOutcome {
    guard args.count >= 2, args.count.isMultiple(of: 2) else { return .error(.error(.value)) }
    guard let first = rangeAnchor(args[0]) else { return .error(.error(.value)) }

    let resolvedCriteria: [CellValue]
    let resolvedTests: [CriteriaTest]
    if let criteriaValues, let tests, criteriaValues.count * 2 == args.count {
      resolvedCriteria = criteriaValues
      resolvedTests = tests
    } else {
      var builtValues: [CellValue] = []
      var builtTests: [CriteriaTest] = []
      var index = 0
      while index < args.count {
        guard let anchor = rangeAnchor(args[index]) else { return .error(.error(.value)) }
        if anchor.rows != first.rows || anchor.cols != first.cols { return .error(.error(.value)) }
        let criterion = evaluate(args[index + 1])
        if case .error = criterion { return .error(criterion) }
        builtValues.append(criterion)
        builtTests.append(criteriaTest(from: criterion))
        index += 2
      }
      resolvedCriteria = builtValues
      resolvedTests = builtTests
    }

    var rangeTests: [(RangeAnchor, CriteriaTest, CellValue)] = []
    rangeTests.reserveCapacity(resolvedTests.count)
    var index = 0
    while index < args.count {
      guard let anchor = rangeAnchor(args[index]) else { return .error(.error(.value)) }
      if anchor.rows != first.rows || anchor.cols != first.cols { return .error(.error(.value)) }
      let testIndex = index / 2
      rangeTests.append((anchor, resolvedTests[testIndex], resolvedCriteria[testIndex]))
      index += 2
    }

    var memo: [LookupMemoKey: CellValue] = [:]
    if let cache = aggregateRangeCache,
       let lookupKeys = aggregateLookupKeys(
         criteria: rangeTests.map(\.2),
         tests: rangeTests.map(\.1)
       ) {
      let rangeKeys = rangeTests.map { aggregateRangeKey(for: $0.0) }
      let matches = cache.countForCriteria(
        rangeKeys: rangeKeys,
        criteriaKeys: lookupKeys,
        supplyColumns: {
          var snapMemo: [LookupMemoKey: CellValue] = [:]
          return rangeTests.map { snapshotValues(anchor: $0.0, memo: &snapMemo) }
        }
      )
      recalcProfile?.countifsHistogramLookups += 1
      return .value(matches)
    }
    let rangeSnapshots = rangeTests.map { snapshotValues(anchor: $0.0, memo: &memo) }
    let count = rangeSnapshots[0].count
    var matches = 0
    recalcProfile?.countifsRowScanCells += count
    for offset in 0..<count {
      var matched = true
      for (rangeIndex, test) in rangeTests.map(\.1).enumerated() {
        let value = rangeSnapshots[rangeIndex][offset]
        if aggregateRowError(value) {
          matched = false
          break
        }
        if !criteriaMatch(value, test) {
          matched = false
          break
        }
      }
      if matched { matches += 1 }
    }
    return .value(matches)
  }

  private func unwrapCountIFSExpr(_ expr: FormulaExpr) -> FormulaExpr {
    if case .unary(.plus, let inner) = expr { return unwrapCountIFSExpr(inner) }
    return expr
  }

  private func collectAddTreeCountIFS(_ lhs: FormulaExpr, _ rhs: FormulaExpr) -> [FormulaExpr]? {
    var terms: [FormulaExpr] = []
    func collect(_ expr: FormulaExpr) -> Bool {
      let node = unwrapCountIFSExpr(expr)
      if case .binary(.add, let left, let right) = node {
        return collect(left) && collect(right)
      }
      guard case .call(let name, let args) = node,
            name.uppercased() == "COUNTIFS",
            args.count >= 4,
            args.count.isMultiple(of: 2)
      else { return false }
      terms.append(node)
      return true
    }
    guard collect(lhs), collect(rhs) else { return nil }
    return terms
  }

  private func sharedCountIFSCriteriaExprs(in terms: [FormulaExpr]) -> [FormulaExpr]? {
    guard let first = terms.first,
          case .call(_, let firstArgs) = first
    else { return nil }
    let arity = firstArgs.count
    var criteria: [FormulaExpr] = []
    for index in stride(from: 1, to: arity, by: 2) {
      let expr = firstArgs[index]
      for term in terms.dropFirst() {
        guard case .call(_, let args) = term, args.count == arity, args[index] == expr else {
          return nil
        }
      }
      criteria.append(expr)
    }
    return criteria
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
    let booleanShaped = looksLikeBooleanSumProduct(args)
    if let fast = tryEvalBooleanSumProduct(args) {
      recalcProfile?.sumproductBooleanHits += 1
      return fast
    }
    if booleanShaped {
      recalcProfile?.sumproductBooleanFallbacks += 1
    }
    if args.count == 1 {
      let cacheBox = FormulaEvaluator.ArrayEvalCacheBox()
      let values = arrayEvaluate(args[0], cache: cacheBox)
      var total = 0.0
      for value in values {
        if case .error(let error) = value { return .error(error) }
        total += sumProductCoefficient(value)
      }
      return .number(total)
    }
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
    return reduceMatches(criteria: criteria, test: test, criterion: criterion, values: sumAnchor, kind: kind)
  }

  private func multiCriteriaAggregate(_ args: [FormulaExpr], kind: AggregateKind) -> CellValue {
    guard args.count >= 3, (args.count - 1).isMultiple(of: 2) else { return .error(.value) }
    guard let sum = rangeAnchor(args[0]) else { return .error(.value) }
    var tests: [(RangeAnchor, CriteriaTest, CellValue)] = []
    var index = 1
    while index < args.count {
      guard let anchor = rangeAnchor(args[index]) else { return .error(.value) }
      if anchor.rows != sum.rows || anchor.cols != sum.cols { return .error(.value) }
      let criterion = evaluate(args[index + 1])
      if case .error = criterion { return criterion }
      tests.append((anchor, criteriaTest(from: criterion), criterion))
      index += 2
    }
    var memo: [LookupMemoKey: CellValue] = [:]
    if let cache = aggregateRangeCache {
      if let lookupKeys = aggregateLookupKeys(criteria: tests.map(\.2), tests: tests.map(\.1)) {
        let criteriaKeys = tests.map { aggregateRangeKey(for: $0.0) }
        let sumKey = aggregateRangeKey(for: sum)
        let bucket = cache.sumForCriteria(
          criteriaRangeKeys: criteriaKeys,
          sumRangeKey: sumKey,
          criteriaKeys: lookupKeys,
          supplyColumns: {
            var snapMemo: [LookupMemoKey: CellValue] = [:]
            let sumValues = snapshotValues(anchor: sum, memo: &snapMemo)
            let criteriaColumns = tests.map { snapshotValues(anchor: $0.0, memo: &snapMemo) }
            return (criteriaColumns, sumValues)
          }
        )
        switch kind {
        case .sum:
          return .number(bucket.sum)
        case .average:
          guard bucket.count > 0 else { return .error(.divZero) }
          return .number(bucket.sum / Double(bucket.count))
        }
      }
      if tests.allSatisfy({ !$0.1.wildcard }) {
        let sumValues = snapshotValues(anchor: sum, memo: &memo)
        let rangeSnapshots = tests.map { snapshotValues(anchor: $0.0, memo: &memo) }
        let bucket = cache.sumByRowFilter(sumColumn: sumValues) { row in
          for (rangeIndex, test) in tests.map(\.1).enumerated() {
            let value = rangeSnapshots[rangeIndex][row]
            if aggregateRowError(value) { return false }
            if !criteriaMatch(value, test) { return false }
          }
          return true
        }
        switch kind {
        case .sum:
          return .number(bucket.sum)
        case .average:
          guard bucket.count > 0 else { return .error(.divZero) }
          return .number(bucket.sum / Double(bucket.count))
        }
      }
    }
    let sumValues = snapshotValues(anchor: sum, memo: &memo)
    let rangeSnapshots = tests.map { snapshotValues(anchor: $0.0, memo: &memo) }
    let cellCount = sumValues.count
    var total = 0.0
    var matchCount = 0
    for offset in 0..<cellCount {
      var matched = true
      for (rangeIndex, test) in tests.map(\.1).enumerated() {
        let value = rangeSnapshots[rangeIndex][offset]
        if aggregateRowError(value) {
          matched = false
          break
        }
        if !criteriaMatch(value, test) {
          matched = false
          break
        }
      }
      guard matched else { continue }
      let value = sumValues[offset]
      if aggregateRowError(value) { continue }
      guard let number = numericAddend(value) else { continue }
      total += number
      matchCount += 1
    }
    switch kind {
    case .sum:
      return .number(total)
    case .average:
      guard matchCount > 0 else { return .error(.divZero) }
      return .number(total / Double(matchCount))
    }
  }

  private func reduceMatches(
    criteria: RangeAnchor,
    test: CriteriaTest,
    criterion: CellValue,
    values: RangeAnchor,
    kind: AggregateKind
  ) -> CellValue {
    var memo: [LookupMemoKey: CellValue] = [:]
    let criteriaValues = snapshotValues(anchor: criteria, memo: &memo)
    let sumValues = snapshotValues(anchor: values, memo: &memo)
    if let cache = aggregateRangeCache,
       criteriaSupportsIndexLookup(test),
       let lookupKey = lookupKeyForCriterion(criterion, test: test) {
      let criteriaKey = aggregateRangeKey(for: criteria)
      let sumKey = aggregateRangeKey(for: values)
      let bucket = cache.sumForCriteria(
        criteriaRangeKeys: [criteriaKey],
        sumRangeKey: sumKey,
        criteriaKeys: [lookupKey],
        supplyColumns: { ([criteriaValues], sumValues) }
      )
      switch kind {
      case .sum:
        return .number(bucket.sum)
      case .average:
        guard bucket.count > 0 else { return .error(.divZero) }
        return .number(bucket.sum / Double(bucket.count))
      }
    }
    var total = 0.0
    var count = 0
    for offset in 0..<criteriaValues.count {
      let candidate = criteriaValues[offset]
      if aggregateRowError(candidate) { continue }
      guard criteriaMatch(candidate, test) else { continue }
      let value = sumValues[offset]
      if aggregateRowError(value) { continue }
      guard let number = numericAddend(value) else { continue }
      total += number
      count += 1
    }
    switch kind {
    case .sum:
      return .number(total)
    case .average:
      guard count > 0 else { return .error(.divZero) }
      return .number(total / Double(count))
    }
  }

  private func aggregateRangeKey(for anchor: RangeAnchor) -> AggregateRangeKey {
    AggregateRangeKey(
      sheet: anchor.sheet,
      row: anchor.row,
      col: anchor.col,
      rows: anchor.rows,
      cols: anchor.cols
    )
  }

  private func criteriaSupportsIndexLookup(_ test: CriteriaTest) -> Bool {
    test.op == .eq && !test.wildcard
  }

  private func lookupKeyForCriterion(_ criterion: CellValue, test: CriteriaTest) -> AggregateValueKey? {
    guard criteriaSupportsIndexLookup(test) else { return nil }
    if case .error = criterion { return nil }
    if test.blank {
      return AggregateValueKey(kind: .blank, numberBits: 0, text: "")
    }
    if let number = test.number {
      return AggregateValueKey(kind: .number, numberBits: number.bitPattern, text: "")
    }
    return AggregateValueKey.from(cellValue: criterion)
  }

  private func aggregateLookupKeys(criteria: [CellValue], tests: [CriteriaTest]) -> [AggregateValueKey]? {
    guard criteria.count == tests.count else { return nil }
    var keys: [AggregateValueKey] = []
    keys.reserveCapacity(criteria.count)
    for (value, test) in zip(criteria, tests) {
      guard let key = lookupKeyForCriterion(value, test: test) else { return nil }
      keys.append(key)
    }
    return keys
  }

  private func snapshotValues(
    anchor: RangeAnchor,
    memo: inout [LookupMemoKey: CellValue]
  ) -> [CellValue] {
    let count = anchor.rows * anchor.cols
    let key = AggregateRangeKey(
      sheet: anchor.sheet,
      row: anchor.row,
      col: anchor.col,
      rows: anchor.rows,
      cols: anchor.cols
    )
    if let cache = aggregateRangeCache {
      return cache.rowMajorValues(key: key, count: count) { index in
        let row = index / anchor.cols
        let col = index % anchor.cols
        return lookupForAggregate(cellRef(anchor, row: row, col: col), memo: &memo)
      }
    }
    var values: [CellValue] = []
    values.reserveCapacity(count)
    for row in 0..<anchor.rows {
      for col in 0..<anchor.cols {
        values.append(lookupForAggregate(cellRef(anchor, row: row, col: col), memo: &memo))
      }
    }
    return values
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

  func criteriaText(_ value: CellValue) -> String {
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

  func isBlankForCount(_ value: CellValue) -> Bool {
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

  func excelWildcardMatch(_ text: String, pattern: String) -> Bool {
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

  func resolvedExpr(_ expr: FormulaExpr) -> FormulaExpr {
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

  private func statsNumericValue(_ value: CellValue) -> Double? {
    switch value {
    case .number(let number):
      return number
    case .bool(let flag):
      return flag ? 1 : 0
    case .blank, .string, .error:
      return nil
    }
  }

  func fastAverageIfPossible(_ args: [FormulaExpr]) -> CellValue? {
    guard args.count == 1 else { return nil }
    guard let anchor = rangeAnchor(args[0]) else { return nil }
    var memo: [LookupMemoKey: CellValue] = [:]
    let values = snapshotValues(anchor: anchor, memo: &memo)
    var sum = 0.0
    var count = 0
    for value in values {
      if case .error = value { continue }
      guard let number = statsNumericValue(value) else { continue }
      sum += number
      count += 1
    }
    guard count > 0 else { return .error(.divZero) }
    return .number(sum / Double(count))
  }

  // MARK: - SUMPRODUCT boolean products

  private func tryEvalBooleanSumProduct(_ args: [FormulaExpr]) -> CellValue? {
    guard let plan = parseSumProductBooleanPlan(args) else { return nil }
    guard let cache = aggregateRangeCache else { return nil }
    var memo: [LookupMemoKey: CellValue] = [:]
    let columns = plan.anchors.map { snapshotValues(anchor: $0, memo: &memo) }
    let rowCount = columns.first?.count ?? 0
    guard rowCount > 0, columns.allSatisfy({ $0.count == rowCount }) else { return nil }

    let staticMask = cache.booleanStaticMask(key: plan.staticMaskKey, rowCount: rowCount) { row in
      for test in plan.staticTests {
        let value = columns[test.columnIndex][row]
        if aggregateRowError(value) { return false }
        if !criteriaMatch(value, test.test) { return false }
      }
      for diff in plan.diffBoundTests {
        let lhs = columns[diff.lhsColumnIndex][row]
        let rhs = columns[diff.rhsColumnIndex][row]
        guard let left = lhs.asNumber, let right = rhs.asNumber else { return false }
        let delta = left - right
        switch diff.op {
        case .ge:
          if delta < diff.threshold { return false }
        case .le:
          if delta > diff.threshold { return false }
        default:
          return false
        }
      }
      return true
    }

    if plan.dynamicTests.count == 1, plan.dynamicTests[0].op == .eq {
      let dynamic = plan.dynamicTests[0]
      let criterion = evaluate(dynamic.criterionExpr)
      if case .error = criterion { return criterion }
      if let test = criteriaTestFromComparison(criterion: criterion, op: dynamic.op),
         criteriaSupportsIndexLookup(test),
         let lookupKey = lookupKeyForCriterion(criterion, test: test) {
        let rangeKey = aggregateRangeKey(for: plan.anchors[dynamic.columnIndex])
        let count = cache.countForMaskedCriteria(
          rangeKey: rangeKey,
          column: columns[dynamic.columnIndex],
          staticMaskKey: plan.staticMaskKey,
          mask: staticMask,
          criteriaKey: lookupKey
        )
        return .number(Double(count))
      }
    }

    var dynamicTests: [(columnIndex: Int, test: CriteriaTest)] = []
    for dynamic in plan.dynamicTests {
      let criterion = evaluate(dynamic.criterionExpr)
      if case .error = criterion { return criterion }
      guard let test = criteriaTestFromComparison(criterion: criterion, op: dynamic.op) else { return nil }
      dynamicTests.append((dynamic.columnIndex, test))
    }

    var count = 0
    for row in 0..<rowCount {
      guard staticMask[row] else { continue }
      var matched = true
      for dynamic in dynamicTests {
        let value = columns[dynamic.columnIndex][row]
        if aggregateRowError(value) {
          matched = false
          break
        }
        if !criteriaMatch(value, dynamic.test) {
          matched = false
          break
        }
      }
      if matched { count += 1 }
    }
    return .number(Double(count))
  }

  private struct SumProductBooleanPlan {
    var anchors: [RangeAnchor]
    var staticTests: [StaticColumnTest]
    var dynamicTests: [DynamicColumnTest]
    var diffBoundTests: [DiffBoundTest]
    var staticMaskKey: UInt64

    struct StaticColumnTest {
      var columnIndex: Int
      var test: CriteriaTest
    }

    struct DynamicColumnTest {
      var columnIndex: Int
      var op: BinaryOp
      var criterionExpr: FormulaExpr
    }

    struct DiffBoundTest {
      var lhsColumnIndex: Int
      var rhsColumnIndex: Int
      var op: CriteriaOp
      var threshold: Double
    }
  }

  private enum ParsedBooleanFactor {
    case staticTest(RangeAnchor, CriteriaTest)
    case dynamicTest(RangeAnchor, BinaryOp, FormulaExpr)
    case diffBound(RangeAnchor, RangeAnchor, CriteriaOp, Double)
  }

  private func looksLikeBooleanSumProduct(_ args: [FormulaExpr]) -> Bool {
    guard let factors = booleanProductFactors(from: args), !factors.isEmpty else { return false }
    let meaningful = factors.filter { !isIgnorableBooleanProductFactor($0) }
    guard !meaningful.isEmpty else { return false }
    return meaningful.allSatisfy { parseBooleanFactor($0) != nil }
  }

  private func booleanProductFactors(from args: [FormulaExpr]) -> [FormulaExpr]? {
    guard !args.isEmpty else { return nil }
    if args.count == 1 {
      var factors: [FormulaExpr] = []
      guard collectMultiplyFactors(unwrapSumProductParen(args[0]), into: &factors) else { return nil }
      return factors.map { unwrapBooleanCoercion($0) }
    }
    return args.map { unwrapBooleanCoercion($0) }
  }

  private func isIgnorableBooleanProductFactor(_ expr: FormulaExpr) -> Bool {
    switch unwrapBooleanCoercion(expr) {
    case .number(let value):
      return value == 1
    case .boolean(let flag):
      return flag
    default:
      return false
    }
  }

  private func unwrapBooleanCoercion(_ expr: FormulaExpr) -> FormulaExpr {
    var node = unwrapSumProductParen(expr)
    while case .unary(.plus, let inner) = node {
      node = unwrapSumProductParen(inner)
    }
    while case .unary(.negate, let inner) = node {
      node = unwrapSumProductParen(inner)
    }
    return node
  }

  private func parseSumProductBooleanPlan(_ args: [FormulaExpr]) -> SumProductBooleanPlan? {
    guard let factors = booleanProductFactors(from: args), !factors.isEmpty else { return nil }
    var anchors: [RangeAnchor] = []
    var staticTests: [SumProductBooleanPlan.StaticColumnTest] = []
    var dynamicTests: [SumProductBooleanPlan.DynamicColumnTest] = []
    var diffBoundTests: [SumProductBooleanPlan.DiffBoundTest] = []
    var staticHasher = Hasher()

    for factor in factors {
      if isIgnorableBooleanProductFactor(factor) { continue }
      guard let parsed = parseBooleanFactor(factor) else { return nil }
      switch parsed {
      case .staticTest(let anchor, let test):
        let index = sumProductAnchorIndex(anchor, anchors: &anchors)
        staticTests.append(.init(columnIndex: index, test: test))
        mixStaticCriteriaTest(test, into: &staticHasher)
      case .dynamicTest(let anchor, let op, let criterionExpr):
        let index = sumProductAnchorIndex(anchor, anchors: &anchors)
        dynamicTests.append(.init(columnIndex: index, op: op, criterionExpr: criterionExpr))
      case .diffBound(let lhs, let rhs, let op, let threshold):
        let li = sumProductAnchorIndex(lhs, anchors: &anchors)
        let ri = sumProductAnchorIndex(rhs, anchors: &anchors)
        diffBoundTests.append(.init(lhsColumnIndex: li, rhsColumnIndex: ri, op: op, threshold: threshold))
        staticHasher.combine(op.hashValue)
        staticHasher.combine(threshold)
      }
    }

    guard !(staticTests.isEmpty && dynamicTests.isEmpty && diffBoundTests.isEmpty) else { return nil }
    for anchor in anchors {
      mixSumProductAnchor(anchor, into: &staticHasher)
    }
    return SumProductBooleanPlan(
      anchors: anchors,
      staticTests: staticTests,
      dynamicTests: dynamicTests,
      diffBoundTests: diffBoundTests,
      staticMaskKey: UInt64(bitPattern: Int64(staticHasher.finalize()))
    )
  }

  private func unwrapSumProductParen(_ expr: FormulaExpr) -> FormulaExpr {
    if case .unary(.plus, let inner) = expr { return unwrapSumProductParen(inner) }
    return expr
  }

  private func collectMultiplyFactors(_ expr: FormulaExpr, into factors: inout [FormulaExpr]) -> Bool {
    switch expr {
    case .binary(.multiply, let lhs, let rhs):
      guard collectMultiplyFactors(lhs, into: &factors), collectMultiplyFactors(rhs, into: &factors) else {
        return false
      }
      return true
    case .unary(.plus, let inner):
      return collectMultiplyFactors(inner, into: &factors)
    default:
      factors.append(unwrapBooleanCoercion(expr))
      return true
    }
  }

  private func parseBooleanFactor(_ expr: FormulaExpr) -> ParsedBooleanFactor? {
    let node = unwrapSumProductParen(expr)
    guard case .binary(let op, let lhs, let rhs) = node else { return nil }
    if let diff = parseRangeSubtractBound(lhs: lhs, op: op, rhs: rhs) {
      return diff
    }
    switch op {
    case .eq, .ne, .lt, .le, .gt, .ge:
      break
    default:
      return nil
    }
    if let anchor = rangeAnchor(lhs) {
      guard !isRangeExpr(rhs) else { return nil }
      if isDynamicCriterion(rhs) {
        return .dynamicTest(anchor, op, rhs)
      }
      let criterion = evaluate(rhs)
      if case .error = criterion { return nil }
      guard let test = criteriaTestFromComparison(criterion: criterion, op: op) else { return nil }
      return .staticTest(anchor, test)
    }
    if let anchor = rangeAnchor(rhs) {
      guard !isRangeExpr(lhs) else { return nil }
      let flipped = flipComparisonOp(op)
      if isDynamicCriterion(lhs) {
        return .dynamicTest(anchor, flipped, lhs)
      }
      let criterion = evaluate(lhs)
      if case .error = criterion { return nil }
      guard let test = criteriaTestFromComparison(criterion: criterion, op: flipped) else { return nil }
      return .staticTest(anchor, test)
    }
    return nil
  }

  private func parseRangeSubtractBound(
    lhs: FormulaExpr,
    op: BinaryOp,
    rhs: FormulaExpr
  ) -> ParsedBooleanFactor? {
    guard op == .ge || op == .le else { return nil }
    guard case .number(let threshold) = evaluate(rhs) else { return nil }
    guard case .binary(.subtract, let left, let right) = unwrapSumProductParen(lhs),
          let lhsAnchor = rangeAnchor(left),
          let rhsAnchor = rangeAnchor(right),
          lhsAnchor.rows == rhsAnchor.rows,
          lhsAnchor.cols == rhsAnchor.cols
    else {
      return nil
    }
    let boundOp: CriteriaOp = op == .ge ? .ge : .le
    return .diffBound(lhsAnchor, rhsAnchor, boundOp, threshold)
  }

  private func isRangeExpr(_ expr: FormulaExpr) -> Bool {
    if case .range = expr { return true }
    return false
  }

  private func isDynamicCriterion(_ expr: FormulaExpr) -> Bool {
    switch expr {
    case .cellRef, .namedRange:
      return true
    case .unary(.plus, let inner), .unary(.negate, let inner):
      return isDynamicCriterion(inner)
    default:
      return false
    }
  }

  private func flipComparisonOp(_ op: BinaryOp) -> BinaryOp {
    switch op {
    case .eq: return .eq
    case .ne: return .ne
    case .lt: return .gt
    case .le: return .ge
    case .gt: return .lt
    case .ge: return .le
    default: return op
    }
  }

  private func criteriaTestFromComparison(criterion: CellValue, op: BinaryOp) -> CriteriaTest? {
    guard let criteriaOp = binaryOpToCriteriaOp(op) else { return nil }
    if criteriaOp == .ne {
      if case .string(let text) = criterion, text.isEmpty {
        return CriteriaTest(op: .ne, number: nil, text: "", wildcard: false, blank: true)
      }
      if case .blank = criterion {
        return CriteriaTest(op: .ne, number: nil, text: "", wildcard: false, blank: true)
      }
    }
    var test = criteriaTest(from: criterion)
    if test.wildcard { return nil }
    test.op = criteriaOp
    return test
  }

  private func binaryOpToCriteriaOp(_ op: BinaryOp) -> CriteriaOp? {
    switch op {
    case .eq: return .eq
    case .ne: return .ne
    case .lt: return .lt
    case .le: return .le
    case .gt: return .gt
    case .ge: return .ge
    default: return nil
    }
  }

  private func sumProductAnchorIndex(_ anchor: RangeAnchor, anchors: inout [RangeAnchor]) -> Int {
    if let index = anchors.firstIndex(where: { sameSumProductAnchorShape($0, anchor) }) {
      return index
    }
    anchors.append(anchor)
    return anchors.count - 1
  }

  private func sameSumProductAnchorShape(_ lhs: RangeAnchor, _ rhs: RangeAnchor) -> Bool {
    (lhs.sheet ?? "").caseInsensitiveCompare(rhs.sheet ?? "") == .orderedSame
      && lhs.row == rhs.row && lhs.col == rhs.col && lhs.rows == rhs.rows && lhs.cols == rhs.cols
  }

  private func mixSumProductAnchor(_ anchor: RangeAnchor, into hasher: inout Hasher) {
    hasher.combine((anchor.sheet ?? "").lowercased())
    hasher.combine(anchor.row)
    hasher.combine(anchor.col)
    hasher.combine(anchor.rows)
    hasher.combine(anchor.cols)
  }

  private func mixStaticCriteriaTest(_ test: CriteriaTest, into hasher: inout Hasher) {
    hasher.combine(test.op.hashValue)
    hasher.combine(test.number ?? 0)
    hasher.combine(test.text)
    hasher.combine(test.wildcard)
    hasher.combine(test.blank)
  }

  private func excelRound(_ value: Double, places: Int, mode: NSDecimalNumber.RoundingMode) -> Double {
    // Foundation rounds toward ±infinity. Excel ROUNDUP is away from zero and ROUNDDOWN is toward zero,
    // so the sign is applied after rounding the magnitude.
    let negative = value < 0
    let magnitude = abs(value)
    let source = Decimal(string: String(magnitude)) ?? Decimal(magnitude)
    var input = source
    var output = Decimal()
    NSDecimalRound(&output, &input, places, mode)
    let rounded = NSDecimalNumber(decimal: output).doubleValue
    return negative ? -rounded : rounded
  }
}
