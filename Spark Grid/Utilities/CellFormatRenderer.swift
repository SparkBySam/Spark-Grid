import AppKit
import Foundation

enum CellFormatRenderer {
  static let defaultFontSize: CGFloat = 12
  static let defaultFontFamily = "Helvetica Neue"

  static let fontFamilies = [
    "Helvetica Neue",
    "Helvetica",
    "Arial",
    "Times New Roman",
    "Georgia",
    "Courier New",
    "Menlo",
  ]

  static func displayText(raw: String, format: CellFormat?) -> String {
    guard let format, !raw.isEmpty else { return raw }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let number = parseNumber(trimmed) else { return raw }

    let places = format.decimalPlaces ?? decimalPlaces(for: format.numberFormat)
    switch format.numberFormat {
    case .general:
      return raw
    case .number:
      return formatNumber(number, places: places)
    case .currency:
      return formatCurrency(number, places: places)
    case .percent:
      return formatPercent(number, places: places)
    case .scientific:
      return String(format: "%.\(places)e", number)
    case .date, .time:
      return raw
    }
  }

  static func attributes(for format: CellFormat?) -> [NSAttributedString.Key: Any] {
    let resolved = format ?? CellFormat()
    var attrs: [NSAttributedString.Key: Any] = [
      .font: font(for: resolved),
      .foregroundColor: nsColor(resolved.textColor) ?? NSColor.labelColor,
    ]

    if resolved.underline {
      attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
    }
    if resolved.strikethrough {
      attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
    }

    let paragraph = NSMutableParagraphStyle()
    switch resolved.horizontalAlign {
    case .general, .left: paragraph.alignment = .left
    case .center: paragraph.alignment = .center
    case .right: paragraph.alignment = .right
    }
    paragraph.lineBreakMode = resolved.wrapText ? .byWordWrapping : .byTruncatingTail
    attrs[.paragraphStyle] = paragraph

    return attrs
  }

  static func drawText(_ text: String, in cellRect: NSRect, format: CellFormat?) {
    let resolved = format ?? CellFormat()
    let attrs = attributes(for: format)
    let inset = cellRect.insetBy(dx: 4, dy: 2)
    guard inset.width > 1, inset.height > 1 else { return }

    if resolved.wrapText {
      (text as NSString).draw(
        with: inset,
        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
        attributes: attrs
      )
      return
    }

    let size = (text as NSString).size(withAttributes: attrs)
    let point = alignedOrigin(for: size, in: inset, format: resolved)
    (text as NSString).draw(at: point, withAttributes: attrs)
  }

  static func measuredWidth(for text: String, format: CellFormat?) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    let attrs = attributes(for: format)
    return (text as NSString).size(withAttributes: attrs).width
  }

  static func measuredHeight(for text: String, format: CellFormat?) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    let attrs = attributes(for: format)
    return (text as NSString).size(withAttributes: attrs).height
  }

  private static func alignedOrigin(for size: NSSize, in rect: NSRect, format: CellFormat) -> NSPoint {
    let x: CGFloat
    switch format.horizontalAlign {
    case .center:
      x = rect.midX - size.width / 2
    case .right:
      x = rect.maxX - size.width
    default:
      x = rect.minX
    }

    let y: CGFloat
    switch format.verticalAlign {
    case .top:
      y = rect.minY
    case .middle:
      y = rect.midY - size.height / 2
    case .bottom:
      y = rect.maxY - size.height
    }

    return NSPoint(x: x, y: y)
  }

  static func font(for format: CellFormat) -> NSFont {
    let family = format.fontFamily ?? defaultFontFamily
    let size = format.fontSize ?? defaultFontSize
    var font = NSFont(name: family, size: size) ?? NSFont.systemFont(ofSize: size)

    if format.bold && format.italic {
      font = NSFontManager.shared.convert(font, toHaveTrait: [.boldFontMask, .italicFontMask])
    } else if format.bold {
      font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    } else if format.italic {
      font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }
    return font
  }

  static func fillColor(for format: CellFormat?) -> NSColor? {
    guard let color = format?.fillColor else { return nil }
    return nsColor(color)
  }

  static func nsColor(_ color: CodableColor?) -> NSColor? {
    guard let color else { return nil }
    return NSColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
  }

  static func codableColor(from color: NSColor) -> CodableColor {
    let rgb = color.usingColorSpace(.sRGB) ?? color
    return CodableColor(
      red: Double(rgb.redComponent),
      green: Double(rgb.greenComponent),
      blue: Double(rgb.blueComponent),
      alpha: Double(rgb.alphaComponent)
    )
  }

  // MARK: - Number helpers

  private static func parseNumber(_ text: String) -> Double? {
    let stripped = text
      .replacingOccurrences(of: "$", with: "")
      .replacingOccurrences(of: "%", with: "")
      .replacingOccurrences(of: ",", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return Double(stripped)
  }

  private static func decimalPlaces(for format: CellFormat.NumberFormat) -> Int {
    switch format {
    case .general: return 0
    case .number, .currency: return 2
    case .percent: return 2
    case .scientific: return 2
    case .date, .time: return 0
    }
  }

  private static func formatNumber(_ value: Double, places: Int) -> String {
    String(format: "%.\(places)f", value)
  }

  private static func formatCurrency(_ value: Double, places: Int) -> String {
    "$" + String(format: "%.\(places)f", value)
  }

  private static func formatPercent(_ value: Double, places: Int) -> String {
    let normalized = abs(value) <= 1 ? value * 100 : value
    return String(format: "%.\(places)f%%", normalized)
  }
}

extension CellFormat {
  var isDefault: Bool { self == CellFormat() }
}
