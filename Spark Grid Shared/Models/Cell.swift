import Foundation

struct Cell: Codable, Equatable, Sendable {
    var raw: String = ""
    var format: CellFormat?
    /// Excel's last calculated `<v>` for a formula cell; seeds the engine until recalc.
    var importedFormulaResult: String?

    var displayText: String { raw }

    var isEmpty: Bool {
        raw.isEmpty && (format == nil || format == CellFormat())
    }
}
