import Foundation

/// Display formatting for a cell. Phase 1 stores values only; fields are ready for Phase 2.
struct CellFormat: Codable, Equatable, Sendable {
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var horizontalAlign: HorizontalAlign = .general
    var verticalAlign: VerticalAlign = .bottom
    var textColor: CodableColor?
    var fillColor: CodableColor?
    var numberFormat: NumberFormat = .general
    var fontFamily: String?
    var fontSize: CGFloat?
    var decimalPlaces: Int?
    var wrapText = false
    var textRotation: Int = 0

    enum HorizontalAlign: String, Codable, Sendable {
        case general, left, center, right
    }

    enum VerticalAlign: String, Codable, Sendable {
        case top, middle, bottom
    }

    enum NumberFormat: String, Codable, Sendable {
        case general, number, currency, percent, scientific, date, time
    }
}

/// Serializable color for document persistence (Phase 2+).
struct CodableColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
}
