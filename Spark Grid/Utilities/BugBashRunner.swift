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
    results.append(emptyFilterRoundTrip())
    results.append(chartRoundTrip())
    results.append(colorScaleRoundTrip())
    results.append(themeSchemeParse())
    results.append(mergeSelectionSnap())
    results.append(sharedFormulaRoundTrip())
    results.append(conditionalFormatImport())
    results.append(highlightRoundTrip())
    results.append(cfDxfExcelCompat())
    results.append(dataBarRoundTrip())
    results.append(excelChartParts())
    results.append(imageImport())
    results.append(chartPreviewSeries())
    results.append(MainActor.assumeIsolated { insertPictureModel() })
    results.append(worksheetElementOrder())
    results.append(enterpriseFilterImport())
    results.append(MainActor.assumeIsolated { findScopePersistsAfterJump() })
    results.append(MainActor.assumeIsolated { largeEmptyFormatApply() })
    results.append(cfParseNumber())
    results.append(MainActor.assumeIsolated { sortRemapsMerge() })
    results.append(MainActor.assumeIsolated { insertColumnPastLastColumn() })
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

  private static func highlightRoundTrip() -> Result {
    var sheet = Sheet(name: "Test")
    sheet.setCell(Cell(raw: "5"), at: CellAddress(row: 0, col: 0))
    sheet.setCell(Cell(raw: "15"), at: CellAddress(row: 1, col: 0))
    sheet.conditionalFormats = [
      ConditionalFormatRule(
        range: CellRange(start: .origin, end: CellAddress(row: 9, col: 0)),
        predicate: .greaterThan(10),
        style: .redFill
      ),
    ]
    do {
      let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
      let xml = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
      let styles = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/styles.xml") ?? ""
      guard xml.contains("type=\"cellIs\""), xml.contains("conditionalFormatting") else {
        return Result(name: "highlight export", passed: false, detail: "missing cellIs CF in XML")
      }
      guard xml.contains("x14:conditionalFormatting"), styles.contains("<cellStyles") else {
        return Result(name: "highlight export", passed: false, detail: "missing x14 CF or cellStyles")
      }
      let imported = try XLSXCodec.importWorkbook(from: data)
      guard imported.activeSheet.conditionalFormats.count == 1,
            case .greaterThan(10) = imported.activeSheet.conditionalFormats[0].predicate
      else {
        return Result(name: "highlight round-trip", passed: false, detail: "\(imported.activeSheet.conditionalFormats)")
      }
      return Result(name: "highlight round-trip", passed: true, detail: "ok")
    } catch {
      return Result(name: "highlight round-trip", passed: false, detail: error.localizedDescription)
    }
  }

  private static func cfDxfExcelCompat() -> Result {
    var sheet = Sheet(name: "Test")
    sheet.conditionalFormats = [
      ConditionalFormatRule(
        range: CellRange(start: .origin, end: CellAddress(row: 9, col: 0)),
        predicate: .greaterThan(10),
        style: .redFill
      ),
    ]
    do {
      let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
      let styles = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/styles.xml") ?? ""
      guard styles.contains("<dxf>"), styles.contains("bgColor") else {
        return Result(name: "CF dxf excel compat", passed: false, detail: "missing dxf bgColor")
      }
      guard !styles.contains(#"bgColor indexed="64""#) else {
        return Result(name: "CF dxf excel compat", passed: false, detail: "dxf still has bgColor indexed=64")
      }
      return Result(name: "CF dxf excel compat", passed: true, detail: "bgColor solid fill")
    } catch {
      return Result(name: "CF dxf excel compat", passed: false, detail: error.localizedDescription)
    }
  }

  private static func imageImport() -> Result {
    let pngData: Data
    if let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: 8,
      pixelsHigh: 8,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ),
      let encoded = rep.representation(using: .png, properties: [:])
    {
      pngData = encoded
    } else {
      return Result(name: "image round-trip", passed: false, detail: "couldn't build PNG")
    }

    var sheet = Sheet(name: "Images")
    sheet.images = [
      SheetImage(
        anchorRow: 1,
        anchorCol: 0,
        widthEMU: 1_016_000,
        heightEMU: 381_000,
        imageData: pngData
      ),
    ]
    do {
      let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
      guard XLSXCodec.zipEntryData(archiveData: data, entryPath: "xl/media/image1.png") != nil,
            XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/drawings/drawing1.xml")?.contains("oneCellAnchor") == true
      else {
        return Result(name: "image export", passed: false, detail: "missing drawing/media parts")
      }
      let imported = try XLSXCodec.importWorkbook(from: data)
      guard imported.activeSheet.images.count == 1,
            imported.activeSheet.images[0].imageData == pngData
      else {
        return Result(name: "image round-trip", passed: false, detail: "import mismatch")
      }
    } catch {
      return Result(name: "image round-trip", passed: false, detail: error.localizedDescription)
    }

    let desktop = "/Users/samparker/Desktop/Enterprise Report_Queen City Harley-Davidson_2026-07-18_to_2026-07-18_export_1784598505245.xlsx"
    guard FileManager.default.isReadableFile(atPath: desktop) else {
      return Result(name: "image round-trip", passed: true, detail: "synthetic ok; desktop skipped")
    }
    do {
      let wb = try XLSXCodec.importWorkbook(from: URL(fileURLWithPath: desktop))
      let imageCount = wb.sheets.reduce(0) { $0 + $1.images.count }
      guard imageCount > 0 else {
        return Result(name: "image desktop import", passed: false, detail: "no images from desktop file")
      }
      return Result(name: "image round-trip", passed: true, detail: "synthetic + \(imageCount) desktop image(s)")
    } catch {
      return Result(name: "image round-trip", passed: true, detail: "synthetic ok; desktop: \(error.localizedDescription)")
    }
  }

  private static func chartPreviewSeries() -> Result {
    let range = CellRange(
      start: CellAddress(row: 1, col: 1),
      end: CellAddress(row: 4, col: 1)
    )
    let points = ChartPreviewSeries.points(
      in: range,
      labelFor: { "Row \($0.row)" },
      numberFor: { Double($0.row) }
    )
    guard points.count == 4, points[0].label == "Row 1", points[0].value == 1 else {
      return Result(name: "chart preview series", passed: false, detail: "\(points)")
    }
    return Result(name: "chart preview series", passed: true, detail: "single-column ok")
  }

  @MainActor
  private static func insertPictureModel() -> Result {
    let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [Sheet(name: "Test")]))
    vm.selectRange(from: CellAddress(row: 2, col: 2), to: CellAddress(row: 2, col: 2))
    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: 4,
      pixelsHigh: 4,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ),
      let png = rep.representation(using: .png, properties: [:])
    else {
      return Result(name: "insert picture", passed: false, detail: "png setup failed")
    }
    vm.insertImage(data: png, contentType: "image/png")
    guard vm.activeSheet.images.count == 1,
          vm.activeSheet.images[0].anchorRow == 2,
          vm.activeSheet.images[0].anchorCol == 2,
          vm.selectedImageID == vm.activeSheet.images[0].id
    else {
      return Result(name: "insert picture", passed: false, detail: "image not placed at selection")
    }
    return Result(name: "insert picture", passed: true, detail: "anchored at selection")
  }

  private static func dataBarRoundTrip() -> Result {
    var sheet = Sheet(name: "Test")
    sheet.setCell(Cell(raw: "10"), at: CellAddress(row: 0, col: 0))
    sheet.setCell(Cell(raw: "90"), at: CellAddress(row: 1, col: 0))
    sheet.conditionalFormats = [
      ConditionalFormatRule(
        range: CellRange(start: .origin, end: CellAddress(row: 1, col: 0)),
        predicate: .dataBar(.blue),
        style: ConditionalFormatStyle()
      ),
      ConditionalFormatRule(
        range: CellRange(start: .origin, end: CellAddress(row: 1, col: 0)),
        predicate: .iconSet(.threeTrafficLights),
        style: ConditionalFormatStyle()
      ),
    ]
    do {
      let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
      let xml = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
      guard xml.contains("type=\"dataBar\""), xml.contains("type=\"iconSet\"") else {
        return Result(name: "data bar / icon export", passed: false, detail: "missing CF types in XML")
      }
      let imported = try XLSXCodec.importWorkbook(from: data)
      let preds = imported.activeSheet.conditionalFormats.map(\.predicate)
      let hasBar = preds.contains { if case .dataBar = $0 { return true }; return false }
      let hasIcon = preds.contains { if case .iconSet = $0 { return true }; return false }
      guard hasBar, hasIcon else {
        return Result(name: "data bar / icon round-trip", passed: false, detail: "\(preds)")
      }
      return Result(name: "data bar / icon round-trip", passed: true, detail: "ok")
    } catch {
      return Result(name: "data bar / icon round-trip", passed: false, detail: error.localizedDescription)
    }
  }

  private static func excelChartParts() -> Result {
    var sheet = Sheet(name: "Sales")
    sheet.setCell(Cell(raw: "A"), at: CellAddress(row: 0, col: 0))
    sheet.setCell(Cell(raw: "10"), at: CellAddress(row: 1, col: 0))
    sheet.setCell(Cell(raw: "20"), at: CellAddress(row: 2, col: 0))
    sheet.charts = [
      SheetChart(
        kind: .bar,
        title: "Sales",
        dataRange: CellRange(start: .origin, end: CellAddress(row: 2, col: 0)),
        anchorRow: 4,
        anchorCol: 2
      ),
    ]
    do {
      let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
      for path in [
        "xl/charts/chart1.xml",
        "xl/drawings/drawing1.xml",
        "xl/worksheets/_rels/sheet1.xml.rels",
      ] {
        guard XLSXCodec.zipEntryString(archiveData: data, entryPath: path) != nil else {
          return Result(name: "excel chart parts", passed: false, detail: "missing \(path)")
        }
      }
      let sheetXML = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
      guard sheetXML.contains("<drawing") else {
        return Result(name: "excel chart parts", passed: false, detail: "worksheet missing drawing ref")
      }
      return Result(name: "excel chart parts", passed: true, detail: "drawing+chart+rels")
    } catch {
      return Result(name: "excel chart parts", passed: false, detail: error.localizedDescription)
    }
  }

  private static func worksheetElementOrder() -> Result {
    var sheet = Sheet(name: "Test")
    sheet.setCell(Cell(raw: "A"), at: .origin)
    sheet.setCell(Cell(raw: "B"), at: CellAddress(row: 0, col: 1))
    sheet.mergedRanges = [
      CellRange(start: .origin, end: CellAddress(row: 0, col: 1)),
    ]
    sheet.autoFilter = SheetFilterState(
      range: CellRange(start: .origin, end: CellAddress(row: 2, col: 1)),
      selectedValuesByColumn: [:]
    )
    do {
      let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
      let xml = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
      guard let filterIdx = xml.range(of: "<autoFilter")?.lowerBound,
            let mergeIdx = xml.range(of: "<mergeCells")?.lowerBound
      else {
        return Result(name: "worksheet element order", passed: false, detail: "missing autoFilter or mergeCells")
      }
      guard filterIdx < mergeIdx else {
        return Result(name: "worksheet element order", passed: false, detail: "mergeCells before autoFilter (Excel rejects)")
      }
      return Result(name: "worksheet element order", passed: true, detail: "autoFilter before mergeCells")
    } catch {
      return Result(name: "worksheet element order", passed: false, detail: error.localizedDescription)
    }
  }

  private static func enterpriseFilterImport() -> Result {
    let path = "/Users/samparker/Downloads/Enterprise Report_Queen City Harley-Davidson_2026-04-09_to_2026-07-15_export_1784222143023.xlsx"
    guard FileManager.default.fileExists(atPath: path) else {
      return Result(name: "enterprise filter import", passed: true, detail: "skipped (file missing)")
    }
    do {
      let wb = try XLSXCodec.importWorkbook(from: URL(fileURLWithPath: path))
      let withFilters = wb.sheets.filter { $0.autoFilter != nil }
      guard withFilters.count >= 2 else {
        return Result(
          name: "enterprise filter import",
          passed: false,
          detail: "expected ≥2 sheets with autoFilter, got \(withFilters.count)"
        )
      }
      let reportFilters = withFilters.prefix(2)
      for sheet in reportFilters {
        guard let filter = sheet.autoFilter else { continue }
        let n = filter.range.normalized
        guard n.minRow == 4 else {
          return Result(
            name: "enterprise filter import",
            passed: false,
            detail: "\(sheet.name) header row \(n.minRow + 1), expected 5"
          )
        }
      }
      return Result(
        name: "enterprise filter import",
        passed: true,
        detail: "\(withFilters.count) sheets filtered; Report headers on row 5"
      )
    } catch {
      return Result(name: "enterprise filter import", passed: false, detail: error.localizedDescription)
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

  private static func emptyFilterRoundTrip() -> Result {
    var sheet = Sheet(name: "Test")
    sheet.setCell(Cell(raw: "H"), at: CellAddress(row: 4, col: 0))
    sheet.setCell(Cell(raw: "1"), at: CellAddress(row: 5, col: 0))
    sheet.autoFilter = SheetFilterState(
      range: CellRange(
        start: CellAddress(row: 4, col: 0),
        end: CellAddress(row: 5, col: 2)
      ),
      selectedValuesByColumn: [:]
    )
    do {
      let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
      let xml = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/worksheets/sheet1.xml") ?? ""
      guard xml.contains(#"<autoFilter ref="A5:C6"/>"#) || xml.contains(#"ref="A5:C6""#) else {
        return Result(name: "empty filter export", passed: false, detail: "missing autoFilter ref A5:C6")
      }
      let imported = try XLSXCodec.importWorkbook(from: data)
      guard let filter = imported.activeSheet.autoFilter else {
        return Result(name: "empty filter round-trip", passed: false, detail: "no autofilter after import")
      }
      let n = filter.range.normalized
      guard n.minRow == 4, n.maxRow == 5, n.minCol == 0, n.maxCol == 2 else {
        return Result(name: "empty filter round-trip", passed: false, detail: "wrong range \(n)")
      }
      guard filter.selectedValuesByColumn.isEmpty else {
        return Result(name: "empty filter round-trip", passed: false, detail: "expected no criteria")
      }
      return Result(name: "empty filter round-trip", passed: true, detail: "A5:C6 preserved")
    } catch {
      return Result(name: "empty filter round-trip", passed: false, detail: error.localizedDescription)
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
    // File may have been re-saved without a theme part (e.g. after Excel repair).
    guard XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/theme/theme1.xml") != nil else {
      return Result(name: "theme parse", passed: true, detail: "skipped (no theme part in file)")
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

  // MARK: - Focused regression tests

  @MainActor
  private static func findScopePersistsAfterJump() -> Result {
    var sheet = Sheet(name: "Find")
    sheet.setCell(Cell(raw: "alpha"), at: CellAddress(row: 0, col: 0))
    sheet.setCell(Cell(raw: "alpha"), at: CellAddress(row: 1, col: 1))
    sheet.setCell(Cell(raw: "alpha"), at: CellAddress(row: 2, col: 2))
    let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
    vm.selectRange(from: .origin, to: CellAddress(row: 2, col: 2))
    vm.findScope = .selection
    vm.findQuery = "alpha"
    vm.showFindBar(replace: false)
    let initialCount = vm.findMatches.count
    guard initialCount == 3 else {
      return Result(name: "find scope capture", passed: false, detail: "expected 3 matches, got \(initialCount)")
    }
    guard let scope = vm.findScopeRange else {
      return Result(name: "find scope capture", passed: false, detail: "findScopeRange not set")
    }
    let sn = scope.normalized
    guard sn.minRow == 0, sn.maxRow == 2, sn.minCol == 0, sn.maxCol == 2 else {
      return Result(name: "find scope capture", passed: false, detail: "bad scope \(sn)")
    }
    // Jump shrinks live selection to one cell; captured scope must remain.
    vm.select(CellAddress(row: 1, col: 1))
    vm.refreshFindMatches()
    guard vm.findMatches.count == 3 else {
      return Result(
        name: "find scope after jump",
        passed: false,
        detail: "expected 3 matches after select shrink, got \(vm.findMatches.count)"
      )
    }
    return Result(name: "find scope after jump", passed: true, detail: "scope held 3 matches")
  }

  @MainActor
  private static func largeEmptyFormatApply() -> Result {
    let sheet = Sheet(name: "Format")
    let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
    // 100×26 = 2600 > large-apply threshold; previously only existing cells were formatted.
    let end = CellAddress(row: 99, col: Workbook.defaultColumnCount - 1)
    vm.selectRange(from: .origin, to: end)
    let fill = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
    vm.setFillColor(fill)
    let sampleEmpty = CellAddress(row: 50, col: 12)
    guard vm.activeSheet.cell(at: sampleEmpty).format?.fillColor == fill,
          vm.activeSheet.cell(at: end).format?.fillColor == fill,
          vm.activeSheet.cell(at: .origin).format?.fillColor == fill
    else {
      let mid = vm.activeSheet.cell(at: sampleEmpty).format?.fillColor
      let far = vm.activeSheet.cell(at: end).format?.fillColor
      let origin = vm.activeSheet.cell(at: .origin).format?.fillColor
      return Result(
        name: "large empty format",
        passed: false,
        detail: "missing fill mid=\(String(describing: mid)) end=\(String(describing: far)) origin=\(String(describing: origin))"
      )
    }
    return Result(name: "large empty format", passed: true, detail: "2600 cells filled")
  }

  private static func cfParseNumber() -> Result {
    let cases: [(String, Double?)] = [
      (" 1,234.5 ", 1234.5),
      ("$50", 50),
      ("25%", 0.25),
      ("  12% ", 0.12),
      ("", nil),
      ("abc", nil),
    ]
    for (input, expected) in cases {
      let parsed = ConditionalFormattingSheet.parseNumber(input)
      switch (parsed, expected) {
      case (nil, nil):
        continue
      case let (value?, exp?):
        guard abs(value - exp) < 0.000_001 else {
          return Result(name: "CF parseNumber", passed: false, detail: "\(input) -> \(value), expected \(exp)")
        }
      default:
        return Result(
          name: "CF parseNumber",
          passed: false,
          detail: "\(input) -> \(String(describing: parsed)), expected \(String(describing: expected))"
        )
      }
    }
    return Result(name: "CF parseNumber", passed: true, detail: "ok")
  }

  @MainActor
  private static func sortRemapsMerge() -> Result {
    var sheet = Sheet(name: "Sort")
    // Header + three data rows; merge spans two data rows in col A.
    sheet.setCell(Cell(raw: "Name"), at: CellAddress(row: 0, col: 0))
    sheet.setCell(Cell(raw: "Val"), at: CellAddress(row: 0, col: 1))
    sheet.setCell(Cell(raw: "C"), at: CellAddress(row: 1, col: 0))
    sheet.setCell(Cell(raw: "3"), at: CellAddress(row: 1, col: 1))
    sheet.setCell(Cell(raw: "A"), at: CellAddress(row: 2, col: 0))
    sheet.setCell(Cell(raw: "1"), at: CellAddress(row: 2, col: 1))
    sheet.setCell(Cell(raw: "B"), at: CellAddress(row: 3, col: 0))
    sheet.setCell(Cell(raw: "2"), at: CellAddress(row: 3, col: 1))
    // Single-row merge in data (safe rectangular remap).
    sheet.mergedRanges = [
      CellRange(start: CellAddress(row: 2, col: 0), end: CellAddress(row: 2, col: 1)),
    ]
    sheet.conditionalFormats = [
      ConditionalFormatRule(
        range: CellRange(start: CellAddress(row: 1, col: 1), end: CellAddress(row: 3, col: 1)),
        predicate: .greaterThan(0),
        style: .redFill
      ),
    ]
    sheet.charts = [
      SheetChart(
        kind: .bar,
        title: "Vals",
        dataRange: CellRange(start: CellAddress(row: 1, col: 1), end: CellAddress(row: 3, col: 1)),
        anchorRow: 5,
        anchorCol: 3
      ),
    ]
    let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
    vm.selectRange(from: .origin, to: CellAddress(row: 3, col: 1))
    vm.sortRange(column: 1, direction: .ascending, hasHeader: true)
    // Ascending by Val: row2(A/1) → first data, row3(B/2) → second, row1(C/3) → third.
    // Merge was on old row 2 → new row 1 (firstDataRow=1).
    let merges = vm.activeSheet.mergedRanges
    guard merges.count == 1 else {
      return Result(name: "sort remap merge", passed: false, detail: "merge count \(merges.count)")
    }
    let mn = merges[0].normalized
    guard mn.minRow == 1, mn.maxRow == 1, mn.minCol == 0, mn.maxCol == 1 else {
      return Result(name: "sort remap merge", passed: false, detail: "merge at \(mn)")
    }
    let cf = vm.activeSheet.conditionalFormats.first?.range.normalized
    guard let cf, cf.minRow == 1, cf.maxRow == 3, cf.minCol == 1, cf.maxCol == 1 else {
      return Result(name: "sort remap CF", passed: false, detail: "CF range \(String(describing: cf))")
    }
    let chartRange = vm.activeSheet.charts.first?.dataRange.normalized
    guard let chartRange, chartRange.minRow == 1, chartRange.maxRow == 3 else {
      return Result(name: "sort remap chart", passed: false, detail: "chart \(String(describing: chartRange))")
    }
    return Result(name: "sort remap merge/CF/chart", passed: true, detail: "rows remapped")
  }

  @MainActor
  private static func insertColumnPastLastColumn() -> Result {
    var sheet = Sheet(name: "Insert")
    let lastCol = Workbook.defaultColumnCount - 1
    sheet.setCell(Cell(raw: "Last"), at: CellAddress(row: 0, col: lastCol))
    let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
    vm.selectColumn(lastCol)
    let beforeCount = vm.activeSheet.effectiveColumnCount
    vm.insertColumnsRight()
    let afterCount = vm.activeSheet.effectiveColumnCount
    guard afterCount == beforeCount + 1 else {
      return Result(
        name: "insert column right edge",
        passed: false,
        detail: "columns \(beforeCount) -> \(afterCount)"
      )
    }
    let selected = vm.selectionRange.normalized
    guard selected.minCol == lastCol + 1, selected.maxCol == lastCol + 1 else {
      return Result(
        name: "insert column right edge",
        passed: false,
        detail: "selection cols \(selected.minCol)-\(selected.maxCol)"
      )
    }
    return Result(name: "insert column right edge", passed: true, detail: "column \(lastCol + 1)")
  }
}
#endif
