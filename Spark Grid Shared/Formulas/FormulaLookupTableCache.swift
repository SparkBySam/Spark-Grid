import Foundation

struct LookupTableKey: Hashable {
  var sheet: String
  var minRow: Int
  var minCol: Int
  var maxRow: Int
  var maxCol: Int
  var resultIndex: Int
  var horizontal: Bool

  func contains(address: CellAddress) -> Bool {
    address.row >= minRow && address.row <= maxRow && address.col >= minCol && address.col <= maxCol
  }
}

/// Exact-match VLOOKUP / HLOOKUP: one scan per table, then O(1) needle lookup (KPI Config rows).
final class FormulaLookupTableCache {
  private var exactMaps: [LookupTableKey: [AggregateValueKey: CellValue]] = [:]

  func invalidateAll() {
    exactMaps.removeAll(keepingCapacity: true)
  }

  func invalidate(sheetName: String, address: CellAddress) {
    let sheet = sheetName.lowercased()
    exactMaps = exactMaps.filter { key, _ in
      key.sheet != sheet || !key.contains(address: address)
    }
  }

  func exactLookup(
    key: LookupTableKey,
    needle: CellValue,
    build: () -> [AggregateValueKey: CellValue]
  ) -> CellValue? {
    guard let needleKey = AggregateValueKey.from(cellValue: needle) else { return nil }
    let map = exactMaps[key] ?? {
      let built = build()
      exactMaps[key] = built
      return built
    }()
    return map[needleKey]
  }
}
