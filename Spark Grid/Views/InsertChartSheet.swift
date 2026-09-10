import SwiftUI

/// Insert Chart chooser: kind, category column, value mode / column, live preview.
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

  private var range: CellRange { viewModel.selectionRange }

  private var normalized: (minRow: Int, maxRow: Int, minCol: Int, maxCol: Int) {
    range.normalized
  }

  private var draftChart: SheetChart {
    let n = normalized
    return SheetChart(
      id: draftID,
      kind: kind,
      title: draftTitle,
      dataRange: range,
      categoryColumn: categoryColumn,
      valueColumn: valueColumn,
      hasHeaderRow: hasHeaderRow,
      valueMode: valueMode,
      anchorRow: min(viewModel.activeSheet.effectiveRowCount - 1, n.maxRow + 2),
      anchorCol: n.minCol
    )
  }

  private var draftTitle: String {
    let cat = header(for: categoryColumn)
    let val = header(for: valueColumn)
    return ChartPreviewSeries.seriesDescription(
      for: SheetChart(
        id: draftID,
        kind: kind,
        dataRange: range,
        categoryColumn: categoryColumn,
        valueColumn: valueColumn,
        hasHeaderRow: hasHeaderRow,
        valueMode: valueMode,
        anchorRow: 0,
        anchorCol: 0
      ),
      categoryHeader: cat,
      valueHeader: val
    )
  }

  private var canInsert: Bool {
    guard !columnOptions.isEmpty else { return false }
    let series = ChartPreviewSeries.points(
      for: draftChart,
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
        } header: {
          Text("Data")
        } footer: {
          Text("Range \(range.a1Description). Pick a label column and either a numeric column or “Count of rows”.")
            .font(.caption)
        }
      }
      .formStyle(.grouped)
      .frame(maxHeight: 280)

      VStack(alignment: .leading, spacing: 8) {
        Text("Preview")
          .font(.headline)
        SheetChartView(chart: draftChart, viewModel: viewModel)
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
          viewModel.insertChart(draftChart)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canInsert)
      }
      .padding(16)
    }
    .frame(width: 480, height: 560)
    .onAppear(perform: configureDefaultsIfNeeded)
  }

  private func header(for column: Int) -> String {
    columnOptions.first(where: { $0.column == column })?.header ?? ""
  }

  private func configureDefaultsIfNeeded() {
    guard !didConfigure else { return }
    didConfigure = true
    kind = viewModel.pendingChartKind
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

extension CellRange {
  var a1Description: String {
    let n = normalized
    let start = CellAddress(row: n.minRow, col: n.minCol).a1
    let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
    return start == end ? start : "\(start):\(end)"
  }
}
