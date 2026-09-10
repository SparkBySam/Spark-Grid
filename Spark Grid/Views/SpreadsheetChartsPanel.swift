import AppKit
import Charts
import SwiftUI

struct SpreadsheetChartsPanel: View {
  @Bindable var viewModel: SpreadsheetViewModel
  @Binding var isCollapsed: Bool

  private let expandedWidth: CGFloat = 360
  private let collapsedWidth: CGFloat = 28

  var body: some View {
    let charts = viewModel.activeSheet.charts
    if charts.isEmpty {
      EmptyView()
    } else {
      Group {
        if isCollapsed {
          collapsedBar
        } else {
          expandedPanel(charts: charts)
        }
      }
      .frame(width: isCollapsed ? collapsedWidth : expandedWidth)
      .frame(maxHeight: .infinity)
      .background(Color(nsColor: .controlBackgroundColor))
    }
  }

  private var collapsedBar: some View {
    VStack(spacing: 8) {
      Button {
        withAnimation(.easeInOut(duration: 0.15)) { isCollapsed = false }
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 11, weight: .semibold))
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Show charts")

      Text("Charts")
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .rotationEffect(.degrees(-90))
        .fixedSize()
        .frame(width: 28)

      Spacer(minLength: 0)
    }
    .padding(.top, 4)
  }

  private func expandedPanel(charts: [SheetChart]) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        Text("Charts")
          .font(.system(size: 12, weight: .semibold))
        Spacer(minLength: 0)
        Button {
          withAnimation(.easeInOut(duration: 0.15)) { isCollapsed = true }
        } label: {
          Image(systemName: "sidebar.trailing")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Hide charts")
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)

      ChromeDivider()
        .padding(.horizontal, 10)

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(charts) { chart in
            chartCard(chart)
          }
        }
        .padding(10)
      }
    }
  }

  private func chartCard(_ chart: SheetChart) -> some View {
    let subtitle = seriesSubtitle(for: chart)
    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 6) {
        VStack(alignment: .leading, spacing: 2) {
          Text(chart.title)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(2)
          Text(subtitle)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        Spacer(minLength: 0)
        Button {
          viewModel.removeChart(id: chart.id)
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Delete chart")
      }
      SheetChartView(chart: chart, viewModel: viewModel)
        .frame(height: 240)
    }
    .padding(10)
    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
  }

  private func seriesSubtitle(for chart: SheetChart) -> String {
    let n = chart.dataRange.normalized
    let headerRow = chart.hasHeaderRow ? n.minRow : n.minRow
    let catCol = chart.categoryColumn ?? n.minCol
    let valCol = chart.valueColumn ?? min(n.maxCol, n.minCol + 1)
    let cat = viewModel.displayString(at: CellAddress(row: headerRow, col: catCol))
    let val = viewModel.displayString(at: CellAddress(row: headerRow, col: valCol))
    let series = ChartPreviewSeries.seriesDescription(
      for: chart,
      categoryHeader: chart.hasHeaderRow ? cat : "",
      valueHeader: chart.hasHeaderRow ? val : ""
    )
    return "\(series) · \(chart.dataRange.a1Description)"
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

  @State private var cachedPoints: [Point] = []
  @State private var cachedTotalCount = 0
  @State private var cachedToken = ""

  var body: some View {
    Group {
      if cachedPoints.isEmpty {
        VStack(spacing: 6) {
          Text("Nothing to plot")
            .font(.system(size: 12, weight: .medium))
          Text(emptyDetail)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
      } else {
        VStack(alignment: .leading, spacing: 6) {
          chartBody
          if cachedTotalCount > ChartPreviewSeries.maxPreviewPoints {
            Text("Showing first \(ChartPreviewSeries.maxPreviewPoints) of \(cachedTotalCount)")
              .font(.system(size: 9))
              .foregroundStyle(.tertiary)
          }
        }
      }
    }
    .onAppear { refreshPoints() }
    .onChange(of: cacheToken) { _, _ in
      refreshPoints()
    }
  }

  private var emptyDetail: String {
    switch chart.valueMode {
    case .count:
      return "No category labels in the selected range."
    case .values:
      return "Pick a numeric Value (Y) column, or switch Values to “Count of rows”."
    }
  }

  @ViewBuilder
  private var chartBody: some View {
    let labelIndexes = xLabelIndexes(for: cachedPoints.count)
    Chart(cachedPoints) { point in
      switch chart.kind {
      case .bar:
        BarMark(
          x: .value("Category", point.id),
          y: .value("Value", point.value)
        )
        .foregroundStyle(Color.accentColor.gradient)
      case .line:
        LineMark(
          x: .value("Category", point.id),
          y: .value("Value", point.value)
        )
        .foregroundStyle(Color.accentColor)
        .interpolationMethod(.catmullRom)
        PointMark(
          x: .value("Category", point.id),
          y: .value("Value", point.value)
        )
        .foregroundStyle(Color.accentColor)
        .symbolSize(cachedPoints.count > 20 ? 16 : 28)
      case .area:
        AreaMark(
          x: .value("Category", point.id),
          y: .value("Value", point.value)
        )
        .foregroundStyle(Color.accentColor.opacity(0.22).gradient)
        LineMark(
          x: .value("Category", point.id),
          y: .value("Value", point.value)
        )
        .foregroundStyle(Color.accentColor)
      }
    }
    .chartYScale(domain: yDomain)
    .chartXScale(domain: -0.5...(Double(max(0, cachedPoints.count - 1)) + 0.5))
    .chartYAxis {
      AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
          .foregroundStyle(Color.secondary.opacity(0.3))
        AxisValueLabel {
          if let number = value.as(Double.self) {
            Text(Self.formatAxisNumber(number))
              .font(.system(size: 9))
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .chartXAxis {
      AxisMarks(values: labelIndexes.map(Double.init)) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
          .foregroundStyle(Color.secondary.opacity(0.15))
        if let number = value.as(Double.self) {
          let index = Int(number.rounded())
          if let point = cachedPoints.first(where: { $0.id == index }) {
            AxisValueLabel(centered: true) {
              Text(Self.displayLabel(point.label))
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var yDomain: ClosedRange<Double> {
    let values = cachedPoints.map(\.value)
    guard let rawMax = values.max(), let rawMin = values.min() else {
      return 0...1
    }
    let maxValue = rawMax.isFinite ? rawMax : 1
    let minValue = min(0, rawMin.isFinite ? rawMin : 0)
    if !maxValue.isFinite || !minValue.isFinite || maxValue <= minValue {
      return min(minValue, 0)...(max(maxValue, 0) + 1)
    }
    let pad = max((maxValue - minValue) * 0.08, 0.5)
    return minValue...(maxValue + pad)
  }

  private var cacheToken: String {
    let n = chart.dataRange.normalized
    // Use series config only — never a regenerating identity — so previews stay stable.
    return [
      String(viewModel.contentRevision),
      chart.kind.rawValue,
      chart.valueMode.rawValue,
      String(chart.hasHeaderRow),
      String(chart.categoryColumn ?? -1),
      String(chart.valueColumn ?? -1),
      String(n.minRow), String(n.maxRow), String(n.minCol), String(n.maxCol),
    ].joined(separator: "-")
  }

  private func refreshPoints() {
    let token = cacheToken
    guard token != cachedToken else { return }
    let computed = Self.computePoints(chart: chart, viewModel: viewModel)
    cachedTotalCount = computed.totalCount
    cachedPoints = computed.points
    cachedToken = token
  }

  private static func computePoints(
    chart: SheetChart,
    viewModel: SpreadsheetViewModel
  ) -> (points: [Point], totalCount: Int) {
    let all = ChartPreviewSeries.points(
      for: chart,
      labelFor: { viewModel.displayString(at: $0) },
      numberFor: { viewModel.displayValue(at: $0).asChartNumber }
    )
    let points = all.points.map { Point(id: $0.id, label: $0.label, value: $0.value) }
    return (points, all.totalCount)
  }

  private func xLabelIndexes(for count: Int) -> [Int] {
    guard count > 0 else { return [] }
    let desired = min(6, count)
    if count <= desired { return Array(0..<count) }
    var indexes: [Int] = []
    for i in 0..<desired {
      let index = Int(round(Double(i) * Double(count - 1) / Double(desired - 1)))
      if indexes.last != index {
        indexes.append(index)
      }
    }
    return indexes
  }

  private static func formatAxisNumber(_ value: Double) -> String {
    let absValue = abs(value)
    if absValue >= 1_000_000 {
      return String(format: "%.1fM", value / 1_000_000)
    }
    if absValue >= 10_000 {
      return String(format: "%.0fK", value / 1_000)
    }
    if value.rounded() == value, absValue < 1e9 {
      return String(Int(value))
    }
    return String(format: "%.1f", value)
  }

  private static func displayLabel(_ label: String) -> String {
    guard label.count > 12 else { return label }
    return String(label.prefix(11)) + "…"
  }
}
