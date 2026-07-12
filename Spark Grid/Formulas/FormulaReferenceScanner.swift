import AppKit
import Foundation

/// A cell/range reference found inside a formula, with a stable color index and text span.
struct FormulaRefHighlight: Equatable, Sendable {
  var sheet: String?
  var start: CellAddress
  var end: CellAddress
  var colorIndex: Int
  /// UTF-16 range of the reference token in the formula string.
  var utf16Range: NSRange

  var cellRange: CellRange {
    CellRange(start: start, end: end)
  }

  static let palette: [NSColor] = [
    NSColor.systemBlue,
    NSColor.systemOrange,
    NSColor.systemPurple,
    NSColor.systemGreen,
    NSColor.systemPink,
    NSColor.systemTeal,
    NSColor.systemYellow,
    NSColor.systemIndigo,
  ]

  var color: NSColor {
    Self.palette[colorIndex % Self.palette.count]
  }
}

/// Scans formula text for A1 / Sheet!A1 / A1:B2 references without requiring a full parse.
enum FormulaReferenceScanner {
  static func highlights(
    in raw: String,
    maxRow: Int = Workbook.defaultRowCount - 1,
    maxCol: Int = Workbook.defaultColumnCount - 1
  ) -> [FormulaRefHighlight] {
    let nsRaw = raw as NSString
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("=") else { return [] }
    let trimOffset = nsRaw.range(of: trimmed).location
    guard trimOffset != NSNotFound else { return [] }

    let expr = String(trimmed.dropFirst()) // drop '='
    let exprOffset = trimOffset + 1

    // Cells, open columns (`A`), open rows (`2`), and ranges (`A2:A`, `A:A`, `2:2`).
    let pattern = #"(?:'(?:[^']|'')+'|[A-Za-z_][\w.]*)?!?(?:\$?[A-Za-z]+\$?\d*|\$?\d+)(?::(?:\$?[A-Za-z]+\$?\d*|\$?\d+))?"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

    let nsExpr = expr as NSString
    let full = NSRange(location: 0, length: nsExpr.length)
    var highlights: [FormulaRefHighlight] = []
    var colorIndex = 0

    regex.enumerateMatches(in: expr, options: [], range: full) { match, _, _ in
      guard let match, match.range.location != NSNotFound else { return }
      let token = nsExpr.substring(with: match.range)
      // Skip bare identifiers that aren't refs (function names before '(').
      let afterLoc = match.range.location + match.range.length
      if afterLoc < nsExpr.length {
        let next = nsExpr.character(at: afterLoc)
        if next == 40 { // '(' → function call, not a sheet ref alone without A1
          // Still allow Sheet1!A1; function names have no digits/address.
          if A1Reference.parseFormulaRef(token) == nil,
             A1Reference.parseFormulaRange(token) == nil
          {
            return
          }
        }
      }

      if let (start, end) = A1Reference.parseFormulaRange(token) {
        let bounds = A1Reference.resolvedBounds(
          start: start,
          end: end,
          maxRow: maxRow,
          maxCol: maxCol
        )
        let utf16 = NSRange(location: exprOffset + match.range.location, length: match.range.length)
        highlights.append(
          FormulaRefHighlight(
            sheet: start.sheet,
            start: CellAddress(row: bounds.minRow, col: bounds.minCol),
            end: CellAddress(row: bounds.maxRow, col: bounds.maxCol),
            colorIndex: colorIndex,
            utf16Range: utf16
          )
        )
        colorIndex += 1
        return
      }

      if let ref = A1Reference.parseFormulaRef(token) {
        let utf16 = NSRange(location: exprOffset + match.range.location, length: match.range.length)
        highlights.append(
          FormulaRefHighlight(
            sheet: ref.sheet,
            start: ref.address,
            end: ref.address,
            colorIndex: colorIndex,
            utf16Range: utf16
          )
        )
        colorIndex += 1
        return
      }
    }

    return highlights
  }

  static func attributedFormula(
    _ raw: String,
    highlights: [FormulaRefHighlight],
    focusedIndex: Int?,
    baseFont: NSFont,
    baseColor: NSColor
  ) -> NSAttributedString {
    let result = NSMutableAttributedString(
      string: raw,
      attributes: [
        .font: baseFont,
        .foregroundColor: baseColor,
        .backgroundColor: NSColor.clear,
      ]
    )
    for (index, highlight) in highlights.enumerated() {
      guard NSMaxRange(highlight.utf16Range) <= result.length else { continue }
      let isFocused = focusedIndex == index
      var attrs: [NSAttributedString.Key: Any] = [
        .foregroundColor: isFocused ? highlight.color.blended(withFraction: 0.15, of: .black) ?? highlight.color : highlight.color,
        .font: baseFont,
      ]
      // Sheets-style: active ref gets a tinted background chip in the formula text.
      if isFocused {
        attrs[.backgroundColor] = highlight.color.withAlphaComponent(0.28)
      } else {
        attrs[.backgroundColor] = highlight.color.withAlphaComponent(0.10)
      }
      result.addAttributes(attrs, range: highlight.utf16Range)
    }
    return result
  }

  /// Prefer the token containing the caret; if between tokens, pick the nearest touching one.
  static func highlightIndex(atUTF16 location: Int, in highlights: [FormulaRefHighlight]) -> Int? {
    if let exact = highlights.firstIndex(where: { NSLocationInRange(location, $0.utf16Range) }) {
      return exact
    }
    // Caret at end of a token counts as inside that token.
    if let atEnd = highlights.firstIndex(where: { location == NSMaxRange($0.utf16Range) }) {
      return atEnd
    }
    return nil
  }
}
