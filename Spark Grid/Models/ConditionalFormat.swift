import Foundation

/// Overlay style applied when a conditional formatting rule matches.
/// Only non-nil fields are applied (Excel dxf semantics).
struct ConditionalFormatStyle: Codable, Equatable, Hashable, Sendable {
  var bold: Bool?
  var textColor: CodableColor?
  var fillColor: CodableColor?

  static let redFill = ConditionalFormatStyle(
    fillColor: CodableColor(red: 0.96, green: 0.78, blue: 0.78, alpha: 1)
  )

  static let yellowFill = ConditionalFormatStyle(
    fillColor: CodableColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 1)
  )

  static let greenFill = ConditionalFormatStyle(
    fillColor: CodableColor(red: 0.78, green: 0.94, blue: 0.78, alpha: 1)
  )

  func applying(to base: CellFormat) -> CellFormat {
    var result = base
    if let bold { result.bold = bold }
    if let textColor { result.textColor = textColor }
    if let fillColor { result.fillColor = fillColor }
    return result
  }

  var hasAny: Bool {
    bold != nil || textColor != nil || fillColor != nil
  }
}

struct ColorScaleStop: Codable, Equatable, Sendable {
  enum StopType: String, Codable, Sendable {
    case min
    case max
    case number
    case percent
    case percentile
  }

  var type: StopType
  var value: Double?
  var color: CodableColor
}

struct DataBarStyle: Codable, Equatable, Sendable {
  var color: CodableColor
  var showValue: Bool

  static let blue = DataBarStyle(
    color: CodableColor(red: 0.39, green: 0.58, blue: 0.93, alpha: 1),
    showValue: true
  )

  static let green = DataBarStyle(
    color: CodableColor(red: 0.39, green: 0.78, blue: 0.47, alpha: 1),
    showValue: true
  )
}

enum IconSetStyle: String, Codable, Sendable, CaseIterable {
  case threeTrafficLights
  case threeArrows
  case threeSymbols

  var title: String {
    switch self {
    case .threeTrafficLights: return "3 Traffic Lights"
    case .threeArrows: return "3 Arrows"
    case .threeSymbols: return "3 Symbols"
    }
  }

  /// Excel `iconSet` attribute.
  var excelName: String {
    switch self {
    case .threeTrafficLights: return "3TrafficLights1"
    case .threeArrows: return "3Arrows"
    case .threeSymbols: return "3Symbols"
    }
  }

  static func fromExcelName(_ name: String) -> IconSetStyle? {
    switch name {
    case "3TrafficLights1", "3TrafficLights2": return .threeTrafficLights
    case "3Arrows", "3ArrowsGray": return .threeArrows
    case "3Symbols", "3Symbols2": return .threeSymbols
    default: return nil
    }
  }
}

enum IconSetGlyph: String, Codable, Sendable {
  case greenCircle, yellowCircle, redCircle
  case greenArrow, yellowArrow, redArrow
  case greenCheck, yellowDash, redX
}

/// Resolved conditional paint for a cell (format overlays + decorations).
struct ConditionalPaint: Equatable, Sendable {
  var format: CellFormat?
  var dataBarFraction: Double?
  var dataBarColor: CodableColor?
  var dataBarShowValue: Bool = true
  var icon: IconSetGlyph?

  var hasDecoration: Bool {
    dataBarFraction != nil || icon != nil
  }
}

enum ConditionalFormatPredicate: Codable, Equatable, Sendable {
  case greaterThan(Double)
  case lessThan(Double)
  case greaterOrEqual(Double)
  case lessOrEqual(Double)
  case equal(Double)
  case between(Double, Double)
  case textContains(String)
  case blanks
  case nonBlanks
  /// Formula relative to the top-left of the rule range (Excel-style).
  case formula(String)
  /// 2- or 3-color scale; style fills come from interpolation, not `rule.style`.
  case colorScale([ColorScaleStop])
  case dataBar(DataBarStyle)
  case iconSet(IconSetStyle)

  var title: String {
    switch self {
    case .greaterThan(let v): return "Cell value > \(formatNumber(v))"
    case .lessThan(let v): return "Cell value < \(formatNumber(v))"
    case .greaterOrEqual(let v): return "Cell value ≥ \(formatNumber(v))"
    case .lessOrEqual(let v): return "Cell value ≤ \(formatNumber(v))"
    case .equal(let v): return "Cell value = \(formatNumber(v))"
    case .between(let a, let b): return "Cell value between \(formatNumber(a)) and \(formatNumber(b))"
    case .textContains(let s): return "Text contains “\(s)”"
    case .blanks: return "Blanks"
    case .nonBlanks: return "Non-blanks"
    case .formula(let f): return "Formula: \(f)"
    case .colorScale(let stops): return "Color scale (\(stops.count) stops)"
    case .dataBar: return "Data bars"
    case .iconSet(let style): return "Icon set: \(style.title)"
    }
  }

  private func formatNumber(_ value: Double) -> String {
    if value.rounded() == value, abs(value) < 1e12 {
      return String(Int(value))
    }
    return String(value)
  }
}

struct ConditionalFormatRule: Identifiable, Codable, Equatable, Sendable {
  var id: UUID
  var range: CellRange
  var stopIfTrue: Bool
  var predicate: ConditionalFormatPredicate
  var style: ConditionalFormatStyle

  init(
    id: UUID = UUID(),
    range: CellRange,
    stopIfTrue: Bool = true,
    predicate: ConditionalFormatPredicate,
    style: ConditionalFormatStyle = ConditionalFormatStyle()
  ) {
    self.id = id
    self.range = range
    self.stopIfTrue = stopIfTrue
    self.predicate = predicate
    self.style = style
  }
}

enum ConditionalFormatEvaluator {
  /// Resolves base format plus matching conditional overlays for a cell.
  static func resolvedPaint(
    at address: CellAddress,
    base: CellFormat?,
    rules: [ConditionalFormatRule],
    value: CellValue,
    displayString: String,
    numberFormat: CellFormat.NumberFormat?,
    numericValuesInRange: (CellRange) -> [Double],
    evaluateFormula: (String, CellAddress, CellAddress) -> CellValue
  ) -> ConditionalPaint {
    guard !rules.isEmpty else {
      return ConditionalPaint(format: base)
    }
    var result = base ?? CellFormat()
    var applied = false
    var paint = ConditionalPaint(format: base)

    for rule in rules {
      guard rule.range.contains(address) else { continue }
      let origin = CellAddress(
        row: rule.range.normalized.minRow,
        col: rule.range.normalized.minCol
      )

      switch rule.predicate {
      case .colorScale(let stops):
        guard let fill = colorScaleFill(
          stops: stops,
          value: value,
          range: rule.range,
          numericValuesInRange: numericValuesInRange
        ) else { continue }
        result.fillColor = fill
        paint.format = result.isDefault ? nil : result
        applied = true
        if rule.stopIfTrue { break }

      case .dataBar(let style):
        guard let fraction = dataBarFraction(
          value: value,
          range: rule.range,
          numericValuesInRange: numericValuesInRange
        ) else { continue }
        paint.dataBarFraction = fraction
        paint.dataBarColor = style.color
        paint.dataBarShowValue = style.showValue
        applied = true
        if rule.stopIfTrue { break }

      case .iconSet(let style):
        guard let glyph = iconGlyph(
          style: style,
          value: value,
          range: rule.range,
          numericValuesInRange: numericValuesInRange
        ) else { continue }
        paint.icon = glyph
        applied = true
        if rule.stopIfTrue { break }

      default:
        guard matches(
          rule.predicate,
          value: value,
          displayString: displayString,
          numberFormat: numberFormat,
          address: address,
          origin: origin,
          evaluateFormula: evaluateFormula
        ) else { continue }

        result = rule.style.applying(to: result)
        paint.format = result.isDefault ? nil : result
        applied = true
        if rule.stopIfTrue { break }
      }
    }

    if !applied {
      return ConditionalPaint(format: base)
    }
    if paint.format == nil, !result.isDefault {
      paint.format = result
    }
    return paint
  }

  /// Convenience for callers that only need the format overlay.
  static func resolvedFormat(
    at address: CellAddress,
    base: CellFormat?,
    rules: [ConditionalFormatRule],
    value: CellValue,
    displayString: String,
    numberFormat: CellFormat.NumberFormat?,
    numericValuesInRange: (CellRange) -> [Double],
    evaluateFormula: (String, CellAddress, CellAddress) -> CellValue
  ) -> CellFormat? {
    resolvedPaint(
      at: address,
      base: base,
      rules: rules,
      value: value,
      displayString: displayString,
      numberFormat: numberFormat,
      numericValuesInRange: numericValuesInRange,
      evaluateFormula: evaluateFormula
    ).format
  }

  static func matches(
    _ predicate: ConditionalFormatPredicate,
    value: CellValue,
    displayString: String,
    numberFormat: CellFormat.NumberFormat?,
    address: CellAddress,
    origin: CellAddress,
    evaluateFormula: (String, CellAddress, CellAddress) -> CellValue
  ) -> Bool {
    switch predicate {
    case .blanks:
      return value == .blank || displayString.isEmpty
    case .nonBlanks:
      return value != .blank && !displayString.isEmpty
    case .textContains(let needle):
      guard !needle.isEmpty else { return false }
      return displayString.localizedCaseInsensitiveContains(needle)
    case .greaterThan(let n):
      guard let v = compareNumber(value, threshold: n, numberFormat: numberFormat) else { return false }
      return v.cell > v.threshold
    case .lessThan(let n):
      guard let v = compareNumber(value, threshold: n, numberFormat: numberFormat) else { return false }
      return v.cell < v.threshold
    case .greaterOrEqual(let n):
      guard let v = compareNumber(value, threshold: n, numberFormat: numberFormat) else { return false }
      return v.cell >= v.threshold
    case .lessOrEqual(let n):
      guard let v = compareNumber(value, threshold: n, numberFormat: numberFormat) else { return false }
      return v.cell <= v.threshold
    case .equal(let n):
      guard let v = compareNumber(value, threshold: n, numberFormat: numberFormat) else { return false }
      return abs(v.cell - v.threshold) < 1e-9
    case .between(let a, let b):
      guard let loPair = compareNumber(value, threshold: a, numberFormat: numberFormat),
            let hiPair = compareNumber(value, threshold: b, numberFormat: numberFormat)
      else { return false }
      let lo = min(loPair.threshold, hiPair.threshold)
      let hi = max(loPair.threshold, hiPair.threshold)
      return loPair.cell >= lo && loPair.cell <= hi
    case .formula(let raw):
      let result = evaluateFormula(raw, address, origin)
      if case .error = result { return false }
      return result.asBool == true || (result.asNumber ?? 0) != 0
    case .colorScale, .dataBar, .iconSet:
      return false
    }
  }

  /// When the cell is percent-formatted, compare using display percentage (×100)
  /// so a rule “> 50” matches `100%` stored as `1.0`.
  private static func compareNumber(
    _ value: CellValue,
    threshold: Double,
    numberFormat: CellFormat.NumberFormat?
  ) -> (cell: Double, threshold: Double)? {
    guard let raw = value.asNumber else { return nil }
    if numberFormat == .percent {
      return (raw * 100, threshold)
    }
    return (raw, threshold)
  }

  private static func dataBarFraction(
    value: CellValue,
    range: CellRange,
    numericValuesInRange: (CellRange) -> [Double]
  ) -> Double? {
    guard let cellValue = value.asNumber else { return nil }
    let values = numericValuesInRange(range)
    guard !values.isEmpty else { return nil }
    let dataMin = min(0, values.min() ?? 0)
    let dataMax = values.max() ?? cellValue
    let span = dataMax - dataMin
    if span <= 0 { return cellValue > 0 ? 1 : 0 }
    return min(1, max(0, (cellValue - dataMin) / span))
  }

  private static func iconGlyph(
    style: IconSetStyle,
    value: CellValue,
    range: CellRange,
    numericValuesInRange: (CellRange) -> [Double]
  ) -> IconSetGlyph? {
    guard let cellValue = value.asNumber else { return nil }
    let values = numericValuesInRange(range).sorted()
    guard !values.isEmpty else { return nil }
    let p67 = percentile(values, p: 67)
    let p33 = percentile(values, p: 33)
    let tier: Int
    if cellValue >= p67 {
      tier = 0
    } else if cellValue >= p33 {
      tier = 1
    } else {
      tier = 2
    }
    switch style {
    case .threeTrafficLights:
      return [.greenCircle, .yellowCircle, .redCircle][tier]
    case .threeArrows:
      return [.greenArrow, .yellowArrow, .redArrow][tier]
    case .threeSymbols:
      return [.greenCheck, .yellowDash, .redX][tier]
    }
  }

  private static func colorScaleFill(
    stops: [ColorScaleStop],
    value: CellValue,
    range: CellRange,
    numericValuesInRange: (CellRange) -> [Double]
  ) -> CodableColor? {
    guard let cellValue = value.asNumber, stops.count >= 2 else { return nil }
    let values = numericValuesInRange(range)
    guard !values.isEmpty else { return nil }
    let dataMin = values.min() ?? cellValue
    let dataMax = values.max() ?? cellValue
    let resolved = stops.map { stop -> (position: Double, color: CodableColor) in
      let position: Double
      switch stop.type {
      case .min:
        position = dataMin
      case .max:
        position = dataMax
      case .number:
        position = stop.value ?? dataMin
      case .percent:
        let pct = (stop.value ?? 0) / 100
        position = dataMin + (dataMax - dataMin) * pct
      case .percentile:
        position = percentile(values.sorted(), p: stop.value ?? 50)
      }
      return (position, stop.color)
    }.sorted { $0.position < $1.position }

    guard let first = resolved.first, let last = resolved.last else { return nil }
    if cellValue <= first.position { return first.color }
    if cellValue >= last.position { return last.color }
    for index in 0..<(resolved.count - 1) {
      let a = resolved[index]
      let b = resolved[index + 1]
      if cellValue >= a.position && cellValue <= b.position {
        let span = b.position - a.position
        let t = span == 0 ? 0 : (cellValue - a.position) / span
        return interpolate(a.color, b.color, t: t)
      }
    }
    return last.color
  }

  private static func percentile(_ sorted: [Double], p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let clamped = min(100, max(0, p))
    if sorted.count == 1 { return sorted[0] }
    let rank = (clamped / 100) * Double(sorted.count - 1)
    let lo = Int(rank.rounded(.down))
    let hi = min(sorted.count - 1, lo + 1)
    let frac = rank - Double(lo)
    return sorted[lo] * (1 - frac) + sorted[hi] * frac
  }

  private static func interpolate(_ a: CodableColor, _ b: CodableColor, t: Double) -> CodableColor {
    let u = min(1, max(0, t))
    return CodableColor(
      red: a.red + (b.red - a.red) * u,
      green: a.green + (b.green - a.green) * u,
      blue: a.blue + (b.blue - a.blue) * u,
      alpha: a.alpha + (b.alpha - a.alpha) * u
    )
  }
}
