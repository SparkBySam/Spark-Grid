import Calc
import Formula
import Foundation
import GridCore
import Model

/// Compares calculated formula results with saved caches or an external answer file.
public enum AnswerValues {
  /// True when two calculated results are the same value.
  /// Booleans match 1 and 0. Numbers match within a tiny relative tolerance.
  /// Errors match on the code the cell shows, so `#VALUE!` covers both value errors.
  public static func same(_ lhs: CellValue, _ rhs: CellValue) -> Bool {
    switch (lhs, rhs) {
    case (.blank, .blank):
      return true
    case (.blank, .string(let text)), (.string(let text), .blank):
      return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case (.string(let left), .string(let right)):
      return left == right
    case (.bool(let left), .bool(let right)):
      return left == right
    case (.bool(let flag), .number(let number)):
      return number == (flag ? 1 : 0)
    case (.number(let number), .bool(let flag)):
      return number == (flag ? 1 : 0)
    case (.number(let left), .number(let right)):
      if left == right { return true }
      let scale = max(abs(left), abs(right), 1)
      return abs(left - right) <= scale * 1e-9
    case (.error(let left), .error(let right)):
      return left.displayCode == right.displayCode
    default:
      return false
    }
  }

  /// Token written by the ledger generator: `n:18`, `s:text`, `b:TRUE`, `e:#N/A`, or `blank`.
  public static func parseToken(_ token: String) -> CellValue? {
    if token == "blank" { return .blank }
    if token.hasPrefix("n:") {
      guard let number = Double(String(token.dropFirst(2))) else { return nil }
      return .number(number)
    }
    if token.hasPrefix("s:") {
      return .string(String(token.dropFirst(2)))
    }
    if token.hasPrefix("b:") {
      switch String(token.dropFirst(2)).uppercased() {
      case "TRUE": return .bool(true)
      case "FALSE": return .bool(false)
      default: return nil
      }
    }
    if token.hasPrefix("e:") {
      guard let error = FormulaError(displayCode: String(token.dropFirst(2))) else { return nil }
      return .error(error)
    }
    return nil
  }
}

public struct AnswerMismatch: Equatable, Sendable {
  public var key: String
  public var expected: String
  public var actual: String

  public init(key: String, expected: String, actual: String) {
    self.key = key
    self.expected = expected
    self.actual = actual
  }
}

public enum AnswerComparison {
  /// Drops imported formula caches so the next calculation cannot reuse them.
  public static func clearingFormulaCaches(_ workbook: Workbook) -> Workbook {
    var copy = workbook
    for sheetIndex in copy.sheets.indices {
      var cells = copy.sheets[sheetIndex].cells
      var changed = false
      for (address, cell) in cells {
        guard FormulaSyntax.isFormula(cell.raw) else { continue }
        guard cell.importedFormulaResult != nil || cell.importedFormulaValueType != nil else {
          continue
        }
        var next = cell
        next.importedFormulaResult = nil
        next.importedFormulaValueType = nil
        cells[address] = next
        changed = true
      }
      if changed {
        copy.sheets[sheetIndex].cells = cells
        copy.sheets[sheetIndex].rebuildFormulaIngestIndex()
      }
    }
    return copy
  }

  /// Saved `<v>` values for formula cells, keyed `Sheet!A1`.
  public static func savedFormulaResults(in workbook: Workbook) -> [String: CellValue] {
    var saved: [String: CellValue] = [:]
    for sheet in workbook.sheets {
      for (address, cell) in sheet.cells {
        guard FormulaSyntax.isFormula(cell.raw), let cached = cell.cachedFormulaValue else {
          continue
        }
        saved[cellKey(sheet: sheet.name, address: address)] = cached
      }
    }
    return saved
  }

  /// Recalculates every formula and returns the stored result, keyed `Sheet!A1`.
  public static func calculatedFormulaResults(in workbook: Workbook) -> [String: CellValue] {
    let engine = FormulaEngine()
    engine.recalculateEntireWorkbook(workbook)
    var results: [String: CellValue] = [:]
    for sheet in workbook.sheets {
      let stored = engine.formulaResults(on: sheet)
      for (address, cell) in sheet.cells where FormulaSyntax.isFormula(cell.raw) {
        let key = cellKey(sheet: sheet.name, address: address)
        results[key] = stored[address] ?? .blank
      }
    }
    return results
  }

  public static func cellKey(sheet: String, address: CellAddress) -> String {
    "\(sheet)!\(address.a1)"
  }

  /// Compares saved formula caches with a fresh calculation. Formulas with no cache are not mismatches.
  public static func compareSavedResults(in workbook: Workbook, exempt: Set<String> = []) -> (
    checked: Int, mismatches: [AnswerMismatch]
  ) {
    let expected = savedFormulaResults(in: workbook)
    let cleared = clearingFormulaCaches(workbook)
    let calculated = calculatedFormulaResults(in: cleared)
    var actual: [String: CellValue] = [:]
    actual.reserveCapacity(expected.count)
    for key in expected.keys {
      actual[key] = calculated[key] ?? .blank
    }
    return mismatches(expected: expected, actual: actual, exempt: exempt)
  }

  public static func mismatches(
    expected: [String: CellValue],
    actual: [String: CellValue],
    exempt: Set<String> = []
  ) -> (checked: Int, mismatches: [AnswerMismatch]) {
    var keys = Set(expected.keys)
    keys.formUnion(actual.keys)
    var failures: [AnswerMismatch] = []
    for key in keys.sorted() {
      if exempt.contains(key.lowercased()) { continue }
      let want = expected[key] ?? .blank
      let got = actual[key] ?? .blank
      if AnswerValues.same(want, got) { continue }
      failures.append(
        AnswerMismatch(key: key, expected: want.displayString, actual: got.displayString)
      )
    }
    return (keys.count, failures)
  }
}
