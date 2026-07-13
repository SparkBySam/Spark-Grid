import Foundation

nonisolated enum FormulaError: Equatable, Sendable, CaseIterable {
  case divZero
  case ref
  case value
  /// Multi-cell / array result forced into a single cell (Sheets-style `#VALUE!`).
  case arrayResult
  case name
  case cycle
  case na
  case error

  /// What appears in the cell (e.g. `#VALUE!`).
  var displayCode: String {
    switch self {
    case .divZero: return "#DIV/0!"
    case .ref: return "#REF!"
    case .value, .arrayResult: return "#VALUE!"
    case .name: return "#NAME?"
    case .cycle: return "#CYCLE!"
    case .na: return "#N/A"
    case .error: return "#ERROR!"
    }
  }

  /// Short Sheets-style explanation of what went wrong.
  var explanation: String {
    switch self {
    case .divZero:
      return "Division by zero."
    case .ref:
      return "Invalid cell reference. The formula points at a cell that doesn’t exist (often after deleting rows or columns)."
    case .value:
      return "Wrong type of argument or operand. Check that values and ranges are the kinds this formula expects."
    case .arrayResult:
      return "This formula produces more than one value, but it sits in a single cell. Wrap it in SUM(…) to combine the results, or use ARRAYFORMULA to fill a range."
    case .name:
      return "Unknown function or named range. Check the spelling, or define the name under Sheet → Define Named Range…"
    case .cycle:
      return "Circular reference. This formula depends on itself (directly or through other cells)."
    case .na:
      return "Value not available. A lookup didn’t find a match."
    case .error:
      return "Couldn’t parse or evaluate this formula. Check for typos, missing parentheses, or unsupported syntax."
    }
  }

  init?(displayCode code: String) {
    switch code.uppercased() {
    case "#DIV/0!": self = .divZero
    case "#REF!": self = .ref
    case "#VALUE!": self = .value
    case "#NAME?": self = .name
    case "#CYCLE!": self = .cycle
    case "#N/A": self = .na
    case "#ERROR!": self = .error
    default: return nil
    }
  }
}

nonisolated enum CellValue: Equatable, Sendable {
  case number(Double)
  case string(String)
  case bool(Bool)
  case blank
  case error(FormulaError)

  var isError: Bool {
    if case .error = self { return true }
    return false
  }

  var formulaError: FormulaError? {
    if case .error(let e) = self { return e }
    return nil
  }

  var displayString: String {
    switch self {
    case .number(let n):
      if n.rounded() == n, abs(n) < 1e15 {
        return String(Int(n))
      }
      var text = String(n)
      if text.hasSuffix(".0") {
        text = String(text.dropLast(2))
      }
      return text
    case .string(let s):
      return s
    case .bool(let b):
      return b ? "TRUE" : "FALSE"
    case .blank:
      return ""
    case .error(let e):
      return e.displayCode
    }
  }

  var asNumber: Double? {
    switch self {
    case .number(let n): return n
    case .bool(let b): return b ? 1 : 0
    case .blank: return 0
    case .string(let s):
      let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { return 0 }
      return Double(trimmed.replacingOccurrences(of: ",", with: ""))
    case .error:
      return nil
    }
  }

  var asBool: Bool? {
    switch self {
    case .bool(let b): return b
    case .number(let n): return n != 0
    case .string(let s):
      let upper = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
      if upper == "TRUE" { return true }
      if upper == "FALSE" { return false }
      return nil
    case .blank: return false
    case .error: return nil
    }
  }

  var asString: String {
    switch self {
    case .string(let s): return s
    case .number, .bool, .blank, .error: return displayString
    }
  }

  static func fromLiteralRaw(_ raw: String) -> CellValue {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return .blank }
    let upper = trimmed.uppercased()
    if upper == "TRUE" { return .bool(true) }
    if upper == "FALSE" { return .bool(false) }
    if let number = Double(trimmed.replacingOccurrences(of: ",", with: "")) {
      return .number(number)
    }
    if trimmed.hasPrefix("$"),
       let number = Double(String(trimmed.dropFirst()).replacingOccurrences(of: ",", with: ""))
    {
      return .number(number)
    }
    if trimmed.hasSuffix("%"),
       let number = Double(
         String(trimmed.dropLast())
           .trimmingCharacters(in: .whitespaces)
           .replacingOccurrences(of: ",", with: "")
       )
    {
      return .number(number / 100)
    }
    return .string(trimmed)
  }
}
