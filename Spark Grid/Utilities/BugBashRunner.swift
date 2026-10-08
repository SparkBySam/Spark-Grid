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
    results.append(importSmoke(fixture: .formulas, label: "formulas"))
    results.append(importSmoke(fixture: .conditionalFormat, label: "CF bash"))
    results.append(importSmoke(fixture: .enterpriseThemed, label: "enterprise themed"))
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
    results.append(MainActor.assumeIsolated { selectionSizedInsert() })
    results.append(MainActor.assumeIsolated { freezeThroughSelection() })
    results.append(MainActor.assumeIsolated { insertChartEmptySelection() })
    results.append(formulaExactTokenSkipsAutocomplete())
    results.append(MainActor.assumeIsolated { editExistingChart() })
    results.append(onSheetChartFrame())
    results.append(chartPlotPaddingBounded())
    results.append(chartScaleDomainHolds())
    results.append(weeklyCallsLastLabel())
    results.append(chartValueColors())
    results.append(chartFrameDrag())
    results.append(chartCommandFreePlacement())
    results.append(chartSlidesUnderFrozenPanes())
    results.append(MainActor.assumeIsolated { frozenPanesCoverChartPixels() })
    results.append(MainActor.assumeIsolated { chartMoveResizeAndColorRoundTrip() })
    results.append(legacyChartLandsUnderData())
    results.append(cfFillTextContrast())
    results.append(everydayFormulas())
    results.append(lookupFormulas())
    results.append(formulaFunctionPicker())
    results.append(excelFormatCodes())
    results.append(definedNamesResolve())
    results.append(MainActor.assumeIsolated { nameManagerEditsSheet() })
    results.append(MainActor.assumeIsolated { cellFormatCodeEditsSheet() })
    results.append(MainActor.assumeIsolated { conditionalFormatRuleEdit() })
    results.append(cellTextOverflowAndClip())
    results.append(MainActor.assumeIsolated { cellTextWrapLayout() })
    results.append(MainActor.assumeIsolated { textDisplayToolbarLabel() })
    results.append(MainActor.assumeIsolated { unsavedPromptOnce() })
    results.append(MainActor.assumeIsolated { conditionalFormatPaste() })
    return results
  }

  /// Optional local xlsx samples for import/round-trip checks.
  /// Set `SPARK_GRID_FIXTURES` to a directory of generic filenames, or override a single
  /// file with the matching `SPARK_GRID_FIXTURE_*` env var (absolute path).
  private enum Fixture: String {
    case formulas
    case conditionalFormat = "conditional_format"
    case enterpriseThemed = "enterprise_themed"
    case enterpriseImages = "enterprise_images"

    var envKey: String {
      switch self {
      case .formulas: return "SPARK_GRID_FIXTURE_FORMULAS"
      case .conditionalFormat: return "SPARK_GRID_FIXTURE_CF"
      case .enterpriseThemed: return "SPARK_GRID_FIXTURE_ENTERPRISE"
      case .enterpriseImages: return "SPARK_GRID_FIXTURE_ENTERPRISE_IMAGES"
      }
    }

    var fileName: String { "\(rawValue).xlsx" }
  }

  private static func fixturePath(_ fixture: Fixture) -> String? {
    let env = ProcessInfo.processInfo.environment
    if let explicit = env[fixture.envKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !explicit.isEmpty,
       FileManager.default.fileExists(atPath: explicit)
    {
      return explicit
    }
    if let dir = env["SPARK_GRID_FIXTURES"]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !dir.isEmpty
    {
      let path = (dir as NSString).appendingPathComponent(fixture.fileName)
      if FileManager.default.fileExists(atPath: path) { return path }
    }
    return nil
  }

  private static func sharedFormulaRoundTrip() -> Result {
    guard let path = fixturePath(.formulas) else {
      return Result(name: "shared formula round-trip", passed: true, detail: "skipped (no fixture)")
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
    guard let path = fixturePath(.conditionalFormat) else {
      return Result(name: "CF import", passed: true, detail: "skipped (no fixture)")
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

    guard let samplePath = fixturePath(.enterpriseImages) else {
      return Result(name: "image round-trip", passed: true, detail: "synthetic ok; sample fixture skipped")
    }
    do {
      let wb = try XLSXCodec.importWorkbook(from: URL(fileURLWithPath: samplePath))
      let imageCount = wb.sheets.reduce(0) { $0 + $1.images.count }
      guard imageCount > 0 else {
        return Result(name: "image sample import", passed: false, detail: "no images in sample fixture")
      }
      return Result(name: "image round-trip", passed: true, detail: "synthetic + \(imageCount) sample image(s)")
    } catch {
      return Result(name: "image round-trip", passed: true, detail: "synthetic ok; sample: \(error.localizedDescription)")
    }
  }

  private static func chartPreviewSeries() -> Result {
    // Count-by-category (CRM-style): dates in col 0, junk ids in col 1.
    let range = CellRange(
      start: CellAddress(row: 0, col: 0),
      end: CellAddress(row: 3, col: 1)
    )
    let labels = ["Lead Date", "8/1/26", "8/1/26", "8/2/26"]
    let ids = ["Lead ID", "100", "200", "300"]
    let chart = SheetChart(
      kind: .bar,
      title: "Count by Lead Date",
      dataRange: range,
      categoryColumn: 0,
      valueColumn: 1,
      hasHeaderRow: true,
      valueMode: .count,
      anchorRow: 5,
      anchorCol: 0
    )
    let series = ChartPreviewSeries.points(
      for: chart,
      labelFor: { address in
        address.col == 0 ? labels[address.row] : ids[address.row]
      },
      numberFor: { address in
        address.col == 1 ? Double(ids[address.row]) : nil
      }
    )
    guard series.points.count == 2,
          series.points[0].label == "8/1/26",
          series.points[0].value == 2,
          series.points[1].label == "8/2/26",
          series.points[1].value == 1
    else {
      return Result(name: "chart preview series", passed: false, detail: "\(series.points)")
    }

    let suggestion = ChartPreviewSeries.suggest(
      in: range,
      labelFor: { address in
        address.col == 0 ? labels[address.row] : ids[address.row]
      },
      numberFor: { address in
        // Treat Lead ID as non-chart numeric noise: only pure small ints from a metrics col.
        nil
      }
    )
    guard suggestion.valueMode == .count, suggestion.categoryColumn == 0 else {
      return Result(name: "chart preview series", passed: false, detail: "bad suggestion \(suggestion)")
    }
    return Result(name: "chart preview series", passed: true, detail: "count-by-category ok")
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
    guard let path = fixturePath(.enterpriseThemed) else {
      return Result(name: "enterprise filter import", passed: true, detail: "skipped (no fixture)")
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

  private static func importSmoke(fixture: Fixture, label: String) -> Result {
    guard let path = fixturePath(fixture) else {
      return Result(name: "import \(label)", passed: true, detail: "skipped (no fixture)")
    }
    let url = URL(fileURLWithPath: path)
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
      let saved = imported.activeSheet.charts
      guard saved.count == 1,
            saved[0].title == "Test",
            saved[0].anchorRow == 4,
            saved[0].anchorCol == 0
      else {
        return Result(name: "chart round-trip", passed: false, detail: "charts: \(saved)")
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
    guard let path = fixturePath(.enterpriseThemed),
          let data = try? Data(contentsOf: URL(fileURLWithPath: path))
    else {
      return Result(name: "theme parse", passed: true, detail: "skipped (no fixture)")
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

  @MainActor
  private static func insertChartEmptySelection() -> Result {
    let name = "insert chart empty selection"
    var sheet = Sheet(name: "Charts")
    sheet.setCell(Cell(raw: "Name"), at: .origin)
    sheet.setCell(Cell(raw: "Ada"), at: CellAddress(row: 1, col: 0))
    sheet.setCell(Cell(raw: "10"), at: CellAddress(row: 1, col: 1))
    let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
    guard vm.selectionRange.isSingleCell else {
      return Result(name: name, passed: false, detail: "expected a single-cell selection")
    }
    guard vm.chartSelectionRange == nil else {
      return Result(name: name, passed: false, detail: "invented a range from nearby cells")
    }
    vm.beginInsertChart(preferredKind: .line)
    guard vm.isInsertChartPresented, vm.pendingChartKind == .line else {
      return Result(name: name, passed: false, detail: "chart menu did not open")
    }
    guard vm.activeSheet.charts.isEmpty else {
      return Result(name: name, passed: false, detail: "chart created before a range was chosen")
    }
    let refused = vm.insertChart(
      SheetChart(kind: .bar, dataRange: .singleOrigin, anchorRow: 0, anchorCol: 0)
    )
    guard !refused, vm.activeSheet.charts.isEmpty, vm.isInsertChartPresented else {
      return Result(name: name, passed: false, detail: "single-cell insert was accepted")
    }
    guard ChartDataRangeParser.parse("") == nil,
          ChartDataRangeParser.parse("A1") == nil,
          ChartDataRangeParser.parse("A1:A1") == nil,
          ChartDataRangeParser.parse("A:A") == nil,
          ChartDataRangeParser.parse("Sheet1!A1:B2") == nil
    else {
      return Result(name: name, passed: false, detail: "parser accepted an empty selection")
    }
    guard let parsed = ChartDataRangeParser.parse("A1:B2"), !parsed.isSingleCell else {
      return Result(name: name, passed: false, detail: "parser rejected A1:B2")
    }
    let inserted = vm.insertChart(
      SheetChart(
        kind: .line,
        title: "Picked",
        dataRange: parsed,
        categoryColumn: 0,
        valueColumn: 1,
        anchorRow: 4,
        anchorCol: 0
      )
    )
    guard inserted, vm.activeSheet.charts.count == 1, vm.activeSheet.charts[0].dataRange == parsed else {
      return Result(name: name, passed: false, detail: "explicit range was not inserted")
    }
    guard !vm.isInsertChartPresented else {
      return Result(name: name, passed: false, detail: "menu stayed open after insert")
    }

    let ranged = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
    ranged.selectRange(from: .origin, to: CellAddress(row: 1, col: 1))
    guard let chosen = ranged.chartSelectionRange, !chosen.isSingleCell else {
      return Result(name: name, passed: false, detail: "multi-cell selection was dropped")
    }
    ranged.beginInsertChart()
    guard ranged.isInsertChartPresented, ranged.activeSheet.charts.isEmpty else {
      return Result(name: name, passed: false, detail: "ranged insert opened wrong")
    }
    return Result(name: name, passed: true, detail: "menu opens; chart waits for a range")
  }

  /// `=SU` still offers SUM. After that token is `=SUM`, the popup must stay
  /// closed so Return commits the cell instead of accepting SUM again.
  private static func formulaExactTokenSkipsAutocomplete() -> Result {
    let named: [String] = []
    let offersPartial = FormulaAutocomplete.shouldOfferPopup(in: "=SU", utf16Cursor: 3, namedRanges: named)
    let offersExact = FormulaAutocomplete.shouldOfferPopup(in: "=SUM", utf16Cursor: 4, namedRanges: named)
    let offersLower = FormulaAutocomplete.shouldOfferPopup(in: "=sum", utf16Cursor: 4, namedRanges: named)
    guard offersPartial, !offersExact, !offersLower else {
      return Result(
        name: "formula exact token",
        passed: false,
        detail: "popup SU=\(offersPartial) SUM=\(offersExact) sum=\(offersLower)"
      )
    }
    guard FormulaAutocomplete.isExactCompletion(partial: "SUM", completion: "SUM"),
          !FormulaAutocomplete.isExactCompletion(partial: "SU", completion: "SUM")
    else {
      return Result(name: "formula exact token", passed: false, detail: "exact-match check failed")
    }
    let matches = FormulaAutocomplete.suggestions(matching: "SUM", namedRanges: named)
    guard matches == ["SUM"] else {
      return Result(name: "formula exact token", passed: false, detail: "SUM matches \(matches)")
    }
    return Result(name: "formula exact token", passed: true, detail: "=SU offers popup; =SUM does not")
  }

  @MainActor
  private static func editExistingChart() -> Result {
    let name = "edit existing chart"
    var sheet = Sheet(name: "Weekly Calls")
    sheet.setCell(Cell(raw: "Week"), at: .origin)
    sheet.setCell(Cell(raw: "Calls"), at: CellAddress(row: 0, col: 1))
    for index in 1...4 {
      sheet.setCell(Cell(raw: "Week \(index)"), at: CellAddress(row: index, col: 0))
      sheet.setCell(Cell(raw: "\(index * 3)"), at: CellAddress(row: index, col: 1))
    }
    let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
    let range = CellRange(start: .origin, end: CellAddress(row: 4, col: 1))
    let inserted = vm.insertChart(
      SheetChart(
        kind: .bar,
        title: "Calls by Week",
        dataRange: range,
        categoryColumn: 0,
        valueColumn: 1,
        hasHeaderRow: true,
        valueMode: .values,
        anchorRow: 7,
        anchorCol: 0,
        rowSpan: 12,
        colSpan: 8
      )
    )
    guard inserted, vm.activeSheet.charts.count == 1 else {
      return Result(name: name, passed: false, detail: "chart was not inserted")
    }
    let original = vm.activeSheet.charts[0]
    guard vm.selectedChartID == original.id else {
      return Result(name: name, passed: false, detail: "inserted chart was not selected on the sheet")
    }
    vm.beginEditChart(id: original.id)
    guard vm.isInsertChartPresented, vm.editingChartID == original.id, vm.activeSheet.charts.count == 1 else {
      return Result(name: name, passed: false, detail: "edit did not reopen the existing chart")
    }
    var edited = original
    edited.kind = .line
    edited.categoryColumn = 1
    edited.valueColumn = 0
    edited.valueMode = .count
    edited.title = "Calls by Week"
    guard vm.updateChart(edited) else {
      return Result(name: name, passed: false, detail: "update was refused")
    }
    guard vm.activeSheet.charts.count == 1 else {
      return Result(name: name, passed: false, detail: "update inserted a second chart")
    }
    let saved = vm.activeSheet.charts[0]
    guard saved.id == original.id,
          saved.kind == .line,
          saved.categoryColumn == 1,
          saved.valueColumn == 0,
          saved.valueMode == .count,
          saved.dataRange == range,
          saved.anchorRow == 7,
          saved.anchorCol == 0,
          saved.rowSpan == 12,
          saved.colSpan == 8,
          !vm.isInsertChartPresented,
          vm.editingChartID == nil
    else {
      return Result(name: name, passed: false, detail: "saved \(saved.kind) anchor \(saved.anchorRow),\(saved.anchorCol)")
    }
    var rejected = saved
    rejected.dataRange = .singleOrigin
    guard !vm.updateChart(rejected), vm.activeSheet.charts[0].dataRange == range else {
      return Result(name: name, passed: false, detail: "single-cell edit was accepted")
    }
    vm.selection = .origin
    vm.beginInsertChart(preferredKind: .bar)
    guard vm.editingChartID == nil, vm.isInsertChartPresented, vm.chartSelectionRange == nil else {
      return Result(name: name, passed: false, detail: "empty selection started an edit")
    }
    guard vm.activeSheet.charts.count == 1 else {
      return Result(name: name, passed: false, detail: "empty selection created a chart")
    }
    return Result(name: name, passed: true, detail: "type, range, and series update; anchor stays")
  }

  private static func onSheetChartFrame() -> Result {
    let name = "on-sheet chart frame"
    let frame = OnSheetChartGeometry.frame(
      anchorRow: 7,
      anchorCol: 0,
      rowSpan: 12,
      colSpan: 8,
      rowCount: 1_000,
      columnCount: 26,
      xForColumn: { 28 + CGFloat($0) * 80 },
      yForRow: { 28 + CGFloat($0) * 22 },
      columnWidth: { _ in 80 },
      rowHeight: { _ in 22 }
    )
    guard frame.width == 640, frame.height == 264, frame.minX == 28, frame.minY == 28 + 7 * 22 else {
      return Result(name: name, passed: false, detail: "\(frame)")
    }
    let dataBottom: CGFloat = 28 + 5 * 22
    guard frame.minY >= dataBottom else {
      return Result(name: name, passed: false, detail: "chart covers the data rows")
    }
    guard OnSheetChartGeometry.placedHeight(top: frame.minY, bottom: frame.maxY) == frame.height else {
      return Result(name: name, passed: false, detail: "placed height \(String(describing: OnSheetChartGeometry.placedHeight(top: frame.minY, bottom: frame.maxY)))")
    }
    // bottom - top is negative when the lower edge sits above the upper edge.
    guard OnSheetChartGeometry.placedHeight(top: 400, bottom: 120) == nil else {
      return Result(name: name, passed: false, detail: "reversed edges were treated as a view height")
    }
    guard OnSheetChartGeometry.placedHeight(top: 10, bottom: 10.5) == nil else {
      return Result(name: name, passed: false, detail: "sub-point height was placed")
    }
    let collapsed = OnSheetChartGeometry.frame(
      anchorRow: 0,
      anchorCol: 0,
      rowSpan: 12,
      colSpan: 4,
      rowCount: 100,
      columnCount: 8,
      xForColumn: { CGFloat($0) * 80 },
      yForRow: { 400 - CGFloat($0) * 30 },
      columnWidth: { _ in 80 },
      rowHeight: { _ in -10 }
    )
    guard collapsed == .zero else {
      return Result(name: name, passed: false, detail: "negative row span produced \(collapsed)")
    }
    let scrolled = OnSheetChartGeometry.frame(
      anchorRow: 0,
      anchorCol: 0,
      rowSpan: 12,
      colSpan: 4,
      rowCount: 100,
      columnCount: 8,
      xForColumn: { CGFloat($0) * 80 },
      yForRow: { row in
        row < 2 ? CGFloat(row) * 22 : CGFloat(row) * 22 - 800
      },
      columnWidth: { _ in 80 },
      rowHeight: { _ in 22 }
    )
    guard scrolled.height >= 1, scrolled.height == 12 * 22 else {
      return Result(name: name, passed: false, detail: "scrolled span \(scrolled.height)")
    }
    return Result(name: name, passed: true, detail: "\(Int(frame.width))×\(Int(frame.height)) at row 7")
  }

  /// `SheetChartView` hands `.chartPlotStyle { plot.padding(.bottom, _) }` a
  /// value that must stay under whatever height the chart is actually given;
  /// otherwise Charts computes a negative plot height in
  /// `PositionScaleRange.plotFrame` and traps. A normal multi-cell chart
  /// (plenty of height) must still get the full 20pt inset for category
  /// labels — this only has to shrink once the proposed height is small
  /// (side panel mid-resize, first layout, or a squeezed on-sheet card).
  private static func chartPlotPaddingBounded() -> Result {
    let name = "chart plot padding bounded"
    let ideal = SheetChartView.plotBottomInset
    let minimum = SheetChartView.minimumPlotHeight
    // A normal 8×12 chart card has well over `minimum` to spare: full padding.
    let roomy = SheetChartView.clampedBottomPadding(idealPadding: ideal, availableHeight: 236)
    guard roomy == ideal else {
      return Result(name: name, passed: false, detail: "roomy chart lost its padding: \(roomy)")
    }
    // Exactly `ideal + minimum` is the last height that still affords full padding.
    let boundary = SheetChartView.clampedBottomPadding(idealPadding: ideal, availableHeight: ideal + minimum)
    guard boundary == ideal else {
      return Result(name: name, passed: false, detail: "boundary height lost its padding: \(boundary)")
    }
    // Below that, padding must shrink by exactly the shortfall — plot height
    // stays pinned at `minimum`, never negative.
    for availableHeight: CGFloat in [minimum, minimum + 8, ideal + minimum - 1, 10, 1] {
      let padding = SheetChartView.clampedBottomPadding(idealPadding: ideal, availableHeight: availableHeight)
      guard padding >= 0, padding <= availableHeight, availableHeight - padding >= min(minimum, availableHeight) else {
        return Result(name: name, passed: false, detail: "height \(availableHeight) padding \(padding) went negative")
      }
    }
    // A degenerate or reversed proposal must never produce negative padding.
    for availableHeight: CGFloat in [0, -5] {
      let padding = SheetChartView.clampedBottomPadding(idealPadding: ideal, availableHeight: availableHeight)
      guard padding == 0 else {
        return Result(name: name, passed: false, detail: "non-positive height \(availableHeight) kept padding \(padding)")
      }
    }
    return Result(name: name, passed: true, detail: "padding stays within the proposed height at every size")
  }

  /// Insert Chart on Weekly Calls must hand Charts a finite domain with
  /// `lower < upper`. An empty, NaN, or reversed domain hits the same
  /// `PositionScaleRange.plotFrame` trap as a negative plot height.
  private static func chartScaleDomainHolds() -> Result {
    let name = "chart scale domain"
    func holds(_ domain: ClosedRange<Double>?) -> Bool {
      guard let domain else { return false }
      return domain.lowerBound.isFinite
        && domain.upperBound.isFinite
        && domain.lowerBound < domain.upperBound
    }
    let weeklyValues = [3.0, 6, 9, 12]
    guard let weekly = SheetChartView.plotValueDomain(values: weeklyValues),
          holds(weekly),
          weekly.lowerBound <= 0,
          weekly.upperBound > 12
    else {
      return Result(name: name, passed: false, detail: "weekly \(String(describing: SheetChartView.plotValueDomain(values: weeklyValues)))")
    }
    guard holds(SheetChartView.plotValueDomain(values: [5, 5, 5])),
          holds(SheetChartView.plotValueDomain(values: [0, 0])),
          let negatives = SheetChartView.plotValueDomain(values: [-4, -4]),
          holds(negatives),
          negatives.lowerBound <= -4
    else {
      return Result(name: name, passed: false, detail: "flat series domain collapsed")
    }
    guard SheetChartView.plotValueDomain(values: []) == nil,
          SheetChartView.plotValueDomain(values: [.nan, .infinity]) == nil,
          let mixed = SheetChartView.plotValueDomain(values: [.nan, 4]),
          holds(mixed),
          mixed.upperBound > 4
    else {
      return Result(name: name, passed: false, detail: "non-finite values still produced a domain")
    }
    guard SheetChartView.plotCategoryDomain(count: 0) == nil,
          SheetChartView.plotCategoryDomain(count: 1) == -0.5...0.5,
          SheetChartView.plotCategoryDomain(count: 4) == -0.5...3.5
    else {
      return Result(name: name, passed: false, detail: "category domain \(String(describing: SheetChartView.plotCategoryDomain(count: 4)))")
    }

    let range = CellRange(start: .origin, end: CellAddress(row: 2, col: 1))
    let chart = SheetChart(
      kind: .bar,
      dataRange: range,
      categoryColumn: 0,
      valueColumn: 1,
      hasHeaderRow: false,
      valueMode: .values,
      anchorRow: 0,
      anchorCol: 0
    )
    let series = ChartPreviewSeries.points(
      for: chart,
      labelFor: { _ in "Week" },
      numberFor: { address in
        address.row == 1 ? .nan : Double(address.row + 1)
      }
    )
    guard series.points.count == 2, series.points.allSatisfy({ $0.value.isFinite }) else {
      return Result(name: name, passed: false, detail: "NaN point was plotted \(series.points)")
    }
    return Result(name: name, passed: true, detail: "weekly \(weekly.lowerBound)...\(weekly.upperBound)")
  }

  private static func weeklyCallsLastLabel() -> Result {
    let name = "weekly calls last label"
    let names = [
      "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun",
      "Mon 2", "Tue 2", "Wed 2", "Thu 2", "Fri 2", "Sat 2", "Closing Call",
    ]
    let count = names.count
    let indexes = ChartCategoryLabelLayout.labelIndexes(count: count)
    guard indexes.last == count - 1 else {
      return Result(name: name, passed: false, detail: "last category was dropped from the axis")
    }
    let chartWidth: CGFloat = 280
    let plotMinX: CGFloat = 36
    let plotWidth = chartWidth - plotMinX
    let items = indexes.map { ChartCategoryLabelLayout.Item(index: $0, text: names[$0]) }
    let placements = ChartCategoryLabelLayout.placements(
      items: items,
      chartWidth: chartWidth,
      barCenterX: { index in
        ChartCategoryLabelLayout.barCenterX(
          index: index,
          count: count,
          plotMinX: plotMinX,
          plotWidth: plotWidth
        )
      },
      labelWidth: { ChartCategoryLabelLayout.measure($0, fontSize: 8) }
    )
    guard let last = placements.first(where: { $0.index == count - 1 }) else {
      return Result(name: name, passed: false, detail: "last label was not placed")
    }
    let center = ChartCategoryLabelLayout.barCenterX(
      index: count - 1,
      count: count,
      plotMinX: plotMinX,
      plotWidth: plotWidth
    )
    let labelWidth = ChartCategoryLabelLayout.measure(names[count - 1], fontSize: 8)
    let centeredMaxX = center + labelWidth / 2
    guard center > plotMinX, center < chartWidth else {
      return Result(name: name, passed: false, detail: "last bar center \(center) is off the chart")
    }
    guard centeredMaxX > chartWidth + 1 else {
      return Result(
        name: name,
        passed: false,
        detail: "fixture does not clip a centered label (center \(center), width \(labelWidth), chart \(chartWidth))"
      )
    }
    guard last.text == "Closing Call", last.minX >= -0.01, last.maxX <= chartWidth + 0.01 else {
      return Result(name: name, passed: false, detail: "last label \(last.text) \(last.minX)...\(last.maxX)")
    }
    let outside = placements.filter { $0.minX < -0.01 || $0.maxX > chartWidth + 0.01 }
    guard outside.isEmpty else {
      return Result(name: name, passed: false, detail: "label outside the chart")
    }
    return Result(name: name, passed: true, detail: "Closing Call fits; centered max \(Int(centeredMaxX.rounded()))")
  }

  private static func chartValueColors() -> Result {
    let name = "chart value colors"
    let colors = (0..<8).map { ChartMarkPalette.swatch(at: $0) }
    guard Set(colors).count == colors.count else {
      return Result(name: name, passed: false, detail: "first 8 swatches are not distinct")
    }
    let swatch = ChartMarkPalette.swatch(at: 0)
    let fallback = SheetChart.defaultSeriesColor(for: .bar)
    guard abs(swatch.red - fallback.red) < 0.001,
          abs(swatch.green - fallback.green) < 0.001,
          abs(swatch.blue - fallback.blue) < 0.001
    else {
      return Result(name: name, passed: false, detail: "series default drifted from the first swatch")
    }
    var chart = SheetChart(
      kind: .bar,
      dataRange: CellRange(start: .origin, end: CellAddress(row: 3, col: 1)),
      anchorRow: 6,
      anchorCol: 0
    )
    guard chart.resolvedColor(forPoint: 0) == chart.resolvedColor(forPoint: 2),
          chart.resolvedColor(forPoint: 0) == chart.resolvedSeriesColor
    else {
      return Result(name: name, passed: false, detail: "points did not share the series color")
    }
    let point = CodableColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1)
    chart.setPointColor(point, at: 1)
    guard chart.resolvedColor(forPoint: 1) == point,
          chart.resolvedColor(forPoint: 0) == chart.resolvedSeriesColor
    else {
      return Result(name: name, passed: false, detail: "point override did not stick")
    }
    chart.setPointColor(nil, at: 1)
    guard chart.pointColors[1] == nil, chart.resolvedColor(forPoint: 1) == chart.resolvedSeriesColor else {
      return Result(name: name, passed: false, detail: "clearing a point did not return to the series color")
    }
    let series = CodableColor(red: 0.1, green: 0.6, blue: 0.3, alpha: 1)
    chart.seriesColor = series
    chart.setPointColor(point, at: 2)
    guard chart.resolvedColor(forPoint: 0) == series, chart.resolvedColor(forPoint: 2) == point else {
      return Result(name: name, passed: false, detail: "series color did not replace the default")
    }
    return Result(name: name, passed: true, detail: "series color, point override, and clear")
  }

  private static func chartFrameDrag() -> Result {
    let name = "chart frame drag"
    func columnAt(_ x: CGFloat) -> Int { min(25, max(0, Int(floor(x / 80)))) }
    func rowAt(_ y: CGFloat) -> Int { min(99, max(0, Int(floor(y / 22)))) }
    let start = OnSheetChartGeometry.ChartFrameAnchor(anchorRow: 4, anchorCol: 0, rowSpan: 12, colSpan: 8)
    let rect = CGRect(x: 0, y: 88, width: 640, height: 264)
    let moved = OnSheetChartGeometry.anchorAfterDrag(
      start: start,
      handle: .body,
      startRect: rect,
      translation: CGSize(width: 100, height: 30),
      minimumSpan: SheetChart.minimumSpan,
      rowLimit: 100,
      columnLimit: 26,
      columnAt: columnAt,
      rowAt: rowAt
    )
    guard moved.anchorCol == 1, moved.anchorRow == 5, moved.colSpan == 8, moved.rowSpan == 12 else {
      return Result(name: name, passed: false, detail: "move \(moved)")
    }
    let downward = SpreadsheetGridNSView.chartDragTranslation(dx: 100, dy: 30)
    guard downward.width == 100, downward.height == 30 else {
      return Result(name: name, passed: false, detail: "downward sign \(downward)")
    }
    let followed = OnSheetChartGeometry.anchorAfterDrag(
      start: start,
      handle: .body,
      startRect: rect,
      translation: downward,
      minimumSpan: SheetChart.minimumSpan,
      rowLimit: 100,
      columnLimit: 26,
      columnAt: columnAt,
      rowAt: rowAt
    )
    guard followed.anchorCol == 1, followed.anchorRow == 5, followed.rowSpan == 12 else {
      return Result(name: name, passed: false, detail: "pointer down \(followed)")
    }
    let grown = OnSheetChartGeometry.anchorAfterDrag(
      start: start,
      handle: .bottom,
      startRect: rect,
      translation: downward,
      minimumSpan: SheetChart.minimumSpan,
      rowLimit: 100,
      columnLimit: 26,
      columnAt: columnAt,
      rowAt: rowAt
    )
    guard grown.anchorRow == 4, grown.anchorCol == 0, grown.rowSpan == 14 else {
      return Result(name: name, passed: false, detail: "bottom follows \(grown)")
    }
    let loweredTop = OnSheetChartGeometry.anchorAfterDrag(
      start: start,
      handle: .top,
      startRect: rect,
      translation: downward,
      minimumSpan: SheetChart.minimumSpan,
      rowLimit: 100,
      columnLimit: 26,
      columnAt: columnAt,
      rowAt: rowAt
    )
    guard loweredTop.anchorRow == 5, loweredTop.rowSpan == 11, loweredTop.anchorCol == 0 else {
      return Result(name: name, passed: false, detail: "top follows \(loweredTop)")
    }
    let layer = CGRect(x: 28, y: 28, width: 800, height: 600)
    let atRest = CGRect(x: 100, y: 200, width: 320, height: 180)
    let scrolled = atRest.offsetBy(dx: 0, dy: -40)
    let hostAtRest = OnSheetChartGeometry.hostFrame(chartRect: atRest, layerFrame: layer)
    let hostScrolled = OnSheetChartGeometry.hostFrame(chartRect: scrolled, layerFrame: layer)
    guard hostAtRest.minY == 172, hostScrolled.minY == 132,
          hostAtRest.minY - hostScrolled.minY == 40,
          hostScrolled.minX == hostAtRest.minX
    else {
      return Result(name: name, passed: false, detail: "scroll host \(hostAtRest) \(hostScrolled)")
    }
    let nudged = OnSheetChartGeometry.anchorAfterDrag(
      start: start,
      handle: .body,
      startRect: rect,
      translation: CGSize(width: 40, height: 10),
      minimumSpan: SheetChart.minimumSpan,
      rowLimit: 100,
      columnLimit: 26,
      columnAt: columnAt,
      rowAt: rowAt
    )
    guard nudged == start else {
      return Result(name: name, passed: false, detail: "sub-cell move changed \(nudged)")
    }
    let wider = OnSheetChartGeometry.anchorAfterDrag(
      start: start,
      handle: .right,
      startRect: rect,
      translation: CGSize(width: 80, height: 0),
      minimumSpan: SheetChart.minimumSpan,
      rowLimit: 100,
      columnLimit: 26,
      columnAt: columnAt,
      rowAt: rowAt
    )
    guard wider.anchorCol == 0, wider.colSpan == 9, wider.rowSpan == 12 else {
      return Result(name: name, passed: false, detail: "resize right \(wider)")
    }
    let inset = OnSheetChartGeometry.anchorAfterDrag(
      start: start,
      handle: .left,
      startRect: rect,
      translation: CGSize(width: 480, height: 0),
      minimumSpan: SheetChart.minimumSpan,
      rowLimit: 100,
      columnLimit: 26,
      columnAt: columnAt,
      rowAt: rowAt
    )
    guard inset.anchorCol == 4, inset.colSpan == 4, inset.anchorRow == 4 else {
      return Result(name: name, passed: false, detail: "resize left min span \(inset)")
    }
    guard OnSheetChartGeometry.frameHandle(at: CGPoint(x: 320, y: 200), in: rect, thickness: 8) == .body,
          OnSheetChartGeometry.frameHandle(at: CGPoint(x: 2, y: 200), in: rect, thickness: 8) == .left,
          OnSheetChartGeometry.frameHandle(at: CGPoint(x: 638, y: 90), in: rect, thickness: 8) == .topRight,
          OnSheetChartGeometry.frameHandle(at: CGPoint(x: -40, y: -40), in: rect, thickness: 8) == nil
    else {
      return Result(name: name, passed: false, detail: "handle hit test")
    }
    let wide = OnSheetChartGeometry.previewHeight(colSpan: 16, rowSpan: 4, width: 320)
    let tall = OnSheetChartGeometry.previewHeight(colSpan: 4, rowSpan: 16, width: 320)
    guard tall > wide else {
      return Result(name: name, passed: false, detail: "preview tall \(tall) wide \(wide)")
    }
    return Result(name: name, passed: true, detail: "move, resize, handles, preview size")
  }

  /// Command during a drag or resize leaves the edge on the pointer. Without
  /// it, the same gesture snaps to the cell border. The chart still scrolls
  /// with its anchor, and dragging down still moves it down.
  private static func chartCommandFreePlacement() -> Result {
    let name = "chart command free placement"
    guard SpreadsheetGridNSView.chartDragUsesFreePlacement(modifierFlags: .command),
          SpreadsheetGridNSView.chartDragUsesFreePlacement(modifierFlags: [.command, .shift]),
          !SpreadsheetGridNSView.chartDragUsesFreePlacement(modifierFlags: []),
          !SpreadsheetGridNSView.chartDragUsesFreePlacement(modifierFlags: .shift),
          !SpreadsheetGridNSView.chartDragUsesFreePlacement(modifierFlags: .option),
          !SpreadsheetGridNSView.chartDragUsesFreePlacement(modifierFlags: .control)
    else {
      return Result(name: name, passed: false, detail: "modifier was not command")
    }
    func columnAt(_ x: CGFloat) -> Int { min(25, max(0, Int(floor(x / 80)))) }
    func rowAt(_ y: CGFloat) -> Int { min(99, max(0, Int(floor(y / 22)))) }
    func xForColumn(_ col: Int) -> CGFloat { CGFloat(col) * 80 }
    func yForRow(_ row: Int) -> CGFloat { CGFloat(row) * 22 }
    let start = OnSheetChartGeometry.ChartFrameAnchor(anchorRow: 4, anchorCol: 0, rowSpan: 12, colSpan: 8)
    let rect = CGRect(x: 0, y: 88, width: 640, height: 264)
    func drag(
      _ handle: OnSheetChartGeometry.ChartFrameHandle,
      _ translation: CGSize,
      free: Bool
    ) -> OnSheetChartGeometry.ChartFrameAnchor {
      OnSheetChartGeometry.anchorAfterDrag(
        start: start,
        handle: handle,
        startRect: rect,
        translation: translation,
        minimumSpan: SheetChart.minimumSpan,
        rowLimit: 100,
        columnLimit: 26,
        columnAt: columnAt,
        rowAt: rowAt,
        freePlacement: free,
        xForColumn: xForColumn,
        yForRow: yForRow,
        columnWidth: { _ in 80 },
        rowHeight: { _ in 22 }
      )
    }
    func placed(_ anchor: OnSheetChartGeometry.ChartFrameAnchor) -> CGRect {
      OnSheetChartGeometry.frame(
        anchorRow: anchor.anchorRow,
        anchorCol: anchor.anchorCol,
        rowSpan: anchor.rowSpan,
        colSpan: anchor.colSpan,
        rowCount: 100,
        columnCount: 26,
        originXOffset: anchor.originXOffset,
        originYOffset: anchor.originYOffset,
        endXOffset: anchor.endXOffset,
        endYOffset: anchor.endYOffset,
        xForColumn: xForColumn,
        yForRow: yForRow,
        columnWidth: { _ in 80 },
        rowHeight: { _ in 22 }
      )
    }
    let nudge = CGSize(width: 40, height: 10)
    let snappedNudge = drag(.body, nudge, free: false)
    let freedNudge = drag(.body, nudge, free: true)
    guard snappedNudge == start, placed(snappedNudge).minX == 0, placed(snappedNudge).minY == 88 else {
      return Result(name: name, passed: false, detail: "sub-cell snap \(snappedNudge) \(placed(snappedNudge))")
    }
    let freedRect = placed(freedNudge)
    guard freedNudge.anchorCol == 0, freedNudge.anchorRow == 4,
          freedNudge.colSpan == 8, freedNudge.rowSpan == 12,
          freedNudge.originXOffset == 40, freedNudge.originYOffset == 10,
          freedNudge.endXOffset == 40, freedNudge.endYOffset == 10,
          freedRect.minX == 40, freedRect.minY == 98,
          freedRect.width == 640, freedRect.height == 264
    else {
      return Result(name: name, passed: false, detail: "free nudge \(freedNudge) \(freedRect)")
    }
    let downward = SpreadsheetGridNSView.chartDragTranslation(dx: 100, dy: 30)
    guard downward.height > 0 else {
      return Result(name: name, passed: false, detail: "downward sign \(downward)")
    }
    let snappedMove = drag(.body, downward, free: false)
    let freedMove = drag(.body, downward, free: true)
    guard snappedMove.anchorCol == 1, snappedMove.anchorRow == 5,
          snappedMove.originXOffset == 0, snappedMove.originYOffset == 0,
          placed(snappedMove).minX == 80, placed(snappedMove).minY == 110
    else {
      return Result(name: name, passed: false, detail: "snap move \(snappedMove) \(placed(snappedMove))")
    }
    let freedMoveRect = placed(freedMove)
    guard freedMove.anchorCol == 1, freedMove.anchorRow == 5,
          freedMove.originXOffset == 20, freedMove.originYOffset == 8,
          freedMoveRect.minX == 100, freedMoveRect.minY == 118,
          freedMoveRect.width == 640, freedMoveRect.height == 264
    else {
      return Result(name: name, passed: false, detail: "free move \(freedMove) \(freedMoveRect)")
    }
    let snapRight = drag(.right, CGSize(width: 30, height: 0), free: false)
    let freeRight = drag(.right, CGSize(width: 30, height: 0), free: true)
    guard snapRight.colSpan == 9, snapRight.endXOffset == 0, placed(snapRight).width == 720 else {
      return Result(name: name, passed: false, detail: "snap resize \(snapRight) \(placed(snapRight))")
    }
    guard freeRight.anchorCol == 0, freeRight.colSpan == 8, freeRight.endXOffset == 30,
          freeRight.rowSpan == 12, placed(freeRight).width == 670, placed(freeRight).minX == 0
    else {
      return Result(name: name, passed: false, detail: "free resize \(freeRight) \(placed(freeRight))")
    }
    let downEdge = SpreadsheetGridNSView.chartDragTranslation(dx: 0, dy: 10)
    let freeBottom = drag(.bottom, downEdge, free: true)
    guard freeBottom.anchorRow == 4, freeBottom.rowSpan == 12, freeBottom.endYOffset == 10,
          placed(freeBottom).minY == 88, placed(freeBottom).height == 274
    else {
      return Result(name: name, passed: false, detail: "bottom down \(freeBottom) \(placed(freeBottom))")
    }
    let freeCorner = drag(.topLeft, CGSize(width: 50, height: 10), free: true)
    guard freeCorner.originXOffset == 50, freeCorner.originYOffset == 10,
          freeCorner.colSpan == 8, freeCorner.rowSpan == 12,
          placed(freeCorner).minX == 50, placed(freeCorner).minY == 98
    else {
      return Result(name: name, passed: false, detail: "corner \(freeCorner) \(placed(freeCorner))")
    }
    func widthAt(_ col: Int) -> CGFloat { col == 0 ? 50 : (col == 1 ? 100 : 80) }
    func xOf(_ col: Int) -> CGFloat {
      var x: CGFloat = 0
      for index in 0..<max(0, col) { x += widthAt(index) }
      return x
    }
    func colAt(_ x: CGFloat) -> Int {
      var index = 0
      var cursor: CGFloat = 0
      while index < 25 {
        let width = widthAt(index)
        if x < cursor + width { return index }
        cursor += width
        index += 1
      }
      return 25
    }
    let variableRect = CGRect(x: 0, y: 88, width: xOf(8), height: 264)
    let variableFree = OnSheetChartGeometry.anchorAfterDrag(
      start: start,
      handle: .body,
      startRect: variableRect,
      translation: CGSize(width: 60, height: 0),
      minimumSpan: SheetChart.minimumSpan,
      rowLimit: 100,
      columnLimit: 26,
      columnAt: colAt,
      rowAt: rowAt,
      freePlacement: true,
      xForColumn: xOf,
      yForRow: yForRow,
      columnWidth: widthAt,
      rowHeight: { _ in 22 }
    )
    let variableSnap = OnSheetChartGeometry.anchorAfterDrag(
      start: start,
      handle: .body,
      startRect: variableRect,
      translation: CGSize(width: 60, height: 0),
      minimumSpan: SheetChart.minimumSpan,
      rowLimit: 100,
      columnLimit: 26,
      columnAt: colAt,
      rowAt: rowAt,
      freePlacement: false,
      xForColumn: xOf,
      yForRow: yForRow,
      columnWidth: widthAt,
      rowHeight: { _ in 22 }
    )
    let variablePlaced = OnSheetChartGeometry.frame(
      anchorRow: variableFree.anchorRow,
      anchorCol: variableFree.anchorCol,
      rowSpan: variableFree.rowSpan,
      colSpan: variableFree.colSpan,
      rowCount: 100,
      columnCount: 26,
      originXOffset: variableFree.originXOffset,
      originYOffset: variableFree.originYOffset,
      endXOffset: variableFree.endXOffset,
      endYOffset: variableFree.endYOffset,
      xForColumn: xOf,
      yForRow: yForRow,
      columnWidth: widthAt,
      rowHeight: { _ in 22 }
    )
    guard variableFree.anchorCol == 1, variableFree.originXOffset == 10,
          variablePlaced.minX == 60, variablePlaced.width == variableRect.width,
          variableSnap.anchorCol == 1, variableSnap.originXOffset == 0
    else {
      return Result(name: name, passed: false, detail: "variable \(variableFree) snap \(variableSnap) \(variablePlaced)")
    }

    let header: CGFloat = 28
    let rowH: CGFloat = 22
    let colW: CGFloat = 80
    let frozenRows = 7
    let frozenCols = 2
    let content = CGRect(x: header, y: header, width: 960, height: 640)
    let boundaryX = header + CGFloat(frozenCols) * colW
    let boundaryY = header + CGFloat(frozenRows) * rowH
    func scrolledY(_ row: Int, scrollY: CGFloat) -> CGFloat {
      let model = CGFloat(row) * rowH
      if row < frozenRows { return header + model }
      return header + model - scrollY
    }
    func scrolledX(_ col: Int, scrollX: CGFloat) -> CGFloat {
      let model = CGFloat(col) * colW
      if col < frozenCols { return header + model }
      return header + model - scrollX
    }
    func offsetChart(scrollX: CGFloat, scrollY: CGFloat) -> CGRect {
      OnSheetChartGeometry.frame(
        anchorRow: 10,
        anchorCol: 3,
        rowSpan: 14,
        colSpan: 8,
        rowCount: 200,
        columnCount: 26,
        originXOffset: 5,
        originYOffset: 6,
        endXOffset: 5,
        endYOffset: 6,
        xForColumn: { scrolledX($0, scrollX: scrollX) },
        yForRow: { scrolledY($0, scrollY: scrollY) },
        columnWidth: { _ in colW },
        rowHeight: { _ in rowH }
      )
    }
    let rested = offsetChart(scrollX: 0, scrollY: 0)
    let scrolled = offsetChart(scrollX: 200, scrollY: 120)
    guard rested.minY == header + 10 * rowH + 6, rested.minX == header + 3 * colW + 5,
          rested.height == 14 * rowH, rested.width == 8 * colW,
          rested.minY - scrolled.minY == 120, rested.minX - scrolled.minX == 200
    else {
      return Result(name: name, passed: false, detail: "offset scroll \(rested) \(scrolled)")
    }
    let hostRest = OnSheetChartGeometry.hostFrame(chartRect: rested, layerFrame: content)
    let hostScroll = OnSheetChartGeometry.hostFrame(chartRect: scrolled, layerFrame: content)
    guard hostRest.minY - hostScroll.minY == 120, hostRest.minX - hostScroll.minX == 200 else {
      return Result(name: name, passed: false, detail: "host scroll \(hostRest) \(hostScroll)")
    }
    let underHeader = CGPoint(x: scrolled.midX, y: boundaryY - 4)
    guard scrolled.minY < boundaryY, scrolled.contains(underHeader),
          OnSheetChartGeometry.frozenPaneCovers(
            underHeader,
            contentRect: content,
            frozenColumnBoundaryX: boundaryX,
            frozenRowBoundaryY: boundaryY,
            frozenColumns: frozenCols,
            frozenRows: frozenRows
          )
    else {
      return Result(name: name, passed: false, detail: "frozen cover \(scrolled)")
    }

    var sheet = Sheet(name: "Weekly Calls")
    sheet.setCell(Cell(raw: "Week"), at: .origin)
    sheet.setCell(Cell(raw: "Calls"), at: CellAddress(row: 0, col: 1))
    var chart = SheetChart(
      kind: .bar,
      title: "Calls by Week",
      dataRange: CellRange(start: .origin, end: CellAddress(row: 4, col: 1)),
      anchorRow: 7,
      anchorCol: 0
    )
    chart.originXOffset = 12
    chart.originYOffset = 6
    chart.endXOffset = 3
    chart.endYOffset = 9
    sheet.charts = [chart]
    do {
      let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
      let drawing = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/drawings/drawing1.xml") ?? ""
      func emu(_ points: CGFloat) -> String { "\(SheetImage.emu(fromPoints: points))" }
      guard drawing.contains("<xdr:colOff>\(emu(12))</xdr:colOff>"),
            drawing.contains("<xdr:rowOff>\(emu(6))</xdr:rowOff>"),
            drawing.contains("<xdr:colOff>\(emu(3))</xdr:colOff>"),
            drawing.contains("<xdr:rowOff>\(emu(9))</xdr:rowOff>")
      else {
        return Result(name: name, passed: false, detail: "drawing offsets missing")
      }
      let imported = try XLSXCodec.importWorkbook(from: data)
      let saved = imported.sheets[0].charts.first
      guard saved?.originXOffset == 12, saved?.originYOffset == 6,
            saved?.endXOffset == 3, saved?.endYOffset == 9,
            saved?.anchorRow == 7, saved?.colSpan == 8
      else {
        return Result(name: name, passed: false, detail: "reopen offsets \(String(describing: saved?.originXOffset))")
      }
    } catch {
      return Result(name: name, passed: false, detail: error.localizedDescription)
    }
    let legacyJSON = """
    {"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","kind":"bar","title":"Old","dataRange":{"start":{"row":0,"col":0},"end":{"row":3,"col":1}},"anchorRow":1,"anchorCol":2,"rowSpan":10,"colSpan":6}
    """
    guard let legacy = try? JSONDecoder().decode(SheetChart.self, from: Data(legacyJSON.utf8)),
          legacy.originXOffset == 0, legacy.originYOffset == 0,
          legacy.endXOffset == 0, legacy.endYOffset == 0
    else {
      return Result(name: name, passed: false, detail: "legacy chart kept a free offset")
    }

    let placedSheet = sheet
    let model = MainActor.assumeIsolated { () -> Result? in
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [placedSheet]))
      guard let original = vm.activeSheet.charts.first else {
        return Result(name: name, passed: false, detail: "chart missing on the sheet")
      }
      let undo = UndoManager()
      vm.undoManager = undo
      vm.setChartFrame(
        id: original.id,
        anchorRow: 5,
        anchorCol: 1,
        rowSpan: 12,
        colSpan: 8,
        originXOffset: 20,
        originYOffset: 8,
        endXOffset: 20,
        endYOffset: 8,
        preservingCustomFrom: original
      )
      guard let live = vm.chart(with: original.id),
            live.anchorRow == 5, live.anchorCol == 1,
            live.originXOffset == 20, live.originYOffset == 8,
            live.endXOffset == 20, live.endYOffset == 8,
            live.frameIsCustom
      else {
        return Result(name: name, passed: false, detail: "live frame dropped the offset")
      }
      vm.commitChartFrame(id: original.id, before: original, actionName: "Move Chart")
      guard undo.canUndo else {
        return Result(name: name, passed: false, detail: "free move was not undoable")
      }
      undo.undo()
      guard vm.chart(with: original.id)?.originXOffset == 12 else {
        return Result(name: name, passed: false, detail: "undo did not restore the offset")
      }
      undo.redo()
      vm.setChartFrame(
        id: original.id,
        anchorRow: 5,
        anchorCol: 1,
        rowSpan: 12,
        colSpan: 8,
        preservingCustomFrom: original
      )
      guard let snapped = vm.chart(with: original.id),
            snapped.originXOffset == 0, snapped.endXOffset == 0,
            snapped.endYOffset == 0, snapped.anchorCol == 1
      else {
        return Result(name: name, passed: false, detail: "releasing the offset did not snap")
      }
      return nil
    }
    if let model { return model }
    return Result(name: name, passed: true, detail: "command frees move and resize; release snaps")
  }

  /// Weekly Calls: "Calls by Rep" scrolls with its anchor and slides under
  /// the frozen header and frozen columns. Those panes cover the chart; the
  /// chart frame itself is not clipped, so the scroll delta stays intact.
  private static func chartSlidesUnderFrozenPanes() -> Result {
    let name = "chart under frozen panes"
    let header: CGFloat = 28
    let rowH: CGFloat = 22
    let colW: CGFloat = 80
    let frozenRows = 7
    let frozenCols = 2
    let content = CGRect(x: header, y: header, width: 960, height: 640)
    let boundaryX = header + CGFloat(frozenCols) * colW
    let boundaryY = header + CGFloat(frozenRows) * rowH
    func yForRow(_ row: Int, scrollY: CGFloat) -> CGFloat {
      let model = CGFloat(row) * rowH
      if row < frozenRows { return header + model }
      return header + model - scrollY
    }
    func xForColumn(_ col: Int, scrollX: CGFloat) -> CGFloat {
      let model = CGFloat(col) * colW
      if col < frozenCols { return header + model }
      return header + model - scrollX
    }
    func chart(scrollX: CGFloat, scrollY: CGFloat) -> CGRect {
      OnSheetChartGeometry.frame(
        anchorRow: 10,
        anchorCol: 3,
        rowSpan: 14,
        colSpan: 8,
        rowCount: 200,
        columnCount: 26,
        xForColumn: { xForColumn($0, scrollX: scrollX) },
        yForRow: { yForRow($0, scrollY: scrollY) },
        columnWidth: { _ in colW },
        rowHeight: { _ in rowH }
      )
    }
    func covers(_ point: CGPoint, columns: Int = frozenCols, rows: Int = frozenRows) -> Bool {
      OnSheetChartGeometry.frozenPaneCovers(
        point,
        contentRect: content,
        frozenColumnBoundaryX: columns > 0 ? boundaryX : content.minX,
        frozenRowBoundaryY: rows > 0 ? boundaryY : content.minY,
        frozenColumns: columns,
        frozenRows: rows
      )
    }
    let rested = chart(scrollX: 0, scrollY: 0)
    guard rested.minY > boundaryY, rested.minX > boundaryX, rested.height == 14 * rowH else {
      return Result(name: name, passed: false, detail: "rest frame \(rested)")
    }
    let scrolled = chart(scrollX: 0, scrollY: 120)
    guard scrolled.minY < boundaryY, scrolled.height == rested.height else {
      return Result(name: name, passed: false, detail: "scroll under header \(scrolled)")
    }
    let layer = content
    let hostRest = OnSheetChartGeometry.hostFrame(chartRect: rested, layerFrame: layer)
    let hostScroll = OnSheetChartGeometry.hostFrame(chartRect: scrolled, layerFrame: layer)
    guard hostRest.minY - hostScroll.minY == 120, hostScroll.minX == hostRest.minX else {
      return Result(name: name, passed: false, detail: "anchor scroll \(hostRest) \(hostScroll)")
    }
    let underHeader = CGPoint(x: scrolled.midX, y: boundaryY - 4)
    let inBody = CGPoint(x: scrolled.midX, y: boundaryY + 8)
    guard scrolled.contains(underHeader), covers(underHeader),
          scrolled.contains(inBody), !covers(inBody)
    else {
      return Result(name: name, passed: false, detail: "header cover \(underHeader) \(inBody)")
    }
    let slidLeft = chart(scrollX: 200, scrollY: 0)
    let underCols = CGPoint(x: boundaryX - 4, y: slidLeft.midY)
    let rightOfCols = CGPoint(x: boundaryX + 8, y: slidLeft.midY)
    guard slidLeft.minX < boundaryX, slidLeft.height == rested.height,
          slidLeft.contains(underCols), covers(underCols),
          slidLeft.contains(rightOfCols), !covers(rightOfCols)
    else {
      return Result(name: name, passed: false, detail: "column cover \(slidLeft)")
    }
    let onDivider = CGPoint(x: scrolled.midX, y: boundaryY)
    guard covers(onDivider) else {
      return Result(name: name, passed: false, detail: "divider was left to the chart")
    }
    let panes = OnSheetChartGeometry.frozenPaneCoverRects(
      contentRect: content,
      frozenColumnBoundaryX: boundaryX,
      frozenRowBoundaryY: boundaryY,
      frozenColumns: frozenCols,
      frozenRows: frozenRows
    )
    guard panes.count == 2,
          panes[0] == CGRect(x: header, y: header, width: 960, height: boundaryY - header),
          panes[1] == CGRect(x: header, y: boundaryY, width: boundaryX - header, height: content.maxY - boundaryY)
    else {
      return Result(name: name, passed: false, detail: "cover rects \(panes)")
    }
    guard OnSheetChartGeometry.frozenPaneCoverRects(
      contentRect: content,
      frozenColumnBoundaryX: content.minX,
      frozenRowBoundaryY: content.minY,
      frozenColumns: 0,
      frozenRows: 0
    ).isEmpty, !covers(underHeader, columns: 0, rows: 0) else {
      return Result(name: name, passed: false, detail: "unfrozen sheet still covered the chart")
    }
    return Result(name: name, passed: true, detail: "header and columns cover the scrolled chart")
  }

  /// Draws Weekly Calls with "Calls by Rep" sitting on top of the frozen header
  /// and frozen columns. Those cells stay the fill color; the same cells without
  /// a freeze are covered by the chart.
  @MainActor
  private static func frozenPanesCoverChartPixels() -> Result {
    let name = "frozen panes cover chart"
    let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
    let green = CodableColor(red: 0, green: 1, blue: 0, alpha: 1)
    let blue = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)
    func painted(_ color: CodableColor) -> Cell {
      var format = CellFormat()
      format.fillColor = color
      return Cell(raw: "", format: format)
    }
    func makeSheet(frozen: Bool) -> Sheet {
      var sheet = Sheet(
        name: "Weekly Calls",
        frozenRows: frozen ? 2 : 0,
        frozenColumns: frozen ? 1 : 0
      )
      sheet.setCell(painted(red), at: CellAddress(row: 0, col: 2))
      sheet.setCell(painted(green), at: CellAddress(row: 4, col: 0))
      sheet.setCell(painted(blue), at: CellAddress(row: 4, col: 2))
      sheet.charts = [
        SheetChart(
          kind: .bar,
          title: "Calls by Rep",
          dataRange: CellRange(start: .origin, end: CellAddress(row: 4, col: 1)),
          anchorRow: 0,
          anchorCol: 0,
          rowSpan: 12,
          colSpan: 8
        )
      ]
      return sheet
    }
    let header: CGFloat = SpreadsheetGridNSView.baseHeaderSize
    let rowH = Workbook.defaultRowHeight
    let colW = Workbook.defaultColumnWidth
    let redPoint = NSPoint(x: header + 2 * colW + colW / 2, y: header + rowH / 2)
    let greenPoint = NSPoint(x: header + colW / 2, y: header + 4 * rowH + rowH / 2)
    let bluePoint = NSPoint(x: header + 2 * colW + colW / 2, y: header + 4 * rowH + rowH / 2)

    func isRed(_ color: NSColor) -> Bool {
      guard let rgb = color.usingColorSpace(.deviceRGB) else { return false }
      return rgb.redComponent > 0.85 && rgb.greenComponent < 0.2 && rgb.blueComponent < 0.2
    }
    func isGreen(_ color: NSColor) -> Bool {
      guard let rgb = color.usingColorSpace(.deviceRGB) else { return false }
      return rgb.greenComponent > 0.85 && rgb.redComponent < 0.2 && rgb.blueComponent < 0.2
    }
    func isBlue(_ color: NSColor) -> Bool {
      guard let rgb = color.usingColorSpace(.deviceRGB) else { return false }
      return rgb.blueComponent > 0.85 && rgb.redComponent < 0.2 && rgb.greenComponent < 0.2
    }
    func describe(_ color: NSColor?) -> String {
      guard let rgb = color?.usingColorSpace(.deviceRGB) else { return "nil" }
      return String(format: "%.2f,%.2f,%.2f", rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    }

    guard let open = snapshotGrid(sheet: makeSheet(frozen: false)),
          let frozen = snapshotGrid(sheet: makeSheet(frozen: true))
    else {
      return Result(name: name, passed: false, detail: "grid snapshot failed")
    }
    let fromTop = [true, false].first { fromTop in
      !isRed(open.color(at: redPoint, fromTop: fromTop))
        && !isGreen(open.color(at: greenPoint, fromTop: fromTop))
        && !isBlue(open.color(at: bluePoint, fromTop: fromTop))
    }
    guard let fromTop else {
      return Result(
        name: name,
        passed: false,
        detail: "chart did not cover the cells top \(describe(open.color(at: redPoint, fromTop: true))) \(describe(open.color(at: greenPoint, fromTop: true))) \(describe(open.color(at: bluePoint, fromTop: true))) bottom \(describe(open.color(at: redPoint, fromTop: false))) \(describe(open.color(at: greenPoint, fromTop: false))) \(describe(open.color(at: bluePoint, fromTop: false)))"
      )
    }
    let frozenRed = frozen.color(at: redPoint, fromTop: fromTop)
    let frozenGreen = frozen.color(at: greenPoint, fromTop: fromTop)
    let frozenBlue = frozen.color(at: bluePoint, fromTop: fromTop)
    guard isRed(frozenRed), isGreen(frozenGreen), !isBlue(frozenBlue) else {
      return Result(
        name: name,
        passed: false,
        detail: "panes red \(describe(frozenRed)) green \(describe(frozenGreen)) body \(describe(frozenBlue))"
      )
    }
    let chartAboveOverlay = frozen.chartAboveFrozenPane
    guard !chartAboveOverlay else {
      return Result(name: name, passed: false, detail: "chart layer is above the frozen pane")
    }
    return Result(name: name, passed: true, detail: "frozen header and columns cover Calls by Rep")
  }

  private struct GridSnapshot {
    var image: NSBitmapImageRep
    var pointScale: CGFloat
    var chartAboveFrozenPane: Bool

    func color(at point: NSPoint, fromTop: Bool) -> NSColor {
      let x = Int((point.x * pointScale).rounded(.down))
      let yFromTop = Int((point.y * pointScale).rounded(.down))
      let y = fromTop ? yFromTop : image.pixelsHigh - 1 - yFromTop
      let px = min(image.pixelsWide - 1, max(0, x))
      let py = min(image.pixelsHigh - 1, max(0, y))
      return image.colorAt(x: px, y: py) ?? .clear
    }
  }

  @MainActor
  private static func snapshotGrid(sheet: Sheet) -> GridSnapshot? {
    let frame = NSRect(x: 0, y: 0, width: 900, height: 560)
    let grid = SpreadsheetGridNSView(frame: frame)
    let window = NSWindow(
      contentRect: frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = grid
    window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
    window.orderFrontRegardless()
    grid.viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
    grid.layoutSubtreeIfNeeded()
    grid.needsDisplay = true
    window.displayIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    grid.layoutSubtreeIfNeeded()
    grid.display()

    let scale = max(1, window.backingScaleFactor)
    let pixelsWide = Int((grid.bounds.width * scale).rounded())
    let pixelsHigh = Int((grid.bounds.height * scale).rounded())
    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: pixelsWide,
      pixelsHigh: pixelsHigh,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ), let gfx = NSGraphicsContext(bitmapImageRep: rep) else {
      window.orderOut(nil)
      window.close()
      return nil
    }
    rep.size = grid.bounds.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gfx
    let cg = gfx.cgContext
    cg.translateBy(x: 0, y: CGFloat(pixelsHigh))
    cg.scaleBy(x: scale, y: -scale)
    grid.layer?.render(in: cg)
    NSGraphicsContext.restoreGraphicsState()

    let chartLayer = grid.subviews.first { ($0.layer?.zPosition ?? -1) == 5 }
    let pane = grid.subviews.first { ($0.layer?.zPosition ?? -1) == 6 }
    let chartAbove = pane == nil || pane?.isHidden == true
      || (chartLayer?.layer?.zPosition ?? 0) > (pane?.layer?.zPosition ?? 0)
    window.orderOut(nil)
    window.close()
    return GridSnapshot(image: rep, pointScale: scale, chartAboveFrozenPane: chartAbove)
  }

  @MainActor
  private static func chartMoveResizeAndColorRoundTrip() -> Result {
    let name = "chart move color round-trip"
    var sheet = Sheet(name: "Weekly Calls")
    sheet.setCell(Cell(raw: "Week"), at: .origin)
    sheet.setCell(Cell(raw: "Calls"), at: CellAddress(row: 0, col: 1))
    for index in 1...4 {
      sheet.setCell(Cell(raw: "Week \(index)"), at: CellAddress(row: index, col: 0))
      sheet.setCell(Cell(raw: "\(index * 3)"), at: CellAddress(row: index, col: 1))
    }
    let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
    let range = CellRange(start: .origin, end: CellAddress(row: 4, col: 1))
    let inserted = vm.insertChart(
      SheetChart(
        kind: .bar,
        title: "Calls by Week",
        dataRange: range,
        categoryColumn: 0,
        valueColumn: 1,
        anchorRow: 7,
        anchorCol: 0
      )
    )
    guard inserted, let original = vm.activeSheet.charts.first else {
      return Result(name: name, passed: false, detail: "chart was not inserted")
    }
    vm.setChartFrame(
      id: original.id,
      anchorRow: 0,
      anchorCol: 0,
      rowSpan: 6,
      colSpan: 5,
      preservingCustomFrom: original
    )
    vm.commitChartFrame(id: original.id, before: original, actionName: "Move Chart")
    let series = CodableColor(red: 0.12, green: 0.55, blue: 0.32, alpha: 1)
    let point = CodableColor(red: 0.86, green: 0.24, blue: 0.18, alpha: 1)
    vm.updateChartContent(id: original.id, actionName: "Chart Color") {
      $0.seriesColor = series
      $0.setPointColor(point, at: 1)
      $0.showsLegend = true
      $0.showsGridlines = false
      $0.categoryAxisTitle = "Week"
      $0.valueAxisTitle = "Calls"
      $0.title = "Pipeline"
    }
    guard let live = vm.chart(with: original.id) else {
      return Result(name: name, passed: false, detail: "chart disappeared")
    }
    guard live.anchorRow == 0, live.anchorCol == 0, live.rowSpan == 6, live.colSpan == 5, live.frameIsCustom else {
      return Result(name: name, passed: false, detail: "frame \(live.anchorRow),\(live.anchorCol) \(live.colSpan)×\(live.rowSpan)")
    }
    guard live.placementDescription == "At A1 · 5×6" else {
      return Result(name: name, passed: false, detail: live.placementDescription)
    }
    guard live.seriesColor == series,
          live.resolvedColor(forPoint: 1) == point,
          live.resolvedColor(forPoint: 0) == series,
          live.showsLegend, !live.showsGridlines,
          live.categoryAxisTitle == "Week",
          live.valueAxisTitle == "Calls",
          live.title == "Pipeline"
    else {
      return Result(name: name, passed: false, detail: "format did not apply")
    }
    vm.updateChartContent(id: original.id, actionName: "Chart Color") {
      $0.setPointColor(nil, at: 1)
    }
    guard vm.chart(with: original.id)?.resolvedColor(forPoint: 1) == series else {
      return Result(name: name, passed: false, detail: "cleared point kept its color")
    }
    vm.updateChartContent(id: original.id, actionName: "Chart Color") {
      $0.setPointColor(point, at: 1)
    }
    do {
      let data = try XLSXCodec.exportWorkbook(vm.workbook)
      let chartXML = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/charts/chart1.xml") ?? ""
      guard chartXML.contains("srgbClr val=\"\(XLSXCodec.rgbHex(series))\""),
            chartXML.contains("srgbClr val=\"\(XLSXCodec.rgbHex(point))\""),
            chartXML.contains("<c:dPt>"),
            chartXML.contains("legendPos val=\"b\""),
            chartXML.contains(">Week<"),
            chartXML.contains(">Calls<"),
            chartXML.contains(">Pipeline<"),
            !chartXML.contains("<c:majorGridlines")
      else {
        return Result(name: name, passed: false, detail: "excel chart xml missed format")
      }
      let imported = try XLSXCodec.importWorkbook(from: data)
      let saved = imported.sheets[0].charts.first
      guard let saved else {
        return Result(name: name, passed: false, detail: "import dropped the chart")
      }
      guard saved.anchorRow == 0, saved.anchorCol == 0, saved.rowSpan == 6, saved.colSpan == 5,
            saved.frameIsCustom, saved.seriesColor == series, saved.pointColors[1] == point,
            saved.showsLegend, !saved.showsGridlines,
            saved.categoryAxisTitle == "Week", saved.valueAxisTitle == "Calls",
            saved.title == "Pipeline"
      else {
        return Result(name: name, passed: false, detail: "reopen \(saved.anchorRow),\(saved.anchorCol) legend \(saved.showsLegend)")
      }
      let kept = saved.positionedUnderData()
      guard kept.anchorRow == 0, kept.anchorCol == 0 else {
        return Result(name: name, passed: false, detail: "custom frame was moved under the data")
      }
    } catch {
      return Result(name: name, passed: false, detail: error.localizedDescription)
    }
    let legacyJSON = """
    {"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","kind":"line","title":"Old","dataRange":{"start":{"row":0,"col":0},"end":{"row":3,"col":1}},"anchorRow":1,"anchorCol":2,"rowSpan":10,"colSpan":6}
    """
    guard let decoded = try? JSONDecoder().decode(SheetChart.self, from: Data(legacyJSON.utf8)) else {
      return Result(name: name, passed: false, detail: "legacy chart json did not decode")
    }
    guard decoded.seriesColor == nil, decoded.pointColors.isEmpty, !decoded.showsLegend,
          decoded.showsGridlines, decoded.categoryAxisTitle.isEmpty, !decoded.frameIsCustom,
          decoded.anchorRow == 1, decoded.rowSpan == 10
    else {
      return Result(name: name, passed: false, detail: "legacy defaults \(decoded.showsGridlines) custom \(decoded.frameIsCustom)")
    }
    return Result(name: name, passed: true, detail: "frame and colors reopen; legacy json still decodes")
  }

  @MainActor
  private static func selectionSizedInsert() -> Result {
    let name = "selection sized insert"

    guard SpreadsheetViewModel.structureInsertTitle(count: 1, singular: "Column", plural: "Columns", placement: "Left")
            == "Insert Column Left",
          SpreadsheetViewModel.structureInsertTitle(count: 3, singular: "Column", plural: "Columns", placement: "Right")
            == "Insert 3 Columns Right",
          SpreadsheetViewModel.structureInsertTitle(count: 3, singular: "Row", plural: "Rows", placement: "Above")
            == "Insert 3 Rows Above",
          SpreadsheetViewModel.structureInsertTitle(count: 4, singular: "Row", plural: "Rows", placement: "Below")
            == "Insert 4 Rows Below"
    else {
      return Result(name: name, passed: false, detail: "menu title wording")
    }

    func raw(_ vm: SpreadsheetViewModel, _ row: Int, _ col: Int) -> String {
      vm.activeSheet.cell(at: CellAddress(row: row, col: col)).raw
    }

    do {
      var sheet = Sheet(name: "Cols")
      sheet.setCell(Cell(raw: "left"), at: CellAddress(row: 0, col: 1))
      sheet.setCell(Cell(raw: "sel"), at: CellAddress(row: 0, col: 2))
      sheet.setCell(Cell(raw: "right"), at: CellAddress(row: 0, col: 5))
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      vm.selectColumns(from: 2, to: 4)
      guard vm.columnInsertCount == 3, vm.rowInsertCount == 1 else {
        return Result(name: name, passed: false, detail: "header columns count \(vm.columnInsertCount) rows \(vm.rowInsertCount)")
      }
      guard vm.insertColumnLeftTitle == "Insert 3 Columns Left",
            vm.insertColumnRightTitle == "Insert 3 Columns Right",
            vm.insertRowAboveTitle == "Insert Row Above"
      else {
        return Result(name: name, passed: false, detail: "header column menu titles")
      }
      vm.insertColumnsLeft()
      guard raw(vm, 0, 1) == "left", raw(vm, 0, 2).isEmpty, raw(vm, 0, 5) == "sel", raw(vm, 0, 8) == "right" else {
        return Result(name: name, passed: false, detail: "insert 3 columns left shifted \(raw(vm, 0, 5))")
      }
    }

    do {
      var sheet = Sheet(name: "ColsRight")
      sheet.setCell(Cell(raw: "sel"), at: CellAddress(row: 0, col: 4))
      sheet.setCell(Cell(raw: "after"), at: CellAddress(row: 0, col: 7))
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      vm.selectColumns(from: 4, to: 6)
      vm.insertColumnsRight()
      let selected = vm.selectionRange.normalized
      guard raw(vm, 0, 4) == "sel", raw(vm, 0, 7).isEmpty, raw(vm, 0, 10) == "after" else {
        return Result(name: name, passed: false, detail: "insert 3 columns right did not open a gap of 3")
      }
      guard selected.minCol == 7, selected.maxCol == 9, vm.selectionAxis == .column else {
        return Result(name: name, passed: false, detail: "insert right selection \(selected.minCol)-\(selected.maxCol)")
      }
    }

    do {
      var sheet = Sheet(name: "Rows")
      sheet.setCell(Cell(raw: "above"), at: CellAddress(row: 1, col: 0))
      sheet.setCell(Cell(raw: "sel"), at: CellAddress(row: 2, col: 0))
      sheet.setCell(Cell(raw: "below"), at: CellAddress(row: 5, col: 0))
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      vm.selectRows(from: 2, to: 4)
      guard vm.rowInsertCount == 3, vm.columnInsertCount == 1,
            vm.insertRowAboveTitle == "Insert 3 Rows Above",
            vm.insertRowBelowTitle == "Insert 3 Rows Below",
            vm.insertColumnLeftTitle == "Insert Column Left"
      else {
        return Result(name: name, passed: false, detail: "header row counts/titles")
      }
      vm.insertRowsAbove()
      guard raw(vm, 1, 0) == "above", raw(vm, 2, 0).isEmpty, raw(vm, 5, 0) == "sel", raw(vm, 8, 0) == "below" else {
        return Result(name: name, passed: false, detail: "insert 3 rows above")
      }
    }

    do {
      var sheet = Sheet(name: "RowsBelow")
      sheet.setCell(Cell(raw: "sel"), at: CellAddress(row: 2, col: 0))
      sheet.setCell(Cell(raw: "after"), at: CellAddress(row: 5, col: 0))
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      vm.selectRows(from: 2, to: 4)
      vm.insertRowsBelow()
      guard raw(vm, 2, 0) == "sel", raw(vm, 5, 0).isEmpty, raw(vm, 8, 0) == "after" else {
        return Result(name: name, passed: false, detail: "insert 3 rows below")
      }
      let selected = vm.selectionRange.normalized
      guard selected.minRow == 2, selected.maxRow == 4 else {
        return Result(name: name, passed: false, detail: "row below selection moved")
      }
    }

    do {
      var sheet = Sheet(name: "Rect")
      sheet.setCell(Cell(raw: "keep"), at: CellAddress(row: 0, col: 1))
      sheet.setCell(Cell(raw: "body"), at: CellAddress(row: 1, col: 2))
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      vm.selectRange(from: CellAddress(row: 1, col: 2), to: CellAddress(row: 4, col: 4))
      guard vm.selectionAxis == .cells, vm.rowInsertCount == 4, vm.columnInsertCount == 3 else {
        return Result(name: name, passed: false, detail: "rectangle counts rows \(vm.rowInsertCount) cols \(vm.columnInsertCount)")
      }
      guard vm.insertRowAboveTitle == "Insert 4 Rows Above",
            vm.insertColumnLeftTitle == "Insert 3 Columns Left"
      else {
        return Result(name: name, passed: false, detail: "rectangle menu titles")
      }
      vm.insertRowsAbove()
      guard raw(vm, 0, 1) == "keep", raw(vm, 5, 2) == "body", raw(vm, 1, 2).isEmpty else {
        return Result(name: name, passed: false, detail: "rectangle row insert used \(raw(vm, 5, 2))")
      }
    }

    do {
      var sheet = Sheet(name: "RectCols")
      sheet.setCell(Cell(raw: "keep"), at: CellAddress(row: 1, col: 1))
      sheet.setCell(Cell(raw: "body"), at: CellAddress(row: 1, col: 2))
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      vm.selectRange(from: CellAddress(row: 1, col: 2), to: CellAddress(row: 4, col: 4))
      vm.insertColumnsLeft()
      guard raw(vm, 1, 1) == "keep", raw(vm, 1, 5) == "body", raw(vm, 1, 2).isEmpty else {
        return Result(name: name, passed: false, detail: "rectangle column insert")
      }
      vm.selectRange(from: CellAddress(row: 1, col: 2), to: CellAddress(row: 4, col: 4))
      vm.insertColumnsRight()
      let selected = vm.selectionRange.normalized
      guard selected.minRow == 1, selected.maxRow == 4, selected.minCol == 5, selected.maxCol == 7 else {
        return Result(name: name, passed: false, detail: "rectangle insert right selection")
      }
    }

    do {
      var sheet = Sheet(name: "One")
      sheet.setCell(Cell(raw: "only"), at: CellAddress(row: 3, col: 3))
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      vm.select(CellAddress(row: 3, col: 3))
      guard vm.rowInsertCount == 1, vm.columnInsertCount == 1,
            vm.insertRowAboveTitle == "Insert Row Above",
            vm.insertColumnRightTitle == "Insert Column Right"
      else {
        return Result(name: name, passed: false, detail: "single cell labels")
      }
      vm.insertColumnsLeft()
      guard raw(vm, 3, 4) == "only", raw(vm, 3, 3).isEmpty else {
        return Result(name: name, passed: false, detail: "single cell inserted more than one column")
      }
    }

    do {
      var sheet = Sheet(name: "Gaps")
      sheet.setCell(Cell(raw: "b"), at: CellAddress(row: 0, col: 1))
      sheet.setCell(Cell(raw: "gap"), at: CellAddress(row: 0, col: 2))
      sheet.setCell(Cell(raw: "d"), at: CellAddress(row: 0, col: 3))
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      vm.selectColumn(1)
      vm.commandClickColumn(3)
      vm.commandClickColumn(5)
      guard vm.columnInsertCount == 3, vm.insertColumnLeftTitle == "Insert 3 Columns Left" else {
        return Result(name: name, passed: false, detail: "disjoint columns counted \(vm.columnInsertCount)")
      }
      vm.insertColumnsLeft()
      guard raw(vm, 0, 1).isEmpty, raw(vm, 0, 4) == "b", raw(vm, 0, 5) == "gap", raw(vm, 0, 6) == "d" else {
        return Result(name: name, passed: false, detail: "disjoint insert count was not 3")
      }
    }

    do {
      var sheet = Sheet(name: "Edge")
      let last = Workbook.defaultColumnCount - 1
      sheet.setCell(Cell(raw: "end"), at: CellAddress(row: 0, col: last - 1))
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
      vm.selectColumns(from: last - 1, to: last)
      let before = vm.activeSheet.effectiveColumnCount
      guard vm.columnInsertCount == 2 else {
        return Result(name: name, passed: false, detail: "edge selection count \(vm.columnInsertCount)")
      }
      vm.insertColumnsRight()
      guard vm.activeSheet.effectiveColumnCount == before + 2 else {
        return Result(name: name, passed: false, detail: "edge insert grew by \(vm.activeSheet.effectiveColumnCount - before)")
      }
      guard raw(vm, 0, last - 1) == "end" else {
        return Result(name: name, passed: false, detail: "edge insert moved the selected column")
      }
    }

    return Result(name: name, passed: true, detail: "rows and columns match the selection")
  }

  /// Freeze keeps every row or column through the far edge of the selection.
  @MainActor
  private static func freezeThroughSelection() -> Result {
    let name = "freeze through selection"

    do {
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [Sheet(name: "Rows")]))
      vm.selectRows(from: 0, to: 2)
      guard vm.freezeRowsTitle == "Freeze up to row 3",
            vm.freezeColumnsTitle == "Freeze up to column A"
      else {
        return Result(name: name, passed: false, detail: "rows 1–3 titles \(vm.freezeRowsTitle) / \(vm.freezeColumnsTitle)")
      }
      guard vm.freezeRowsAtSelection(),
            vm.activeSheet.frozenRows == 3,
            vm.activeSheet.frozenColumns == 0
      else {
        return Result(name: name, passed: false, detail: "rows 1–3 froze \(vm.activeSheet.frozenRows)")
      }
      guard vm.freezeColumnsAtSelection(),
            vm.activeSheet.frozenColumns == 1,
            vm.activeSheet.frozenRows == 3
      else {
        return Result(name: name, passed: false, detail: "row selection columns froze \(vm.activeSheet.frozenColumns)")
      }
    }

    do {
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [Sheet(name: "Cols")]))
      vm.selectColumns(from: 0, to: 2)
      guard vm.freezeColumnsTitle == "Freeze up to column C",
            vm.freezeRowsTitle == "Freeze up to row 1"
      else {
        return Result(name: name, passed: false, detail: "columns A–C titles \(vm.freezeColumnsTitle) / \(vm.freezeRowsTitle)")
      }
      guard vm.freezeColumnsAtSelection(),
            vm.activeSheet.frozenColumns == 3,
            vm.activeSheet.frozenRows == 0
      else {
        return Result(name: name, passed: false, detail: "columns A–C froze \(vm.activeSheet.frozenColumns)")
      }
      guard vm.freezeRowsAtSelection(),
            vm.activeSheet.frozenRows == 1,
            vm.activeSheet.frozenColumns == 3
      else {
        return Result(name: name, passed: false, detail: "column selection rows froze \(vm.activeSheet.frozenRows)")
      }
    }

    do {
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [Sheet(name: "Below")]))
      vm.selectRows(from: 4, to: 6)
      guard vm.freezeRowsTitle == "Freeze up to row 7" else {
        return Result(name: name, passed: false, detail: "rows 5–7 title \(vm.freezeRowsTitle)")
      }
      guard vm.freezeRowsAtSelection(), vm.activeSheet.frozenRows == 7 else {
        return Result(name: name, passed: false, detail: "rows 5–7 froze \(vm.activeSheet.frozenRows)")
      }
    }

    do {
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [Sheet(name: "Right")]))
      vm.selectColumns(from: 2, to: 4)
      guard vm.freezeColumnsTitle == "Freeze up to column E" else {
        return Result(name: name, passed: false, detail: "columns C–E title \(vm.freezeColumnsTitle)")
      }
      guard vm.freezeColumnsAtSelection(), vm.activeSheet.frozenColumns == 5 else {
        return Result(name: name, passed: false, detail: "columns C–E froze \(vm.activeSheet.frozenColumns)")
      }
    }

    do {
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [Sheet(name: "Block")]))
      vm.selectRange(from: CellAddress(row: 4, col: 1), to: CellAddress(row: 7, col: 3))
      guard vm.freezeRowsTitle == "Freeze up to row 8",
            vm.freezeColumnsTitle == "Freeze up to column D"
      else {
        return Result(name: name, passed: false, detail: "block titles \(vm.freezeRowsTitle) / \(vm.freezeColumnsTitle)")
      }
      guard vm.freezeRowsAtSelection(),
            vm.activeSheet.frozenRows == 8,
            vm.activeSheet.frozenColumns == 0
      else {
        return Result(name: name, passed: false, detail: "block rows froze \(vm.activeSheet.frozenRows)")
      }
      guard vm.freezeColumnsAtSelection(),
            vm.activeSheet.frozenColumns == 4,
            vm.activeSheet.frozenRows == 8
      else {
        return Result(name: name, passed: false, detail: "block columns froze \(vm.activeSheet.frozenColumns) rows \(vm.activeSheet.frozenRows)")
      }
    }

    do {
      let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [Sheet(name: "Reverse")]))
      vm.selectRange(from: CellAddress(row: 7, col: 3), to: CellAddress(row: 4, col: 1))
      guard vm.freezeRowsTitle == "Freeze up to row 8",
            vm.freezeColumnsTitle == "Freeze up to column D"
      else {
        return Result(name: name, passed: false, detail: "reverse titles \(vm.freezeRowsTitle) / \(vm.freezeColumnsTitle)")
      }
      vm.selectRows(from: 2, to: 0)
      guard vm.freezeRowsTitle == "Freeze up to row 3" else {
        return Result(name: name, passed: false, detail: "upward rows title \(vm.freezeRowsTitle)")
      }
      vm.selectColumns(from: 2, to: 0)
      guard vm.freezeColumnsTitle == "Freeze up to column C" else {
        return Result(name: name, passed: false, detail: "leftward columns title \(vm.freezeColumnsTitle)")
      }
    }

    return Result(name: name, passed: true, detail: "freeze follows the bottom row and right column")
  }

  private static func legacyChartLandsUnderData() -> Result {
    let name = "legacy chart lands under data"
    let range = CellRange(
      start: CellAddress(row: 2, col: 0),
      end: CellAddress(row: 8, col: 5)
    )
    let covering = SheetChart(
      kind: .bar,
      title: "Calls by Rep",
      dataRange: range,
      categoryColumn: 0,
      valueColumn: 1,
      hasHeaderRow: true,
      valueMode: .values,
      anchorRow: 0,
      anchorCol: 0
    )
    let placed = covering.positionedUnderData()
    guard placed.anchorRow == 10, placed.anchorCol == 0, placed.id == covering.id else {
      return Result(name: name, passed: false, detail: "moved to \(placed.anchorRow),\(placed.anchorCol)")
    }
    let already = SheetChart(
      id: covering.id,
      kind: .bar,
      title: "Calls by Rep",
      dataRange: range,
      categoryColumn: 0,
      valueColumn: 1,
      anchorRow: 10,
      anchorCol: 0,
      rowSpan: 12,
      colSpan: 8
    )
    let kept = already.positionedUnderData()
    guard kept == already else {
      return Result(name: name, passed: false, detail: "anchored chart moved to \(kept.anchorRow),\(kept.anchorCol)")
    }
    var sheet = Sheet(name: "Weekly Calls")
    sheet.charts = [covering]
    do {
      let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
      let imported = try XLSXCodec.importWorkbook(from: data)
      let chart = imported.sheets[0].charts.first
      guard chart?.anchorRow == 10, chart?.anchorCol == 0, chart?.title == "Calls by Rep" else {
        return Result(name: name, passed: false, detail: "import kept \(String(describing: chart?.anchorRow))")
      }
    } catch {
      return Result(name: name, passed: false, detail: error.localizedDescription)
    }
    return Result(name: name, passed: true, detail: "covering chart opens under A3:F9")
  }

  private static func cfFillTextContrast() -> Result {
    let name = "cf fill text contrast"
    let yellow = CodableColor(red: 1, green: 0.953, blue: 0.804, alpha: 1)
    let dark = CodableColor(red: 0.12, green: 0.18, blue: 0.42, alpha: 1)
    guard CodableColor.contrastingText(on: yellow).relativeLuminance < 0.2,
          CodableColor.contrastingText(on: dark).relativeLuminance > 0.8
    else {
      return Result(name: name, passed: false, detail: "luminance threshold missed the palette")
    }

    let stops = [
      ColorScaleStop(type: .min, value: nil, color: CodableColor(red: 0.992, green: 0.886, blue: 0.882, alpha: 1)),
      ColorScaleStop(type: .percentile, value: 50, color: yellow),
      ColorScaleStop(type: .max, value: nil, color: CodableColor(red: 0.847, green: 0.953, blue: 0.863, alpha: 1)),
    ]
    let scale = ConditionalFormatRule(
      range: CellRange(start: CellAddress(row: 3, col: 4), end: CellAddress(row: 8, col: 4)),
      predicate: .colorScale(stops),
      style: ConditionalFormatStyle()
    )
    let values = [0.41, 0.37, 0.44, 0.29, 0.38, 0.33]
    let lightPaint = ConditionalFormatEvaluator.resolvedPaint(
      at: CellAddress(row: 3, col: 4),
      base: nil,
      rules: [scale],
      value: .number(0.41),
      displayString: "0.41",
      numberFormat: nil,
      numericValuesInRange: { _ in values },
      evaluateFormula: { _, _, _ in .blank }
    )
    guard let lightText = lightPaint.format?.textColor, lightText.relativeLuminance < 0.25 else {
      return Result(name: name, passed: false, detail: "scale text \(String(describing: lightPaint.format?.textColor))")
    }

    var whiteBase = CellFormat()
    whiteBase.textColor = CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
    let darkRule = ConditionalFormatRule(
      range: CellRange(start: .origin, end: .origin),
      predicate: .greaterThan(0),
      style: ConditionalFormatStyle(fillColor: dark)
    )
    let darkPaint = ConditionalFormatEvaluator.resolvedPaint(
      at: .origin,
      base: whiteBase,
      rules: [darkRule],
      value: .number(5),
      displayString: "5",
      numberFormat: nil,
      numericValuesInRange: { _ in [] },
      evaluateFormula: { _, _, _ in .blank }
    )
    guard let darkText = darkPaint.format?.textColor, darkText.relativeLuminance > 0.8 else {
      return Result(name: name, passed: false, detail: "dark fill text \(String(describing: darkPaint.format?.textColor))")
    }

    let chosen = CodableColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1)
    let keptRule = ConditionalFormatRule(
      range: CellRange(start: .origin, end: .origin),
      predicate: .greaterThan(0),
      style: ConditionalFormatStyle(textColor: chosen, fillColor: yellow)
    )
    let keptPaint = ConditionalFormatEvaluator.resolvedPaint(
      at: .origin,
      base: nil,
      rules: [keptRule],
      value: .number(5),
      displayString: "5",
      numberFormat: nil,
      numericValuesInRange: { _ in [] },
      evaluateFormula: { _, _, _ in .blank }
    )
    guard let keptText = keptPaint.format?.textColor, abs(keptText.red - chosen.red) < 0.01 else {
      return Result(name: name, passed: false, detail: "rule text was replaced \(String(describing: keptPaint.format?.textColor))")
    }
    return Result(name: name, passed: true, detail: "dark on light scale, light on dark fill")
  }

  private static func formulaFunctionPicker() -> Result {
    let name = "formula function picker"
    let groups = FormulaFunctionCatalog.groups(matching: "")
    let listed = groups.flatMap { $0.entries.map(\.name) }
    let implemented = Set(FormulaFunctions.all)
    let listedSet = Set(listed)
    if listedSet != implemented || listed.count != implemented.count {
      let missing = implemented.subtracting(listedSet).sorted()
      let extra = listedSet.subtracting(implemented).sorted()
      return Result(
        name: name,
        passed: false,
        detail: "catalog missing \(missing.joined(separator: ", ")) extra \(extra.joined(separator: ", "))"
      )
    }
    let titles = groups.map(\.kind.title)
    if titles != ["Math", "Statistical", "Logical", "Text", "Lookup", "Date & Time"] {
      return Result(name: name, passed: false, detail: "groups \(titles.joined(separator: ", "))")
    }

    for group in groups {
      for entry in group.entries {
        if entry.kind != group.kind {
          return Result(name: name, passed: false, detail: "\(entry.name) kind")
        }
        guard let insertion = FormulaFunctionCatalog.insertion(for: entry.name) else {
          return Result(name: name, passed: false, detail: "no insertion for \(entry.name)")
        }
        if insertion.text != "=\(entry.name)()" || insertion.signatureLine != entry.signatureLine {
          return Result(name: name, passed: false, detail: "\(entry.name) insertion \(insertion.text)")
        }
        if insertion.signatureLine.isEmpty || insertion.signatureLine.contains("\n") {
          return Result(name: name, passed: false, detail: "\(entry.name) argument line")
        }
        let ns = insertion.text as NSString
        let caret = insertion.caretUTF16
        if caret <= 0 || caret >= ns.length
          || ns.character(at: caret - 1) != UInt16(UnicodeScalar("(").value)
          || ns.character(at: caret) != UInt16(UnicodeScalar(")").value)
        {
          return Result(name: name, passed: false, detail: "\(entry.name) caret \(caret) in \(insertion.text)")
        }
        let value = evalFormula(insertion.text, cells: [:])
        if case .error(.name) = value {
          return Result(name: name, passed: false, detail: "\(entry.name) does not calculate")
        }
        if case .error(.error) = value {
          return Result(name: name, passed: false, detail: "\(entry.name) did not parse")
        }
      }
    }

    let sumNames = Set(FormulaFunctionCatalog.groups(matching: "sum").flatMap { $0.entries.map(\.name) })
    if sumNames != ["SUM", "SUMIF", "SUMIFS", "SUMPRODUCT"] {
      return Result(name: name, passed: false, detail: "sum search \(sumNames.sorted())")
    }
    let lookup = Set(FormulaFunctionCatalog.groups(matching: "xLoOkUp").flatMap { $0.entries.map(\.name) })
    if lookup != ["XLOOKUP"] {
      return Result(name: name, passed: false, detail: "lookup search \(lookup.sorted())")
    }
    if !FormulaFunctionCatalog.groups(matching: "notafunction").isEmpty {
      return Result(name: name, passed: false, detail: "unknown query returned functions")
    }
    if FormulaFunctionCatalog.insertion(for: "SUMIFZ") != nil {
      return Result(name: name, passed: false, detail: "inserted an unknown function")
    }
    if !FormulaFunctionListKeys.shouldClose(keyCode: FormulaFunctionListKeys.escapeKeyCode, modifierFlags: [])
      || FormulaFunctionListKeys.shouldClose(keyCode: 36, modifierFlags: [])
      || FormulaFunctionListKeys.shouldClose(keyCode: FormulaFunctionListKeys.escapeKeyCode, modifierFlags: .command)
    {
      return Result(name: name, passed: false, detail: "escape check failed")
    }

    let placed = MainActor.assumeIsolated { () -> String in
      let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [Sheet(name: "Sheet1")]))
      viewModel.setCellValue("12", at: .origin)
      viewModel.insertFormulaFunction("ROUND")
      guard viewModel.isEditing, viewModel.formulaBarText == "=ROUND()", viewModel.editText == "=ROUND()" else {
        return "bar \(viewModel.formulaBarText) editing \(viewModel.isEditing)"
      }
      guard viewModel.formulaCaretUTF16 == 7, viewModel.formulaCaretToken == 1 else {
        return "caret \(viewModel.formulaCaretUTF16) token \(viewModel.formulaCaretToken)"
      }
      guard viewModel.formulaArgumentHint == "ROUND(number, [num_digits])" else {
        return "hint \(viewModel.formulaArgumentHint ?? "")"
      }
      viewModel.insertFormulaFunction("NOPE")
      guard viewModel.formulaBarText == "=ROUND()", viewModel.formulaCaretToken == 1 else {
        return "unknown function changed the bar"
      }
      viewModel.commitEdit()
      guard !viewModel.isEditing,
            viewModel.formulaArgumentHint == nil,
            viewModel.activeSheet.cell(at: .origin).raw == "=ROUND()"
      else {
        return "commit \(viewModel.activeSheet.cell(at: .origin).raw)"
      }
      viewModel.insertFormulaFunction("abs")
      guard viewModel.formulaBarText == "=ABS()",
            viewModel.formulaCaretUTF16 == 5,
            viewModel.formulaArgumentHint == "ABS(number)"
      else {
        return "abs \(viewModel.formulaBarText) \(viewModel.formulaArgumentHint ?? "")"
      }
      return ""
    }
    if !placed.isEmpty {
      return Result(name: name, passed: false, detail: placed)
    }
    return Result(
      name: name,
      passed: true,
      detail: "\(listed.count) functions, grouped, caret inside parentheses"
    )
  }

  private static func everydayFormulas() -> Result {
    let name = "everyday formulas"
    let wanted = [
      "SUMIF", "AVERAGEIF", "COUNTIF", "SUMIFS", "COUNTIFS", "AVERAGEIFS",
      "COUNTBLANK", "SUMPRODUCT", "IFNA", "IFS", "NOT", "UPPER", "LOWER",
      "MID", "SUBSTITUTE", "TEXTJOIN", "ROUNDUP", "ROUNDDOWN", "NOW",
    ]
    let missing = wanted.filter { !FormulaFunctions.all.contains($0) }
    if !missing.isEmpty {
      return Result(name: name, passed: false, detail: "catalog missing \(missing.joined(separator: ", "))")
    }

    let cells: [CellAddress: String] = [
      CellAddress(row: 0, col: 0): "10",
      CellAddress(row: 1, col: 0): "20",
      CellAddress(row: 2, col: 0): "30",
      CellAddress(row: 0, col: 1): "1",
      CellAddress(row: 1, col: 1): "2",
      CellAddress(row: 2, col: 1): "3",
      CellAddress(row: 0, col: 2): "east",
      CellAddress(row: 1, col: 2): "west",
      CellAddress(row: 2, col: 2): "eastern",
      CellAddress(row: 0, col: 3): "5",
      CellAddress(row: 1, col: 3): "7",
      CellAddress(row: 2, col: 3): "9",
      CellAddress(row: 4, col: 0): "apple",
      CellAddress(row: 6, col: 0): "Apple",
      CellAddress(row: 0, col: 4): "FALSE",
      CellAddress(row: 1, col: 4): "0",
      CellAddress(row: 1, col: 5): "star*",
      CellAddress(row: 2, col: 5): "starX",
    ]
    let cases: [(String, CellValue)] = [
      ("=SUMIF(A1:A3,\">15\")", .number(50)),
      ("=SUMIF(A1:A3,\">15\",B1:B3)", .number(5)),
      ("=SUMIF(A1:A3,\">15\",B1)", .number(5)),
      ("=SUMIF(C1:C3,\"*east*\",D1:D3)", .number(14)),
      ("=COUNTIF(C1:C3,\"*east*\")", .number(2)),
      ("=COUNTIF(C1:C3,\"?est\")", .number(1)),
      ("=COUNTIF(A1:A3,\">=20\")", .number(2)),
      ("=COUNTIF(A5:A7,\"apple\")", .number(2)),
      ("=COUNTIF(F1:F3,\"star~*\")", .number(1)),
      ("=COUNTIF(F1:F3,\"*\")", .number(2)),
      ("=AVERAGEIF(A1:A3,\">15\")", .number(25)),
      ("=AVERAGEIF(A1:A3,\">100\")", .error(.divZero)),
      ("=SUMIFS(B1:B3,A1:A3,\">10\",A1:A3,\"<30\")", .number(2)),
      ("=COUNTIFS(A1:A3,\">15\",B1:B3,\"<3\")", .number(1)),
      ("=AVERAGEIFS(B1:B3,A1:A3,\">=20\")", .number(2.5)),
      ("=AVERAGEIFS(B1:B3,A1:A3,\">100\")", .error(.divZero)),
      ("=SUMIFS(B1:B2,A1:A3,\">0\")", .error(.value)),
      ("=COUNTBLANK(A1:A4)", .number(1)),
      ("=COUNTBLANK(E1:E3)", .number(1)),
      ("=SUMPRODUCT(A1:A3,B1:B3)", .number(140)),
      ("=SUMPRODUCT(A1:A3,B1:B2)", .error(.value)),
      ("=SUMPRODUCT((A1:A3>15)*(B1:B3))", .number(5)),
      ("=IFNA(1,2)", .number(1)),
      ("=IFNA(VLOOKUP(\"z\",A1:B3,2,FALSE),9)", .number(9)),
      ("=IFNA(1/0,9)", .error(.divZero)),
      ("=IFS(FALSE,1,TRUE,2)", .number(2)),
      ("=IFS(FALSE,1)", .error(.na)),
      ("=IFS(1,\"yes\")", .string("yes")),
      ("=NOT(FALSE)", .bool(true)),
      ("=NOT(1)", .bool(false)),
      ("=NOT(0)", .bool(true)),
      ("=UPPER(\"Ab\")", .string("AB")),
      ("=LOWER(\"Ab\")", .string("ab")),
      ("=UPPER(12)", .string("12")),
      ("=MID(\"spark\",2,3)", .string("par")),
      ("=MID(\"spark\",0,1)", .error(.value)),
      ("=SUBSTITUTE(\"a-a-a\",\"a\",\"b\")", .string("b-b-b")),
      ("=SUBSTITUTE(\"a-a-a\",\"a\",\"b\",2)", .string("a-b-a")),
      ("=SUBSTITUTE(\"Apple\",\"p\",\"X\")", .string("AXXle")),
      ("=SUBSTITUTE(\"Apple\",\"P\",\"X\")", .string("Apple")),
      ("=TEXTJOIN(\", \",TRUE,C1:C3)", .string("east, west, eastern")),
      ("=TEXTJOIN(\",\",FALSE,C1,C4,C3)", .string("east,,eastern")),
      ("=ROUNDUP(1.1,0)", .number(2)),
      ("=ROUNDUP(-1.2,0)", .number(-2)),
      ("=ROUNDDOWN(1.9,0)", .number(1)),
      ("=ROUNDDOWN(-1.9,0)", .number(-1)),
      ("=ROUNDUP(1.234,2)", .number(1.24)),
      ("=ROUNDDOWN(1.239,2)", .number(1.23)),
      ("=ROUNDUP(1234,-2)", .number(1300)),
      ("=ROUNDDOWN(1234,-2)", .number(1200)),
    ]
    for (formula, expected) in cases {
      let value = evalFormula(formula, cells: cells)
      if !sameCellValue(value, expected) {
        return Result(
          name: name,
          passed: false,
          detail: "\(formula) got \(value.displayString) expected \(expected.displayString)"
        )
      }
    }

    let before = ExcelDate.serialWithTime(from: Date())
    let now = evalFormula("=NOW()", cells: [:])
    let after = ExcelDate.serialWithTime(from: Date())
    guard case .number(let serial) = now, serial >= before - 0.00001, serial <= after + 0.00001 else {
      return Result(name: name, passed: false, detail: "NOW got \(now.displayString)")
    }
    return Result(name: name, passed: true, detail: "criteria, wildcards, text, and rounding")
  }

  private static func lookupFormulas() -> Result {
    let name = "lookup formulas"
    let missing = ["HLOOKUP", "XMATCH", "XLOOKUP", "VLOOKUP"].filter { !FormulaFunctions.all.contains($0) }
    if !missing.isEmpty {
      return Result(name: name, passed: false, detail: "catalog missing \(missing.joined(separator: ", "))")
    }

    let cells: [CellAddress: String] = [
      CellAddress(row: 0, col: 0): "10",
      CellAddress(row: 1, col: 0): "20",
      CellAddress(row: 2, col: 0): "30",
      CellAddress(row: 3, col: 0): "15",
      CellAddress(row: 4, col: 0): "20",
      CellAddress(row: 0, col: 1): "a",
      CellAddress(row: 1, col: 1): "b",
      CellAddress(row: 2, col: 1): "c",
      CellAddress(row: 3, col: 1): "d",
      CellAddress(row: 4, col: 1): "later",
      CellAddress(row: 0, col: 2): "east",
      CellAddress(row: 1, col: 2): "west",
      CellAddress(row: 2, col: 2): "eastern",
      CellAddress(row: 0, col: 3): "5",
      CellAddress(row: 1, col: 3): "7",
      CellAddress(row: 2, col: 3): "9",
      CellAddress(row: 0, col: 4): "apple",
      CellAddress(row: 1, col: 4): "banana",
      CellAddress(row: 2, col: 4): "cherry",
      CellAddress(row: 0, col: 5): "1",
      CellAddress(row: 1, col: 5): "2",
      CellAddress(row: 2, col: 5): "3",
      CellAddress(row: 1, col: 6): "star*",
      CellAddress(row: 2, col: 6): "starX",
      CellAddress(row: 1, col: 7): "11",
      CellAddress(row: 2, col: 7): "22",
      CellAddress(row: 5, col: 0): "10",
      CellAddress(row: 5, col: 1): "20",
      CellAddress(row: 5, col: 2): "30",
      CellAddress(row: 6, col: 0): "a",
      CellAddress(row: 6, col: 1): "b",
      CellAddress(row: 6, col: 2): "c",
      CellAddress(row: 8, col: 0): "30",
      CellAddress(row: 8, col: 1): "10",
      CellAddress(row: 8, col: 2): "20",
      CellAddress(row: 9, col: 0): "x",
      CellAddress(row: 9, col: 1): "y",
      CellAddress(row: 9, col: 2): "z",
      CellAddress(row: 11, col: 0): "east",
      CellAddress(row: 11, col: 1): "west",
      CellAddress(row: 11, col: 2): "eastern",
      CellAddress(row: 12, col: 0): "5",
      CellAddress(row: 12, col: 1): "7",
      CellAddress(row: 12, col: 2): "9",
      CellAddress(row: 14, col: 0): "10",
      CellAddress(row: 14, col: 1): "20",
      CellAddress(row: 14, col: 2): "20",
      CellAddress(row: 15, col: 0): "p",
      CellAddress(row: 15, col: 1): "q",
      CellAddress(row: 15, col: 2): "r",
      CellAddress(row: 19, col: 0): "10",
      CellAddress(row: 20, col: 0): "20",
      CellAddress(row: 21, col: 0): "20",
      CellAddress(row: 19, col: 1): "p",
      CellAddress(row: 20, col: 1): "q",
      CellAddress(row: 21, col: 1): "r",
    ]
    let cases: [(String, CellValue)] = [
      ("=VLOOKUP(20,A1:B3,2,FALSE)", .string("b")),
      ("=VLOOKUP(25,A1:B3,2)", .string("b")),
      ("=VLOOKUP(25,A1:B3,2,TRUE)", .string("b")),
      ("=VLOOKUP(20,A20:B22,2)", .string("r")),
      ("=VLOOKUP(20,A20:B22,2,FALSE)", .string("q")),
      ("=VLOOKUP(5,A1:B3,2)", .error(.na)),
      ("=VLOOKUP(20,A1:B3,3,FALSE)", .error(.ref)),
      ("=VLOOKUP(\"z\",A1:B3,2,FALSE)", .error(.na)),
      ("=HLOOKUP(20,A6:C7,2,FALSE)", .string("b")),
      ("=HLOOKUP(25,A6:C7,2)", .string("b")),
      ("=HLOOKUP(25,A6:C7,2,TRUE)", .string("b")),
      ("=hlookup(20,A6:C7,1,FALSE)", .number(20)),
      ("=HLOOKUP(25,A6:C7,2,FALSE)", .error(.na)),
      ("=HLOOKUP(5,A6:C7,2)", .error(.na)),
      ("=HLOOKUP(20,A6:C7,3,FALSE)", .error(.ref)),
      ("=HLOOKUP(10,A6:C7,0,FALSE)", .error(.ref)),
      ("=HLOOKUP(10,A6:C7,\"x\",FALSE)", .error(.value)),
      ("=HLOOKUP(10,A6:C7)", .error(.value)),
      ("=HLOOKUP(25,A9:C10,2)", .string("z")),
      ("=HLOOKUP(10,A9:C10,2,FALSE)", .string("y")),
      ("=HLOOKUP(\"WEST\",A12:C13,2,FALSE)", .number(7)),
      ("=HLOOKUP(\"nope\",A12:C13,2,FALSE)", .error(.na)),
      ("=HLOOKUP(20,A15:C16,2)", .string("r")),
      ("=HLOOKUP(20,A15:C16,2,FALSE)", .string("q")),
      ("=XLOOKUP(20,A1:A3,B1:B3)", .string("b")),
      ("=XLOOKUP(20,A1:A3,B1:B3,\"missing\")", .string("b")),
      ("=XLOOKUP(\"z\",A1:A3,B1:B3,9)", .number(9)),
      ("=XLOOKUP(25,A1:A3,B1:B3,\"missing\")", .string("missing")),
      ("=XLOOKUP(\"*east*\",C1:C3,D1:D3,\"no\")", .string("no")),
      ("=XLOOKUP(20,A6:C6,A7:C7)", .string("b")),
      ("=XLOOKUP(\"APPLE\",E1:E3,F1:F3)", .number(1)),
      ("=XLOOKUP(20,A1:A3,B1:B3,\"no\",0)", .string("b")),
      ("=XLOOKUP(25,A1:A5,B1:B5,\"missing\",-1)", .string("b")),
      ("=XLOOKUP(25,A1:A5,B1:B5,\"missing\",1)", .string("c")),
      ("=XLOOKUP(5,A1:A4,B1:B4,\"missing\",-1)", .string("missing")),
      ("=XLOOKUP(40,A1:A4,B1:B4,\"missing\",1)", .string("missing")),
      ("=XLOOKUP(20,A1:A5,B1:B5,\"missing\",-1)", .string("b")),
      ("=XLOOKUP(\"blueberry\",E1:E3,F1:F3,\"missing\",-1)", .number(2)),
      ("=XLOOKUP(\"blueberry\",E1:E3,F1:F3,\"missing\",1)", .number(3)),
      ("=XLOOKUP(\"aardvark\",E1:E3,F1:F3,\"missing\",-1)", .string("missing")),
      ("=XLOOKUP(\"date\",E1:E3,F1:F3,\"missing\",1)", .string("missing")),
      ("=XLOOKUP(25,A6:C6,A7:C7,\"missing\",-1)", .string("b")),
      ("=XLOOKUP(25,A6:C6,A7:C7,\"missing\",1)", .string("c")),
      ("=XLOOKUP(\"*east*\",C1:C3,D1:D3,\"no\",2)", .number(5)),
      ("=XLOOKUP(\"w*\",C1:C3,D1:D3,\"no\",2)", .number(7)),
      ("=XLOOKUP(\"*ern\",C1:C3,D1:D3,\"no\",2)", .number(9)),
      ("=XLOOKUP(\"2*\",A1:A3,B1:B3,\"no\",2)", .string("b")),
      ("=XLOOKUP(\"star~*\",G2:G3,H2:H3,\"no\",2)", .number(11)),
      ("=XLOOKUP(\"nope*\",C1:C3,D1:D3,\"no\",2)", .string("no")),
      ("=XLOOKUP(20,A1:A3,B1:B3,\"no\",3)", .error(.value)),
      ("=XLOOKUP(20,A1:A3,B1:B3,\"no\",0,1)", .error(.value)),
      ("=XLOOKUP(10,A1:A3)", .error(.value)),
      ("=XMATCH(20,A1:A3)", .number(2)),
      ("=XMATCH(\"z\",A1:A3)", .error(.na)),
      ("=XMATCH(25,A1:A4,-1)", .number(2)),
      ("=XMATCH(25,A1:A4,1)", .number(3)),
      ("=XMATCH(5,A1:A4,-1)", .error(.na)),
      ("=XMATCH(\"blueberry\",E1:E3,-1)", .number(2)),
      ("=XMATCH(\"blueberry\",E1:E3,1)", .number(3)),
      ("=XMATCH(\"w*\",C1:C3,2)", .number(2)),
      ("=XMATCH(\"*ern\",C1:C3,2)", .number(3)),
      ("=XMATCH(\"star~*\",G2:G3,2)", .number(1)),
      ("=XMATCH(30,A6:C6)", .number(3)),
      ("=XMATCH(25,A6:C6,-1)", .number(2)),
      ("=XMATCH(25,A6:C6,1)", .number(3)),
      ("=xmatch(20,A1:A3,0)", .number(2)),
      ("=XMATCH(20,A1:A3,4)", .error(.value)),
      ("=XMATCH(10)", .error(.value)),
    ]
    for (formula, expected) in cases {
      let value = evalFormula(formula, cells: cells)
      if !sameCellValue(value, expected) {
        return Result(
          name: name,
          passed: false,
          detail: "\(formula) got \(value.displayString) expected \(expected.displayString)"
        )
      }
    }
    return Result(name: name, passed: true, detail: "HLOOKUP, XMATCH, and XLOOKUP match modes")
  }

  private static func sameCellValue(_ lhs: CellValue, _ rhs: CellValue) -> Bool {
    if case .number(let left) = lhs, case .number(let right) = rhs {
      return abs(left - right) < 0.000_000_1
    }
    return lhs == rhs
  }

  private static func evalFormula(_ formula: String, cells: [CellAddress: String]) -> CellValue {
    var sheet = Sheet(name: "Sheet1")
    for (address, raw) in cells {
      sheet.setCell(Cell(raw: raw), at: address)
    }
    let result = CellAddress(row: 40, col: 0)
    sheet.setCell(Cell(raw: formula), at: result)
    let engine = FormulaEngine()
    let workbook = Workbook(sheets: [sheet])
    engine.rebuild(workbook: workbook)
    return engine.displayValue(at: result, sheet: workbook.activeSheet)
  }

  private static func excelFormatCodes() -> Result {
    let name = "excel format codes"
    func shown(_ number: Double, code: String, places: Int? = nil) -> String {
      var format = CellFormat()
      format.formatCode = code
      format.decimalPlaces = places
      return CellFormatRenderer.displayText(for: .number(number), format: format, fallbackRaw: "")
    }

    func shownText(_ text: String, code: String) -> String {
      var format = CellFormat()
      format.formatCode = code
      return CellFormatRenderer.displayText(for: .string(text), format: format, fallbackRaw: text)
    }

    let sections = "#,##0.00;(#,##0.00);\"zero\";\"id \"@"
    let checks: [(String, String)] = [
      (shown(1234.5, code: "€#,##0.00"), "€1,234.50"),
      (shown(-1234.5, code: "€#,##0.00"), "-€1,234.50"),
      (shown(1234.5, code: "[$£-809]#,##0.00"), "£1,234.50"),
      (shown(1234.5, code: "\"$\"#,##0.00"), "$1,234.50"),
      (shown(1234.5, code: "#,##0.00"), "1,234.50"),
      (shown(1234.4, code: "#,##0"), "1,234"),
      (shown(1234.5, code: "#,##0.00 \"kg\""), "1,234.50 kg"),
      (shown(1234.5, code: "\"Qty \"#,##0.00"), "Qty 1,234.50"),
      (shown(5, code: "\"say \"\"hi\"\" \"0"), "say \"hi\" 5"),
      (shown(1, code: "\"a;b\""), "a;b"),
      (shown(5, code: "0\\;0"), "5;0"),
      (shown(0.5, code: "0%"), "50%"),
      (shown(0.256, code: "0.00%"), "25.60%"),
      (shown(-0.256, code: "0.00%"), "-25.60%"),
      (shown(0.256, code: "0.00\"%\""), "0.26%"),
      (shown(-1234.5, code: "$#,##0.00_);($#,##0.00)"), "($1,234.50)"),
      (shown(1234.5, code: sections), "1,234.50"),
      (shown(-1234.5, code: sections), "(1,234.50)"),
      (shown(0, code: sections), "zero"),
      (shown(0, code: "0;-0;;"), ""),
      (shown(1234, code: "\"n/a\""), "n/a"),
      (shown(1234, code: "0.00E+00"), "1.23E+03"),
      (shown(1234.5, code: "#,##0.00", places: 0), "1,235"),
      (shownText("Hello", code: sections), "id Hello"),
      (shownText("Hello", code: "0;0;0;@\" and \"@"), "Hello and Hello"),
      (shownText("Hello", code: "0;0;0;\"@\"@"), "@Hello"),
      (shownText("Hello", code: "0;0;0;[Red]@"), "Hello"),
      (shownText("Hello", code: "0;0;0;\"n/a\""), "n/a"),
      (shownText("Hello", code: "0;0;0;\"a;b \"@"), "a;b Hello"),
      (shownText("Hello", code: "0.00"), "Hello"),
    ]
    for (actual, expected) in checks where actual != expected {
      return Result(name: name, passed: false, detail: "\(actual) expected \(expected)")
    }

    var plainCurrency = CellFormat()
    plainCurrency.numberFormat = .currency
    let forced = CellFormatRenderer.displayText(for: .number(1234.5), format: plainCurrency, fallbackRaw: "1234.5")
    if forced != "$1234.50" {
      return Result(name: name, passed: false, detail: "toolbar currency \(forced)")
    }

    guard let noon = octoberEighth2026() else {
      return Result(name: name, passed: false, detail: "date components")
    }
    let serial = ExcelDate.serial(from: noon)
    let dates: [(String, String)] = [
      (shown(serial, code: "dd/mm/yyyy"), "08/10/2026"),
      (shown(serial, code: "d-mmm-yy"), "8-Oct-26"),
      (shown(serial, code: "m/d/yyyy"), "10/8/2026"),
      (shown(serial, code: "yyyy-mm-dd"), "2026-10-08"),
      (shown(serial, code: "d \"of\" mmm yyyy"), "8 of Oct 2026"),
      (shown(0.75, code: "h:mm"), "18:00"),
      (shown(0.75, code: "h:mm AM/PM"), "6:00 PM"),
      (shown(0.75, code: "h:mm \"AM\""), "18:00 AM"),
      (shown(0.75, code: "h\"h\" mm\"m\""), "18h 00m"),
      (shown(1.5, code: "[h]:mm:ss"), "36:00:00"),
      (shown(1.5, code: "[h]:mm \"sec\""), "36:00"),
    ]
    for (actual, expected) in dates where actual != expected {
      return Result(name: name, passed: false, detail: "\(actual) expected \(expected)")
    }

    do {
      var sheet = Sheet(name: "Formats")
      var euro = CellFormat()
      euro.numberFormat = .currency
      euro.formatCode = "€#,##0.00"
      sheet.setCell(Cell(raw: "1234.5", format: euro), at: CellAddress(row: 0, col: 0))
      var toolbar = CellFormat()
      toolbar.numberFormat = .currency
      sheet.setCell(Cell(raw: "1234.5", format: toolbar), at: CellAddress(row: 1, col: 0))
      var dated = CellFormat()
      dated.numberFormat = .date
      sheet.setCell(Cell(raw: String(serial), format: dated), at: CellAddress(row: 2, col: 0))
      var custom = CellFormat()
      custom.formatCode = sections
      custom.numberFormat = .number
      sheet.setCell(Cell(raw: "1234.5", format: custom), at: CellAddress(row: 3, col: 0))
      sheet.setCell(Cell(raw: "Hello", format: custom), at: CellAddress(row: 4, col: 0))

      let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [sheet]))
      let imported = try XLSXCodec.importWorkbook(from: data)
      let euroCell = imported.sheets[0].cell(at: CellAddress(row: 0, col: 0))
      let euroShown = CellFormatRenderer.displayText(
        for: .number(1234.5),
        format: euroCell.format,
        fallbackRaw: euroCell.raw
      )
      if euroCell.format?.formatCode != "€#,##0.00" || euroShown != "€1,234.50" {
        return Result(name: name, passed: false, detail: "euro reimport \(euroCell.format?.formatCode ?? "") \(euroShown)")
      }
      let dollar = imported.sheets[0].cell(at: CellAddress(row: 1, col: 0))
      let dollarShown = CellFormatRenderer.displayText(
        for: .number(1234.5),
        format: dollar.format,
        fallbackRaw: dollar.raw
      )
      if dollar.format?.formatCode != "$#,##0.00" || dollarShown != "$1,234.50" {
        return Result(name: name, passed: false, detail: "currency reimport \(dollar.format?.formatCode ?? "") \(dollarShown)")
      }
      if imported.sheets[0].cell(at: CellAddress(row: 2, col: 0)).format?.formatCode != "m/d/yyyy" {
        return Result(name: name, passed: false, detail: "builtin 14 code missing")
      }

      guard var styles = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/styles.xml") else {
        return Result(name: name, passed: false, detail: "styles.xml missing")
      }
      guard styles.contains("numFmtId=\"14\"") else {
        return Result(name: name, passed: false, detail: "date did not export as builtin 14")
      }
      styles = styles.replacingOccurrences(of: "numFmtId=\"14\"", with: "numFmtId=\"15\"")
      guard let patched = XLSXCodec.replacingZipEntries(data, entries: ["xl/styles.xml": Data(styles.utf8)]) else {
        return Result(name: name, passed: false, detail: "could not patch styles")
      }
      let builtin = try XLSXCodec.importWorkbook(from: patched)
      let dateCell = builtin.sheets[0].cell(at: CellAddress(row: 2, col: 0))
      let dateShown = CellFormatRenderer.displayText(for: .number(serial), format: dateCell.format, fallbackRaw: dateCell.raw)
      if dateCell.format?.formatCode != "d-mmm-yy" || dateShown != "8-Oct-26" {
        return Result(name: name, passed: false, detail: "builtin 15 \(dateCell.format?.formatCode ?? "") \(dateShown)")
      }
      let customNumber = imported.sheets[0].cell(at: CellAddress(row: 3, col: 0))
      let customShown = CellFormatRenderer.displayText(
        for: .number(1234.5),
        format: customNumber.format,
        fallbackRaw: customNumber.raw
      )
      if customNumber.format?.formatCode != sections || customShown != "1,234.50" {
        return Result(name: name, passed: false, detail: "custom reimport \(customNumber.format?.formatCode ?? "") \(customShown)")
      }
      let customText = imported.sheets[0].cell(at: CellAddress(row: 4, col: 0))
      let textShown = CellFormatRenderer.displayText(for: .string("Hello"), format: customText.format, fallbackRaw: "Hello")
      let rawShown = CellFormatRenderer.displayText(raw: "Hello", format: customText.format)
      if customText.format?.formatCode != sections || textShown != "id Hello" || rawShown != "id Hello" {
        return Result(name: name, passed: false, detail: "text reimport \(customText.format?.formatCode ?? "") \(textShown) \(rawShown)")
      }
    } catch {
      return Result(name: name, passed: false, detail: error.localizedDescription)
    }
    return Result(name: name, passed: true, detail: "sections, quotes, symbol, and date pattern")
  }

  private static func definedNamesResolve() -> Result {
    let name = "defined names resolve"
    var sheet = Sheet(name: "Q3 Sales")
    sheet.setCell(Cell(raw: "10"), at: CellAddress(row: 0, col: 0))
    sheet.setCell(Cell(raw: "20"), at: CellAddress(row: 1, col: 0))
    sheet.setCell(Cell(raw: "4"), at: CellAddress(row: 0, col: 1))
    sheet.setCell(Cell(raw: "=SUM(Sales)"), at: CellAddress(row: 0, col: 2))
    sheet.setCell(Cell(raw: "=Rate"), at: CellAddress(row: 1, col: 2))
    var workbook = Workbook(sheets: [sheet])
    workbook.setNamedRange(
      NamedRange(
        name: "Sales",
        sheetName: "Q3 Sales",
        range: CellRange(start: CellAddress(row: 0, col: 0), end: CellAddress(row: 1, col: 0))
      )
    )
    do {
      let data = try XLSXCodec.exportWorkbook(workbook)
      let roundTrip = try XLSXCodec.importWorkbook(from: data)
      let engine = FormulaEngine()
      engine.rebuild(workbook: roundTrip)
      let summed = engine.displayValue(at: CellAddress(row: 0, col: 2), sheet: roundTrip.activeSheet)
      if summed != .number(30) || roundTrip.namedRange(named: "Sales") == nil {
        return Result(name: name, passed: false, detail: "exported Sales resolved to \(summed.displayString)")
      }

      guard var xml = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/workbook.xml"),
            let start = xml.range(of: "<definedNames"),
            let end = xml.range(of: "</definedNames>")
      else {
        return Result(name: name, passed: false, detail: "workbook.xml has no definedNames")
      }
      let excelNames = """
      <definedNames>\
      <definedName name="Sales">'Q3 Sales'!$A$1:$A$2</definedName>\
      <definedName name="Rate">'q3 sales'!$B$1</definedName>\
      <definedName name="Broken">OFFSET('Q3 Sales'!$A$1,0,0)</definedName>\
      </definedNames>
      """
      xml.replaceSubrange(start.lowerBound..<end.upperBound, with: excelNames)
      guard let patched = XLSXCodec.replacingZipEntries(data, entries: ["xl/workbook.xml": Data(xml.utf8)]) else {
        return Result(name: name, passed: false, detail: "could not patch workbook.xml")
      }
      let imported = try XLSXCodec.importWorkbook(from: patched)
      guard let broken = imported.namedRange(named: "Broken"),
            broken.resolvesToRange == false,
            broken.refersTo?.contains("OFFSET") == true
      else {
        return Result(name: name, passed: false, detail: "OFFSET name was dropped or resolved")
      }
      guard let sales = imported.namedRange(named: "Sales"),
            sales.resolvesToRange,
            sales.sheetName == "Q3 Sales",
            sales.startRow == 0, sales.endRow == 1, sales.startCol == 0,
            let rate = imported.namedRange(named: "Rate"),
            rate.resolvesToRange,
            rate.sheetName == "Q3 Sales",
            rate.startRow == 0, rate.startCol == 1, rate.endRow == 0, rate.endCol == 1
      else {
        return Result(name: name, passed: false, detail: "Sales or Rate did not parse")
      }
      var withFormula = imported
      var formulaSheet = withFormula.activeSheet
      formulaSheet.setCell(Cell(raw: "=Broken"), at: CellAddress(row: 3, col: 0))
      withFormula.activeSheet = formulaSheet
      let patchedEngine = FormulaEngine()
      patchedEngine.rebuild(workbook: withFormula)
      let total = patchedEngine.displayValue(at: CellAddress(row: 0, col: 2), sheet: withFormula.activeSheet)
      let rateValue = patchedEngine.displayValue(at: CellAddress(row: 1, col: 2), sheet: withFormula.activeSheet)
      let offsetValue = patchedEngine.displayValue(at: CellAddress(row: 3, col: 0), sheet: withFormula.activeSheet)
      if total != .number(30) || rateValue != .number(4) || offsetValue != .error(.name) {
        return Result(
          name: name,
          passed: false,
          detail: "SUM(Sales)=\(total.displayString) Rate=\(rateValue.displayString) OFFSET=\(offsetValue.displayString)"
        )
      }
      let again = try XLSXCodec.exportWorkbook(imported)
      let workbookXML = XLSXCodec.zipEntryString(archiveData: again, entryPath: "xl/workbook.xml") ?? ""
      if !workbookXML.contains("name=\"Broken\"") || !workbookXML.contains("OFFSET") {
        return Result(name: name, passed: false, detail: "export replaced OFFSET with a range")
      }
    } catch {
      return Result(name: name, passed: false, detail: error.localizedDescription)
    }
    return Result(name: name, passed: true, detail: "Sales and Rate resolve; OFFSET stays unresolved")
  }

  private static func nameManagerEditsSheet() -> Result {
    let name = "name manager edits"
    var sheet = Sheet(name: "Sheet1")
    sheet.setCell(Cell(raw: "10"), at: CellAddress(row: 0, col: 0))
    sheet.setCell(Cell(raw: "20"), at: CellAddress(row: 1, col: 0))
    sheet.setCell(Cell(raw: "=SUM(Sales)"), at: CellAddress(row: 2, col: 0))
    let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
    if let error = viewModel.upsertDefinedName(originalName: nil, name: "Sales", refersTo: "Sheet1!$A$1:$A$2") {
      return Result(name: name, passed: false, detail: error)
    }
    if viewModel.displayValue(at: CellAddress(row: 2, col: 0)) != .number(30) {
      return Result(name: name, passed: false, detail: "add did not sum Sales")
    }
    if let error = viewModel.upsertDefinedName(originalName: "Sales", name: "Sales", refersTo: "Sheet1!$A$1") {
      return Result(name: name, passed: false, detail: error)
    }
    if viewModel.displayValue(at: CellAddress(row: 2, col: 0)) != .number(10) {
      return Result(name: name, passed: false, detail: "reference change did not update SUM")
    }
    if let error = viewModel.upsertDefinedName(originalName: "Sales", name: "Revenue", refersTo: "Sheet1!$A$1") {
      return Result(name: name, passed: false, detail: error)
    }
    if viewModel.activeSheet.cell(at: CellAddress(row: 2, col: 0)).raw != "=SUM(Revenue)" {
      return Result(
        name: name,
        passed: false,
        detail: "rename left \(viewModel.activeSheet.cell(at: CellAddress(row: 2, col: 0)).raw)"
      )
    }
    if let error = viewModel.upsertDefinedName(
      originalName: nil,
      name: "Grow",
      refersTo: "OFFSET(Sheet1!$A$1,0,0,2,1)"
    ) {
      return Result(name: name, passed: false, detail: error)
    }
    guard let grow = viewModel.workbook.namedRange(named: "Grow"), grow.resolvesToRange == false else {
      return Result(name: name, passed: false, detail: "OFFSET was stored as a range")
    }
    viewModel.setCellValue("=Grow", at: CellAddress(row: 3, col: 0))
    if viewModel.displayValue(at: CellAddress(row: 3, col: 0)) != .error(.name) {
      return Result(name: name, passed: false, detail: "OFFSET name resolved")
    }
    viewModel.deleteDefinedName(named: "Revenue")
    if viewModel.workbook.namedRange(named: "Revenue") != nil
      || viewModel.displayValue(at: CellAddress(row: 2, col: 0)) != .error(.name)
    {
      return Result(name: name, passed: false, detail: "delete left Revenue in use")
    }
    return Result(name: name, passed: true, detail: "add, retarget, rename, unresolved formula, delete")
  }

  private static func cellFormatCodeEditsSheet() -> Result {
    let name = "cell format code edits"
    var sheet = Sheet(name: "Sheet1")
    sheet.setCell(Cell(raw: "1234.5"), at: .origin)
    let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
    viewModel.selection = .origin
    viewModel.setFormatCode("#,##0.00")
    let grouped = viewModel.displayString(at: .origin)
    if grouped != "1,234.50" || viewModel.selectedFormat.formatCode != "#,##0.00" {
      return Result(name: name, passed: false, detail: "thousands \(grouped)")
    }
    viewModel.setFormatCode("$#,##0.00")
    let currency = viewModel.displayString(at: .origin)
    if currency != "$1,234.50" || viewModel.selectedFormat.numberFormat != .currency {
      return Result(name: name, passed: false, detail: "currency \(currency)")
    }
    guard let noon = octoberEighth2026() else {
      return Result(name: name, passed: false, detail: "date components")
    }
    let serial = ExcelDate.serial(from: noon)
    viewModel.setCellValue(String(serial), at: .origin)
    viewModel.setFormatCode("d-mmm-yy")
    let dated = viewModel.displayString(at: .origin)
    if dated != "8-Oct-26" || viewModel.selectedFormat.numberFormat != .date {
      return Result(name: name, passed: false, detail: "date \(dated)")
    }
    viewModel.setCellValue("0.75", at: .origin)
    viewModel.setFormatCode("h:mm AM/PM")
    let timed = viewModel.displayString(at: .origin)
    if timed != "6:00 PM" || viewModel.selectedFormat.numberFormat != .time {
      return Result(name: name, passed: false, detail: "time \(timed)")
    }
    viewModel.setCellValue("1234.5", at: .origin)
    viewModel.setFormatCode(nil)
    let cleared = viewModel.displayString(at: .origin)
    if cleared != "1234.5" || viewModel.selectedFormat.formatCode != nil || viewModel.selectedFormat.numberFormat != .general {
      return Result(name: name, passed: false, detail: "clear \(cleared)")
    }

    let sections = "#,##0.00;(#,##0.00);\"zero\";\"id \"@"
    viewModel.setFormatCode(sections)
    if viewModel.displayString(at: .origin) != "1,234.50" || viewModel.selectedFormat.formatCode != sections {
      return Result(name: name, passed: false, detail: "apply \(viewModel.displayString(at: .origin))")
    }
    viewModel.setCellValue("-8", at: .origin)
    if viewModel.displayString(at: .origin) != "(8.00)" {
      return Result(name: name, passed: false, detail: "negative section \(viewModel.displayString(at: .origin))")
    }
    viewModel.setCellValue("0", at: .origin)
    if viewModel.displayString(at: .origin) != "zero" {
      return Result(name: name, passed: false, detail: "zero section \(viewModel.displayString(at: .origin))")
    }
    viewModel.setCellValue("Hello", at: .origin)
    if viewModel.displayString(at: .origin) != "id Hello" {
      return Result(name: name, passed: false, detail: "text section \(viewModel.displayString(at: .origin))")
    }

    viewModel.setCellValue("1234.5", at: .origin)
    viewModel.setFormatCode("#,##0.00")
    viewModel.setNumberFormat(.number)
    if viewModel.selectedFormat.formatCode != nil || viewModel.displayString(at: .origin) != "1234.50" {
      return Result(name: name, passed: false, detail: "number preset left \(viewModel.selectedFormat.formatCode ?? "nil") \(viewModel.displayString(at: .origin))")
    }
    viewModel.setFormatCode("€#,##0.00")
    viewModel.setNumberFormat(.currency)
    if viewModel.selectedFormat.formatCode != nil || viewModel.displayString(at: .origin) != "$1234.50" {
      return Result(name: name, passed: false, detail: "currency preset left \(viewModel.selectedFormat.formatCode ?? "nil") \(viewModel.displayString(at: .origin))")
    }
    viewModel.setFormatCode("0.00%")
    viewModel.setNumberFormat(.general)
    if viewModel.selectedFormat.formatCode != nil || viewModel.displayString(at: .origin) != "1234.5" {
      return Result(name: name, passed: false, detail: "general preset left \(viewModel.selectedFormat.formatCode ?? "nil") \(viewModel.displayString(at: .origin))")
    }
    viewModel.setCellValue("0.5", at: .origin)
    viewModel.setFormatCode("0%")
    viewModel.setNumberFormat(.percent)
    if viewModel.selectedFormat.formatCode != nil || viewModel.displayString(at: .origin) != "50.00%" {
      return Result(name: name, passed: false, detail: "percent preset left \(viewModel.selectedFormat.formatCode ?? "nil") \(viewModel.displayString(at: .origin))")
    }
    viewModel.setCellValue("1234", at: .origin)
    viewModel.setFormatCode("0.00E+00")
    viewModel.setNumberFormat(.scientific)
    if viewModel.selectedFormat.formatCode != nil || viewModel.displayString(at: .origin) != "1.23e+03" {
      return Result(name: name, passed: false, detail: "scientific preset left \(viewModel.selectedFormat.formatCode ?? "nil") \(viewModel.displayString(at: .origin))")
    }
    guard let presetNoon = octoberEighth2026() else {
      return Result(name: name, passed: false, detail: "date components")
    }
    viewModel.setCellValue(String(ExcelDate.serial(from: presetNoon)), at: .origin)
    viewModel.setFormatCode("d-mmm-yy")
    viewModel.setNumberFormat(.date)
    if viewModel.selectedFormat.formatCode != nil || viewModel.displayString(at: .origin) != "10/8/2026" {
      return Result(name: name, passed: false, detail: "date preset left \(viewModel.selectedFormat.formatCode ?? "nil") \(viewModel.displayString(at: .origin))")
    }
    viewModel.setCellValue("0.75", at: .origin)
    viewModel.setFormatCode("h:mm")
    viewModel.setNumberFormat(.time)
    if viewModel.selectedFormat.formatCode != nil || viewModel.displayString(at: .origin) != "6:00:00 PM" {
      return Result(name: name, passed: false, detail: "time preset left \(viewModel.selectedFormat.formatCode ?? "nil") \(viewModel.displayString(at: .origin))")
    }
    viewModel.setCellValue("1234.5", at: .origin)

    viewModel.setFormatCode(sections)
    do {
      let data = try XLSXCodec.exportWorkbook(viewModel.workbook)
      let imported = try XLSXCodec.importWorkbook(from: data)
      let cell = imported.sheets[0].cell(at: .origin)
      let shown = CellFormatRenderer.displayText(for: .number(1234.5), format: cell.format, fallbackRaw: cell.raw)
      if cell.format?.formatCode != sections || cell.raw != "1234.5" || shown != "1,234.50" {
        return Result(name: name, passed: false, detail: "reopen \(cell.format?.formatCode ?? "") \(shown)")
      }
    } catch {
      return Result(name: name, passed: false, detail: error.localizedDescription)
    }
    return Result(name: name, passed: true, detail: "custom code, text section, preset clears it")
  }

  private static func conditionalFormatRuleEdit() -> Result {
    let name = "conditional format rule edit"
    var sheet = Sheet(name: "Sheet1")
    let original = ConditionalFormatRule(
      range: CellRange(start: .origin, end: CellAddress(row: 9, col: 0)),
      predicate: .greaterThan(10),
      style: .redFill
    )
    sheet.conditionalFormats = [original]
    let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
    guard let edited = viewModel.activeSheet.conditionalFormats[0].edited(
      rangeText: "B2:B4",
      primary: "12",
      secondary: ""
    ) else {
      return Result(name: name, passed: false, detail: "edit helper rejected a valid rule")
    }
    viewModel.replaceConditionalFormatRule(edited)
    guard let stored = viewModel.activeSheet.conditionalFormats.first,
          stored.range.a1Label == "B2:B4",
          stored.predicate == .greaterThan(12)
    else {
      return Result(name: name, passed: false, detail: "rule was not updated on the sheet")
    }
    let untouched = ConditionalFormatRule(
      range: original.range,
      predicate: .colorScale([
        ColorScaleStop(type: .min, value: nil, color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1)),
        ColorScaleStop(type: .max, value: nil, color: CodableColor(red: 0, green: 1, blue: 0, alpha: 1)),
      ]),
      style: ConditionalFormatStyle()
    )
    guard let kept = untouched.edited(rangeText: "C1:C3", primary: "", secondary: ""),
          kept.range.a1Label == "C1:C3",
          kept.predicate == untouched.predicate
    else {
      return Result(name: name, passed: false, detail: "color scale range edit changed the rule")
    }
    return Result(name: name, passed: true, detail: "stored rule range and value")
  }

  private static func cellTextOverflowAndClip() -> Result {
    let name = "cell text overflow"
    if CellFormat().textDisplay != .overflow || CellFormatRenderer.showsEllipsis(CellFormat()) {
      return Result(name: name, passed: false, detail: "default should overflow without ellipsis")
    }
    var clipFormat = CellFormat()
    clipFormat.textDisplay = .clip
    var wrapFormat = CellFormat()
    wrapFormat.textDisplay = .wrap
    if !CellFormatRenderer.showsEllipsis(clipFormat)
      || CellFormatRenderer.showsEllipsis(wrapFormat)
      || CellFormatRenderer.lineBreakMode(for: CellFormat()) != .byClipping
      || CellFormatRenderer.lineBreakMode(for: wrapFormat) != .byWordWrapping
      || CellFormatRenderer.lineBreakMode(for: clipFormat) != .byWordWrapping
    {
      return Result(name: name, passed: false, detail: "clip/wrap/overflow drawing modes diverged")
    }

    let origin: (Int) -> CGFloat = { CGFloat($0) * 80 }
    let width: (Int) -> CGFloat = { _ in 80 }
    let spill = CellTextLayout.overflowClip(
      cellMinX: 0,
      cellMaxX: 80,
      textWidth: 200,
      alignment: .left,
      insetX: 4,
      sourceColumns: 0...0,
      paneColumns: 0...5,
      columnOrigin: origin,
      columnWidth: width,
      blocks: { $0 == 2 }
    )
    if spill.maxX != 160 || spill.minX != 0 || spill.maxX <= 80 {
      return Result(name: name, passed: false, detail: "left overflow clip \(spill)")
    }

    let open = CellTextLayout.overflowClip(
      cellMinX: 0,
      cellMaxX: 80,
      textWidth: 200,
      alignment: .general,
      insetX: 4,
      sourceColumns: 0...0,
      paneColumns: 0...5,
      columnOrigin: origin,
      columnWidth: width,
      blocks: { _ in false }
    )
    if open.maxX <= 80 || open.maxX != 204 {
      return Result(name: name, passed: false, detail: "open overflow clip \(open)")
    }

    let blocked = CellTextLayout.overflowClip(
      cellMinX: 0,
      cellMaxX: 80,
      textWidth: 200,
      alignment: .left,
      insetX: 4,
      sourceColumns: 0...0,
      paneColumns: 0...5,
      columnOrigin: origin,
      columnWidth: width,
      blocks: { $0 == 1 }
    )
    if blocked.maxX != 80 {
      return Result(name: name, passed: false, detail: "adjacent content should stop at the border, got \(blocked)")
    }

    let right = CellTextLayout.overflowClip(
      cellMinX: 160,
      cellMaxX: 240,
      textWidth: 200,
      alignment: .right,
      insetX: 4,
      sourceColumns: 2...2,
      paneColumns: 0...5,
      columnOrigin: origin,
      columnWidth: width,
      blocks: { $0 == 0 }
    )
    if right.minX != 80 || right.maxX != 240 {
      return Result(name: name, passed: false, detail: "right overflow clip \(right)")
    }

    let center = CellTextLayout.overflowClip(
      cellMinX: 80,
      cellMaxX: 160,
      textWidth: 200,
      alignment: .center,
      insetX: 4,
      sourceColumns: 1...1,
      paneColumns: 0...5,
      columnOrigin: origin,
      columnWidth: width,
      blocks: { $0 == 0 }
    )
    if center.minX != 80 || center.maxX <= 160 {
      return Result(name: name, passed: false, detail: "center overflow clip \(center)")
    }

    var sheet = Sheet(name: "Spill")
    var fill = Cell(raw: "")
    var fillFormat = CellFormat()
    fillFormat.fillColor = CodableColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)
    fill.format = fillFormat
    sheet.setCell(fill, at: CellAddress(row: 0, col: 1))
    sheet.setCell(Cell(raw: "busy"), at: CellAddress(row: 0, col: 2))
    let display: (CellAddress) -> String = { address in
      address.col == 2 ? "busy" : ""
    }
    if CellTextLayout.blocksOverflow(sheet: sheet, row: 0, column: 1, displayText: display) {
      return Result(name: name, passed: false, detail: "fill without text blocked overflow")
    }
    if !CellTextLayout.blocksOverflow(sheet: sheet, row: 0, column: 2, displayText: display) {
      return Result(name: name, passed: false, detail: "text neighbor did not block overflow")
    }

    let long = String(repeating: "alpha ", count: 30)
    var clipCell = Cell(raw: long)
    clipCell.format = clipFormat
    var overflowCell = Cell(raw: long)
    var bold = CellFormat()
    bold.bold = true
    overflowCell.format = bold
    var plain = Sheet(name: "Modes")
    plain.setCell(clipCell, at: CellAddress(row: 0, col: 0))
    plain.setCell(overflowCell, at: CellAddress(row: 1, col: 0))
    let idle: (CellAddress) -> String = { $0.row == 0 || $0.row == 1 ? long : "" }
    let columnWidth: (Int) -> CGFloat = { _ in 60 }
    let wrappedOnly = CellTextLayout.wrappedRowHeights(
      sheet: plain,
      defaultRowHeight: Workbook.defaultRowHeight,
      defaultColumnWidth: Workbook.defaultColumnWidth,
      columnWidth: columnWidth,
      displayText: idle
    )
    if wrappedOnly[0] != nil || wrappedOnly[1] != nil {
      return Result(name: name, passed: false, detail: "clip/overflow changed row height \(wrappedOnly)")
    }

    var wrapShort = CellFormat()
    wrapShort.textDisplay = .wrap
    var wrapLong = CellFormat()
    wrapLong.textDisplay = .wrap
    let shortText = "Hello"
    let shortHeight = CellTextLayout.preferredWrappedRowHeight(
      text: shortText,
      format: wrapShort,
      columnWidth: 60
    )
    let longHeight = CellTextLayout.preferredWrappedRowHeight(
      text: long,
      format: wrapLong,
      columnWidth: 60
    )
    if longHeight <= shortHeight || longHeight <= Workbook.defaultRowHeight {
      return Result(name: name, passed: false, detail: "wrap height short=\(shortHeight) long=\(longHeight)")
    }
    var wrapSheet = Sheet(name: "Wrap")
    var shortCell = Cell(raw: shortText)
    shortCell.format = wrapShort
    var longCell = Cell(raw: long)
    longCell.format = wrapLong
    wrapSheet.setCell(shortCell, at: CellAddress(row: 0, col: 0))
    wrapSheet.setCell(longCell, at: CellAddress(row: 0, col: 1))
    wrapSheet.columnWidths[0] = 60
    wrapSheet.columnWidths[1] = 60
    let heights = CellTextLayout.wrappedRowHeights(
      sheet: wrapSheet,
      defaultRowHeight: Workbook.defaultRowHeight,
      defaultColumnWidth: Workbook.defaultColumnWidth,
      columnWidth: { wrapSheet.columnWidth(for: $0, default: Workbook.defaultColumnWidth) },
      displayText: { address in wrapSheet.cell(at: address).raw }
    )
    let rowHeight = CellTextLayout.displayRowHeight(
      row: 0,
      sheet: wrapSheet,
      defaultRowHeight: Workbook.defaultRowHeight,
      wrapped: heights
    )
    if abs(rowHeight - longHeight) > 0.6 {
      return Result(name: name, passed: false, detail: "row used \(rowHeight), tallest is \(longHeight)")
    }

    var saved = wrapSheet
    var clipSaved = Cell(raw: "clip me")
    var clipSavedFormat = CellFormat()
    clipSavedFormat.italic = true
    clipSavedFormat.textDisplay = .clip
    clipSaved.format = clipSavedFormat
    saved.setCell(clipSaved, at: CellAddress(row: 2, col: 0))
    var overflowSaved = Cell(raw: "spill me")
    var overflowSavedFormat = CellFormat()
    overflowSavedFormat.bold = true
    overflowSaved.format = overflowSavedFormat
    saved.setCell(overflowSaved, at: CellAddress(row: 3, col: 0))
    do {
      let data = try XLSXCodec.exportWorkbook(Workbook(sheets: [saved]))
      let styles = XLSXCodec.zipEntryString(archiveData: data, entryPath: "xl/styles.xml") ?? ""
      if !styles.contains("wrapText=\"1\"") || !styles.contains("sparkTextDisplay=\"clip\"") {
        return Result(name: name, passed: false, detail: "styles missing wrap or clip marker")
      }
      let imported = try XLSXCodec.importWorkbook(from: data)
      let sheet = imported.activeSheet
      let wrapCell = sheet.cell(at: CellAddress(row: 0, col: 0))
      let tallCell = sheet.cell(at: CellAddress(row: 0, col: 1))
      let clipRoundTrip = sheet.cell(at: CellAddress(row: 2, col: 0))
      let overflowRoundTrip = sheet.cell(at: CellAddress(row: 3, col: 0))
      guard wrapCell.format?.textDisplay == .wrap,
            tallCell.format?.textDisplay == .wrap,
            clipRoundTrip.format?.textDisplay == .clip,
            clipRoundTrip.format?.italic == true,
            overflowRoundTrip.format?.textDisplay == .overflow,
            overflowRoundTrip.format?.bold == true
      else {
        return Result(
          name: name,
          passed: false,
          detail: "round-trip wrap=\(wrapCell.format?.textDisplay == .wrap) clip=\(clipRoundTrip.format?.textDisplay == .clip) overflow=\(overflowRoundTrip.format?.textDisplay == .overflow) italic=\(clipRoundTrip.format?.italic == true) bold=\(overflowRoundTrip.format?.bold == true)"
        )
      }
    } catch {
      return Result(name: name, passed: false, detail: error.localizedDescription)
    }
    return Result(name: name, passed: true, detail: "overflow stops at content; wrap is tallest; clip keeps ellipsis")
  }

  @MainActor
  private static func cellTextWrapLayout() -> Result {
    let name = "cell text wrap layout"
    let long = String(repeating: "alpha ", count: 30)
    var sheet = Sheet(name: "Layout")
    sheet.frozenRows = 1
    sheet.columnWidths[0] = 60
    sheet.columnWidths[1] = 60
    var wrap = CellFormat()
    wrap.textDisplay = .wrap
    var tall = Cell(raw: long)
    tall.format = wrap
    var shorter = Cell(raw: "Hello")
    shorter.format = wrap
    sheet.setCell(tall, at: CellAddress(row: 0, col: 0))
    sheet.setCell(shorter, at: CellAddress(row: 0, col: 1))
    let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))
    let grid = SpreadsheetGridNSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900))
    grid.viewModel = viewModel

    let heights = CellTextLayout.wrappedRowHeights(
      sheet: viewModel.activeSheet,
      defaultRowHeight: Workbook.defaultRowHeight,
      defaultColumnWidth: Workbook.defaultColumnWidth,
      columnWidth: { viewModel.activeSheet.columnWidth(for: $0, default: Workbook.defaultColumnWidth) },
      displayText: { viewModel.displayString(at: $0) }
    )
    let expected = CellTextLayout.displayRowHeight(
      row: 0,
      sheet: viewModel.activeSheet,
      defaultRowHeight: Workbook.defaultRowHeight,
      wrapped: heights
    )
    let rowHeight = grid.rowHeight(at: 0)
    if expected <= Workbook.defaultRowHeight + 4 || abs(rowHeight - expected) > 0.6 {
      return Result(name: name, passed: false, detail: "grid row \(rowHeight) layout \(expected)")
    }

    let header = SpreadsheetGridNSView.baseHeaderSize
    let inside = header + Workbook.defaultRowHeight + 4
    if grid.rowAtContent(y: inside) != 0 {
      return Result(name: name, passed: false, detail: "hit test in the grown row returned \(grid.rowAtContent(y: inside))")
    }
    let below = header + rowHeight + 1
    if grid.rowAtContent(y: below) != 1 {
      return Result(name: name, passed: false, detail: "hit test below the grown row returned \(grid.rowAtContent(y: below))")
    }

    let selected = grid.rectForCell(row: 0, col: 0)
    let next = grid.rectForCell(row: 1, col: 0)
    if abs(selected.height - rowHeight) > 0.6 || abs(next.minY - selected.maxY) > 0.6 {
      return Result(name: name, passed: false, detail: "selection rects \(selected) \(next)")
    }
    if abs(grid.frozenRowBoundaryY() - (header + rowHeight)) > 0.6 {
      return Result(name: name, passed: false, detail: "frozen boundary \(grid.frozenRowBoundaryY()) expected \(header + rowHeight)")
    }

    grid.showEditor()
    if abs(grid.editorFrame.height - (rowHeight - 2)) > 1 {
      return Result(name: name, passed: false, detail: "editor height \(grid.editorFrame.height) row \(rowHeight)")
    }
    return Result(name: name, passed: true, detail: "hit testing, selection, freeze, and editor share \(Int(rowHeight))pt")
  }

  @MainActor
  private static func textDisplayToolbarLabel() -> Result {
    let name = "text display toolbar label"
    let overflowTitle = CellFormat.TextDisplay.overflow.toolbarTitle
    let wrapTitle = CellFormat.TextDisplay.wrap.toolbarTitle
    let clipTitle = CellFormat.TextDisplay.clip.toolbarTitle
    let mixedTitle = CellFormat.TextDisplay.mixedToolbarTitle
    let modeTitles = [overflowTitle, wrapTitle, clipTitle]
    if modeTitles != ["Overflow", "Wrap", "Clip"] || modeTitles.contains(mixedTitle) {
      return Result(name: name, passed: false, detail: "menu titles \(modeTitles) mixed \(mixedTitle)")
    }

    var sheet = Sheet(name: "Label")
    var wrap = CellFormat()
    wrap.textDisplay = .wrap
    var clip = CellFormat()
    clip.textDisplay = .clip
    sheet.setCell(Cell(raw: "wrap", format: wrap), at: CellAddress(row: 0, col: 0))
    sheet.setCell(Cell(raw: "clip", format: clip), at: CellAddress(row: 0, col: 1))
    sheet.setCell(Cell(raw: "plain"), at: CellAddress(row: 0, col: 2))
    var mergedWrap = CellFormat()
    mergedWrap.textDisplay = .wrap
    sheet.setCell(Cell(raw: "merged", format: mergedWrap), at: CellAddress(row: 1, col: 0))
    sheet.mergedRanges = [
      CellRange(start: CellAddress(row: 1, col: 0), end: CellAddress(row: 1, col: 1))
    ]
    let viewModel = SpreadsheetViewModel(workbook: Workbook(sheets: [sheet]))

    func label(_ expected: String, detail: String) -> Result? {
      if viewModel.textDisplayToolbarTitle != expected {
        return Result(
          name: name,
          passed: false,
          detail: "\(detail) label \(viewModel.textDisplayToolbarTitle)"
        )
      }
      return nil
    }

    if let failed = label(wrapTitle, detail: "wrap cell") { return failed }
    if viewModel.uniformTextDisplay != .wrap {
      return Result(name: name, passed: false, detail: "wrap cell claimed \(String(describing: viewModel.uniformTextDisplay))")
    }

    viewModel.select(CellAddress(row: 0, col: 1))
    if let failed = label(clipTitle, detail: "clip cell") { return failed }

    viewModel.select(CellAddress(row: 0, col: 2))
    if let failed = label(overflowTitle, detail: "overflow cell") { return failed }

    viewModel.selectRange(from: CellAddress(row: 0, col: 2), to: CellAddress(row: 0, col: 3))
    if let failed = label(overflowTitle, detail: "empty neighbors") { return failed }

    viewModel.selectRange(from: CellAddress(row: 0, col: 0), to: CellAddress(row: 0, col: 1))
    if viewModel.uniformTextDisplay != nil || modeTitles.contains(viewModel.textDisplayToolbarTitle) {
      return Result(
        name: name,
        passed: false,
        detail: "mixed range claimed \(viewModel.textDisplayToolbarTitle)"
      )
    }
    if let failed = label(mixedTitle, detail: "mixed range") { return failed }

    viewModel.select(CellAddress(row: 0, col: 0))
    viewModel.commandClickCell(CellAddress(row: 0, col: 2))
    if viewModel.uniformTextDisplay != nil || viewModel.textDisplayToolbarTitle != mixedTitle {
      return Result(
        name: name,
        passed: false,
        detail: "split selection claimed \(viewModel.textDisplayToolbarTitle)"
      )
    }

    viewModel.setTextDisplay(.clip)
    if let failed = label(clipTitle, detail: "after applying clip") { return failed }
    if viewModel.activeSheet.cell(at: CellAddress(row: 0, col: 0)).format?.textDisplay != .clip
      || viewModel.activeSheet.cell(at: CellAddress(row: 0, col: 2)).format?.textDisplay != .clip
    {
      return Result(name: name, passed: false, detail: "clip did not apply to both selected cells")
    }

    viewModel.selectRange(from: CellAddress(row: 1, col: 0), to: CellAddress(row: 1, col: 1))
    if let failed = label(wrapTitle, detail: "merged wrap") { return failed }

    return Result(name: name, passed: true, detail: "label follows the selection; mixed does not name a mode")
  }

  /// Quit calls attemptClose from both the app and the window. That must show one prompt.
  @MainActor
  private static func unsavedPromptOnce() -> Result {
    let name = "unsaved prompt once"

    let cancelled = dirtyStore()
    cancelled.unsavedPromptTestAnswer = .cancel
    let delegate = SparkGridAppDelegate()
    delegate.documentStore = cancelled
    let reply = delegate.applicationShouldTerminate(NSApp)
    let windowClosed = delegate.windowShouldClose(NSWindow(
      contentRect: .zero,
      styleMask: [.titled],
      backing: .buffered,
      defer: true
    ))
    if reply != .terminateCancel || windowClosed || cancelled.unsavedPromptCount != 1 {
      return Result(
        name: name,
        passed: false,
        detail: "cancel reply \(reply.rawValue) window \(windowClosed) prompts \(cancelled.unsavedPromptCount)"
      )
    }
    drainMainQueue()
    if cancelled.attemptClose() != false || cancelled.unsavedPromptCount != 2 {
      return Result(name: name, passed: false, detail: "later quit prompts \(cancelled.unsavedPromptCount)")
    }

    let discarded = dirtyStore()
    discarded.unsavedPromptTestAnswer = .discard
    if discarded.attemptClose() != true || discarded.attemptClose() != true || discarded.unsavedPromptCount != 1 {
      return Result(name: name, passed: false, detail: "don't save prompts \(discarded.unsavedPromptCount)")
    }

    let savedURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("spark-grid-close-\(UUID().uuidString).xlsx")
    defer { try? FileManager.default.removeItem(at: savedURL) }
    let saved = dirtyStore()
    saved.fileURL = savedURL
    saved.unsavedPromptTestAnswer = .save
    if saved.attemptClose() != true {
      return Result(name: name, passed: false, detail: "save did not close")
    }
    var sheet = saved.document.workbook.activeSheet
    sheet.setCell(Cell(raw: "2"), at: CellAddress(row: 1, col: 0))
    saved.document.workbook.activeSheet = sheet
    saved.documentDidChange()
    if saved.attemptClose() != true || saved.unsavedPromptCount != 1 {
      return Result(name: name, passed: false, detail: "save prompts \(saved.unsavedPromptCount)")
    }
    do {
      let written = try XLSXCodec.importWorkbook(from: savedURL)
      if written.activeSheet.cell(at: .origin).raw != "1" {
        return Result(name: name, passed: false, detail: "saved raw \(written.activeSheet.cell(at: .origin).raw)")
      }
    } catch {
      return Result(name: name, passed: false, detail: error.localizedDescription)
    }

    let replaced = dirtyStore()
    replaced.unsavedPromptTestAnswer = .cancel
    replaced.newDocument()
    if replaced.unsavedPromptCount != 1 || replaced.document.workbook.activeSheet.cell(at: .origin).raw != "1" {
      return Result(name: name, passed: false, detail: "new prompts \(replaced.unsavedPromptCount)")
    }

    let opened = dirtyStore()
    opened.unsavedPromptTestAnswer = .cancel
    let openURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("spark-grid-open-\(UUID().uuidString).xlsx")
    defer { try? FileManager.default.removeItem(at: openURL) }
    do {
      try XLSXCodec.exportWorkbook(Workbook()).write(to: openURL)
      try opened.load(from: openURL)
    } catch {
      return Result(name: name, passed: false, detail: error.localizedDescription)
    }
    if opened.unsavedPromptCount != 1 || opened.fileURL != nil || opened.document.workbook.activeSheet.cell(at: .origin).raw != "1" {
      return Result(name: name, passed: false, detail: "open prompts \(opened.unsavedPromptCount)")
    }

    return Result(name: name, passed: true, detail: "quit, New, and Open each ask once")
  }

  @MainActor
  private static func dirtyStore() -> SpreadsheetDocumentStore {
    let store = SpreadsheetDocumentStore()
    var sheet = store.document.workbook.activeSheet
    sheet.setCell(Cell(raw: "1"), at: .origin)
    store.document.workbook.activeSheet = sheet
    store.documentDidChange()
    return store
  }

  private static func drainMainQueue() {
    var fired = false
    DispatchQueue.main.async { fired = true }
    let deadline = Date().addingTimeInterval(1)
    while !fired, Date() < deadline {
      RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
  }

  /// Copy carries conditional formatting onto another sheet, and onto a new range on the same sheet.
  @MainActor
  private static func conditionalFormatPaste() -> Result {
    let name = "conditional format paste"
    func fail(_ detail: String) -> Result {
      Result(name: name, passed: false, detail: detail)
    }

    var source = Sheet(name: "Source")
    source.setCell(Cell(raw: "5"), at: CellAddress(row: 0, col: 0))
    source.setCell(Cell(raw: "15"), at: CellAddress(row: 1, col: 0))
    source.setCell(Cell(raw: "8"), at: CellAddress(row: 2, col: 0))
    let block = CellRange(start: .origin, end: CellAddress(row: 2, col: 0))
    source.conditionalFormats = [
      ConditionalFormatRule(range: block, predicate: .greaterThan(10), style: .redFill),
      ConditionalFormatRule(
        range: block,
        stopIfTrue: false,
        predicate: .formula("=A1>B1"),
        style: .greenFill
      ),
      ConditionalFormatRule(range: block, predicate: .formula("=$A$1>10"), style: .yellowFill),
      ConditionalFormatRule(
        range: CellRange(start: CellAddress(row: 0, col: 2), end: CellAddress(row: 0, col: 2)),
        predicate: .greaterThan(99),
        style: .blueFill
      ),
    ]
    let testSheet = Sheet(name: "Test")
    let vm = SpreadsheetViewModel(workbook: Workbook(sheets: [source, testSheet]))
    let originals = vm.activeSheet.conditionalFormats
    guard originals.count == 4 else {
      return fail("setup rules \(originals.count)")
    }

    vm.selectRange(from: .origin, to: CellAddress(row: 2, col: 0))
    guard vm.copySelectionToPasteboard() else { return fail("copy failed") }

    vm.selectSheet(at: 1)
    vm.selectRange(from: CellAddress(row: 4, col: 2), to: CellAddress(row: 4, col: 2))
    vm.pasteFromPasteboard()
    guard vm.activeSheet.name == "Test" else { return fail("paste landed on \(vm.activeSheet.name)") }
    guard vm.activeSheet.cell(at: CellAddress(row: 4, col: 2)).raw == "5",
          vm.activeSheet.cell(at: CellAddress(row: 5, col: 2)).raw == "15",
          vm.activeSheet.cell(at: CellAddress(row: 6, col: 2)).raw == "8"
    else { return fail("cross-sheet values missing") }
    guard vm.activeSheet.conditionalFormats.count == 3 else {
      return fail("cross-sheet rules \(describe(vm.activeSheet.conditionalFormats))")
    }
    guard let highlight = rule(vm.activeSheet.conditionalFormats, range: "C5:C7", predicate: .greaterThan(10)),
          highlight.style == .redFill
    else { return fail("highlight not retargeted \(describe(vm.activeSheet.conditionalFormats))") }
    guard let shifted = rule(vm.activeSheet.conditionalFormats, range: "C5:C7", predicate: .formula("=C5>D5")),
          shifted.style == .greenFill,
          shifted.stopIfTrue == false
    else { return fail("relative formula \(describe(vm.activeSheet.conditionalFormats))") }
    guard rule(vm.activeSheet.conditionalFormats, range: "C5:C7", predicate: .formula("=$A$1>10")) != nil else {
      return fail("absolute formula \(describe(vm.activeSheet.conditionalFormats))")
    }
    guard vm.activeSheet.conditionalFormats.allSatisfy({ $0.predicate != .greaterThan(99) }) else {
      return fail("copied a rule outside the selection")
    }
    let painted = vm.resolvedPaint(at: CellAddress(row: 5, col: 2))
    guard painted.format?.fillColor == ConditionalFormatStyle.redFill.fillColor else {
      return fail("pasted 15 did not pick up the highlight")
    }

    vm.selectSheet(at: 0)
    guard sourceRulesIntact(vm.activeSheet.conditionalFormats, originals: originals) else {
      return fail("source rules changed after cross-sheet paste \(describe(vm.activeSheet.conditionalFormats))")
    }

    vm.selectRange(from: CellAddress(row: 0, col: 6), to: CellAddress(row: 0, col: 6))
    vm.pasteFromPasteboard()
    guard vm.activeSheet.cell(at: CellAddress(row: 0, col: 6)).raw == "5",
          vm.activeSheet.cell(at: CellAddress(row: 1, col: 6)).raw == "15",
          vm.activeSheet.cell(at: CellAddress(row: 2, col: 6)).raw == "8",
          vm.activeSheet.cell(at: .origin).raw == "5"
    else { return fail("same-sheet values") }
    guard rule(vm.activeSheet.conditionalFormats, range: "G1:G3", predicate: .formula("=G1>H1")) != nil,
          rule(vm.activeSheet.conditionalFormats, range: "G1:G3", predicate: .formula("=$A$1>10")) != nil,
          rule(vm.activeSheet.conditionalFormats, range: "G1:G3", predicate: .greaterThan(10)) != nil
    else { return fail("same-sheet retarget \(describe(vm.activeSheet.conditionalFormats))") }
    guard sourceRulesIntact(vm.activeSheet.conditionalFormats, originals: originals) else {
      return fail("same-sheet paste moved the original rules")
    }
    guard vm.resolvedPaint(at: CellAddress(row: 1, col: 0)).format?.fillColor
      == ConditionalFormatStyle.redFill.fillColor
    else { return fail("original highlight stopped matching") }

    vm.selectRange(from: CellAddress(row: 1, col: 0), to: CellAddress(row: 1, col: 0))
    guard vm.copySelectionToPasteboard() else { return fail("partial copy failed") }
    vm.selectRange(from: CellAddress(row: 0, col: 4), to: CellAddress(row: 0, col: 4))
    vm.pasteFromPasteboard()
    guard vm.activeSheet.cell(at: CellAddress(row: 0, col: 4)).raw == "15" else {
      return fail("partial paste value")
    }
    guard rule(vm.activeSheet.conditionalFormats, range: "E1", predicate: .formula("=E1>F1")) != nil,
          rule(vm.activeSheet.conditionalFormats, range: "E1", predicate: .formula("=$A$1>10")) != nil,
          rule(vm.activeSheet.conditionalFormats, range: "E1", predicate: .greaterThan(10)) != nil
    else { return fail("partial retarget \(describe(vm.activeSheet.conditionalFormats))") }
    guard sourceRulesIntact(vm.activeSheet.conditionalFormats, originals: originals) else {
      return fail("partial paste changed the original block")
    }

    vm.selectRange(from: .origin, to: CellAddress(row: 2, col: 0))
    vm.copyFormulas()
    vm.selectSheet(at: 1)
    vm.selectRange(from: CellAddress(row: 10, col: 0), to: CellAddress(row: 10, col: 0))
    vm.pasteFormulasFromPasteboard()
    guard vm.activeSheet.cell(at: CellAddress(row: 10, col: 0)).raw == "5",
          vm.activeSheet.cell(at: CellAddress(row: 12, col: 0)).raw == "8"
    else { return fail("paste formulas values") }
    guard rule(vm.activeSheet.conditionalFormats, range: "A11:A13", predicate: .formula("=A11>B11")) != nil,
          rule(vm.activeSheet.conditionalFormats, range: "A11:A13", predicate: .formula("=$A$1>10")) != nil,
          rule(vm.activeSheet.conditionalFormats, range: "C5:C7", predicate: .formula("=C5>D5")) != nil
    else { return fail("paste formulas rules \(describe(vm.activeSheet.conditionalFormats))") }

    vm.selectSheet(at: 0)
    vm.setCellValue("=B1", at: CellAddress(row: 0, col: 3))
    vm.selectRange(from: CellAddress(row: 0, col: 3), to: CellAddress(row: 0, col: 3))
    guard vm.copySelectionToPasteboard() else { return fail("formula cell copy failed") }
    vm.selectSheet(at: 1)
    let rulesBeforePlainPaste = vm.activeSheet.conditionalFormats.count
    vm.selectRange(from: CellAddress(row: 4, col: 5), to: CellAddress(row: 4, col: 5))
    vm.pasteFromPasteboard()
    guard vm.activeSheet.cell(at: CellAddress(row: 4, col: 5)).raw == "=B1" else {
      return fail("cell formula changed to \(vm.activeSheet.cell(at: CellAddress(row: 4, col: 5)).raw)")
    }
    guard vm.activeSheet.conditionalFormats.count == rulesBeforePlainPaste else {
      return fail("copy without rules still pasted conditional formatting")
    }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("99", forType: .string)
    vm.selectRange(from: CellAddress(row: 0, col: 5), to: CellAddress(row: 0, col: 5))
    vm.pasteFromPasteboard()
    guard vm.activeSheet.cell(at: CellAddress(row: 0, col: 5)).raw == "99",
          vm.activeSheet.conditionalFormats.count == rulesBeforePlainPaste
    else { return fail("external paste changed conditional formatting") }

    return Result(name: name, passed: true, detail: "cross-sheet, same-sheet, and formula shift")
  }

  private static func rule(
    _ rules: [ConditionalFormatRule],
    range: String,
    predicate: ConditionalFormatPredicate
  ) -> ConditionalFormatRule? {
    rules.first { $0.range.a1Label == range && $0.predicate == predicate }
  }

  private static func sourceRulesIntact(
    _ rules: [ConditionalFormatRule],
    originals: [ConditionalFormatRule]
  ) -> Bool {
    originals.allSatisfy { original in
      guard let match = rules.first(where: { $0.id == original.id }) else { return false }
      return match.range.a1Label == original.range.a1Label
        && match.predicate == original.predicate
        && match.style == original.style
        && match.stopIfTrue == original.stopIfTrue
    }
  }

  private static func describe(_ rules: [ConditionalFormatRule]) -> String {
    rules.map { "\($0.range.a1Label) \($0.predicate.title)" }.joined(separator: "; ")
  }

  private static func octoberEighth2026() -> Date? {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = 2026
    components.month = 10
    components.day = 8
    components.hour = 12
    return components.date
  }
}
#endif
