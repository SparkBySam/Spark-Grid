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
  @FocusState private var rangeFieldFocused: Bool

  private var draftChart: SheetChart? {
    guard let dataRange, !dataRange.isSingleCell else { return nil }
    let n = dataRange.normalized
    return SheetChart(
      id: draftID,
      kind: kind,
      title: draftTitle,
      dataRange: dataRange,
      categoryColumn: categoryColumn,
      valueColumn: valueColumn,
      hasHeaderRow: hasHeaderRow,
      valueMode: valueMode,
      anchorRow: min(viewModel.activeSheet.effectiveRowCount - 1, n.maxRow + 2),
      anchorCol: n.minCol
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
      }
      .formStyle(.grouped)
      .frame(maxHeight: 280)

      VStack(alignment: .leading, spacing: 8) {
        Text("Preview")
          .font(.headline)
        preview
          .frame(width: 440, height: 200)
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
        Button("Insert Chart") {
          guard let chart = draftChart, viewModel.insertChart(chart) else { return }
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canInsert)
      }
      .padding(16)
    }
    .frame(width: 480, height: 560)
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
    kind = viewModel.pendingChartKind
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

  private func commitRangeText() {
    guard mustChooseRange else { return }
    let parsed = ChartDataRangeParser.parse(rangeText)
    guard parsed != dataRange else { return }
    if let parsed {
      adopt(parsed)
    } else {
      dataRange = nil
      columnOptions = []
    }
  }

  private func adopt(_ range: CellRange) {
    guard !range.isSingleCell else {
      dataRange = nil
      columnOptions = []
      return
    }
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
    categoryColumn = suggestion.categoryColumn
    valueColumn = suggestion.valueColumn
    hasHeaderRow = suggestion.hasHeaderRow
    valueMode = suggestion.valueMode
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
