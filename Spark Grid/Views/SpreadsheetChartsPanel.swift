import Charts
import SwiftUI

struct SpreadsheetChartsPanel: View {
  @Bindable var viewModel: SpreadsheetViewModel

  var body: some View {
    let charts = viewModel.activeSheet.charts
    if charts.isEmpty {
      EmptyView()
    } else {
      VStack(alignment: .leading, spacing: 8) {
        Text("Charts")
          .font(.headline)
        ForEach(charts) { chart in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(chart.title)
                .font(.subheadline.weight(.semibold))
              Spacer()
              Button {
                viewModel.removeChart(id: chart.id)
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
              .help("Delete chart")
            }
            SheetChartView(chart: chart, viewModel: viewModel)
              .frame(height: 160)
          }
          .padding(10)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
      }
      .padding(12)
      .frame(width: 320)
    }
  }
}

struct SheetChartView: View {
  let chart: SheetChart
  let viewModel: SpreadsheetViewModel

  private struct Point: Identifiable {
    let id: Int
    let label: String
    let value: Double
  }

  private var points: [Point] {
    let n = chart.dataRange.normalized
    var result: [Point] = []
    // Prefer first column as labels, remaining columns as a single series (first numeric col).
    let labelCol = n.minCol
    let valueCol = min(n.maxCol, n.minCol + 1)
    let startRow = n.minRow == n.maxRow ? n.minRow : n.minRow + 1
    for (index, row) in (startRow...n.maxRow).enumerated() {
      let labelAddress = CellAddress(row: row, col: labelCol)
      let valueAddress = CellAddress(row: row, col: valueCol)
      let label = viewModel.displayString(at: labelAddress)
      let value = viewModel.displayValue(at: valueAddress).asNumber
        ?? viewModel.displayValue(at: labelAddress).asNumber
      guard let value else { continue }
      let displayLabel = label.isEmpty ? "\(index + 1)" : label
      result.append(Point(id: index, label: displayLabel, value: value))
    }
    // Single-column numeric range: use row index labels.
    if result.isEmpty {
      for (index, row) in (n.minRow...n.maxRow).enumerated() {
        for col in n.minCol...n.maxCol {
          if let value = viewModel.displayValue(at: CellAddress(row: row, col: col)).asNumber {
            result.append(Point(id: result.count, label: "\(index + 1)", value: value))
            break
          }
        }
      }
    }
    return result
  }

  var body: some View {
    Chart(points) { point in
      switch chart.kind {
      case .bar:
        BarMark(
          x: .value("Label", point.label),
          y: .value("Value", point.value)
        )
      case .line:
        LineMark(
          x: .value("Label", point.label),
          y: .value("Value", point.value)
        )
        PointMark(
          x: .value("Label", point.label),
          y: .value("Value", point.value)
        )
      case .area:
        AreaMark(
          x: .value("Label", point.label),
          y: .value("Value", point.value)
        )
        LineMark(
          x: .value("Label", point.label),
          y: .value("Value", point.value)
        )
      }
    }
    .chartXAxis {
      AxisMarks(values: .automatic) { _ in
        AxisValueLabel()
      }
    }
  }
}
