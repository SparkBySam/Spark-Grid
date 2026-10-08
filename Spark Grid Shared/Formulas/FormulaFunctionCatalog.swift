import Foundation

/// Insert Function list. Names come from `FormulaFunctions.all`, which is the
/// set the evaluator already calculates. This catalog does not add functions.
enum FormulaFunctionKind: String, CaseIterable, Hashable {
  case math = "Math"
  case statistical = "Statistical"
  case logical = "Logical"
  case text = "Text"
  case lookup = "Lookup"
  case dateTime = "Date & Time"

  var title: String { rawValue }
}

struct FormulaFunctionEntry: Equatable, Identifiable {
  var name: String
  var kind: FormulaFunctionKind
  /// Argument list inside the parentheses. Empty when the function takes none.
  var arguments: String

  var id: String { name }

  /// One line, such as `SUM(number1, [number2], ...)` or `TODAY()`.
  var signatureLine: String {
    arguments.isEmpty ? "\(name)()" : "\(name)(\(arguments))"
  }

  func matches(_ query: String) -> Bool {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if needle.isEmpty { return true }
    if name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
      return true
    }
    if arguments.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
      return true
    }
    return false
  }
}

struct FormulaFunctionGroup: Equatable {
  var kind: FormulaFunctionKind
  var entries: [FormulaFunctionEntry]
}

struct FormulaFunctionInsertion: Equatable {
  var text: String
  var caretUTF16: Int
  var arguments: String
  var signatureLine: String
}

enum FormulaFunctionCatalog {
  private static let defined: [FormulaFunctionEntry] = [
    FormulaFunctionEntry(name: "ABS", kind: .math, arguments: "number"),
    FormulaFunctionEntry(name: "ROUND", kind: .math, arguments: "number, [num_digits]"),
    FormulaFunctionEntry(name: "ROUNDDOWN", kind: .math, arguments: "number, [num_digits]"),
    FormulaFunctionEntry(name: "ROUNDUP", kind: .math, arguments: "number, [num_digits]"),
    FormulaFunctionEntry(name: "SUM", kind: .math, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "SUMIF", kind: .math, arguments: "range, criteria, [sum_range]"),
    FormulaFunctionEntry(name: "SUMIFS", kind: .math, arguments: "sum_range, criteria_range1, criteria1, ..."),
    FormulaFunctionEntry(name: "SUMPRODUCT", kind: .math, arguments: "array1, [array2], ..."),

    FormulaFunctionEntry(name: "AVERAGE", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "AVERAGEIF", kind: .statistical, arguments: "range, criteria, [average_range]"),
    FormulaFunctionEntry(name: "AVERAGEIFS", kind: .statistical, arguments: "average_range, criteria_range1, criteria1, ..."),
    FormulaFunctionEntry(name: "COUNT", kind: .statistical, arguments: "value1, [value2], ..."),
    FormulaFunctionEntry(name: "COUNTA", kind: .statistical, arguments: "value1, [value2], ..."),
    FormulaFunctionEntry(name: "COUNTBLANK", kind: .statistical, arguments: "range"),
    FormulaFunctionEntry(name: "COUNTIF", kind: .statistical, arguments: "range, criteria"),
    FormulaFunctionEntry(name: "COUNTIFS", kind: .statistical, arguments: "criteria_range1, criteria1, ..."),
    FormulaFunctionEntry(name: "MAX", kind: .statistical, arguments: "number1, [number2], ..."),
    FormulaFunctionEntry(name: "MIN", kind: .statistical, arguments: "number1, [number2], ..."),

    FormulaFunctionEntry(name: "AND", kind: .logical, arguments: "logical1, [logical2], ..."),
    FormulaFunctionEntry(name: "IF", kind: .logical, arguments: "logical_test, value_if_true, [value_if_false]"),
    FormulaFunctionEntry(name: "IFERROR", kind: .logical, arguments: "value, value_if_error"),
    FormulaFunctionEntry(name: "IFNA", kind: .logical, arguments: "value, value_if_na"),
    FormulaFunctionEntry(name: "IFS", kind: .logical, arguments: "logical_test1, value_if_true1, ..."),
    FormulaFunctionEntry(name: "NOT", kind: .logical, arguments: "logical"),
    FormulaFunctionEntry(name: "OR", kind: .logical, arguments: "logical1, [logical2], ..."),

    FormulaFunctionEntry(name: "CONCAT", kind: .text, arguments: "text1, [text2], ..."),
    FormulaFunctionEntry(name: "CONCATENATE", kind: .text, arguments: "text1, [text2], ..."),
    FormulaFunctionEntry(name: "LEFT", kind: .text, arguments: "text, [num_chars]"),
    FormulaFunctionEntry(name: "LEN", kind: .text, arguments: "text"),
    FormulaFunctionEntry(name: "LOWER", kind: .text, arguments: "text"),
    FormulaFunctionEntry(name: "MID", kind: .text, arguments: "text, start_num, num_chars"),
    FormulaFunctionEntry(name: "RIGHT", kind: .text, arguments: "text, [num_chars]"),
    FormulaFunctionEntry(name: "SUBSTITUTE", kind: .text, arguments: "text, old_text, new_text, [instance_num]"),
    FormulaFunctionEntry(name: "TEXT", kind: .text, arguments: "value, format_text"),
    FormulaFunctionEntry(name: "TEXTJOIN", kind: .text, arguments: "delimiter, ignore_empty, text1, ..."),
    FormulaFunctionEntry(name: "TRIM", kind: .text, arguments: "text"),
    FormulaFunctionEntry(name: "UPPER", kind: .text, arguments: "text"),

    FormulaFunctionEntry(name: "HLOOKUP", kind: .lookup, arguments: "lookup_value, table_array, row_index_num, [range_lookup]"),
    FormulaFunctionEntry(name: "INDEX", kind: .lookup, arguments: "array, row_num, [column_num]"),
    FormulaFunctionEntry(name: "MATCH", kind: .lookup, arguments: "lookup_value, lookup_array, [match_type]"),
    FormulaFunctionEntry(name: "VLOOKUP", kind: .lookup, arguments: "lookup_value, table_array, col_index_num, [range_lookup]"),
    FormulaFunctionEntry(name: "XLOOKUP", kind: .lookup, arguments: "lookup_value, lookup_array, return_array, [if_not_found], [match_mode]"),
    FormulaFunctionEntry(name: "XMATCH", kind: .lookup, arguments: "lookup_value, lookup_array, [match_mode]"),

    FormulaFunctionEntry(name: "DATE", kind: .dateTime, arguments: "year, month, day"),
    FormulaFunctionEntry(name: "DAY", kind: .dateTime, arguments: "serial_number"),
    FormulaFunctionEntry(name: "MONTH", kind: .dateTime, arguments: "serial_number"),
    FormulaFunctionEntry(name: "NOW", kind: .dateTime, arguments: ""),
    FormulaFunctionEntry(name: "TODAY", kind: .dateTime, arguments: ""),
    FormulaFunctionEntry(name: "YEAR", kind: .dateTime, arguments: "serial_number"),
  ]

  static func groups(matching query: String) -> [FormulaFunctionGroup] {
    let implemented = Set(FormulaFunctions.all)
    return FormulaFunctionKind.allCases.compactMap { kind in
      let entries = defined
        .filter { $0.kind == kind && implemented.contains($0.name) && $0.matches(query) }
        .sorted { $0.name < $1.name }
      guard !entries.isEmpty else { return nil }
      return FormulaFunctionGroup(kind: kind, entries: entries)
    }
  }

  static func entry(named name: String) -> FormulaFunctionEntry? {
    let upper = name.uppercased()
    guard FormulaFunctions.all.contains(upper) else { return nil }
    return defined.first { $0.name == upper }
  }

  /// `=NAME()` with the caret between the parentheses.
  static func insertion(for name: String) -> FormulaFunctionInsertion? {
    guard let entry = entry(named: name) else { return nil }
    let text = "=\(entry.name)()"
    return FormulaFunctionInsertion(
      text: text,
      caretUTF16: text.utf16.count - 1,
      arguments: entry.arguments,
      signatureLine: entry.signatureLine
    )
  }
}
