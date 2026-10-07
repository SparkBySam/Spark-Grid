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
        Button("Edit") {
          viewModel.beginEditChart(id: chart.id)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11, weight: .medium))
        .help("Edit chart type, range, and series")
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
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(viewModel.selectedChartID == chart.id ? Color.accentColor : Color.clear, lineWidth: 2)
    )
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

  /// Points for this render. A cold cache still plots immediately so an on-sheet
  /// host does not stay empty when `onAppear` has not run yet.
  private var renderPoints: [Point] {
    if cachedToken == cacheToken { return cachedPoints }
    return Self.computePoints(chart: chart, viewModel: viewModel).points
  }

  private var renderTotalCount: Int {
    if cachedToken == cacheToken { return cachedTotalCount }
    return Self.computePoints(chart: chart, viewModel: viewModel).totalCount
  }

  /// Room under the plot for category names. Charts subtracts this from the
  /// view height; the plot is not placed when that remainder is under 1pt.
  static let plotBottomInset: CGFloat = 20

  var body: some View {
    GeometryReader { geo in
      chartStack(in: geo.size)
    }
    .onAppear { refreshPoints() }
    .onChange(of: cacheToken) { _, _ in
      refreshPoints()
    }
  }

  @ViewBuilder
  private func chartStack(in size: CGSize) -> some View {
    if renderPoints.isEmpty {
      let inset: CGFloat = 8
      if let innerWidth = OnSheetChartGeometry.placedHeight(top: inset, bottom: size.width - inset),
         let innerHeight = OnSheetChartGeometry.placedHeight(top: inset, bottom: size.height - inset) {
        VStack(spacing: 6) {
          Text("Nothing to plot")
            .font(.system(size: 12, weight: .medium))
          Text(emptyDetail)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(width: innerWidth, height: innerHeight)
        .position(x: size.width / 2, y: size.height / 2)
      }
    } else if let slot = plotSlotHeight(in: size) {
      let caption = captionHeight
      let spacing: CGFloat = caption >= 1 ? 6 : 0
      VStack(alignment: .leading, spacing: spacing) {
        chartBody
          .frame(width: size.width, height: slot)
        if caption >= 1 {
          Text("Showing first \(ChartPreviewSeries.maxPreviewPoints) of \(renderTotalCount)")
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .frame(height: caption, alignment: .leading)
        }
      }
      .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
  }

  private var captionHeight: CGFloat {
    renderTotalCount > ChartPreviewSeries.maxPreviewPoints ? 14 : 0
  }

  /// Chart view height, or nil when the plot inset would reverse the edges.
  private func plotSlotHeight(in size: CGSize) -> CGFloat? {
    guard size.width >= 1 else { return nil }
    let spacing: CGFloat = captionHeight >= 1 ? 6 : 0
    let slotBottom = size.height - captionHeight - spacing
    guard OnSheetChartGeometry.placedHeight(top: Self.plotBottomInset, bottom: slotBottom) != nil else {
      return nil
    }
    return slotBottom
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
    let points = renderPoints
    let labelIndexes = ChartCategoryLabelLayout.labelIndexes(count: points.count)
    let lineGradient = LinearGradient(
      colors: points.map { valueColor(for: $0, kind: .line) },
      startPoint: .leading,
      endPoint: .trailing
    )
    let marks = Chart(points) { point in
      switch chart.kind {
      case .bar:
        BarMark(
          x: .value("Category", point.id),
          y: .value("Value", point.value)
        )
        .foregroundStyle(by: .value("Swatch", point.id))
      case .line:
        LineMark(
          x: .value("Category", point.id),
          y: .value("Value", point.value)
        )
        .foregroundStyle(lineGradient)
        .interpolationMethod(.catmullRom)
        PointMark(
          x: .value("Category", point.id),
          y: .value("Value", point.value)
        )
        .foregroundStyle(by: .value("Swatch", point.id))
        .symbolSize(points.count > 20 ? 28 : 46)
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
    .chartXScale(domain: -0.5...(Double(max(0, points.count - 1)) + 0.5))
    .chartPlotStyle { plot in
      plot.padding(.bottom, Self.plotBottomInset)
    }
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
      AxisMarks(values: labelIndexes.map(Double.init)) { _ in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
          .foregroundStyle(Color.secondary.opacity(0.15))
      }
    }
    .chartOverlay { proxy in
      GeometryReader { geo in
        if let plotAnchor = proxy.plotFrame {
          let plot = geo[plotAnchor].standardized
          if OnSheetChartGeometry.placedHeight(top: plot.minY, bottom: plot.maxY) != nil {
            let placements = categoryPlacements(plot: plot, chartWidth: geo.size.width)
            ForEach(placements, id: \.index) { placement in
              Text(placement.text)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: max(1, placement.width), alignment: .center)
                .position(x: placement.minX + placement.width / 2, y: plot.maxY + 9)
            }
          }
        }
      }
      .allowsHitTesting(false)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    if ChartMarkPalette.usesDistinctValueColors(chart.kind) {
      marks
        .chartForegroundStyleScale(
          domain: points.map(\.id),
          range: points.map { ChartMarkPalette.swatch(at: $0.id).color }
        )
        .chartLegend(.hidden)
    } else {
      marks
        .chartLegend(.hidden)
    }
  }

  private func categoryPlacements(plot: CGRect, chartWidth: CGFloat) -> [ChartCategoryLabelLayout.Placement] {
    let points = renderPoints
    let indexes = ChartCategoryLabelLayout.labelIndexes(count: points.count)
    let lastIndex = indexes.last
    let items = indexes.compactMap { index -> ChartCategoryLabelLayout.Item? in
      guard points.indices.contains(index) else { return nil }
      let raw = points[index].label
      let text = index == lastIndex ? raw : Self.displayLabel(raw)
      return ChartCategoryLabelLayout.Item(index: index, text: text)
    }
    return ChartCategoryLabelLayout.placements(
      items: items,
      chartWidth: chartWidth,
      barCenterX: { index in
        ChartCategoryLabelLayout.barCenterX(
          index: index,
          count: renderPoints.count,
          plotMinX: plot.minX,
          plotWidth: plot.width
        )
      },
      labelWidth: { ChartCategoryLabelLayout.measure($0, fontSize: 8) }
    )
  }

  private func valueColor(for point: Point, kind: SheetChart.Kind) -> Color {
    guard ChartMarkPalette.usesDistinctValueColors(kind) else { return Color.accentColor }
    return ChartMarkPalette.swatch(at: point.id).color
  }

  private var yDomain: ClosedRange<Double> {
    let values = renderPoints.map(\.value)
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

extension ChartMarkPalette.RGB {
  var color: Color {
    Color(red: red, green: green, blue: blue)
  }
}

/// Chart drawn on the sheet at its cell anchor. Clicks are handled by the grid.
struct OnSheetChartCard: View {
  let chart: SheetChart
  var viewModel: SpreadsheetViewModel

  var body: some View {
    let selected = viewModel.selectedChartID == chart.id
    GeometryReader { geo in
      cardContent(in: geo.size)
    }
    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected ? 2 : 1)
    )
    .allowsHitTesting(false)
  }

  /// Title plus chart, only when each band is at least 1pt. A zero host
  /// frame used to inset this stack until the chart height was negative.
  @ViewBuilder
  private func cardContent(in size: CGSize) -> some View {
    let pad: CGFloat = 6
    let titleHeight: CGFloat = 14
    let spacing: CGFloat = 2
    if let innerWidth = OnSheetChartGeometry.placedHeight(top: pad, bottom: size.width - pad),
       let innerHeight = OnSheetChartGeometry.placedHeight(top: pad, bottom: size.height - pad) {
      if let chartHeight = OnSheetChartGeometry.placedHeight(
        top: titleHeight + spacing,
        bottom: innerHeight
      ) {
        VStack(alignment: .leading, spacing: spacing) {
          Text(chart.title)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: titleHeight)
          SheetChartView(chart: chart, viewModel: viewModel)
            .frame(width: innerWidth, height: chartHeight)
        }
        .frame(width: innerWidth, height: innerHeight, alignment: .topLeading)
        .position(x: size.width / 2, y: size.height / 2)
      } else {
        Text(chart.title)
          .font(.system(size: 11, weight: .semibold))
          .lineLimit(1)
          .padding(.horizontal, 2)
          .frame(width: innerWidth, height: innerHeight, alignment: .topLeading)
          .position(x: size.width / 2, y: size.height / 2)
      }
    }
  }
}

/// Flipped so the card lines up with the grid's top-left coordinates.
/// `NSHostingView.isFlipped` is final and settable, so it cannot be overridden.
final class OnSheetChartHost: NSHostingView<OnSheetChartCard> {
  required init(rootView: OnSheetChartCard) {
    super.init(rootView: rootView)
    isFlipped = true
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    isFlipped = true
  }
}
