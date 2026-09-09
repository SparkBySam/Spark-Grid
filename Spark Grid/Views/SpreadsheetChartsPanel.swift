import AppKit
import Charts
import SwiftUI

struct SpreadsheetChartsPanel: View {
  @Bindable var viewModel: SpreadsheetViewModel
  @Binding var isCollapsed: Bool

  private let expandedWidth: CGFloat = 320
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
        VStack(alignment: .leading, spacing: 10) {
          ForEach(charts) { chart in
            chartCard(chart)
          }
        }
        .padding(10)
      }
    }
  }

  private func chartCard(_ chart: SheetChart) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        VStack(alignment: .leading, spacing: 2) {
          Text(chart.title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
          Text(chart.dataRange.a1Description)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
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
        .frame(height: 200)
    }
    .padding(8)
    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
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
        Text("No numeric data in range")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        VStack(alignment: .leading, spacing: 4) {
          chartBody
          if cachedTotalCount > ChartPreviewSeries.maxPreviewPoints {
            Text("Showing first \(ChartPreviewSeries.maxPreviewPoints) of \(cachedTotalCount) values")
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

  @ViewBuilder
  private var chartBody: some View {
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
        PointMark(
          x: .value("Category", point.id),
          y: .value("Value", point.value)
        )
        .foregroundStyle(Color.accentColor)
      case .area:
        AreaMark(
          x: .value("Category", point.id),
          y: .value("Value", point.value)
        )
        .foregroundStyle(Color.accentColor.opacity(0.25).gradient)
        LineMark(
          x: .value("Category", point.id),
          y: .value("Value", point.value)
        )
        .foregroundStyle(Color.accentColor)
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
          .foregroundStyle(Color.secondary.opacity(0.35))
        AxisValueLabel {
          if let number = value.as(Double.self) {
            Text(Self.formatAxisNumber(number))
              .font(.system(size: 9))
          }
        }
      }
    }
    .chartXAxis {
      AxisMarks(values: .automatic) { value in
        if let index = value.as(Int.self), let point = cachedPoints.first(where: { $0.id == index }) {
          AxisValueLabel(centered: true) {
            Text(Self.truncatedLabel(point.label))
              .font(.system(size: 9))
              .rotationEffect(cachedPoints.count > 6 ? .degrees(-45) : .zero)
          }
        }
      }
    }
    .chartPlotStyle { plot in
      plot.padding(.top, 6)
        .padding(.bottom, cachedPoints.count > 6 ? 18 : 4)
        .padding(.leading, 4)
        .padding(.trailing, 8)
    }
  }

  private var cacheToken: String {
    let n = chart.dataRange.normalized
    return "\(chart.id.uuidString)-\(viewModel.contentRevision)-\(chart.kind.rawValue)-\(n.minRow)-\(n.maxRow)-\(n.minCol)-\(n.maxCol)"
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
    let all = ChartPreviewSeries.series(
      in: chart.dataRange,
      labelFor: { viewModel.displayString(at: $0) },
      numberFor: { viewModel.displayValue(at: $0).asChartNumber }
    )
    let points = all.points.map { Point(id: $0.id, label: $0.label, value: $0.value) }
    return (points, all.totalCount)
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
    return String(format: "%.1g", value)
  }

  private static func truncatedLabel(_ label: String) -> String {
    guard label.count > 10 else { return label }
    return String(label.prefix(9)) + "…"
  }
}

private extension CellRange {
  var a1Description: String {
    let n = normalized
    let start = CellAddress(row: n.minRow, col: n.minCol).a1
    let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
    return start == end ? start : "\(start):\(end)"
  }
}
