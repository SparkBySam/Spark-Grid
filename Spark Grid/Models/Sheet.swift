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
    var conditionalFormats: [ConditionalFormatRule]
    /// Persisted AutoFilter including selected values when present.
    var autoFilter: SheetFilterState?
    /// Merged cell ranges (inclusive). Top-left is the anchor.
    var mergedRanges: [CellRange]
    /// Embedded charts (Spark-native; also stored in a custom xlsx part).
    var charts: [SheetChart]

    init(
        id: UUID = UUID(),
        name: String,
        cells: [CellAddress: Cell] = [:],
        columnWidths: [Int: CGFloat] = [:],
        rowHeights: [Int: CGFloat] = [:],
        frozenRows: Int = 0,
        frozenColumns: Int = 0,
        conditionalFormats: [ConditionalFormatRule] = [],
        autoFilter: SheetFilterState? = nil,
        mergedRanges: [CellRange] = [],
        charts: [SheetChart] = []
    ) {
        self.id = id
        self.name = name
        self.cells = cells
        self.columnWidths = columnWidths
        self.rowHeights = rowHeights
        self.frozenRows = frozenRows
        self.frozenColumns = frozenColumns
        self.conditionalFormats = conditionalFormats
        self.autoFilter = autoFilter
        self.mergedRanges = mergedRanges
        self.charts = charts
    }

    enum CodingKeys: String, CodingKey {
        case id, name, cells, columnWidths, rowHeights
        case frozenRows, frozenColumns, conditionalFormats, autoFilter
        case mergedRanges, charts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        cells = try c.decodeIfPresent([CellAddress: Cell].self, forKey: .cells) ?? [:]
        columnWidths = try c.decodeIfPresent([Int: CGFloat].self, forKey: .columnWidths) ?? [:]
        rowHeights = try c.decodeIfPresent([Int: CGFloat].self, forKey: .rowHeights) ?? [:]
        frozenRows = try c.decodeIfPresent(Int.self, forKey: .frozenRows) ?? 0
        frozenColumns = try c.decodeIfPresent(Int.self, forKey: .frozenColumns) ?? 0
        conditionalFormats = try c.decodeIfPresent([ConditionalFormatRule].self, forKey: .conditionalFormats) ?? []
        autoFilter = try c.decodeIfPresent(SheetFilterState.self, forKey: .autoFilter)
        mergedRanges = try c.decodeIfPresent([CellRange].self, forKey: .mergedRanges) ?? []
        charts = try c.decodeIfPresent([SheetChart].self, forKey: .charts) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(cells, forKey: .cells)
        try c.encode(columnWidths, forKey: .columnWidths)
        try c.encode(rowHeights, forKey: .rowHeights)
        try c.encode(frozenRows, forKey: .frozenRows)
        try c.encode(frozenColumns, forKey: .frozenColumns)
        try c.encode(conditionalFormats, forKey: .conditionalFormats)
        try c.encodeIfPresent(autoFilter, forKey: .autoFilter)
        try c.encode(mergedRanges, forKey: .mergedRanges)
        try c.encode(charts, forKey: .charts)
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

    // MARK: - Merges

    func mergeContaining(_ address: CellAddress) -> CellRange? {
        mergedRanges.first { $0.contains(address) }
    }

    func isMergeAnchor(_ address: CellAddress) -> Bool {
        guard let merge = mergeContaining(address) else { return true }
        let n = merge.normalized
        return address.row == n.minRow && address.col == n.minCol
    }

    /// Non-anchor cells covered by a merge (should not paint content).
    func isCoveredByMerge(_ address: CellAddress) -> Bool {
        guard let merge = mergeContaining(address) else { return false }
        let n = merge.normalized
        return !(address.row == n.minRow && address.col == n.minCol)
    }

    /// Expands a single cell (or range) to include any intersecting merges.
    func selectionExpandedForMerges(_ range: CellRange) -> CellRange {
        var n = range.normalized
        var changed = true
        while changed {
            changed = false
            for merge in mergedRanges {
                let m = merge.normalized
                let intersects = n.minRow <= m.maxRow && n.maxRow >= m.minRow
                    && n.minCol <= m.maxCol && n.maxCol >= m.minCol
                guard intersects else { continue }
                let next = (
                    minRow: min(n.minRow, m.minRow),
                    maxRow: max(n.maxRow, m.maxRow),
                    minCol: min(n.minCol, m.minCol),
                    maxCol: max(n.maxCol, m.maxCol)
                )
                if next != n {
                    n = next
                    changed = true
                }
            }
        }
        return CellRange(
            start: CellAddress(row: n.minRow, col: n.minCol),
            end: CellAddress(row: n.maxRow, col: n.maxCol)
        )
    }
}
