import Foundation
import Observation

@Observable
@MainActor
final class SpreadsheetDocumentStore {
  var document = SpreadsheetDocument()
  var fileURL: URL?
  private(set) var isDirty = false
  private(set) var isAutosaving = false

  private var savedFingerprint: Data?
  private var autosaveTask: Task<Void, Never>?

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

  func newDocument() {
    document = SpreadsheetDocument()
    fileURL = nil
    savedFingerprint = fingerprint(of: document.workbook)
    isDirty = false
    isAutosaving = false
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
    let csv = CSVCodec.exportCSV(from: document.workbook.activeSheet)
    try csv.write(to: destination, atomically: true, encoding: .utf8)
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
}

import AppKit
