import SwiftUI

struct SpreadsheetCommands: Commands {
  @FocusedValue(\.spreadsheetViewModel) private var viewModel: SpreadsheetViewModel?

  var body: some Commands {
    CommandGroup(replacing: .pasteboard) {
      Button("Cut") { viewModel?.cutSelection() }
        .keyboardShortcut("x", modifiers: .command)
        .disabled(viewModel == nil)
      Button("Copy") {
        if let text = viewModel?.copySelection() {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text, forType: .string)
        }
      }
      .keyboardShortcut("c", modifiers: .command)
      .disabled(viewModel == nil)
      Button("Paste") { viewModel?.pasteFromPasteboard() }
        .keyboardShortcut("v", modifiers: .command)
        .disabled(viewModel == nil)
    }

    CommandGroup(after: .pasteboard) {
      Button("Bold") { viewModel?.toggleBold() }
        .keyboardShortcut("b", modifiers: .command)
      Button("Italic") { viewModel?.toggleItalic() }
        .keyboardShortcut("i", modifiers: .command)
      Button("Underline") { viewModel?.toggleUnderline() }
        .keyboardShortcut("u", modifiers: .command)
    }
  }
}

import AppKit

private struct SpreadsheetViewModelFocusedValueKey: FocusedValueKey {
  typealias Value = SpreadsheetViewModel
}

extension FocusedValues {
  var spreadsheetViewModel: SpreadsheetViewModel? {
    get { self[SpreadsheetViewModelFocusedValueKey.self] }
    set { self[SpreadsheetViewModelFocusedValueKey.self] = newValue }
  }
}
