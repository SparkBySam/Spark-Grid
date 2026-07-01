import Foundation

struct Cell: Codable, Equatable, Sendable {
    var raw: String = ""
    var format: CellFormat?

    var displayText: String { raw }

    var isEmpty: Bool { raw.isEmpty && format == nil }
}
