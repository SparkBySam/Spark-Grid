import GridCore
import Model
import XCTest

@testable import Calc

/// A summary sheet can be calculated before the sheet it reads. The total is still the count.
@MainActor
final class CrossSheetTotalTests: XCTestCase {
  func testSummarySumsACountIfOnALaterSheet() {
    let january = Sheet(
      name: "January",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "cat"),
        CellAddress(row: 0, col: 2): Cell(raw: "cat"),
        CellAddress(row: 1, col: 2): Cell(raw: "cat"),
        CellAddress(row: 0, col: 3): Cell(raw: "=COUNTIF(C1:C2,A1)"),
      ]
    )
    let summary = Sheet(
      name: "Summary",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "=January!D1")
      ]
    )
    let workbook = Workbook(sheets: [summary, january])
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false)
    let value = engine.sheetDisplayValue(
      at: CellAddress(row: 0, col: 0), sheet: workbook.sheets[0])
    XCTAssertEqual(value, .number(2))
  }

  /// Two sheets use the same unqualified COUNTIF coordinates. Each range stays on its sheet.
  func testCrossSheetCountIfRangesStayOnTheirOwnSheet() {
    func month(_ name: String, label: String) -> Sheet {
      Sheet(
        name: name,
        cells: [
          CellAddress(row: 0, col: 0): Cell(raw: label),
          CellAddress(row: 0, col: 2): Cell(raw: label),
          CellAddress(row: 1, col: 2): Cell(raw: label),
          CellAddress(row: 0, col: 3): Cell(raw: "=COUNTIF($C$1:$C$2,$A1)"),
        ]
      )
    }
    let summary = Sheet(
      name: "Summary",
      cells: [
        CellAddress(row: 0, col: 0): Cell(raw: "=January!D1+June!D1")
      ]
    )
    let workbook = Workbook(sheets: [
      summary,
      month("January", label: "no"),
      month("June", label: "yes"),
    ])
    let engine = FormulaEngine()
    engine.rebuild(workbook: workbook, recalculate: false)
    let address = CellAddress(row: 0, col: 0)
    let value = engine.sheetDisplayValue(at: address, sheet: workbook.sheets[0])
    XCTAssertEqual(value, .number(4))

    let full = FormulaEngine()
    full.recalculateEntireWorkbook(workbook)
    XCTAssertEqual(full.formulaResults(on: summary)[address], .number(4))
  }
}
