import Foundation

/// Stable identity for a rectangular range used by conditional aggregates (COUNTIFS, SUMIFS, …).
struct AggregateRangeKey: Hashable {
  var sheet: String
  var minRow: Int
  var minCol: Int
  var maxRow: Int
  var maxCol: Int

  init(sheet: String?, row: Int, col: Int, rows: Int, cols: Int) {
    self.sheet = (sheet ?? "").lowercased()
    self.minRow = row
    self.minCol = col
    self.maxRow = row + rows - 1
    self.maxCol = col + cols - 1
  }

  func contains(address: CellAddress) -> Bool {
    address.row >= minRow && address.row <= maxRow && address.col >= minCol && address.col <= maxCol
  }
}

/// Normalized cell value for equality-based aggregate histograms (COUNTIFS / SUMIFS lookups).
struct AggregateValueKey: Hashable {
  enum Kind: UInt8 {
    case blank = 0
    case number = 1
    case text = 2
    case bool = 3
  }

  var kind: Kind
  var numberBits: UInt64
  var text: String

  static func from(cellValue: CellValue) -> AggregateValueKey? {
    switch cellValue {
    case .error:
      return nil
    case .blank:
      return AggregateValueKey(kind: .blank, numberBits: 0, text: "")
    case .number(let number):
      return AggregateValueKey(kind: .number, numberBits: number.bitPattern, text: "")
    case .bool(let flag):
      return AggregateValueKey(kind: .bool, numberBits: flag ? 1 : 0, text: "")
    case .string(let raw):
      return AggregateValueKey(kind: .text, numberBits: 0, text: raw.lowercased())
    }
  }
}

struct AggregateCriteriaTupleKey: Hashable {
  var parts: [AggregateValueKey]
}

private struct CompositeCountIndexKey: Hashable {
  var rangeKeys: [AggregateRangeKey]
}

private struct CompositeSumIndexKey: Hashable {
  var criteriaRangeKeys: [AggregateRangeKey]
  var sumRangeKey: AggregateRangeKey
}

private struct MaskedCountIndexKey: Hashable {
  var rangeKey: AggregateRangeKey
  var staticMaskKey: UInt64
}

struct AggregateSumBucket {
  var count: Int = 0
  var sum: Double = 0
}

/// One scan per criteria range, then O(1) COUNTIFS / SUMIFS lookups via composite histograms.
final class FormulaAggregateRangeCache {
  weak var profile: FormulaRecalcProfile?
  /// Reads cell values directly from the workbook model (no per-cell formula eval).
  var workbookBulkLoader: ((AggregateRangeKey) -> [CellValue])?
  private var snapshots: [AggregateRangeKey: [CellValue]] = [:]
  private var countIndexes: [CompositeCountIndexKey: [AggregateCriteriaTupleKey: Int]] = [:]
  private var sumIndexes: [CompositeSumIndexKey: [AggregateCriteriaTupleKey: AggregateSumBucket]] = [:]
  private var booleanStaticMasks: [UInt64: [Bool]] = [:]
  private var maskedCountIndexes: [MaskedCountIndexKey: [AggregateValueKey: Int]] = [:]

  func invalidateAll() {
    snapshots.removeAll(keepingCapacity: true)
    countIndexes.removeAll(keepingCapacity: true)
    sumIndexes.removeAll(keepingCapacity: true)
    booleanStaticMasks.removeAll(keepingCapacity: true)
    maskedCountIndexes.removeAll(keepingCapacity: true)
  }

  func invalidate(sheetName: String, address: CellAddress) {
    let sheet = sheetName.lowercased()
    var removedKeys: Set<AggregateRangeKey> = []
    snapshots = snapshots.filter { key, _ in
      if key.sheet == sheet && key.contains(address: address) {
        removedKeys.insert(key)
        return false
      }
      return true
    }
    guard !removedKeys.isEmpty else { return }
    countIndexes = countIndexes.filter { !usesAnyRange($0.key.rangeKeys, in: removedKeys) }
    sumIndexes = sumIndexes.filter {
      !usesAnyRange($0.key.criteriaRangeKeys, in: removedKeys) && !removedKeys.contains($0.key.sumRangeKey)
    }
    maskedCountIndexes = maskedCountIndexes.filter { !removedKeys.contains($0.key.rangeKey) }
    booleanStaticMasks.removeAll(keepingCapacity: true)
  }

  func countForMaskedCriteria(
    rangeKey: AggregateRangeKey,
    column: [CellValue],
    staticMaskKey: UInt64,
    mask: [Bool],
    criteriaKey: AggregateValueKey
  ) -> Int {
    let indexKey = MaskedCountIndexKey(rangeKey: rangeKey, staticMaskKey: staticMaskKey)
    let map = maskedCountIndexes[indexKey] ?? buildMaskedCountIndex(
      indexKey: indexKey,
      column: column,
      mask: mask
    )
    return map[criteriaKey, default: 0]
  }

  func booleanStaticMask(key: UInt64, rowCount: Int, build: (Int) -> Bool) -> [Bool] {
    if let cached = booleanStaticMasks[key], cached.count == rowCount {
      return cached
    }
    var mask = [Bool]()
    mask.reserveCapacity(rowCount)
    for row in 0..<rowCount {
      mask.append(build(row))
    }
    booleanStaticMasks[key] = mask
    return mask
  }

  func rowMajorValues(
    key: AggregateRangeKey,
    count: Int,
    fill: (Int) -> CellValue
  ) -> [CellValue] {
    if let cached = snapshots[key] {
      return cached
    }
    let buildStart = CFAbsoluteTimeGetCurrent()
    let values: [CellValue]
    if let bulk = workbookBulkLoader?(key), bulk.count == count {
      values = bulk
    } else {
      var built = [CellValue]()
      built.reserveCapacity(count)
      for index in 0..<count {
        built.append(fill(index))
      }
      values = built
    }
    snapshots[key] = values
    profile?.aggregateIndexBuildSeconds += CFAbsoluteTimeGetCurrent() - buildStart
    return values
  }

  func countForCriteria(
    rangeKeys: [AggregateRangeKey],
    columns: [[CellValue]],
    criteriaKeys: [AggregateValueKey]
  ) -> Int {
    let indexKey = CompositeCountIndexKey(rangeKeys: rangeKeys)
    let map = countIndexes[indexKey] ?? buildCountIndex(indexKey: indexKey, columns: columns)
    return map[AggregateCriteriaTupleKey(parts: criteriaKeys), default: 0]
  }

  func sumByRowFilter(
    sumColumn: [CellValue],
    includeRow: (Int) -> Bool
  ) -> AggregateSumBucket {
    var bucket = AggregateSumBucket()
    for row in 0..<sumColumn.count {
      guard includeRow(row) else { continue }
      let value = sumColumn[row]
      guard case .number(let number) = value else { continue }
      bucket.count += 1
      bucket.sum += number
    }
    return bucket
  }

  func sumForCriteria(
    criteriaRangeKeys: [AggregateRangeKey],
    sumRangeKey: AggregateRangeKey,
    criteriaColumns: [[CellValue]],
    sumColumn: [CellValue],
    criteriaKeys: [AggregateValueKey]
  ) -> AggregateSumBucket {
    let indexKey = CompositeSumIndexKey(criteriaRangeKeys: criteriaRangeKeys, sumRangeKey: sumRangeKey)
    let map = sumIndexes[indexKey] ?? buildSumIndex(
      indexKey: indexKey,
      criteriaColumns: criteriaColumns,
      sumColumn: sumColumn
    )
    return map[AggregateCriteriaTupleKey(parts: criteriaKeys), default: AggregateSumBucket()]
  }

  private func usesAnyRange(_ keys: [AggregateRangeKey], in removed: Set<AggregateRangeKey>) -> Bool {
    keys.contains(where: { removed.contains($0) })
  }

  private func buildCountIndex(
    indexKey: CompositeCountIndexKey,
    columns: [[CellValue]]
  ) -> [AggregateCriteriaTupleKey: Int] {
    let buildStart = CFAbsoluteTimeGetCurrent()
    defer {
      profile?.aggregateIndexBuildSeconds += CFAbsoluteTimeGetCurrent() - buildStart
    }
    guard let rowCount = columns.first?.count, rowCount > 0 else {
      let empty: [AggregateCriteriaTupleKey: Int] = [:]
      countIndexes[indexKey] = empty
      return empty
    }
    var map: [AggregateCriteriaTupleKey: Int] = [:]
    for row in 0..<rowCount {
      var parts: [AggregateValueKey] = []
      parts.reserveCapacity(columns.count)
      var skip = false
      for column in columns {
        guard let key = AggregateValueKey.from(cellValue: column[row]) else {
          skip = true
          break
        }
        parts.append(key)
      }
      if skip { continue }
      let tuple = AggregateCriteriaTupleKey(parts: parts)
      map[tuple, default: 0] += 1
    }
    countIndexes[indexKey] = map
    return map
  }

  private func buildSumIndex(
    indexKey: CompositeSumIndexKey,
    criteriaColumns: [[CellValue]],
    sumColumn: [CellValue]
  ) -> [AggregateCriteriaTupleKey: AggregateSumBucket] {
    let buildStart = CFAbsoluteTimeGetCurrent()
    defer {
      profile?.aggregateIndexBuildSeconds += CFAbsoluteTimeGetCurrent() - buildStart
    }
    let rowCount = sumColumn.count
    guard rowCount > 0 else {
      let empty: [AggregateCriteriaTupleKey: AggregateSumBucket] = [:]
      sumIndexes[indexKey] = empty
      return empty
    }
    var map: [AggregateCriteriaTupleKey: AggregateSumBucket] = [:]
    for row in 0..<rowCount {
      var parts: [AggregateValueKey] = []
      parts.reserveCapacity(criteriaColumns.count)
      var skip = false
      for column in criteriaColumns {
        guard let key = AggregateValueKey.from(cellValue: column[row]) else {
          skip = true
          break
        }
        parts.append(key)
      }
      if skip { continue }
      let sumValue = sumColumn[row]
      guard case .number(let number) = sumValue else { continue }
      let tuple = AggregateCriteriaTupleKey(parts: parts)
      var bucket = map[tuple, default: AggregateSumBucket()]
      bucket.count += 1
      bucket.sum += number
      map[tuple] = bucket
    }
    sumIndexes[indexKey] = map
    return map
  }

  private func buildMaskedCountIndex(
    indexKey: MaskedCountIndexKey,
    column: [CellValue],
    mask: [Bool]
  ) -> [AggregateValueKey: Int] {
    let buildStart = CFAbsoluteTimeGetCurrent()
    defer {
      profile?.aggregateIndexBuildSeconds += CFAbsoluteTimeGetCurrent() - buildStart
    }
    var map: [AggregateValueKey: Int] = [:]
    let rowCount = min(column.count, mask.count)
    for row in 0..<rowCount {
      guard mask[row] else { continue }
      guard let key = AggregateValueKey.from(cellValue: column[row]) else { continue }
      map[key, default: 0] += 1
    }
    maskedCountIndexes[indexKey] = map
    return map
  }
}
