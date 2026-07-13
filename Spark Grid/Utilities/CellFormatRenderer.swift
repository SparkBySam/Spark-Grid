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
      // parseNumber strips `%`; recover Excel fraction semantics when raw was a percent literal.
      let value = trimmed.hasSuffix("%") ? number / 100 : number
      return formatPercent(value, places: places)
    case .scientific:
      return String(format: "%.\(places)e", number)
    case .date, .time:
      return raw
    }
  }

  /// Format an evaluated formula/literal value for display.
  static func displayText(for value: CellValue, format: CellFormat?, fallbackRaw: String) -> String {
    switch value {
    case .error:
      return value.displayString
    case .blank:
      return ""
    case .bool, .string:
      return value.displayString
    case .number(let number):
      let trimmed = fallbackRaw.trimmingCharacters(in: .whitespacesAndNewlines)
      let literalPercent = trimmed.hasSuffix("%") && !trimmed.hasPrefix("=")
      let resolvedFormat: CellFormat? = {
        if let format, format.numberFormat != .general { return format }
        if literalPercent {
          var inferred = format ?? CellFormat()
          inferred.numberFormat = .percent
          return inferred
        }
        return format
      }()
      guard let resolvedFormat else { return value.displayString }
      let places = resolvedFormat.decimalPlaces ?? decimalPlaces(for: resolvedFormat.numberFormat)
      switch resolvedFormat.numberFormat {
      case .general:
        return value.displayString
      case .number:
        return formatNumber(number, places: places)
      case .currency:
        return formatCurrency(number, places: places)
      case .percent:
        return formatPercent(number, places: places)
      case .scientific:
        return String(format: "%.\(places)e", number)
      case .date:
        return formatDate(number)
      case .time:
        return formatTime(number)
      }
    }
  }

  static func attributes(for format: CellFormat?, onLightBackground: Bool = false) -> [NSAttributedString.Key: Any] {
    let resolved = format ?? CellFormat()
    let defaultTextColor = onLightBackground ? NSColor.black : NSColor.labelColor
    let textColor: NSColor = {
      if onLightBackground { return NSColor.black }
      return nsColor(resolved.textColor) ?? defaultTextColor
    }()
    var attrs: [NSAttributedString.Key: Any] = [
      .font: font(for: resolved),
      .foregroundColor: textColor,
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

  static func drawSingleLineText(
    _ text: String,
    in rect: NSRect,
    format: CellFormat?,
    onLightBackground: Bool = false
  ) {
    guard !text.isEmpty else { return }
    var attrs = attributes(for: format, onLightBackground: onLightBackground)
    let paragraph = ((attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy()
      as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    attrs[.paragraphStyle] = paragraph

    let size = (text as NSString).size(withAttributes: attrs)
    var drawRect = rect
    drawRect.size.height = max(size.height, 1)
    drawRect.origin.y += (rect.height - drawRect.height) / 2

    (text as NSString).draw(
      with: drawRect,
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: attrs
    )
  }

  static func drawCenteredLabel(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor
  ) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: paragraph,
    ]
    (text as NSString).draw(
      with: rect,
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: attrs
    )
  }

  static func drawText(
    _ text: String,
    in cellRect: NSRect,
    format: CellFormat?,
    onLightBackground: Bool = false,
    verticalAlign: CellFormat.VerticalAlign? = nil
  ) {
    let resolved = format ?? CellFormat()
    let attrs = attributes(for: format, onLightBackground: onLightBackground)
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

    // Fast path: left-aligned, no rotation — skip size measurement.
    let alignment = verticalAlign ?? resolved.verticalAlign
    if resolved.textRotation == 0,
       resolved.horizontalAlign == .general || resolved.horizontalAlign == .left
    {
      let font = attrs[.font] as? NSFont ?? Self.font(for: resolved)
      let height = font.ascender - font.descender
      var point = inset.origin
      switch alignment {
      case .top: break
      case .middle: point.y = inset.midY - height / 2
      case .bottom: point.y = inset.maxY - height
      }
      (text as NSString).draw(at: point, withAttributes: attrs)
      return
    }

    let size = (text as NSString).size(withAttributes: attrs)
    let point = alignedOrigin(for: size, in: inset, horizontalAlign: resolved.horizontalAlign, verticalAlign: alignment)

    if resolved.textRotation != 0 {
      NSGraphicsContext.saveGraphicsState()
      let center = NSPoint(x: inset.midX, y: inset.midY)
      let transform = NSAffineTransform()
      transform.translateX(by: center.x, yBy: center.y)
      transform.rotate(byDegrees: CGFloat(resolved.textRotation))
      transform.translateX(by: -center.x, yBy: -center.y)
      transform.concat()
      (text as NSString).draw(at: point, withAttributes: attrs)
      NSGraphicsContext.restoreGraphicsState()
    } else {
      (text as NSString).draw(at: point, withAttributes: attrs)
    }
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

  private static func alignedOrigin(
    for size: NSSize,
    in rect: NSRect,
    horizontalAlign: CellFormat.HorizontalAlign,
    verticalAlign: CellFormat.VerticalAlign
  ) -> NSPoint {
    let x: CGFloat
    switch horizontalAlign {
    case .center:
      x = rect.midX - size.width / 2
    case .right:
      x = rect.maxX - size.width
    default:
      x = rect.minX
    }

    let y: CGFloat
    switch verticalAlign {
    case .top:
      y = rect.minY
    case .middle:
      y = rect.midY - size.height / 2
    case .bottom:
      y = rect.maxY - size.height
    }

    return NSPoint(x: x, y: y)
  }

  private static var fontCache: [String: NSFont] = [:]

  static func font(for format: CellFormat) -> NSFont {
    let family = format.fontFamily ?? defaultFontFamily
    let size = format.fontSize ?? defaultFontSize
    let key = "\(family)|\(size)|\(format.bold ? 1 : 0)|\(format.italic ? 1 : 0)"
    if let cached = fontCache[key] { return cached }

    var font = NSFont(name: family, size: size) ?? NSFont.systemFont(ofSize: size)
    if format.bold && format.italic {
      font = NSFontManager.shared.convert(font, toHaveTrait: [.boldFontMask, .italicFontMask])
    } else if format.bold {
      font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    } else if format.italic {
      font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }
    fontCache[key] = font
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
    // Excel stores percentages as fractions (0.5 → 50%). Always scale for display.
    String(format: "%.\(places)f%%", value * 100)
  }

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "M/d/yyyy"
    return formatter
  }()

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "h:mm:ss a"
    return formatter
  }()

  private static func formatDate(_ serial: Double) -> String {
    guard let date = ExcelDate.date(from: serial) else {
      return String(serial)
    }
    return dateFormatter.string(from: date)
  }

  private static func formatTime(_ serial: Double) -> String {
    // Excel times are day fractions; full datetimes still show the time component.
    let fraction = serial.truncatingRemainder(dividingBy: 1)
    let dayFraction = fraction < 0 ? fraction + 1 : fraction
    guard let date = ExcelDate.date(from: dayFraction) else {
      return String(serial)
    }
    return timeFormatter.string(from: date)
  }
}

extension CellFormat {
  var isDefault: Bool { self == CellFormat() }
}

extension CellFormatRenderer {
  static func borderColor(for edge: BorderEdge) -> NSColor {
    if let color = edge.color, let ns = nsColor(color) {
      return ns
    }
    return NSColor.labelColor.withAlphaComponent(0.85)
  }

  static func drawBorders(_ borders: CellBorders, in rect: NSRect, scale: CGFloat = 1) {
    drawBordersBatch([(borders, rect)], scale: scale)
  }

  /// Batched border drawing. Shared edges are deduped and collinear runs are merged into
  /// long spans so a dense “all borders” / double-border grid paints like gridlines
  /// (O(rows+cols) strokes) instead of O(cells) short segments.
  static func drawBordersBatch(_ items: [(CellBorders, NSRect)], scale: CGFloat = 1) {
    guard !items.isEmpty else { return }

    struct LineKey: Hashable {
      var vertical: Bool
      var major: Int
      var style: BorderStyle
      var colorKey: UInt64
    }

    // major → list of [start,end] quanta along the line
    var runs: [LineKey: [(Int, Int)]] = [:]
    runs.reserveCapacity(min(items.count, 512))

    func colorKey(for edge: BorderEdge) -> UInt64 {
      guard let c = edge.color else { return 0 }
      let r = UInt64((c.red * 255).rounded())
      let g = UInt64((c.green * 255).rounded())
      let b = UInt64((c.blue * 255).rounded())
      let a = UInt64((c.alpha * 255).rounded())
      return (r << 24) | (g << 16) | (b << 8) | a
    }

    func quantize(_ value: CGFloat) -> Int {
      Int((value * 2).rounded())
    }

    func dequantize(_ value: Int) -> CGFloat {
      CGFloat(value) * 0.5
    }

    func append(_ edge: BorderEdge?, vertical: Bool, major: CGFloat, from: CGFloat, to: CGFloat) {
      guard let edge else { return }
      let a0 = quantize(from)
      let b0 = quantize(to)
      let a = min(a0, b0)
      let b = max(a0, b0)
      guard b > a else { return }
      let key = LineKey(
        vertical: vertical,
        major: quantize(major),
        style: edge.style,
        colorKey: colorKey(for: edge)
      )
      runs[key, default: []].append((a, b))
    }

    for (borders, rect) in items {
      guard borders.hasAny else { continue }
      append(borders.top, vertical: false, major: rect.minY, from: rect.minX, to: rect.maxX)
      append(borders.bottom, vertical: false, major: rect.maxY, from: rect.minX, to: rect.maxX)
      append(borders.left, vertical: true, major: rect.minX, from: rect.minY, to: rect.maxY)
      append(borders.right, vertical: true, major: rect.maxX, from: rect.minY, to: rect.maxY)
    }

    func mergeIntervals(_ intervals: [(Int, Int)]) -> [(Int, Int)] {
      guard !intervals.isEmpty else { return [] }
      let sorted = intervals.sorted { lhs, rhs in
        if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
        return lhs.1 < rhs.1
      }
      var merged: [(Int, Int)] = []
      merged.reserveCapacity(sorted.count)
      var current = sorted[0]
      for i in 1..<sorted.count {
        let next = sorted[i]
        // Allow 1-quantum gaps so adjacent cell edges fuse into one span.
        if next.0 <= current.1 + 1 {
          current.1 = max(current.1, next.1)
        } else {
          merged.append(current)
          current = next
        }
      }
      merged.append(current)
      return merged
    }

    func strokeColor(for key: LineKey) -> NSColor {
      if key.colorKey == 0 {
        return NSColor.labelColor.withAlphaComponent(0.85)
      }
      let r = CGFloat((key.colorKey >> 24) & 0xFF) / 255
      let g = CGFloat((key.colorKey >> 16) & 0xFF) / 255
      let b = CGFloat((key.colorKey >> 8) & 0xFF) / 255
      let a = CGFloat(key.colorKey & 0xFF) / 255
      return NSColor(red: r, green: g, blue: b, alpha: a)
    }

    guard let cg = NSGraphicsContext.current?.cgContext else { return }
    cg.saveGState()
    cg.setShouldAntialias(false)

    for (key, intervals) in runs {
      let merged = mergeIntervals(intervals)
      guard !merged.isEmpty else { continue }
      let color = strokeColor(for: key)
      cg.setStrokeColor(color.cgColor)
      let major = dequantize(key.major)

      switch key.style {
      case .double:
        let inset = 1.5 * scale
        cg.setLineWidth(max(0.5, 1 * scale))
        cg.beginPath()
        for (a, b) in merged {
          let start = dequantize(a)
          let end = dequantize(b)
          if key.vertical {
            cg.move(to: CGPoint(x: major - inset, y: start))
            cg.addLine(to: CGPoint(x: major - inset, y: end))
            cg.move(to: CGPoint(x: major + inset, y: start))
            cg.addLine(to: CGPoint(x: major + inset, y: end))
          } else {
            cg.move(to: CGPoint(x: start, y: major - inset))
            cg.addLine(to: CGPoint(x: end, y: major - inset))
            cg.move(to: CGPoint(x: start, y: major + inset))
            cg.addLine(to: CGPoint(x: end, y: major + inset))
          }
        }
        cg.strokePath()

      case .dashed, .dotted:
        // Dashes still use NSBezierPath (CG dash + many spans is awkward here).
        let path = NSBezierPath()
        let width = max(0.5, key.style.lineWidth * scale)
        path.lineWidth = width
        if key.style == .dashed {
          path.setLineDash([3 * scale, 2 * scale], count: 2, phase: 0)
        } else {
          path.lineCapStyle = .round
          path.setLineDash([0.5 * scale, 2 * scale], count: 2, phase: 0)
        }
        color.setStroke()
        for (a, b) in merged {
          let start = dequantize(a)
          let end = dequantize(b)
          if key.vertical {
            path.move(to: NSPoint(x: major, y: start))
            path.line(to: NSPoint(x: major, y: end))
          } else {
            path.move(to: NSPoint(x: start, y: major))
            path.line(to: NSPoint(x: end, y: major))
          }
        }
        path.stroke()

      case .thin, .medium, .thick:
        let width = max(0.5, key.style.lineWidth * scale)
        cg.setLineWidth(max(width, 1.25 * scale))
        cg.beginPath()
        for (a, b) in merged {
          let start = dequantize(a)
          let end = dequantize(b)
          if key.vertical {
            cg.move(to: CGPoint(x: major, y: start))
            cg.addLine(to: CGPoint(x: major, y: end))
          } else {
            cg.move(to: CGPoint(x: start, y: major))
            cg.addLine(to: CGPoint(x: end, y: major))
          }
        }
        cg.strokePath()
      }
    }

    cg.restoreGState()
  }
}

