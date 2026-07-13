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
  var fontFamily: String?
  var fontSize: CGFloat?
  var decimalPlaces: Int?
  var wrapText = false
  var textRotation: Int = 0
  var borders: CellBorders = .none

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
}
