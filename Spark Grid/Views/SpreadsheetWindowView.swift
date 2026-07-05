import AppKit
import SwiftUI

private enum SpreadsheetChrome {
  static let formulaBarHeight: CGFloat = 28
  static let dividerHeight: CGFloat = 1

  static func toolbarHeight(showLabels: Bool) -> CGFloat {
    58
  }

  static func topHeight(showLabels: Bool) -> CGFloat {
    toolbarHeight(showLabels: showLabels) + dividerHeight + formulaBarHeight + dividerHeight
  }
}

struct SpreadsheetWindowView: View {
  @Bindable var store: SpreadsheetDocumentStore
  @Environment(\.undoManager) private var undoManager
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
    ZStack(alignment: .top) {
      VStack(spacing: 0) {
        Color.clear.frame(height: SpreadsheetChrome.topHeight(showLabels: settings.showToolbarLabels))
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
      }
      .frame(maxWidth: .infinity)
      .background(Color(nsColor: .controlBackgroundColor))
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
      viewModel.selection = .origin
      viewModel.isEditing = false
      viewModel.syncEditTextFromSelection()
      onDocumentChanged()
    }
    .onAppear {
      viewModel.undoManager = undoManager
      if viewModel.workbook != store.document.workbook {
        viewModel.workbook = store.document.workbook
        viewModel.syncEditTextFromSelection()
      }
    }
    .onChange(of: undoManager) { _, newValue in
      viewModel.undoManager = newValue
    }
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
