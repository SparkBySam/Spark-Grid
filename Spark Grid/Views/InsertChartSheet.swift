import SwiftUI

/// Insert Chart chooser: kind, category column, value mode / column, live preview.
/// A single-cell selection still opens this menu and waits for a real range.
struct InsertChartSheet: View {
  @Bindable var viewModel: SpreadsheetViewModel
  @Environment(\.dismiss) private var dismiss

  @State private var kind: SheetChart.Kind = .bar
  @State private var categoryColumn: Int = 0
  @State private var valueColumn: Int = 0
  @State private var hasHeaderRow = true
  @State private var valueMode: SheetChart.ValueMode = .values
  @State private var didConfigure = false
  /// Stable id so live preview does not regenerate UUIDs every body pass (that caused a layout loop).
  @State private var draftID = UUID()
  @State private var columnOptions: [ChartPreviewSeries.ColumnOption] = []
  /// Set when Insert Chart opened with only the active cell selected.
  @State private var mustChooseRange = false
  @State private var rangeText = ""
  /// Explicit chart range. Stays nil until the selection or the range field covers more than one cell.
  @State private var dataRange: CellRange?
  /// On-sheet frame kept while editing so a type or range change does not move the chart.
  @State private var keptAnchor: KeptAnchor?
  @State private var titleText = ""
  @State private var titleEdited = false
  @State private var showsLegend = false
  @State private var showsGridlines = true
  @State private var categoryAxisTitle = ""
  @State private var valueAxisTitle = ""
  @State private var seriesColor: CodableColor?
  @State private var pointColors: [Int: CodableColor] = [:]
  @State private var frameIsCustom = false
  @FocusState private var rangeFieldFocused: Bool

  private struct KeptAnchor {
    var row: Int
    var col: Int
    var rowSpan: Int
    var colSpan: Int
    var originXOffset: CGFloat
    var originYOffset: CGFloat
    var endXOffset: CGFloat
    var endYOffset: CGFloat
  }

  private var isEditing: Bool { viewModel.editingChartID != nil }

  private var draftChart: SheetChart? {
    guard let dataRange, !dataRange.isSingleCell else { return nil }
    let n = dataRange.normalized
    let anchorRow: Int
    let anchorCol: Int
    let rowSpan: Int
    let colSpan: Int
    if let keptAnchor {
      anchorRow = keptAnchor.row
      anchorCol = keptAnchor.col
      rowSpan = keptAnchor.rowSpan
      colSpan = keptAnchor.colSpan
    } else {
      anchorRow = min(viewModel.activeSheet.effectiveRowCount - 1, n.maxRow + 2)
      anchorCol = n.minCol
      rowSpan = 12
      colSpan = 8
    }
    return SheetChart(
      id: draftID,
      kind: kind,
      title: resolvedTitle,
      dataRange: dataRange,
      categoryColumn: categoryColumn,
      valueColumn: valueColumn,
      hasHeaderRow: hasHeaderRow,
      valueMode: valueMode,
      anchorRow: anchorRow,
      anchorCol: anchorCol,
      rowSpan: rowSpan,
      colSpan: colSpan,
      originXOffset: keptAnchor?.originXOffset ?? 0,
      originYOffset: keptAnchor?.originYOffset ?? 0,
      endXOffset: keptAnchor?.endXOffset ?? 0,
      endYOffset: keptAnchor?.endYOffset ?? 0,
      seriesColor: seriesColor,
      pointColors: pointColors,
      showsLegend: showsLegend,
      showsGridlines: showsGridlines,
      categoryAxisTitle: categoryAxisTitle,
      valueAxisTitle: valueAxisTitle,
      frameIsCustom: frameIsCustom
    )
  }

  /// A new chart takes the series description until the title field is edited.
  /// An existing chart keeps the title it was saved with.
  private var resolvedTitle: String {
    if titleEdited { return titleText }
    return draftTitle
  }

  private var titleField: Binding<String> {
    Binding(
      get: { resolvedTitle },
      set: { newValue in
        titleEdited = true
        titleText = newValue
      }
    )
  }

  private var draftTitle: String {
    guard let dataRange, let chart = titleChart(for: dataRange) else { return "" }
    let cat = header(for: categoryColumn)
    let val = header(for: valueColumn)
    return ChartPreviewSeries.seriesDescription(
      for: chart,
      categoryHeader: cat,
      valueHeader: val
    )
  }

  private var canInsert: Bool {
    guard let chart = draftChart, !columnOptions.isEmpty else { return false }
    let series = ChartPreviewSeries.points(
      for: chart,
      labelFor: { viewModel.displayString(at: $0) },
      numberFor: { viewModel.displayValue(at: $0).asChartNumber }
    )
    return !series.points.isEmpty
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(isEditing ? "Edit Chart" : "Insert Chart")
          .font(.headline)
        Spacer()
      }
      .padding(.horizontal, 20)
      .padding(.top, 16)
      .padding(.bottom, 4)

      Form {
        Section {
          Picker("Type", selection: $kind) {
            ForEach(SheetChart.Kind.allCases) { item in
              Text(item.title).tag(item)
            }
          }
          .pickerStyle(.segmented)

          if mustChooseRange {
            TextField("Data range", text: $rangeText, prompt: Text("A1:D12"))
              .focused($rangeFieldFocused)
              .autocorrectionDisabled()
              .onSubmit(commitRangeText)
          }

          if dataRange != nil {
            Toggle("First row is headers", isOn: $hasHeaderRow)

            Picker("Category (X)", selection: $categoryColumn) {
              ForEach(columnOptions) { option in
                Text(option.displayName).tag(option.column)
              }
            }

            Picker("Values", selection: $valueMode) {
              ForEach(SheetChart.ValueMode.allCases) { mode in
                Text(mode.title).tag(mode)
              }
            }

            if valueMode == .values {
              Picker("Value (Y)", selection: $valueColumn) {
                ForEach(columnOptions) { option in
                  Text(option.displayName).tag(option.column)
                }
              }
            }
          }
        } header: {
          Text("Data")
        } footer: {
          Text(footerText)
            .font(.caption)
        }

        if let chart = draftChart {
          Section {
            ChartFormatFields(
              title: titleField,
              showsLegend: $showsLegend,
              showsGridlines: $showsGridlines,
              categoryAxisTitle: $categoryAxisTitle,
              valueAxisTitle: $valueAxisTitle,
              seriesColor: ChartColorPaint.color(chart.resolvedSeriesColor),
              onSeriesColor: { seriesColor = ChartColorPaint.codable($0) },
              points: plottedPoints(for: chart),
              pointColor: { ChartColorPaint.color(chart.resolvedColor(forPoint: $0)) },
              isPointOverride: { pointColors[$0] != nil },
              onPointColor: { index, color in
                pointColors[index] = ChartColorPaint.codable(color)
              },
              onClearPointColor: { pointColors[$0] = nil }
            )
          } header: {
            Text("Format")
          }
        }
      }
      .formStyle(.grouped)
      .frame(maxHeight: 380)

      VStack(alignment: .leading, spacing: 8) {
        Text("Preview")
          .font(.headline)
        if let chart = draftChart {
          let title = chart.title.trimmingCharacters(in: .whitespacesAndNewlines)
          if !title.isEmpty {
            Text(title)
              .font(.system(size: 13, weight: .semibold))
              .lineLimit(1)
          }
          Text(chart.placementDescription)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        preview
          .frame(width: 440, height: previewHeight)
          .clipped()
          .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)

      Divider()

      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button(isEditing ? "Update Chart" : "Insert Chart") {
          guard let chart = draftChart else { return }
          let saved = isEditing ? viewModel.updateChart(chart) : viewModel.insertChart(chart)
          guard saved else { return }
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canInsert)
      }
      .padding(16)
    }
    .frame(width: 520, height: 760)
    .onAppear(perform: configureDefaultsIfNeeded)
    .onChange(of: rangeText) { _, _ in
      commitRangeText()
    }
  }

  @ViewBuilder
  private var preview: some View {
    if let chart = draftChart {
      SheetChartView(chart: chart, viewModel: viewModel)
    } else {
      VStack(spacing: 6) {
        Text("Select a range")
          .font(.system(size: 12, weight: .medium))
        Text("Choose the cells to chart. The preview uses that range.")
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(8)
    }
  }

  private var footerText: String {
    if let dataRange {
      return "Range \(dataRange.a1Description). Pick a label column and either a numeric column or “Count of rows”."
    }
    if rangeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return "Select a range of cells before a chart is created."
    }
    return "Enter a range such as A1:D12."
  }

  private var previewHeight: CGFloat {
    guard let chart = draftChart else { return 200 }
    return OnSheetChartGeometry.previewHeight(
      colSpan: chart.colSpan,
      rowSpan: chart.rowSpan,
      width: 440,
      minHeight: 160,
      maxHeight: 220
    )
  }

  private func plottedPoints(for chart: SheetChart) -> [ChartPreviewSeries.Point] {
    ChartPreviewSeries.points(
      for: chart,
      labelFor: { viewModel.displayString(at: $0) },
      numberFor: { viewModel.displayValue(at: $0).asChartNumber }
    ).points
  }

  private func resetFormat() {
    titleText = ""
    titleEdited = false
    showsLegend = false
    showsGridlines = true
    categoryAxisTitle = ""
    valueAxisTitle = ""
    seriesColor = nil
    pointColors = [:]
    frameIsCustom = false
  }

  private func header(for column: Int) -> String {
    columnOptions.first(where: { $0.column == column })?.header ?? ""
  }

  private func titleChart(for range: CellRange) -> SheetChart? {
    guard !range.isSingleCell else { return nil }
    return SheetChart(
      id: draftID,
      kind: kind,
      dataRange: range,
      categoryColumn: categoryColumn,
      valueColumn: valueColumn,
      hasHeaderRow: hasHeaderRow,
      valueMode: valueMode,
      anchorRow: 0,
      anchorCol: 0
    )
  }

  private func configureDefaultsIfNeeded() {
    guard !didConfigure else { return }
    didConfigure = true
    if let existing = editingChart() {
      load(existing)
      return
    }
    kind = viewModel.pendingChartKind
    keptAnchor = nil
    resetFormat()
    if let selection = viewModel.chartSelectionRange {
      mustChooseRange = false
      adopt(selection)
    } else {
      mustChooseRange = true
      dataRange = nil
      rangeText = ""
      columnOptions = []
      rangeFieldFocused = true
    }
  }

  private func editingChart() -> SheetChart? {
    guard let id = viewModel.editingChartID else { return nil }
    return viewModel.activeSheet.charts.first { $0.id == id }
  }

  /// Fills the sheet from a chart already on the grid. The range field stays editable.
  private func load(_ chart: SheetChart) {
    draftID = chart.id
    kind = chart.kind
    keptAnchor = KeptAnchor(
      row: chart.anchorRow,
      col: chart.anchorCol,
      rowSpan: chart.rowSpan,
      colSpan: chart.colSpan,
      originXOffset: chart.originXOffset,
      originYOffset: chart.originYOffset,
      endXOffset: chart.endXOffset,
      endYOffset: chart.endYOffset
    )
    mustChooseRange = true
    let text = chart.dataRange.a1Description
    let parsed = ChartDataRangeParser.parse(text)
    dataRange = parsed
    rangeText = text
    titleEdited = true
    titleText = chart.title
    showsLegend = chart.showsLegend
    showsGridlines = chart.showsGridlines
    categoryAxisTitle = chart.categoryAxisTitle
    valueAxisTitle = chart.valueAxisTitle
    seriesColor = chart.seriesColor
    pointColors = chart.pointColors
    frameIsCustom = chart.frameIsCustom
    guard let parsed else {
      columnOptions = []
      return
    }
    columnOptions = ChartPreviewSeries.columnOptions(
      in: parsed,
      labelFor: { viewModel.displayString(at: $0) },
      numberFor: { viewModel.displayValue(at: $0).asChartNumber }
    )
    hasHeaderRow = chart.hasHeaderRow
    valueMode = chart.valueMode
    let suggestion = ChartPreviewSeries.suggest(
      in: parsed,
      labelFor: { viewModel.displayString(at: $0) },
      numberFor: { viewModel.displayValue(at: $0).asChartNumber }
    )
    let category = chart.categoryColumn ?? suggestion.categoryColumn
    let value = chart.valueColumn ?? suggestion.valueColumn
    if columnOptions.contains(where: { $0.column == category }) {
      categoryColumn = category
    } else {
      categoryColumn = suggestion.categoryColumn
    }
    if columnOptions.contains(where: { $0.column == value }) {
      valueColumn = value
    } else {
      valueColumn = suggestion.valueColumn
    }
  }

  private func commitRangeText() {
    guard mustChooseRange else { return }
    let parsed = ChartDataRangeParser.parse(rangeText)
    guard parsed != dataRange else { return }
    if let parsed {
      adopt(parsed, keepSeries: dataRange != nil && !columnOptions.isEmpty)
    } else {
      dataRange = nil
      columnOptions = []
    }
  }

  private func adopt(_ range: CellRange, keepSeries: Bool = false) {
    guard !range.isSingleCell else {
      dataRange = nil
      columnOptions = []
      return
    }
    let previousCategory = categoryColumn
    let previousValue = valueColumn
    dataRange = range
    columnOptions = ChartPreviewSeries.columnOptions(
      in: range,
      labelFor: { viewModel.displayString(at: $0) },
      numberFor: { viewModel.displayValue(at: $0).asChartNumber }
    )
    let suggestion = ChartPreviewSeries.suggest(
      in: range,
      labelFor: { viewModel.displayString(at: $0) },
      numberFor: { viewModel.displayValue(at: $0).asChartNumber }
    )
    if keepSeries, columnOptions.contains(where: { $0.column == previousCategory }) {
      categoryColumn = previousCategory
    } else {
      categoryColumn = suggestion.categoryColumn
    }
    if keepSeries, columnOptions.contains(where: { $0.column == previousValue }) {
      valueColumn = previousValue
    } else {
      valueColumn = suggestion.valueColumn
    }
    if !keepSeries {
      hasHeaderRow = suggestion.hasHeaderRow
      valueMode = suggestion.valueMode
    }
  }
}

/// Closed multi-cell ranges for Insert Chart (`A1:D12`).
/// A blank field, a single cell, and an open row or column are not chart ranges.
enum ChartDataRangeParser {
  static func parse(_ text: String) -> CellRange? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains("!") else { return nil }
    let compact = trimmed.replacingOccurrences(of: " ", with: "")
    guard let (start, end) = A1Reference.parseFormulaRange(compact),
          !start.isRowOpen, !start.isColOpen,
          !end.isRowOpen, !end.isColOpen
    else { return nil }
    let range = CellRange(start: start.address, end: end.address)
    guard !range.isSingleCell else { return nil }
    return range
  }
}

extension CellRange {
  var a1Description: String {
    let n = normalized
    let start = CellAddress(row: n.minRow, col: n.minCol).a1
    let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
    return start == end ? start : "\(start):\(end)"
  }
}
