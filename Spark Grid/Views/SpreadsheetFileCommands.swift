import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

      Button("Save As…") {
        saveAsPanel()
      }
      .keyboardShortcut("s", modifiers: [.command, .shift])
    }
  }

  private func openPanel() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.spreadsheetML, .commaSeparatedText, .plainText]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    try? store.load(from: url)
  }

  private func saveAsPanel() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.spreadsheetML, .commaSeparatedText]
    panel.nameFieldStringValue = store.fileURL?.lastPathComponent
      ?? "\(store.document.workbook.activeSheet.name).xlsx"
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    // Format popup lists UTI descriptions: Excel Workbook vs Comma Separated Values.
    guard panel.runModal() == .OK, let url = panel.url else { return }
    if url.pathExtension.lowercased() != "xlsx",
       store.hasMultipleSheets,
       !confirmCSVOnly()
    {
      return
    }
    try? store.save(to: url)
  }

  private func confirmCSVOnly() -> Bool {
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
