import Foundation

/// Zero-based row and column index into a sheet.
struct CellAddress: Hashable, Codable, Sendable {
    var row: Int
    var col: Int

    static let origin = CellAddress(row: 0, col: 0)
}

extension CellAddress: Comparable {
    static func < (lhs: CellAddress, rhs: CellAddress) -> Bool {
        if lhs.row != rhs.row { return lhs.row < rhs.row }
        return lhs.col < rhs.col
    }
}

extension CellAddress {
    /// Column label for headers and the formula bar (A, B, …, Z, AA, …).
    var columnLabel: String { A1Notation.columnLabel(for: col) }

    /// A1-style reference (e.g. `B3`).
    var a1: String { "\(columnLabel)\(row + 1)" }
}
