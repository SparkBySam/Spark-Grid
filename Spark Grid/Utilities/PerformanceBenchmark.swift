import AppKit
import Darwin
import Foundation

/// Release timings for the seven paths the app actually runs.
///
/// Launch with `SPARK_GRID_BENCHMARK=1`. Sheet names are not built in: the scroll
/// sheet is `SPARK_GRID_BENCHMARK_SCROLL_SHEET` when that sheet exists, otherwise
/// the sheet with the most populated rows.
enum PerformanceBenchmark {
  private static let firstScreenRows = 60
  private static let firstScreenColumns = 25

  static func run() -> Never {
    let env = ProcessInfo.processInfo.environment
    let reference = env["SPARK_GRID_BENCHMARK_REFERENCE"] ?? ""
    let root = env["SPARK_GRID_BENCHMARK_ROOT"] ?? FileManager.default.currentDirectoryPath
    let answersDirectory = env["SPARK_GRID_BENCHMARK_ANSWERS"]
      ?? (root as NSString).appendingPathComponent("scripts/answers")
    let logPath = env["SPARK_GRID_BENCHMARK_LOG"] ?? "/tmp/spark-grid-phase0-baseline.txt"
    var lines: [String] = []
    func emit(_ line: String) {
      print(line)
      fflush(stdout)
      lines.append(line)
      let text = lines.joined(separator: "\n") + "\n"
      try? Data(text.utf8).write(to: URL(fileURLWithPath: logPath), options: .atomic)
    }

    do {
      guard !reference.isEmpty, FileManager.default.fileExists(atPath: reference) else {
        emit("benchmark failed: SPARK_GRID_BENCHMARK_REFERENCE is missing")
        exit(1)
      }
      let otherPath = try resolveLedgerPath(env: env, root: root, emit: emit)
      emit("benchmark reference \(reference)")
      emit("benchmark ledger \(otherPath)")
      _ = NSApplication.shared
      try measure(url: URL(fileURLWithPath: reference), label: "reference", env: env, answersDirectory: answersDirectory, emit: emit)
      try measure(url: URL(fileURLWithPath: otherPath), label: "ledger", env: env, answersDirectory: answersDirectory, emit: emit)
      emit("benchmark done")
      exit(0)
    } catch {
      emit("benchmark failed: \(error)")
      exit(1)
    }
  }

  private static func resolveLedgerPath(
    env: [String: String],
    root: String,
    emit: (String) -> Void
  ) throws -> String {
    if let given = env["SPARK_GRID_BENCHMARK_OTHER"], !given.isEmpty {
      return given
    }
    let script = (root as NSString).appendingPathComponent("scripts/generate_ledger_workbook.py")
    let output = "/tmp/spark-grid-phase0-ledger.xlsx"
    guard FileManager.default.fileExists(atPath: script) else {
      throw BenchmarkFailure("ledger generator missing at \(script)")
    }
    emit("generating ledger with \(script)")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [script, "-o", output]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let outputText = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    emit(outputText.trimmingCharacters(in: .whitespacesAndNewlines))
    guard process.terminationStatus == 0 else {
      throw BenchmarkFailure("ledger generator exited \(process.terminationStatus)")
    }
    return output
  }

  private static func measure(
    url: URL,
    label: String,
    env: [String: String],
    answersDirectory: String,
    emit: @escaping (String) -> Void
  ) throws {
    emit("---- \(label) ----")
    let beforeResident = residentBytes()
    let importStarted = CFAbsoluteTimeGetCurrent()
    let imported = try XLSXCodec.importWorkbook(from: url)
    let importSeconds = CFAbsoluteTimeGetCurrent() - importStarted
    let afterResident = residentBytes()
    emit(String(format: "importWorkbook %.3f s", importSeconds))
    emit(String(format: "resident-after-import %.2f MB delta %.2f MB", Double(afterResident) / 1_048_576, Double(afterResident &- beforeResident) / 1_048_576))
    if label == "ledger" {
      try validateLedger(imported)
      emit("ledger shape ok")
    }

    let fingerprintStarted = CFAbsoluteTimeGetCurrent()
    _ = WorkbookFingerprint.data(for: imported)
    let fingerprintSeconds = CFAbsoluteTimeGetCurrent() - fingerprintStarted
    emit(String(format: "WorkbookFingerprint %.3f s", fingerprintSeconds))

    let exportStarted = CFAbsoluteTimeGetCurrent()
    _ = try XLSXCodec.exportWorkbook(imported)
    let exportSeconds = CFAbsoluteTimeGetCurrent() - exportStarted
    emit(String(format: "exportWorkbook %.3f s", exportSeconds))

    let store = SpreadsheetDocumentStore()
    // Sheet ids are random, so a new store's saved fingerprint does not match its
    // empty document and the first load would ask to save. Write that empty
    // workbook first so `load` takes the clean-document path.
    let baselineURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("spark-grid-phase0-empty-\(label).xlsx")
    try store.save(to: baselineURL)
    let openStarted = CFAbsoluteTimeGetCurrent()
    try store.load(from: url)
    drainMain()
    let viewModel = SpreadsheetViewModel(workbook: store.document.workbook)
    let grid = BenchmarkGrid(viewModel: viewModel, frame: viewportFrame(for: viewModel.activeSheet))
    grid.grid.needsDisplay = true
    grid.grid.display()
    let openSeconds = CFAbsoluteTimeGetCurrent() - openStarted
    emit(String(format: "open %.3f s", openSeconds))

    let unsavedStarted = CFAbsoluteTimeGetCurrent()
    store.documentDidChange()
    let unsavedSeconds = CFAbsoluteTimeGetCurrent() - unsavedStarted
    emit(String(format: "unsaved-check %.3f s", unsavedSeconds))

    var firstScreens: [(String, TimeInterval)] = []
    for index in viewModel.workbook.sheets.indices {
      if viewModel.workbook.activeSheetIndex != index {
        viewModel.selectSheet(at: index)
      }
      let frame = viewportFrame(for: viewModel.activeSheet)
      grid.resize(to: frame)
      grid.grid.reloadContent(resetScrollPosition: true)
      let paintStarted = CFAbsoluteTimeGetCurrent()
      grid.grid.needsDisplay = true
      grid.grid.display()
      let paintSeconds = CFAbsoluteTimeGetCurrent() - paintStarted
      let name = viewModel.activeSheet.name
      firstScreens.append((name, paintSeconds))
      emit("first-screen\t\(name)\t\(formatSeconds(paintSeconds))")
    }

    let scrollIndex = scrollSheetIndex(in: viewModel.workbook, preferredName: env["SPARK_GRID_BENCHMARK_SCROLL_SHEET"])
    let scroll = timeWorstScroll(grid: grid, viewModel: viewModel, sheetIndex: scrollIndex)
    emit("scroll-worst\t\(scroll.sheet)\t\(formatSeconds(scroll.worst))\tticks \(scroll.ticks)")
    grid.close()

    // Same sheet ids as the open document. A second import compares unequal at the
    // first sheet id and hides the workbook-sized sync the window actually runs.
    let loaded = store.document.workbook
    let switchViewModel = SpreadsheetViewModel(workbook: loaded)
    store.activeViewModel = switchViewModel
    store.documentDidChange()
    let switchStarted = CFAbsoluteTimeGetCurrent()
    switchViewModel.selectSheet(at: min(1, switchViewModel.workbook.sheets.count - 1))
    let selectSeconds = CFAbsoluteTimeGetCurrent() - switchStarted
    let selectSyncStarted = CFAbsoluteTimeGetCurrent()
    syncOnChange(store: store, viewModel: switchViewModel)
    let selectSyncSeconds = CFAbsoluteTimeGetCurrent() - selectSyncStarted
    emit(String(format: "selectSheet %.3f s", selectSeconds))
    emit(String(format: "selectSheet-onchange %.3f s", selectSyncSeconds))
    emit(String(format: "tab-switch %.3f s", selectSeconds + selectSyncSeconds))
    emit("tab-switch-dirty\t\(store.isDirty)")

    let editViewModel = SpreadsheetViewModel(workbook: loaded)
    store.activeViewModel = editViewModel
    store.documentDidChange()
    let editGrid = BenchmarkGrid(viewModel: editViewModel, frame: viewportFrame(for: editViewModel.activeSheet))
    editGrid.grid.needsDisplay = true
    editGrid.grid.display()
    let editAddress = firstNumericLiteral(in: editViewModel.activeSheet) ?? .origin
    let oldRaw = editViewModel.activeSheet.cell(at: editAddress).raw
    let newRaw = oldRaw == "0" ? "1" : "0"
    editViewModel.select(editAddress)
    editViewModel.beginEditing()
    editViewModel.editText = newRaw
    let commitStarted = CFAbsoluteTimeGetCurrent()
    editViewModel.commitEdit()
    let commitSeconds = CFAbsoluteTimeGetCurrent() - commitStarted
    let editSyncStarted = CFAbsoluteTimeGetCurrent()
    syncOnChange(store: store, viewModel: editViewModel)
    let editSyncSeconds = CFAbsoluteTimeGetCurrent() - editSyncStarted
    editGrid.close()
    emit("commitEdit\t\(editViewModel.activeSheet.name)!\(editAddress.a1)\t\(formatSeconds(commitSeconds))")
    emit(String(format: "edit-onchange %.3f s", editSyncSeconds))
    emit(String(format: "edit %.3f s", commitSeconds + editSyncSeconds))
    emit("edit-dirty\t\(store.isDirty)")

    let slowest = firstScreens.max(by: { $0.1 < $1.1 })
    emit("first-screen-slowest\t\(slowest?.0 ?? "")\t\(formatSeconds(slowest?.1 ?? 0))")
    emit(summaryLine(
      label: label,
      open: openSeconds,
      unsaved: unsavedSeconds,
      firstScreen: slowest?.1 ?? 0,
      firstScreenName: slowest?.0 ?? "",
      edit: commitSeconds + editSyncSeconds,
      commit: commitSeconds,
      tab: selectSeconds + selectSyncSeconds,
      export: exportSeconds,
      scroll: scroll.worst,
      scrollSheet: scroll.sheet,
      importSeconds: importSeconds,
      fingerprint: fingerprintSeconds,
      residentMB: Double(afterResident) / 1_048_576
    ))

    try checkAnswers(workbook: imported, label: label, answersDirectory: answersDirectory, emit: emit)
  }

  private static func checkAnswers(
    workbook: Workbook,
    label: String,
    answersDirectory: String,
    emit: @escaping (String) -> Void
  ) throws {
    emit("answer-check \(label) scalar evaluate")
    let stripped = withoutImportedResults(workbook)
    let scalar = ScalarFormulaAnswers.evaluate(workbook: stripped) { count in
      emit("answer-check \(label) scalar \(count)")
    }
    var byKey: [AnswerKey: CellValue] = [:]
    byKey.reserveCapacity(scalar.count)
    for answer in scalar {
      byKey[AnswerKey(sheet: answer.sheetIndex, address: answer.address)] = answer.value
    }
    emit("answer-check \(label) path under test")
    let viewModel = SpreadsheetViewModel(workbook: stripped)
    var mismatches: [(String, CellValue, CellValue)] = []
    var checked = 0
    for sheetIndex in stripped.sheets.indices {
      viewModel.selectSheet(at: sheetIndex)
      let sheet = viewModel.activeSheet
      let addresses = sheet.cells.keys.filter { FormulaSyntax.isFormula(sheet.cell(at: $0).raw) }.sorted()
      for address in addresses {
        let actual = viewModel.displayValue(at: address)
        let expected = byKey[AnswerKey(sheet: sheetIndex, address: address)] ?? .error(.error)
        checked += 1
        if !ScalarFormulaAnswers.same(actual, expected) {
          mismatches.append(("\(sheet.name)!\(address.a1)", expected, actual))
        }
        if checked % 5000 == 0 {
          emit("answer-check \(label) path \(checked)")
        }
      }
    }
    emit("answer-check \(label) formulas \(checked) mismatches \(mismatches.count)")
    for mismatch in mismatches.prefix(15) {
      emit("mismatch \(mismatch.0) scalar \(ScalarFormulaAnswers.encode(mismatch.1)) path \(ScalarFormulaAnswers.encode(mismatch.2))")
    }
    let url = URL(fileURLWithPath: answersDirectory).appendingPathComponent("\(label)-answers.txt")
    try ScalarFormulaAnswers.write(scalar, label: label, mismatches: mismatches.count, to: url)
    emit("answers \(url.path)")
  }

  private struct AnswerKey: Hashable {
    var sheet: Int
    var address: CellAddress
  }

  private static func summaryLine(
    label: String,
    open: TimeInterval,
    unsaved: TimeInterval,
    firstScreen: TimeInterval,
    firstScreenName: String,
    edit: TimeInterval,
    commit: TimeInterval,
    tab: TimeInterval,
    export: TimeInterval,
    scroll: TimeInterval,
    scrollSheet: String,
    importSeconds: TimeInterval,
    fingerprint: TimeInterval,
    residentMB: Double
  ) -> String {
    "SUMMARY\t\(label)\topen \(formatSeconds(open))\tunsaved \(formatSeconds(unsaved))\tfirst \(formatSeconds(firstScreen)) (\(firstScreenName))\tedit \(formatSeconds(edit))\tcommitEdit \(formatSeconds(commit))\ttab \(formatSeconds(tab))\texport \(formatSeconds(export))\tscroll \(formatSeconds(scroll)) (\(scrollSheet))\timport \(formatSeconds(importSeconds))\tfingerprint \(formatSeconds(fingerprint))\tresident \(String(format: "%.0f", residentMB))MB"
  }

  private static func formatSeconds(_ seconds: TimeInterval) -> String {
    String(format: "%.3f s", seconds)
  }

  private static func timeWorstScroll(
    grid: BenchmarkGrid,
    viewModel: SpreadsheetViewModel,
    sheetIndex: Int
  ) -> (worst: TimeInterval, ticks: Int, sheet: String) {
    viewModel.selectSheet(at: sheetIndex)
    let sheet = viewModel.activeSheet
    let frame = viewportFrame(for: sheet)
    grid.resize(to: frame)
    grid.grid.reloadContent(resetScrollPosition: true)
    grid.grid.needsDisplay = true
    grid.grid.display()
    grid.grid.testingWarmScrollPlanes()
    let header = SpreadsheetGridNSView.baseHeaderSize
    let body = max(1, frame.height - header)
    let dataRows = max(1, sheet.maxPopulatedRow + 1)
    let screens = max(1, (dataRows + firstScreenRows - 1) / firstScreenRows)
    let landings = sampleLandings(screens: screens)
    var cursor = 0
    var worst = 0.0
    for landing in landings {
      let before = landing - 1
      if cursor < before {
        grid.grid.testingApplyScroll(dx: 0, dy: body * CGFloat(before - cursor))
        cursor = before
      }
      let started = CFAbsoluteTimeGetCurrent()
      grid.grid.testingApplyScroll(dx: 0, dy: body)
      worst = max(worst, CFAbsoluteTimeGetCurrent() - started)
      cursor = landing
    }
    return (worst, landings.count, sheet.name)
  }

  /// 1-based screen index each timed tick lands on.
  private static func sampleLandings(screens: Int) -> [Int] {
    if screens <= 36 {
      return Array(1...max(1, screens))
    }
    let raw = [1, 2, 3, max(1, screens / 4), max(1, screens / 2), max(1, (screens * 3) / 4), screens]
    return Array(Set(raw.filter { $0 >= 1 && $0 <= screens })).sorted()
  }

  private static func scrollSheetIndex(in workbook: Workbook, preferredName: String?) -> Int {
    if let preferredName,
       !preferredName.isEmpty,
       let index = workbook.sheets.firstIndex(where: { $0.name.caseInsensitiveCompare(preferredName) == .orderedSame })
    {
      return index
    }
    return workbook.sheets.indices.max { lhs, rhs in
      workbook.sheets[lhs].maxPopulatedRow < workbook.sheets[rhs].maxPopulatedRow
    } ?? 0
  }

  private static func viewportFrame(for sheet: Sheet) -> NSRect {
    let header = SpreadsheetGridNSView.baseHeaderSize
    var width = header
    let columns = min(firstScreenColumns, max(1, sheet.effectiveColumnCount))
    for column in 0..<columns {
      width += sheet.columnWidth(for: column, default: Workbook.defaultColumnWidth)
    }
    var height = header
    let rows = min(firstScreenRows, max(1, sheet.effectiveRowCount))
    for row in 0..<rows {
      height += sheet.rowHeight(for: row, default: Workbook.defaultRowHeight)
    }
    return NSRect(x: 0, y: 0, width: width + 2, height: height + 2)
  }

  private static func syncOnChange(store: SpreadsheetDocumentStore, viewModel: SpreadsheetViewModel) {
    guard store.document.workbook != viewModel.workbook else { return }
    store.document.workbook = viewModel.workbook
    store.documentDidChange()
  }

  private static func firstNumericLiteral(in sheet: Sheet) -> CellAddress? {
    for address in sheet.cells.keys.sorted() {
      let raw = sheet.cell(at: address).raw
      guard !FormulaSyntax.isFormula(raw) else { continue }
      if case .number = CellValue.fromLiteralRaw(raw) {
        return address
      }
    }
    return nil
  }

  private static func withoutImportedResults(_ workbook: Workbook) -> Workbook {
    var copy = workbook
    for index in copy.sheets.indices {
      var sheet = copy.sheets[index]
      let addresses = sheet.cells.compactMap { address, cell -> CellAddress? in
        cell.importedFormulaResult == nil ? nil : address
      }
      guard !addresses.isEmpty else { continue }
      for address in addresses {
        var cell = sheet.cell(at: address)
        cell.importedFormulaResult = nil
        sheet.setCell(cell, at: address)
      }
      copy.sheets[index] = sheet
    }
    return copy
  }

  private static func validateLedger(_ workbook: Workbook) throws {
    guard let tallest = workbook.sheets.max(by: { $0.maxPopulatedRow < $1.maxPopulatedRow }),
          tallest.maxPopulatedRow + 1 >= 50_000
    else { throw BenchmarkFailure("ledger does not have 50000 rows") }

    var sawVLookup = false
    var sawIndexMatch = false
    var sawSumIfs = false
    var longestFormulaColumn = 0
    for sheet in workbook.sheets {
      var perColumn: [Int: Int] = [:]
      for (address, cell) in sheet.cells where FormulaSyntax.isFormula(cell.raw) {
        let upper = cell.raw.uppercased()
        if upper.contains("VLOOKUP") { sawVLookup = true }
        if upper.contains("INDEX"), upper.contains("MATCH") { sawIndexMatch = true }
        if upper.contains("SUMIFS") { sawSumIfs = true }
        perColumn[address.col, default: 0] += 1
      }
      longestFormulaColumn = max(longestFormulaColumn, perColumn.values.max() ?? 0)
    }
    guard sawVLookup else { throw BenchmarkFailure("ledger has no VLOOKUP") }
    guard sawIndexMatch else { throw BenchmarkFailure("ledger has no INDEX/MATCH") }
    guard sawSumIfs else { throw BenchmarkFailure("ledger has no SUMIFS") }
    guard longestFormulaColumn >= 400 else {
      throw BenchmarkFailure("dependency chain is shorter than 400 formulas")
    }

    let tallName = tallest.name
    let tallRefsOut = tallest.cells.values.contains { cell in
      FormulaSyntax.isFormula(cell.raw) && cell.raw.contains("!")
    }
    let othersRefTall = workbook.sheets.contains { sheet in
      guard sheet.name != tallName else { return false }
      return sheet.cells.values.contains { cell in
        FormulaSyntax.isFormula(cell.raw) && cell.raw.localizedCaseInsensitiveContains(tallName)
      }
    }
    guard tallRefsOut, othersRefTall else {
      throw BenchmarkFailure("cross-sheet references do not run both ways")
    }

    let wideConditionalFormat = workbook.sheets.contains { sheet in
      sheet.conditionalFormats.contains { rule in
        let bounds = rule.range.normalized
        return bounds.maxRow - bounds.minRow >= 10_000
      }
    }
    guard wideConditionalFormat else {
      throw BenchmarkFailure("conditional formatting does not cover a large range")
    }
    let wrapped = workbook.sheets.contains { sheet in
      sheet.cells.values.contains { $0.format?.textDisplay == .wrap }
    }
    guard wrapped else { throw BenchmarkFailure("wrapped text is missing") }
  }

  private static func drainMain() {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
  }

  private static func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return 0 }
    return info.resident_size
  }

  private struct BenchmarkFailure: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
  }
}

@MainActor
private final class BenchmarkGrid {
  let window: NSWindow
  let grid: SpreadsheetGridNSView

  init(viewModel: SpreadsheetViewModel, frame: NSRect) {
    grid = SpreadsheetGridNSView(frame: frame)
    window = NSWindow(
      contentRect: frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = grid
    window.setFrameOrigin(NSPoint(x: -8000, y: -8000))
    window.orderFrontRegardless()
    window.setContentSize(frame.size)
    grid.frame = frame
    grid.viewModel = viewModel
    grid.layoutSubtreeIfNeeded()
  }

  func resize(to frame: NSRect) {
    window.setContentSize(frame.size)
    grid.frame = frame
    grid.layoutSubtreeIfNeeded()
  }

  func close() {
    window.orderOut(nil)
    window.close()
  }
}
