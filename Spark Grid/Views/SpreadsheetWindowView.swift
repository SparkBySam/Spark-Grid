import AppKit
import SwiftUI

private enum SpreadsheetChrome {
  static let toolbarHeight: CGFloat = 44
  static let formulaBarHeight: CGFloat = 28
  static let dividerHeight: CGFloat = 1
  static var topHeight: CGFloat {
    toolbarHeight + dividerHeight + formulaBarHeight + dividerHeight
  }
}

struct SpreadsheetWindowView: View {
  @Binding var document: SpreadsheetDocument
  let windowTitle: String
  @Environment(\.undoManager) private var undoManager

  @State private var viewModel: SpreadsheetViewModel

  init(document: Binding<SpreadsheetDocument>, windowTitle: String = "Spark Sheets") {
    _document = document
    self.windowTitle = windowTitle
    _viewModel = State(initialValue: SpreadsheetViewModel(workbook: document.wrappedValue.workbook))
  }

  var body: some View {
    ZStack(alignment: .top) {
      VStack(spacing: 0) {
        Color.clear.frame(height: SpreadsheetChrome.topHeight)
        SpreadsheetGridView(viewModel: viewModel)
          .frame(minHeight: 0, maxHeight: .infinity)
        Divider()
        SheetTabsView(sheetName: viewModel.activeSheet.name)
      }

      VStack(spacing: 0) {
        FormattingToolbar(viewModel: viewModel, undoManager: undoManager)
        Divider()
        FormulaBarView(viewModel: viewModel)
        Divider()
      }
      .frame(maxWidth: .infinity)
      .background(Color(nsColor: .controlBackgroundColor))
    }
    .focusedValue(\.spreadsheetViewModel, viewModel)
    .onChange(of: windowTitle) { _, title in
      WindowTitleUpdater.apply(title: title)
    }
    .onAppear {
      WindowTitleUpdater.apply(title: windowTitle)
    }
    .onChange(of: viewModel.workbook) { _, newValue in
      guard document.workbook != newValue else { return }
      document.workbook = newValue
    }
    .onChange(of: document.workbook) { _, newValue in
      guard newValue != viewModel.workbook else { return }
      viewModel.workbook = newValue
      viewModel.selection = .origin
      viewModel.isEditing = false
      viewModel.syncEditTextFromSelection()
    }
    .onAppear {
      viewModel.undoManager = undoManager
      if viewModel.workbook != document.workbook {
        viewModel.workbook = document.workbook
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
  SpreadsheetWindowView(document: .constant(SpreadsheetDocument()))
}
