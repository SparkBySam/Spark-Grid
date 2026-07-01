import SwiftUI

struct SpreadsheetFileCommands: Commands {
  @Bindable var store: SpreadsheetDocumentStore

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
        saveDocument()
      }
      .keyboardShortcut("s", modifiers: .command)
      .disabled(store.document.workbook.activeSheet.cells.isEmpty && store.fileURL == nil)
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

  private func saveDocument() {
    if let url = store.fileURL {
      try? store.save(to: url)
      return
    }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = "Untitled.csv"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    try? store.save(to: url)
  }
}

import AppKit
import UniformTypeIdentifiers
