import AppKit
import SwiftUI

struct SpreadsheetCommands: Commands {
  @Bindable private var settings = AppSettings.shared
  @FocusedValue(\.spreadsheetViewModel) private var viewModel: SpreadsheetViewModel?

  var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button("About Spark Grid") {
        Self.showAbout()
      }
    }

    CommandGroup(replacing: .undoRedo) {
      Button("Undo") { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
        .keyboardShortcut(settings.keyEquivalent(for: .undo), modifiers: settings.eventModifiers(for: .undo))
      Button("Redo") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
        .keyboardShortcut(settings.keyEquivalent(for: .redo), modifiers: settings.eventModifiers(for: .redo))
    }

    CommandGroup(replacing: .pasteboard) {
      Button("Cut") { viewModel?.cutSelection() }
        .keyboardShortcut(settings.keyEquivalent(for: .cut), modifiers: settings.eventModifiers(for: .cut))
        .disabled(viewModel == nil)
      Button("Copy") {
        if let text = viewModel?.copySelection() {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text, forType: .string)
        }
      }
      .keyboardShortcut(settings.keyEquivalent(for: .copy), modifiers: settings.eventModifiers(for: .copy))
      .disabled(viewModel == nil)
      Button("Paste") { viewModel?.pasteFromPasteboard() }
        .keyboardShortcut(settings.keyEquivalent(for: .paste), modifiers: settings.eventModifiers(for: .paste))
        .disabled(viewModel == nil)

      Divider()

      Button("Copy Formulas") { viewModel?.copyFormulas() }
        .keyboardShortcut(
          settings.keyEquivalent(for: .copyFormulas),
          modifiers: settings.eventModifiers(for: .copyFormulas)
        )
        .disabled(viewModel == nil)
      Button("Paste Formulas") { viewModel?.pasteFormulasFromPasteboard() }
        .keyboardShortcut(
          settings.keyEquivalent(for: .pasteFormulas),
          modifiers: settings.eventModifiers(for: .pasteFormulas)
        )
        .disabled(viewModel == nil)

      Button("Convert to Values") { viewModel?.convertSelectionToValues() }
        .keyboardShortcut(
          settings.keyEquivalent(for: .convertToValues),
          modifiers: settings.eventModifiers(for: .convertToValues)
        )
        .disabled(viewModel == nil)
    }

    CommandGroup(after: .pasteboard) {
      Button("Select All") { viewModel?.selectAll() }
        .keyboardShortcut("a", modifiers: .command)
        .disabled(viewModel == nil)

      Divider()

      Button("Find…") { viewModel?.toggleFindBar(replace: false) }
        .keyboardShortcut("f", modifiers: .command)
        .disabled(viewModel == nil)
      Button("Find and Replace…") { viewModel?.toggleFindBar(replace: true) }
        .keyboardShortcut("f", modifiers: [.command, .option])
        .disabled(viewModel == nil)
      Button("Find Next") { viewModel?.findNext() }
        .keyboardShortcut("g", modifiers: .command)
        .disabled(viewModel == nil)
      Button("Find Previous") { viewModel?.findPrevious() }
        .keyboardShortcut("g", modifiers: [.command, .shift])
        .disabled(viewModel == nil)
    }
  }

  private static func showAbout() {
    let alert = NSAlert()
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    alert.messageText = "Spark Grid"
    alert.informativeText = "Version \(version) (\(build))\n\nA native Mac spreadsheet for opening, editing, and saving Excel workbooks and CSV files."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}

private struct SpreadsheetViewModelFocusedValueKey: FocusedValueKey {
  typealias Value = SpreadsheetViewModel
}

extension FocusedValues {
  var spreadsheetViewModel: SpreadsheetViewModel? {
    get { self[SpreadsheetViewModelFocusedValueKey.self] }
    set { self[SpreadsheetViewModelFocusedValueKey.self] = newValue }
  }
}
