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
        saveDocument()
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

  private func saveDocument() {
    if store.hasMultipleSheets, !confirmActiveSheetOnlySave() {
      return
    }

    if let url = store.fileURL {
      try? store.save(to: url)
      return
    }

    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = suggestedFilename()
    guard panel.runModal() == .OK, let url = panel.url else { return }
    try? store.save(to: url)
  }

  private func suggestedFilename() -> String {
    let sheetName = store.document.workbook.activeSheet.name
    if store.fileURL != nil {
      return store.fileURL!.lastPathComponent
    }
    return "\(sheetName).csv"
  }

  private func confirmActiveSheetOnlySave() -> Bool {
    let sheetName = store.document.workbook.activeSheet.name
    let alert = NSAlert()
    alert.messageText = "Save Active Sheet Only?"
    alert.informativeText =
      "CSV files contain one sheet. Only \"\(sheetName)\" will be saved; other sheets in this workbook won't be included."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }
}

import AppKit
import UniformTypeIdentifiers
