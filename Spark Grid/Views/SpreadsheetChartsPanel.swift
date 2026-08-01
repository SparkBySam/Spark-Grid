import AppKit
import Charts
import SwiftUI

struct SpreadsheetChartsPanel: View {
  @Bindable var viewModel: SpreadsheetViewModel
  @Binding var isCollapsed: Bool

  private let expandedWidth: CGFloat = 280
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
            VStack(alignment: .leading, spacing: 6) {
              HStack(spacing: 6) {
                Text(chart.title)
                  .font(.system(size: 12, weight: .semibold))
                  .lineLimit(1)
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
                .frame(height: 140)
            }
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
          }
        }
        .padding(10)
      }
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

  @State private var cachedPoints: [Point] = []
  @State private var cachedToken = ""

  var body: some View {
    Group {
      if cachedPoints.isEmpty {
        Text("No numeric data in range")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        chartBody
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

  private var cacheToken: String {
    let n = chart.dataRange.normalized
    return "\(chart.id.uuidString)-\(viewModel.contentRevision)-\(chart.kind.rawValue)-\(n.minRow)-\(n.maxRow)-\(n.minCol)-\(n.maxCol)"
  }

  private func refreshPoints() {
    let token = cacheToken
    guard token != cachedToken else { return }
    cachedPoints = Self.computePoints(chart: chart, viewModel: viewModel)
    cachedToken = token
  }

  private static func computePoints(chart: SheetChart, viewModel: SpreadsheetViewModel) -> [Point] {
    ChartPreviewSeries.points(
      in: chart.dataRange,
      labelFor: { viewModel.displayString(at: $0) },
      numberFor: { viewModel.displayValue(at: $0).asNumber }
    ).map { Point(id: $0.id, label: $0.label, value: $0.value) }
  }
}
