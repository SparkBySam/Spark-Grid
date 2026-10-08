import Foundation

/// Renders an Excel number-format code: thousands separators, the currency symbol
/// in the code, and the date or time pattern.
enum ExcelFormatCode {
  static func formatted(_ value: Double, code: String, fractionDigits: Int?) -> String? {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed.caseInsensitiveCompare("General") == .orderedSame {
      return nil
    }
    let sections = splitSections(trimmed)
    guard let first = sections.first else { return nil }
    let negative = value < 0
    let section: String
    let signedBySection: Bool
    if value == 0, sections.count >= 3 {
      section = sections[2]
      signedBySection = true
    } else if negative, sections.count >= 2 {
      section = sections[1]
      signedBySection = true
    } else {
      section = first
      signedBySection = false
    }
    if section.isEmpty { return "" }
    if isTextPlaceholder(section) {
      return CellValue.number(value).displayString
    }
    if isDateSection(section) {
      return formatDate(value, section: section)
    }
    let parsed = parseNumber(section)
    if parsed.body.isEmpty {
      return parsed.prefix + parsed.suffix
    }
    let digits = formatDigits(abs(value), parsed: parsed, fractionDigits: fractionDigits)
    let rendered = parsed.prefix + digits + parsed.suffix
    let numeric = digits.filter(\.isNumber)
    if negative, !signedBySection, numeric.contains(where: { $0 != "0" }) {
      return "-" + rendered
    }
    return rendered
  }

  /// Fraction digits in the positive section, when the code is a number format.
  static func fractionDigits(in code: String) -> Int? {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare("General") != .orderedSame else { return nil }
    guard let section = splitSections(trimmed).first, !isDateSection(section), !isTextPlaceholder(section) else {
      return nil
    }
    let parsed = parseNumber(section)
    guard !parsed.body.isEmpty else { return nil }
    return parsed.minFraction
  }

  // MARK: - Sections

  private static func splitSections(_ code: String) -> [String] {
    var sections: [String] = []
    var current = ""
    var quoted = false
    var brackets = 0
    for character in code {
      if character == "\"" { quoted.toggle() }
      if !quoted, character == "[" { brackets += 1 }
      if !quoted, character == "]", brackets > 0 { brackets -= 1 }
      if character == ";", !quoted, brackets == 0 {
        sections.append(current)
        current = ""
        continue
      }
      current.append(character)
    }
    sections.append(current)
    return sections
  }

  private static func isTextPlaceholder(_ section: String) -> Bool {
    let stripped = stripDecorations(section).trimmingCharacters(in: .whitespaces)
    return stripped == "@"
  }

  private static func isDateSection(_ section: String) -> Bool {
    var significant = ""
    var quoted = false
    let chars = Array(section)
    var index = 0
    while index < chars.count {
      if chars[index] == "\"" {
        quoted.toggle()
        index += 1
        continue
      }
      if quoted {
        index += 1
        continue
      }
      if chars[index] == "\\" {
        index += 2
        continue
      }
      if chars[index] == "[" {
        var inner = ""
        index += 1
        while index < chars.count, chars[index] != "]" {
          inner.append(chars[index])
          index += 1
        }
        if index < chars.count { index += 1 }
        let lower = inner.lowercased()
        if !lower.isEmpty, lower.allSatisfy({ $0 == "h" || $0 == "m" || $0 == "s" }) {
          significant += lower
        }
        continue
      }
      significant.append(chars[index])
      index += 1
    }
    let lower = significant.lowercased()
      .replacingOccurrences(of: "am/pm", with: "")
      .replacingOccurrences(of: "a/p", with: "")
    if lower.contains("0") || lower.contains("#") || lower.contains("?") { return false }
    if lower.contains("y") || lower.contains("d") || lower.contains("h") || lower.contains("s") { return true }
    return lower.contains("m")
  }

  private static func stripDecorations(_ section: String) -> String {
    var result = ""
    var quoted = false
    let chars = Array(section)
    var index = 0
    while index < chars.count {
      if chars[index] == "\"" {
        quoted.toggle()
        index += 1
        continue
      }
      if quoted {
        result.append(chars[index])
        index += 1
        continue
      }
      if chars[index] == "[" {
        while index < chars.count, chars[index] != "]" { index += 1 }
        if index < chars.count { index += 1 }
        continue
      }
      result.append(chars[index])
      index += 1
    }
    return result
  }

  // MARK: - Numbers

  private struct ParsedNumber {
    var prefix = ""
    var suffix = ""
    var body = ""
    var percent = 0
    var grouping = false
    var scale = 0
    var minInteger = 0
    var minFraction = 0
    var maxFraction = 0
    var scientificPlus: Bool?
    var scientificDigits = 2
  }

  private static func parseNumber(_ section: String) -> ParsedNumber {
    var parsed = ParsedNumber()
    var stage = 0
    let chars = Array(section)
    var index = 0

    func appendLiteral(_ text: String) {
      if stage == 0 {
        parsed.prefix += text
      } else {
        stage = 2
        parsed.suffix += text
      }
    }

    while index < chars.count {
      let character = chars[index]
      if character == "\"" {
        var literal = ""
        index += 1
        while index < chars.count, chars[index] != "\"" {
          literal.append(chars[index])
          index += 1
        }
        if index < chars.count { index += 1 }
        appendLiteral(literal)
        continue
      }
      if character == "\\" {
        index += 1
        if index < chars.count {
          appendLiteral(String(chars[index]))
          index += 1
        }
        continue
      }
      if character == "_" || character == "*" {
        index += min(2, chars.count - index)
        continue
      }
      if character == "[" {
        var inner = ""
        index += 1
        while index < chars.count, chars[index] != "]" {
          inner.append(chars[index])
          index += 1
        }
        if index < chars.count { index += 1 }
        if inner.hasPrefix("$") {
          let symbolSource = inner.dropFirst()
          let symbol = symbolSource.split(separator: "-", maxSplits: 1).first.map(String.init) ?? String(symbolSource)
          appendLiteral(symbol)
        }
        continue
      }
      if character == "%" {
        parsed.percent += 1
        appendLiteral("%")
        index += 1
        continue
      }
      if character == "0" || character == "#" || character == "?" || character == "." || character == "," {
        if stage == 0 { stage = 1 }
        if stage == 1 {
          parsed.body.append(character)
        } else {
          appendLiteral(String(character))
        }
        index += 1
        continue
      }
      if (character == "E" || character == "e"),
         stage == 1,
         index + 1 < chars.count,
         chars[index + 1] == "+" || chars[index + 1] == "-"
      {
        parsed.body.append(character)
        parsed.body.append(chars[index + 1])
        index += 2
        while index < chars.count, chars[index] == "0" {
          parsed.body.append(chars[index])
          index += 1
        }
        stage = 2
        continue
      }
      if stage == 1 { stage = 2 }
      appendLiteral(String(character))
      index += 1
    }

    analyze(&parsed)
    return parsed
  }

  private static func analyze(_ parsed: inout ParsedNumber) {
    var body = parsed.body
    if let range = body.range(of: "E+", options: .caseInsensitive) ?? body.range(of: "E-", options: .caseInsensitive) {
      let marker = body[range].uppercased()
      parsed.scientificPlus = marker.hasSuffix("+")
      let exponent = body[range.upperBound...].filter { $0 == "0" }
      parsed.scientificDigits = max(2, exponent.count)
      body = String(body[..<range.lowerBound])
    }
    var integer = body
    var fraction = ""
    if let dot = integer.firstIndex(of: ".") {
      fraction = String(integer[integer.index(after: dot)...])
      integer = String(integer[..<dot])
    }
    if let lastDigit = integer.lastIndex(where: { $0 == "0" || $0 == "#" || $0 == "?" }) {
      let after = integer[integer.index(after: lastDigit)...]
      parsed.scale = after.filter { $0 == "," }.count
      parsed.grouping = integer[..<lastDigit].contains(",")
      parsed.minInteger = integer.filter { $0 == "0" }.count
    } else {
      parsed.scale = integer.filter { $0 == "," }.count
    }
    parsed.minFraction = fraction.filter { $0 == "0" }.count
    parsed.maxFraction = fraction.filter { $0 == "0" || $0 == "#" || $0 == "?" }.count
  }

  private static func formatDigits(_ value: Double, parsed: ParsedNumber, fractionDigits: Int?) -> String {
    var number = value
    if parsed.percent > 0 {
      number *= pow(100, Double(parsed.percent))
    }
    if parsed.scale > 0 {
      number /= pow(1000, Double(parsed.scale))
    }
    if parsed.scientificPlus != nil {
      return formatScientific(number, fraction: fractionDigits ?? parsed.maxFraction, digits: parsed.scientificDigits, showPlus: parsed.scientificPlus == true)
    }
    let minFraction = fractionDigits ?? parsed.minFraction
    let maxFraction = fractionDigits ?? max(parsed.maxFraction, parsed.minFraction)
    return formatFixed(number, minInteger: max(parsed.minInteger, 1), minFraction: minFraction, maxFraction: maxFraction, grouping: parsed.grouping)
  }

  private static func formatFixed(
    _ value: Double,
    minInteger: Int,
    minFraction: Int,
    maxFraction: Int,
    grouping: Bool
  ) -> String {
    let places = max(0, maxFraction)
    let scale = pow(10, Double(places))
    let rounded = (abs(value) * scale).rounded() / scale
    let text = String(format: "%.\(places)f", rounded)
    let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
    var integer = String(pieces.first ?? "0")
    var fraction = pieces.count > 1 ? String(pieces[1]) : ""
    while integer.count < max(minInteger, 1) {
      integer = "0" + integer
    }
    let minimum = max(0, minFraction)
    while fraction.count > minimum, fraction.last == "0" {
      fraction.removeLast()
    }
    if grouping {
      integer = grouped(integer)
    }
    if fraction.isEmpty { return integer }
    return integer + "." + fraction
  }

  private static func grouped(_ integer: String) -> String {
    guard integer.count > 3 else { return integer }
    var digits = Array(integer)
    var groupedDigits: [Character] = []
    var count = 0
    while let digit = digits.popLast() {
      if count == 3 {
        groupedDigits.append(",")
        count = 0
      }
      groupedDigits.append(digit)
      count += 1
    }
    return String(groupedDigits.reversed())
  }

  private static func formatScientific(_ value: Double, fraction: Int, digits: Int, showPlus: Bool) -> String {
    let places = max(0, fraction)
    if value == 0 {
      let zeros = String(repeating: "0", count: places)
      let exponent = String(repeating: "0", count: max(2, digits))
      let mantissa = places == 0 ? "0" : "0." + zeros
      return mantissa + "E+" + exponent
    }
    let exponent = Int(floor(log10(abs(value))))
    let mantissa = abs(value) / pow(10, Double(exponent))
    let body = formatFixed(mantissa, minInteger: 1, minFraction: places, maxFraction: places, grouping: false)
    let sign = exponent < 0 ? "-" : (showPlus ? "+" : "+")
    let width = max(2, digits)
    return body + "E" + sign + String(format: "%0\(width)d", abs(exponent))
  }

  // MARK: - Dates

  private static func formatDate(_ serial: Double, section: String) -> String {
    if let elapsed = elapsedString(serial: serial, pattern: section) {
      return elapsed
    }
    guard let date = ExcelDate.date(from: serial) else {
      return CellValue.number(serial).displayString
    }
    let pattern = dateFormatterPattern(from: section)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = pattern
    return formatter.string(from: date)
  }

  private static func elapsedString(serial: Double, pattern: String) -> String? {
    guard pattern.range(of: #"\[h+\]"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
    let total = Int((abs(serial) * 86_400).rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    let lower = pattern.lowercased()
    if lower.contains("s") {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    if lower.contains("m") {
      return String(format: "%d:%02d", hours, minutes)
    }
    return String(hours)
  }

  private static func dateFormatterPattern(from excel: String) -> String {
    let chars = Array(excel)
    let upper = excel.uppercased()
    let hasPeriod = upper.contains("AM/PM") || upper.contains("A/P")
    var output = ""
    var index = 0

    func starts(with token: String) -> Bool {
      guard index + token.count <= chars.count else { return false }
      return String(chars[index..<(index + token.count)]).caseInsensitiveCompare(token) == .orderedSame
    }

    while index < chars.count {
      if starts(with: "AM/PM") {
        output += "a"
        index += 5
        continue
      }
      if starts(with: "A/P") {
        output += "a"
        index += 3
        continue
      }
      let character = chars[index]
      if character == "\"" {
        output += "'"
        index += 1
        while index < chars.count, chars[index] != "\"" {
          if chars[index] == "'" { output += "''" } else { output.append(chars[index]) }
          index += 1
        }
        if index < chars.count { index += 1 }
        output += "'"
        continue
      }
      if character == "\\" {
        index += 1
        if index < chars.count {
          output += quotedLiteral(String(chars[index]))
          index += 1
        }
        continue
      }
      if character == "[" {
        var inner = ""
        index += 1
        while index < chars.count, chars[index] != "]" {
          inner.append(chars[index])
          index += 1
        }
        if index < chars.count { index += 1 }
        let lower = inner.lowercased()
        if !lower.isEmpty, lower.allSatisfy({ $0 == "h" || $0 == "m" || $0 == "s" }) {
          let token = lower.first == "h" ? (hasPeriod ? "h" : "H") : String(lower.first!)
          output += String(repeating: token, count: min(lower.count, 2))
        }
        continue
      }
      if "yYdDhHsSmM".contains(character) {
        let kind = String(character).lowercased()
        var end = index
        while end < chars.count, String(chars[end]).lowercased() == kind { end += 1 }
        let count = end - index
        switch kind {
        case "y":
          output += String(repeating: "y", count: min(count, 4))
        case "d":
          switch count {
          case 1: output += "d"
          case 2: output += "dd"
          case 3: output += "EEE"
          default: output += "EEEE"
          }
        case "h":
          output += String(repeating: hasPeriod ? "h" : "H", count: min(count, 2))
        case "s":
          output += String(repeating: "s", count: min(count, 2))
        case "m":
          if isMinute(chars, start: index, end: end) {
            output += String(repeating: "m", count: min(count, 2))
          } else {
            switch count {
            case 1: output += "M"
            case 2: output += "MM"
            case 3: output += "MMM"
            default: output += "MMMM"
            }
          }
        default:
          break
        }
        index = end
        continue
      }
      if character.isLetter {
        output += quotedLiteral(String(character))
      } else {
        output.append(character)
      }
      index += 1
    }
    return output
  }

  private static func isMinute(_ chars: [Character], start: Int, end: Int) -> Bool {
    func neighbor(from index: Int, step: Int) -> Character? {
      var cursor = index
      while cursor >= 0, cursor < chars.count {
        let character = chars[cursor]
        if character == ":" || character == " " || character == "." {
          cursor += step
          continue
        }
        return character
      }
      return nil
    }
    if let left = neighbor(from: start - 1, step: -1), String(left).lowercased() == "h" {
      return true
    }
    if let right = neighbor(from: end, step: 1), String(right).lowercased() == "s" {
      return true
    }
    return false
  }

  private static func quotedLiteral(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
  }
}
