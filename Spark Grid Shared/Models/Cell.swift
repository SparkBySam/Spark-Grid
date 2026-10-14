import Foundation

/// OOXML type of a formula cell's cached `<v>`. Numbers have no `t` attribute.
nonisolated enum ImportedFormulaValueType: String, Codable, Equatable, Sendable {
    case number
    case string
    case boolean
    case error
}

nonisolated struct Cell: Codable, Equatable, Sendable {
    var raw: String = ""
    var format: CellFormat?
    /// Excel's last calculated `<v>` for a formula cell; seeds the engine until recalc.
    var importedFormulaResult: String?
    /// Type of `importedFormulaResult`. Nil means the text has not been classified yet.
    var importedFormulaValueType: ImportedFormulaValueType?

    /// Cached formula result, without calculating. Nil when the cell has no cache.
    var cachedFormulaValue: CellValue? {
        guard let importedFormulaResult else { return nil }
        return CellValue.fromImportedCache(importedFormulaResult, type: importedFormulaValueType)
    }

    var displayText: String { raw }

    var isEmpty: Bool {
        raw.isEmpty && (format == nil || format == CellFormat())
    }
}
