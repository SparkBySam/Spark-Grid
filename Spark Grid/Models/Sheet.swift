import CoreGraphics
import Foundation

struct Sheet: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var cells: [CellAddress: Cell]
    var columnWidths: [Int: CGFloat]
    var rowHeights: [Int: CGFloat]
    var frozenRows: Int
    var frozenColumns: Int

    init(
        id: UUID = UUID(),
        name: String,
        cells: [CellAddress: Cell] = [:],
        columnWidths: [Int: CGFloat] = [:],
        rowHeights: [Int: CGFloat] = [:],
        frozenRows: Int = 0,
        frozenColumns: Int = 0
    ) {
        self.id = id
        self.name = name
        self.cells = cells
        self.columnWidths = columnWidths
        self.rowHeights = rowHeights
        self.frozenRows = frozenRows
        self.frozenColumns = frozenColumns
    }

    func cell(at address: CellAddress) -> Cell {
        cells[address] ?? Cell()
    }

    mutating func setCell(_ cell: Cell, at address: CellAddress) {
        if cell.isEmpty {
            cells.removeValue(forKey: address)
        } else {
            cells[address] = cell
        }
    }

    func columnWidth(for col: Int, default defaultWidth: CGFloat) -> CGFloat {
        columnWidths[col] ?? defaultWidth
    }

    func rowHeight(for row: Int, default defaultHeight: CGFloat) -> CGFloat {
        rowHeights[row] ?? defaultHeight
    }

    /// Highest row index that contains data (for CSV export).
    var maxPopulatedRow: Int {
        cells.keys.map(\.row).max() ?? -1
    }

    /// Highest column index that contains data (for CSV export).
    var maxPopulatedColumn: Int {
        cells.keys.map(\.col).max() ?? -1
    }

    /// Tight bounds around every non-empty cell, if any.
    var populatedBounds: CellRange? {
        guard !cells.isEmpty else { return nil }
        let rows = cells.keys.map(\.row)
        let cols = cells.keys.map(\.col)
        return CellRange(
            start: CellAddress(row: rows.min() ?? 0, col: cols.min() ?? 0),
            end: CellAddress(row: rows.max() ?? 0, col: cols.max() ?? 0)
        )
    }

    /// Full used range from A1 through the last populated row/column.
    var populatedRangeFromOrigin: CellRange {
        if maxPopulatedRow < 0 || maxPopulatedColumn < 0 {
            return .singleOrigin
        }
        return CellRange(
            start: .origin,
            end: CellAddress(row: maxPopulatedRow, col: maxPopulatedColumn)
        )
    }

    func wholeSheetRange() -> CellRange {
        CellRange(
            start: .origin,
            end: CellAddress(row: effectiveRowCount - 1, col: effectiveColumnCount - 1)
        )
    }

    /// Grid row count — at least the default, expands when data exceeds it.
    var effectiveRowCount: Int {
        max(Workbook.defaultRowCount, maxPopulatedRow + 1)
    }

    /// Grid column count — at least the default, expands when data exceeds it.
    var effectiveColumnCount: Int {
        max(Workbook.defaultColumnCount, maxPopulatedColumn + 1)
    }
}
