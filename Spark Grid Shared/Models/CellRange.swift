import Foundation

struct CellRange: Codable, Equatable, Sendable {
  var start: CellAddress
  var end: CellAddress

  static let singleOrigin = CellRange(start: .origin, end: .origin)

  var normalized: (minRow: Int, maxRow: Int, minCol: Int, maxCol: Int) {
    (
      min(start.row, end.row),
      max(start.row, end.row),
      min(start.col, end.col),
      max(start.col, end.col)
    )
  }

  func contains(_ address: CellAddress) -> Bool {
    let n = normalized
    return address.row >= n.minRow && address.row <= n.maxRow
      && address.col >= n.minCol && address.col <= n.maxCol
  }

  func allAddresses() -> [CellAddress] {
    let n = normalized
    var addresses: [CellAddress] = []
    for row in n.minRow...n.maxRow {
      for col in n.minCol...n.maxCol {
        addresses.append(CellAddress(row: row, col: col))
      }
    }
    return addresses
  }

  var isSingleCell: Bool {
    start == end
  }
}
