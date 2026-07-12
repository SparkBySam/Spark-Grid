import SwiftUI

struct SpreadsheetFileCommands: Commands {
  @Bindable var store: SpreadsheetDocumentStore
  @Bindable private var settings = AppSettings.shared

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("New Spreadsheet") {
        store.newDocument()
      }
      .keyboardShortcut("n", modifiers: .command)
    }

    CommandGroup(after: .newItem) {
      Button("Open…") {
        openPanel()
      }
      .keyboardShortcut("o", modifiers: .command)

      Button("Save") {
        _ = store.saveInteractively()
      }
      .keyboardShortcut(settings.keyEquivalent(for: .save), modifiers: settings.eventModifiers(for: .save))
      .disabled(
        (store.fileURL == nil && store.document.workbook.isEffectivelyEmpty)
          || (store.fileURL != nil && !store.isDirty)
      )
    }
  }

  private func openPanel() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.commaSeparatedText, .plainText]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    try? store.load(from: url)
  }
}

import AppKit
import UniformTypeIdentifiers
