import SwiftUI

struct SpreadsheetViewCommands: Commands {
  @FocusedValue(\.spreadsheetViewModel) private var viewModel: SpreadsheetViewModel?

  var body: some Commands {
    CommandMenu("View") {
      Button("Zoom In") { viewModel?.zoomIn() }
        .keyboardShortcut("+", modifiers: .command)
        .disabled(viewModel == nil)
      Button("Zoom Out") { viewModel?.zoomOut() }
        .keyboardShortcut("-", modifiers: .command)
        .disabled(viewModel == nil)
      Button("Actual Size") { viewModel?.zoomActualSize() }
        .keyboardShortcut("0", modifiers: .command)
        .disabled(viewModel == nil)
    }
  }
}
