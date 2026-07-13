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
    style: ConditionalFormatStyle
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
  static func resolvedFormat(
    at address: CellAddress,
    base: CellFormat?,
    rules: [ConditionalFormatRule],
    value: CellValue,
    displayString: String,
    evaluateFormula: (String, CellAddress, CellAddress) -> CellValue
  ) -> CellFormat? {
    guard !rules.isEmpty else { return base }
    var result = base ?? CellFormat()
    var applied = false

    for rule in rules {
      guard rule.range.contains(address) else { continue }
      let origin = CellAddress(
        row: rule.range.normalized.minRow,
        col: rule.range.normalized.minCol
      )
      guard matches(
        rule.predicate,
        value: value,
        displayString: displayString,
        address: address,
        origin: origin,
        evaluateFormula: evaluateFormula
      ) else { continue }

      result = rule.style.applying(to: result)
      applied = true
      if rule.stopIfTrue { break }
    }

    if !applied { return base }
    return result.isDefault ? nil : result
  }

  static func matches(
    _ predicate: ConditionalFormatPredicate,
    value: CellValue,
    displayString: String,
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
      guard let v = value.asNumber else { return false }
      return v > n
    case .lessThan(let n):
      guard let v = value.asNumber else { return false }
      return v < n
    case .greaterOrEqual(let n):
      guard let v = value.asNumber else { return false }
      return v >= n
    case .lessOrEqual(let n):
      guard let v = value.asNumber else { return false }
      return v <= n
    case .equal(let n):
      guard let v = value.asNumber else { return false }
      return v == n
    case .between(let a, let b):
      guard let v = value.asNumber else { return false }
      let lo = min(a, b)
      let hi = max(a, b)
      return v >= lo && v <= hi
    case .formula(let raw):
      let result = evaluateFormula(raw, address, origin)
      if case .error = result { return false }
      return result.asBool == true || (result.asNumber ?? 0) != 0
    }
  }
}
