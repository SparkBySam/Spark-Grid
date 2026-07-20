import AppKit
import SwiftUI

/// Shared geometry for the strip above the grid so spacer and chrome stay in sync.
enum SpreadsheetChrome {
  static let formulaBarLineHeight: CGFloat = 18
  static let formulaBarVerticalPadding: CGFloat = 10
  static let formulaBarMaxLines = 4
  static let findBarHeight: CGFloat = 36
  static let formulaErrorBannerHeight: CGFloat = 40
  static let dividerHeight: CGFloat = 1
  /// Slightly stronger than default `Divider()` / toolbar borders (~+2% contrast).
  static let chromeDividerOpacity: CGFloat = 0.72
  static let chromeBorderOpacity: CGFloat = 0.57

  static var chromeDividerColor: Color {
    Color(nsColor: .separatorColor).opacity(chromeDividerOpacity)
  }

  static var chromeBorderColor: Color {
    Color(nsColor: .separatorColor).opacity(chromeBorderOpacity)
  }

  static func toolbarHeight(showLabels: Bool) -> CGFloat {
    58
  }

  static func formulaBarLineCount(for text: String) -> Int {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
    return min(formulaBarMaxLines, max(1, lines))
  }

  static func formulaBarContentLineCount(for text: String) -> Int {
    max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
  }

  /// Collapsed = one visible row (scroll for overflow); expanded = up to `formulaBarMaxLines`.
  static func formulaBarViewportLineCount(contentLines: Int, expanded: Bool) -> Int {
    if expanded {
      return min(formulaBarMaxLines, max(1, contentLines))
    }
    return 1
  }

  static func formulaBarHeight(lineCount: Int) -> CGFloat {
    CGFloat(lineCount) * formulaBarLineHeight + formulaBarVerticalPadding
  }

  static func formulaFieldHeight(lineCount: Int) -> CGFloat {
    CGFloat(lineCount) * formulaBarLineHeight
  }

  static func topHeight(
    showLabels: Bool,
    showingFormulaError: Bool,
    showingFindBar: Bool,
    formulaBarLineCount: Int = 1
  ) -> CGFloat {
    var height = toolbarHeight(showLabels: showLabels)
      + dividerHeight
      + formulaBarHeight(lineCount: formulaBarLineCount)
      + dividerHeight
    if showingFindBar {
      height += findBarHeight + dividerHeight
    }
    if showingFormulaError {
      height += formulaErrorBannerHeight
    }
    return height
  }
}

/// Chrome hairline — a touch stronger than stock `Divider()`.
struct ChromeDivider: View {
  var body: some View {
    Rectangle()
      .fill(SpreadsheetChrome.chromeDividerColor)
      .frame(height: SpreadsheetChrome.dividerHeight)
      .frame(maxWidth: .infinity)
  }
}

struct SpreadsheetWindowView: View {
  @Bindable var store: SpreadsheetDocumentStore
  @Environment(\.undoManager) private var undoManager
  @Environment(\.sparkGridAppDelegate) private var appDelegate
  @Bindable private var settings = AppSettings.shared

  @State private var viewModel: SpreadsheetViewModel
  @State private var isChartsPanelCollapsed = false
  @State private var isFormulaBarExpanded = false

  private var document: Binding<SpreadsheetDocument> {
    $store.document
  }

  init(
    store: SpreadsheetDocumentStore,
    onDocumentChanged: @escaping () -> Void = {}
  ) {
    self.store = store
    self.onDocumentChanged = onDocumentChanged
    _viewModel = State(initialValue: SpreadsheetViewModel(workbook: store.document.workbook))
  }

  var onDocumentChanged: () -> Void = {}

  var body: some View {
    let showingFormulaError = viewModel.selectedFormulaErrorExplanation != nil
    let formulaContentLines = SpreadsheetChrome.formulaBarContentLineCount(for: viewModel.formulaBarText)
    let formulaViewportLines = SpreadsheetChrome.formulaBarViewportLineCount(
      contentLines: formulaContentLines,
      expanded: isFormulaBarExpanded
    )
    let hasCharts = !viewModel.activeSheet.charts.isEmpty
    ZStack(alignment: .top) {
      VStack(spacing: 0) {
        Color.clear.frame(
          height: SpreadsheetChrome.topHeight(
            showLabels: settings.showToolbarLabels,
            showingFormulaError: showingFormulaError,
            showingFindBar: viewModel.isFindBarVisible,
            formulaBarLineCount: formulaViewportLines
          )
        )
        HStack(spacing: 0) {
          SpreadsheetGridView(viewModel: viewModel)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
          if hasCharts {
            Rectangle()
              .fill(SpreadsheetChrome.chromeDividerColor)
              .frame(width: SpreadsheetChrome.dividerHeight)
            SpreadsheetChartsPanel(viewModel: viewModel, isCollapsed: $isChartsPanelCollapsed)
          }
        }
        ChromeDivider()
        SheetTabsView(viewModel: viewModel)
      }

      VStack(spacing: 0) {
        FormattingToolbar(viewModel: viewModel, store: store, undoManager: undoManager)
        ChromeDivider()
        FormulaBarView(
          viewModel: viewModel,
          isExpanded: $isFormulaBarExpanded
        )
        ChromeDivider()
        if viewModel.isFindBarVisible {
          FindReplaceBar(viewModel: viewModel)
          ChromeDivider()
        }
      }
      .frame(maxWidth: .infinity)
      .background(Color(nsColor: .controlBackgroundColor))
    }
    .onChange(of: viewModel.activeSheet.charts.count) { oldCount, newCount in
      if oldCount == 0, newCount > 0 {
        isChartsPanelCollapsed = false
      }
    }
    .focusedValue(\.spreadsheetViewModel, viewModel)
    .onChange(of: store.displayTitle) { _, title in
      WindowTitleUpdater.apply(title: title)
    }
    .onAppear {
      WindowTitleUpdater.apply(title: store.displayTitle)
    }
    .onChange(of: viewModel.workbook) { _, newValue in
      guard store.document.workbook != newValue else { return }
      store.document.workbook = newValue
      onDocumentChanged()
    }
    .onChange(of: store.document.workbook) { _, newValue in
      guard newValue != viewModel.workbook else { return }
      viewModel.workbook = newValue
      viewModel.isEditing = false
      viewModel.syncEditTextFromSelection()
      viewModel.restoreFilterFromActiveSheet()
      // File/load sync only — don't mark dirty.
    }
    .onAppear {
      viewModel.undoManager = undoManager
      if viewModel.workbook != store.document.workbook {
        viewModel.workbook = store.document.workbook
        viewModel.syncEditTextFromSelection()
      }
      viewModel.restoreFilterFromActiveSheet()
      registerWithAppDelegate()
    }
    .task {
      registerWithAppDelegate()
    }
    .onDisappear {
      appDelegate?.unregisterSpreadsheetViewModel(viewModel, store: store)
    }
    .onChange(of: undoManager) { _, newValue in
      viewModel.undoManager = newValue
    }
  }

  private func registerWithAppDelegate() {
    appDelegate?.registerSpreadsheetViewModel(viewModel, store: store)
  }
}

enum WindowTitleUpdater {
  static func apply(title: String) {
    DispatchQueue.main.async {
      NSApp.keyWindow?.title = title
    }
  }
}

#Preview {
  SpreadsheetWindowView(store: SpreadsheetDocumentStore())
}
