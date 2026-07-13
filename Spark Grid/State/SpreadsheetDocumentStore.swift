import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
final class SpreadsheetDocumentStore {
  var document = SpreadsheetDocument()
  /// Live grid view model for the open window; used by print and menu commands.
  var activeViewModel: SpreadsheetViewModel?
  var fileURL: URL?
  private(set) var isDirty = false
  private(set) var isAutosaving = false

  private var savedFingerprint: Data?
  private var autosaveTask: Task<Void, Never>?
  private var isForceClosing = false

  init() {
    savedFingerprint = try? JSONEncoder().encode(SpreadsheetDocument().workbook)
  }

  var displayTitle: String {
    let base = fileURL?.lastPathComponent ?? "Untitled"
    return isDirty ? "\(base) — Edited" : base
  }

  var hasOpenFile: Bool { fileURL != nil }

  var hasMultipleSheets: Bool {
    document.workbook.sheets.count > 1
  }

  var isXLSXFile: Bool {
    guard let fileURL else { return false }
    return fileURL.pathExtension.lowercased() == "xlsx"
  }

  func newDocument() {
    document = SpreadsheetDocument()
    fileURL = nil
    savedFingerprint = fingerprint(of: document.workbook)
    isDirty = false
    isAutosaving = false
    isForceClosing = false
  }

  func load(from url: URL) throws {
    document = try SpreadsheetDocument.load(from: url)
    fileURL = url
    savedFingerprint = fingerprint(of: document.workbook)
    isDirty = false
    isAutosaving = false
    noteRecent(url)
  }

  func save(to url: URL? = nil) throws {
    let destination = url ?? fileURL
    guard let destination else { return }
    if destination.pathExtension.lowercased() == "xlsx" {
      let data = try XLSXCodec.exportWorkbook(document.workbook)
      try data.write(to: destination, options: .atomic)
    } else {
      let csv = CSVCodec.exportCSV(from: document.workbook.activeSheet)
      try csv.write(to: destination, atomically: true, encoding: .utf8)
    }
    fileURL = destination
    savedFingerprint = fingerprint(of: document.workbook)
    isDirty = false
    noteRecent(destination)
  }

  func documentDidChange() {
    let dirty = computeDirtyState()
    guard dirty != isDirty else { return }
    isDirty = dirty
  }

  func autosaveIfNeeded() {
    guard AppSettings.shared.autosaveEnabled, fileURL != nil, isDirty else { return }
    performAutosave()
  }

  /// Prompts to save when closing with unsaved changes. Returns whether the app may close.
  @discardableResult
  func attemptClose() -> Bool {
    if isForceClosing { return true }
    guard isDirty else { return true }

    let alert = NSAlert()
    alert.messageText = "Do you want to save the changes you made?"
    let documentName = fileURL?.lastPathComponent ?? "Untitled"
    alert.informativeText = "Your changes to \"\(documentName)\" will be lost if you don't save."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Don't Save")
    alert.addButton(withTitle: "Cancel")

    switch alert.runModal() {
    case .alertFirstButtonReturn:
      guard saveInteractively() else { return false }
      return true
    case .alertSecondButtonReturn:
      isForceClosing = true
      return true
    default:
      return false
    }
  }

  @discardableResult
  func saveInteractively() -> Bool {
    if let url = fileURL {
      if !isXLSXFile, hasMultipleSheets, !confirmActiveSheetOnlySave() {
        return false
      }
      do {
        try save(to: url)
        return true
      } catch {
        presentSaveError(error)
        return false
      }
    }

    let panel = NSSavePanel()
    panel.allowedContentTypes = [.spreadsheetML, .commaSeparatedText]
    panel.nameFieldStringValue = suggestedSaveFilename()
    panel.canCreateDirectories = true
    panel.allowsOtherFileTypes = false
    panel.isExtensionHidden = false
    panel.title = "Save Spreadsheet"
    panel.message = "Choose Excel Workbook (.xlsx) to keep all sheets, or CSV for the active sheet only."
    guard panel.runModal() == .OK, let url = panel.url else { return false }

    if url.pathExtension.lowercased() != "xlsx", hasMultipleSheets, !confirmActiveSheetOnlySave() {
      return false
    }

    do {
      try save(to: url)
      return true
    } catch {
      presentSaveError(error)
      return false
    }
  }

  func restartAutosave() {
    autosaveTask?.cancel()
    autosaveTask = nil
    guard AppSettings.shared.autosaveEnabled else { return }

    autosaveTask = Task { [weak self] in
      while !Task.isCancelled {
        let interval = max(5, AppSettings.shared.autosaveIntervalSeconds)
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled else { return }
        await self?.performAutosave()
      }
    }
  }

  func stopAutosave() {
    autosaveTask?.cancel()
    autosaveTask = nil
  }

  // MARK: - Private

  private func performAutosave() {
    guard AppSettings.shared.autosaveEnabled, fileURL != nil, isDirty else { return }
    isAutosaving = true
    defer { isAutosaving = false }
    try? save()
  }

  private func computeDirtyState() -> Bool {
    guard let saved = savedFingerprint else {
      return !document.workbook.isEffectivelyEmpty
    }
    return fingerprint(of: document.workbook) != saved
  }

  private func fingerprint(of workbook: Workbook) -> Data? {
    try? JSONEncoder().encode(workbook)
  }

  private func noteRecent(_ url: URL) {
    NSDocumentController.shared.noteNewRecentDocumentURL(url)
  }

  private func suggestedSaveFilename() -> String {
    if let fileURL {
      return fileURL.lastPathComponent
    }
    let sheetName = document.workbook.activeSheet.name
    return "\(sheetName).xlsx"
  }

  private func confirmActiveSheetOnlySave() -> Bool {
    let sheetName = document.workbook.activeSheet.name
    let alert = NSAlert()
    alert.messageText = "Save Active Sheet Only?"
    alert.informativeText =
      "CSV files contain one sheet. Only \"\(sheetName)\" will be saved; other sheets in this workbook won't be included."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }

  private func presentSaveError(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = "Couldn't Save Spreadsheet"
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning
    alert.runModal()
  }
}
