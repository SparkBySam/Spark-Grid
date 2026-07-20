import AppKit
import Foundation

#if DEBUG
enum BugBashRunner {
  struct Result: Sendable {
    let name: String
    let passed: Bool
    let detail: String
  }

  static func runIfRequested() -> Bool {
    guard ProcessInfo.processInfo.environment["SPARK_GRID_BUG_BASH"] == "1" else { return false }
    let results = runAll()
    let failed = results.filter { !$0.passed }
    for result in results {
      let mark = result.passed ? "PASS" : "FAIL"
      print("[BugBash] \(mark): \(result.name) — \(result.detail)")
    }
    print("[BugBash] \(results.count - failed.count)/\(results.count) passed")
    if failed.isEmpty {
      print("[BugBash] ALL PASSED")
      exit(0)
    }
    fputs("[BugBash] FAILED\n", stderr)
    exit(1)
  }

  static func runAll() -> [Result] {
    var results: [Result] = []
    results.append(importSmoke(path: "/Users/samparker/Downloads/FIT_test.xlsx", label: "FIT_test"))
    results.append(importSmoke(path: "/Users/samparker/Downloads/SourceSummary_cf_bash.xlsx", label: "CF bash"))
    results.append(importSmoke(
      path: "/Users/samparker/Downloads/Enterprise Report_Queen City Harley-Davidson_2026-04-09_to_2026-07-15_export_1784222143023.xlsx",
      label: "Enterprise themed"
    ))
    results.append(percentConditionalCompare())
    results.append(mergeRoundTrip())
    results.append(filterCriteriaRoundTrip())
    results.append(chartRoundTrip())
    results.append(colorScaleRoundTrip())
    results.append(themeSchemeParse())
    results.append(mergeSelectionSnap())
    results.append(sharedFormulaRoundTrip())
    results.append(conditionalFormatImport())
    return results
  }

  private static func sharedFormulaRoundTrip() -> Result {
    let path = "/Users/samparker/Downloads/FIT_test.xlsx"
    guard FileManager.default.fileExists(atPath: path) else {
      return Result(name: "shared formula round-trip", passed: true, detail: "skipped (file missing)")
    }
    do {
      let original = try XLSXCodec.importWorkbook(from: URL(fileURLWithPath: path))
      let formulaCount = original.activeSheet.cells.values.filter {
        FormulaSyntax.isFormula($0.raw)
      }.count
      guard formulaCount > 0 else {
        return Result(name: "shared formula round-trip", passed: false, detail: "no formulas in source")
      }
      let data = try XLSXCodec.exportWorkbook(original)
      let roundTripped = try XLSXCodec.importWorkbook(from: data)
      let rtCount = roundTripped.activeSheet.cells.values.filter {
        FormulaSyntax.isFormula($0.raw)
      }.count
      guard rtCount >= formulaCount else {
        return Result(
          name: "shared formula round-trip",
          passed: false,
          detail: "formulas \(formulaCount) -> \(rtCount)"
        )
      }
      return Result(name: "shared formula round-trip", passed: true, detail: "\(rtCount) formulas")
    } catch {
      return Result(name: "shared formula round-trip", passed: false, detail: error.localizedDescription)
    }
  }

  private static func conditionalFormatImport() -> Result {
    let path = "/Users/samparker/Downloads/SourceSummary_cf_bash.xlsx"
    guard FileManager.default.fileExists(atPath: path) else {
      return Result(name: "CF import", passed: true, detail: "skipped (file missing)")
    }
    do {
      let wb = try XLSXCodec.importWorkbook(from: URL(fileURLWithPath: path))
      let count = wb.activeSheet.conditionalFormats.count
      guard count > 0 else {
        return Result(name: "CF import", passed: false, detail: "no rules imported")
      }
      return Result(name: "CF import", passed: true, detail: "\(count) rule(s)")
    } catch {
      return Result(name: "CF import", passed: false, detail: error.localizedDescription)
    }
  }

  private static func importSmoke(path: String, label: String) -> Result {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else {
      return Result(name: "import \(label)", passed: true, detail: "skipped (file missing)")
    }
    do {
      let wb = try XLSXCodec.importWorkbook(from: url)
      guard !wb.sheets.isEmpty else {
        return Result(name: "import \(label)", passed: false, detail: "empty workbook")
      }
      return Result(
        name: "import \(label)",
        passed: true,
        detail: "\(wb.sheets.count) sheet(s), \(wb.activeSheet.cells.count) cells"
      )
    } catch {
      return Result(name: "import \(label)", passed: false, detail: error.localizedDescription)
    }
  }

  private static func percentConditionalCompare() -> Result {
    let matches = ConditionalFormatEvaluator.matches(
      .greaterThan(50),
      value: .number(1.0),
      displayString: "100%",
      numberFormat: .percent,
      address: .origin,
      origin: .origin,
      evaluateFormula: { _, _, _ in .blank }
    )
    let noMatch = ConditionalFormatEvaluator.matches(
      .greaterThan(50),
      value: .number(0.4),
      displayString: "40%",
      numberFormat: .percent,
      address: .origin,
      origin: .origin,
      evaluateFormula: { _, _, _ in .blank }
    )
    guard matches, !noMatch else {
      return Result(name: "percent CF compare", passed: false, detail: "100% > 50 expected true, 40% > 50 false")
    }
    return Result(name: "percent CF compare", passed: true, detail: "ok")
  }

  private static func mergeRoundTrip() -> Result {
    var sheet = Sheet(name: "Test")
    sheet.setCell(Cell(raw: "Title"), at: CellAddress(row: 0, col: 0))
    sheet.mergedRanges = [CellRange(
      start: CellAddress(row: 0, col: 0),
      end: CellAddress(row: 0, col: 2)
    )]
    let wb = Workbook(sheets: [sheet])
    do {
      let data = try XLSXCodec.exportWorkbook(wb)
      let imported = try XLSXCodec.importWorkbook(from: data)
      guard imported.activeSheet.mergedRanges.count == 1 else {
        return Result(name: "merge round-trip", passed: false, detail: "expected 1 merge, got \(imported.activeSheet.mergedRanges.count)")
      }
      let m = imported.activeSheet.mergedRanges[0].normalized
      guard m.minRow == 0, m.maxRow == 0, m.minCol == 0, m.maxCol == 2 else {
        return Result(name: "merge round-trip", passed: false, detail: "wrong bounds \(m)")
      }
      return Result(name: "merge round-trip", passed: true, detail: "ok")
    } catch {
      return Result(name: "merge round-trip", passed: false, detail: error.localizedDescription)
    }
  }

  private static func filterCriteriaRoundTrip() -> Result {
    var sheet = Sheet(name: "Test")
    for row in 0...3 {
      sheet.setCell(Cell(raw: row == 0 ? "Name" : "A"), at: CellAddress(row: row, col: 0))
      sheet.setCell(Cell(raw: row == 0 ? "Val" : (row == 1 ? "X" : "Y")), at: CellAddress(row: row, col: 1))
    }
    let range = CellRange(
      start: CellAddress(row: 0, col: 0),
      end: CellAddress(row: 3, col: 1)
    )
    sheet.autoFilter = SheetFilterState(
      range: range,
      selectedValuesByColumn: [1: ["X"]]
    )
    let wb = Workbook(sheets: [sheet])
    do {
      let data = try XLSXCodec.exportWorkbook(wb)
      let xml = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
      guard xml.contains("filterColumn"), xml.contains("filter val=\"X\"") else {
        return Result(name: "filter criteria export", passed: false, detail: "missing filterColumn XML")
      }
      let imported = try XLSXCodec.importWorkbook(from: data)
      guard let filter = imported.activeSheet.autoFilter else {
        return Result(name: "filter criteria round-trip", passed: false, detail: "no autofilter after import")
      }
      guard filter.selectedValuesByColumn[1] == ["X"] else {
        return Result(
          name: "filter criteria round-trip",
          passed: false,
          detail: "col 1 values: \(String(describing: filter.selectedValuesByColumn[1]))"
        )
      }
      return Result(name: "filter criteria round-trip", passed: true, detail: "ok")
    } catch {
      return Result(name: "filter criteria round-trip", passed: false, detail: error.localizedDescription)
    }
  }

  private static func chartRoundTrip() -> Result {
    var sheet = Sheet(name: "Test")
    sheet.setCell(Cell(raw: "A"), at: CellAddress(row: 0, col: 0))
    sheet.setCell(Cell(raw: "10"), at: CellAddress(row: 1, col: 0))
    sheet.setCell(Cell(raw: "20"), at: CellAddress(row: 2, col: 0))
    let chart = SheetChart(
      kind: .bar,
      title: "Test",
      dataRange: CellRange(start: CellAddress(row: 0, col: 0), end: CellAddress(row: 2, col: 0)),
      anchorRow: 4,
      anchorCol: 0
    )
    sheet.charts = [chart]
    let wb = Workbook(sheets: [sheet])
    do {
      let data = try XLSXCodec.exportWorkbook(wb)
      guard XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/sparkGrid/charts1.json") != nil else {
        return Result(name: "chart round-trip", passed: false, detail: "missing charts json part")
      }
      let imported = try XLSXCodec.importWorkbook(from: data)
      guard imported.activeSheet.charts.count == 1,
            imported.activeSheet.charts[0].title == "Test"
      else {
        return Result(name: "chart round-trip", passed: false, detail: "charts: \(imported.activeSheet.charts)")
      }
      return Result(name: "chart round-trip", passed: true, detail: "ok")
    } catch {
      return Result(name: "chart round-trip", passed: false, detail: error.localizedDescription)
    }
  }

  private static func colorScaleRoundTrip() -> Result {
    let stops = [
      ColorScaleStop(type: .min, value: nil, color: CodableColor(red: 1, green: 0.8, blue: 0.8, alpha: 1)),
      ColorScaleStop(type: .max, value: nil, color: CodableColor(red: 0.8, green: 1, blue: 0.8, alpha: 1)),
    ]
    var sheet = Sheet(name: "Test")
    sheet.setCell(Cell(raw: "10"), at: CellAddress(row: 0, col: 0))
    sheet.setCell(Cell(raw: "90"), at: CellAddress(row: 1, col: 0))
    sheet.conditionalFormats = [
      ConditionalFormatRule(
        range: CellRange(start: .origin, end: CellAddress(row: 1, col: 0)),
        predicate: .colorScale(stops),
        style: ConditionalFormatStyle()
      ),
    ]
    let wb = Workbook(sheets: [sheet])
    do {
      let data = try XLSXCodec.exportWorkbook(wb)
      let xml = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
      guard xml.contains("type=\"colorScale\"") else {
        return Result(name: "color scale export", passed: false, detail: "missing colorScale in XML")
      }
      let imported = try XLSXCodec.importWorkbook(from: data)
      guard let rule = imported.activeSheet.conditionalFormats.first,
            case .colorScale(let importedStops) = rule.predicate,
            importedStops.count == 2
      else {
        return Result(name: "color scale round-trip", passed: false, detail: "rules: \(imported.activeSheet.conditionalFormats)")
      }
      return Result(name: "color scale round-trip", passed: true, detail: "ok")
    } catch {
      return Result(name: "color scale round-trip", passed: false, detail: error.localizedDescription)
    }
  }

  private static func themeSchemeParse() -> Result {
    let path = "/Users/samparker/Downloads/Enterprise Report_Queen City Harley-Davidson_2026-04-09_to_2026-07-15_export_1784222143023.xlsx"
    guard FileManager.default.fileExists(atPath: path),
          let data = try? Data(contentsOf: URL(fileURLWithPath: path))
    else {
      return Result(name: "theme parse", passed: true, detail: "skipped (file missing)")
    }
    let scheme = XLSXCodec.importThemeScheme(archiveData: data)
    guard scheme.colorsByName["accent1"] != nil else {
      return Result(name: "theme parse", passed: false, detail: "accent1 missing (\(scheme.colorsByName.keys.sorted()))")
    }
    let resolved = scheme.color(themeIndex: 4, tint: 0)
    guard resolved != nil else {
      return Result(name: "theme resolve", passed: false, detail: "theme index 4 unresolved")
    }
    return Result(name: "theme parse", passed: true, detail: "accent1 + theme[4] ok")
  }

  private static func mergeSelectionSnap() -> Result {
    var sheet = Sheet(name: "Test")
    sheet.mergedRanges = [CellRange(
      start: CellAddress(row: 0, col: 0),
      end: CellAddress(row: 0, col: 2)
    )]
    let expanded = sheet.selectionExpandedForMerges(
      CellRange(start: CellAddress(row: 0, col: 1), end: CellAddress(row: 0, col: 1))
    )
    let n = expanded.normalized
    guard n.minCol == 0, n.maxCol == 2 else {
      return Result(name: "merge selection expand", passed: false, detail: "got cols \(n.minCol)-\(n.maxCol)")
    }
    guard sheet.isCoveredByMerge(CellAddress(row: 0, col: 1)) else {
      return Result(name: "merge covered cell", passed: false, detail: "B1 should be covered")
    }
    guard sheet.mergeAnchor(for: CellAddress(row: 0, col: 1)) == CellAddress(row: 0, col: 0) else {
      return Result(name: "merge anchor snap", passed: false, detail: "B1 anchor should be A1")
    }
    return Result(name: "merge selection expand", passed: true, detail: "ok")
  }
}
#endif
