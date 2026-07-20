import AppKit
import SwiftUI

private enum SpreadsheetChrome {
  static let formulaBarLineHeight: CGFloat = 18
  static let formulaBarVerticalPadding: CGFloat = 10
  static let formulaBarMaxLines = 4
  static let findBarHeight: CGFloat = 36
  static let formulaErrorBannerHeight: CGFloat = 40
  static let dividerHeight: CGFloat = 1

  static func toolbarHeight(showLabels: Bool) -> CGFloat {
    58
  }

  static func formulaBarLineCount(for text: String) -> Int {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
    return min(formulaBarMaxLines, max(1, lines))
  }

  static func formulaBarHeight(lineCount: Int) -> CGFloat {
    CGFloat(lineCount) * formulaBarLineHeight + formulaBarVerticalPadding
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

struct SpreadsheetWindowView: View {
  @Bindable var store: SpreadsheetDocumentStore
  @Environment(\.undoManager) private var undoManager
  @Environment(\.sparkGridAppDelegate) private var appDelegate
  @Bindable private var settings = AppSettings.shared

  @State private var viewModel: SpreadsheetViewModel

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
    let formulaLines = SpreadsheetChrome.formulaBarLineCount(for: viewModel.formulaBarText)
    ZStack(alignment: .top) {
      VStack(spacing: 0) {
        Color.clear.frame(
          height: SpreadsheetChrome.topHeight(
            showLabels: settings.showToolbarLabels,
            showingFormulaError: showingFormulaError,
            showingFindBar: viewModel.isFindBarVisible,
            formulaBarLineCount: formulaLines
          )
        )
        SpreadsheetGridView(viewModel: viewModel)
          .frame(minHeight: 0, maxHeight: .infinity)
        Divider()
        SheetTabsView(viewModel: viewModel)
      }

      VStack(spacing: 0) {
        FormattingToolbar(viewModel: viewModel, undoManager: undoManager)
        Divider()
        FormulaBarView(viewModel: viewModel, store: store)
        Divider()
        if viewModel.isFindBarVisible {
          FindReplaceBar(viewModel: viewModel)
          Divider()
        }
      }
      .frame(maxWidth: .infinity)
      .background(Color(nsColor: .controlBackgroundColor))

      if !viewModel.activeSheet.charts.isEmpty {
        HStack {
          Spacer()
          SpreadsheetChartsPanel(viewModel: viewModel)
            .padding(.top, SpreadsheetChrome.topHeight(
              showLabels: settings.showToolbarLabels,
              showingFormulaError: showingFormulaError,
              showingFindBar: viewModel.isFindBarVisible,
              formulaBarLineCount: formulaLines
            ) + 8)
            .padding(.trailing, 8)
        }
        .allowsHitTesting(true)
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
