import Foundation

/// Display formatting for a cell.
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
  /// Excel format code (`€#,##0.00`, `dd/mm/yyyy`, or a code typed in Cell Format). Nil uses `numberFormat`.
  var formatCode: String?
  var fontFamily: String?
  var fontSize: CGFloat?
  var decimalPlaces: Int?
  var wrapText = false
  /// Degrees for tilt/rotate, or `stackedTextRotation` (255) for one character per line (Excel OOXML).
  var textRotation: Int = 0
  var borders: CellBorders = .none

  /// Excel OOXML `textRotation="255"` — upright characters stacked top-to-bottom.
  static let stackedTextRotation = 255

  var isStackedVertically: Bool {
    textRotation == Self.stackedTextRotation
  }

  enum HorizontalAlign: String, Codable, Sendable {
    case general, left, center, right
  }

  enum VerticalAlign: String, Codable, Sendable {
    case top, middle, bottom
  }

  enum NumberFormat: String, Codable, Sendable {
    case general, number, currency, percent, scientific, date, time
  }

  /// Code shown in the cell-format viewer. An imported `formatCode` wins; otherwise the builtin code for `numberFormat`.
  var viewerFormatCode: String {
    if let formatCode {
      let trimmed = formatCode.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
    }
    return Self.builtinFormatCode(for: numberFormat, decimalPlaces: decimalPlaces)
  }

  static func builtinFormatCode(for format: NumberFormat, decimalPlaces: Int?) -> String {
    let places = decimalPlaces ?? defaultViewerPlaces(for: format)
    switch format {
    case .general:
      return "General"
    case .number:
      return "0" + fractionZeros(places)
    case .currency:
      return "$0" + fractionZeros(places)
    case .percent:
      return "0" + fractionZeros(places) + "%"
    case .scientific:
      return "0" + fractionZeros(max(places, 2)) + "E+00"
    case .date:
      return "m/d/yyyy"
    case .time:
      return "h:mm:ss AM/PM"
    }
  }

  private static func defaultViewerPlaces(for format: NumberFormat) -> Int {
    switch format {
    case .general, .date, .time: return 0
    case .number, .currency, .percent, .scientific: return 2
    }
  }

  private static func fractionZeros(_ places: Int) -> String {
    guard places > 0 else { return "" }
    return "." + String(repeating: "0", count: places)
  }
}

/// Per-side borders for a cell.
struct CellBorders: Codable, Equatable, Sendable {
  var top: BorderEdge?
  var bottom: BorderEdge?
  var left: BorderEdge?
  var right: BorderEdge?

  static let none = CellBorders()

  var hasAny: Bool {
    top != nil || bottom != nil || left != nil || right != nil
  }
}

struct BorderEdge: Codable, Equatable, Sendable {
  var style: BorderStyle = .thin
  var color: CodableColor?

  static func thin(_ color: CodableColor? = nil) -> BorderEdge {
    BorderEdge(style: .thin, color: color)
  }

  static func medium(_ color: CodableColor? = nil) -> BorderEdge {
    BorderEdge(style: .medium, color: color)
  }

  static func thick(_ color: CodableColor? = nil) -> BorderEdge {
    BorderEdge(style: .thick, color: color)
  }
}

enum BorderStyle: String, Codable, Sendable, CaseIterable {
  case thin
  case medium
  case thick
  case dashed
  case dotted
  case double

  var title: String {
    switch self {
    case .thin: return "Thin"
    case .medium: return "Medium"
    case .thick: return "Thick"
    case .dashed: return "Dashed"
    case .dotted: return "Dotted"
    case .double: return "Double"
    }
  }

  var lineWidth: CGFloat {
    switch self {
    case .thin, .dashed, .dotted: return 1
    case .medium: return 1.5
    case .thick, .double: return 2.5
    }
  }
}

extension BorderEdge {
  static func styled(_ style: BorderStyle, color: CodableColor? = nil) -> BorderEdge {
    BorderEdge(style: style, color: color)
  }
}

/// Toolbar / menu presets for applying borders to a selection.
enum BorderPreset: String, CaseIterable, Sendable {
  case none
  case all
  case outside
  case inside
  case top
  case bottom
  case left
  case right
  case thickOutside

  var title: String {
    switch self {
    case .none: return "No Border"
    case .all: return "All Borders"
    case .outside: return "Outside Borders"
    case .inside: return "Inside Borders"
    case .top: return "Top Border"
    case .bottom: return "Bottom Border"
    case .left: return "Left Border"
    case .right: return "Right Border"
    case .thickOutside: return "Thick Box Border"
    }
  }

  var systemImage: String {
    switch self {
    case .none: return "xmark.rectangle"
    case .all: return "square.grid.3x3"
    case .outside: return "square"
    case .inside: return "square.split.2x2"
    case .top: return "rectangle.topthird.inset.filled"
    case .bottom: return "rectangle.bottomthird.inset.filled"
    case .left: return "rectangle.lefthalf.inset.filled"
    case .right: return "rectangle.righthalf.inset.filled"
    case .thickOutside: return "rectangle.inset.filled"
    }
  }
}

/// Serializable color for document persistence.
struct CodableColor: Codable, Equatable, Hashable, Sendable {
  var red: Double
  var green: Double
  var blue: Double
  var alpha: Double

  /// sRGB relative luminance, 0 (black) through 1 (white).
  var relativeLuminance: Double {
    let r = min(1, max(0, red))
    let g = min(1, max(0, green))
    let b = min(1, max(0, blue))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
  }

  /// Black on a light fill, white on a dark fill.
  static func contrastingText(on fill: CodableColor) -> CodableColor {
    if fill.relativeLuminance < 0.58 {
      return CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
    }
    return CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
  }
}
