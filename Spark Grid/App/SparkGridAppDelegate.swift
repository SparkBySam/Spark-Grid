import AppKit
import SwiftUI

/// Intercepts `print:` in the responder chain for SwiftUI apps that don't adopt NSDocument printing.
private final class PrintingResponder: NSResponder {
  weak var appDelegate: SparkGridAppDelegate?

  @objc func print(_ sender: Any?) {
    appDelegate?.printDocument(sender)
  }
}

private struct SparkGridAppDelegateKey: EnvironmentKey {
  static let defaultValue: SparkGridAppDelegate? = nil
}

extension EnvironmentValues {
  var sparkGridAppDelegate: SparkGridAppDelegate? {
    get { self[SparkGridAppDelegateKey.self] }
    set { self[SparkGridAppDelegateKey.self] = newValue }
  }
}

final class SparkGridAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  var onOpenFile: ((URL) -> Void)? {
    didSet { flushPendingOpenURL() }
  }
  weak var documentStore: SpreadsheetDocumentStore? {
    didSet { flushPendingOpenURL() }
  }
  var spreadsheetViewModel: SpreadsheetViewModel?
  private var pendingOpenURL: URL?

  private var printingResponder: PrintingResponder?
  private var printKeyMonitor: Any?

  func application(_ application: NSApplication, open urls: [URL]) {
    guard let url = urls.first else { return }
    openExternalFile(url)
  }

  private func openExternalFile(_ url: URL) {
    if let onOpenFile {
      onOpenFile(url)
    } else if let documentStore {
      do {
        try documentStore.load(from: url)
      } catch {
        pendingOpenURL = url
        let alert = NSAlert()
        alert.messageText = "Couldn't Open File"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
      }
    } else {
      pendingOpenURL = url
    }
  }

  private func flushPendingOpenURL() {
    guard let pending = pendingOpenURL else { return }
    if let onOpenFile {
      pendingOpenURL = nil
      onOpenFile(pending)
    } else if let documentStore {
      pendingOpenURL = nil
      do {
        try documentStore.load(from: pending)
      } catch {
        let alert = NSAlert()
        alert.messageText = "Couldn't Open File"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
      }
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    installPrintKeyMonitor()
    configureMainWindow()
    configurePrintMenu()
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    configureMainWindow()
    configurePrintMenu()
  }

  func applicationWillTerminate(_ notification: Notification) {
    if let printKeyMonitor {
      NSEvent.removeMonitor(printKeyMonitor)
      self.printKeyMonitor = nil
    }
  }

  private func installPrintKeyMonitor() {
    guard printKeyMonitor == nil else { return }
    printKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return event }
      guard event.modifierFlags.contains(.command),
            !event.modifierFlags.contains(.shift),
            !event.modifierFlags.contains(.option),
            event.charactersIgnoringModifiers?.lowercased() == "p" else {
        return event
      }
      self.printDocument(nil)
      return nil
    }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let documentStore else { return .terminateNow }
    return documentStore.attemptClose() ? .terminateNow : .terminateCancel
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard let documentStore else { return true }
    return documentStore.attemptClose()
  }

  func resolvedSpreadsheetViewModel() -> SpreadsheetViewModel? {
    if let spreadsheetViewModel { return spreadsheetViewModel }
    guard let documentStore else { return nil }
    if let activeViewModel = documentStore.activeViewModel { return activeViewModel }
    return SpreadsheetViewModel(workbook: documentStore.document.workbook)
  }

  func registerSpreadsheetViewModel(_ viewModel: SpreadsheetViewModel, store: SpreadsheetDocumentStore) {
    spreadsheetViewModel = viewModel
    documentStore = store
    store.activeViewModel = viewModel
  }

  func unregisterSpreadsheetViewModel(_ viewModel: SpreadsheetViewModel, store: SpreadsheetDocumentStore) {
    if spreadsheetViewModel === viewModel {
      spreadsheetViewModel = nil
    }
    if store.activeViewModel === viewModel {
      store.activeViewModel = nil
    }
  }

  @objc func print(_ sender: Any?) {
    printDocument(sender)
  }

  @objc func printDocument(_ sender: Any?) {
    guard let spreadsheetViewModel = resolvedSpreadsheetViewModel() else {
      let alert = NSAlert()
      alert.messageText = "Can’t Print"
      alert.informativeText = "Open a spreadsheet window before printing."
      alert.alertStyle = .warning
      alert.addButton(withTitle: "OK")
      alert.runModal()
      return
    }
    SpreadsheetPrintController.printActiveSheet(
      from: spreadsheetViewModel,
      in: NSApp.keyWindow ?? NSApp.mainWindow
    )
  }

  private func configureMainWindow() {
    for window in NSApp.windows where window.canBecomeMain {
      if window.delegate !== self {
        window.delegate = self
      }
      installPrintingResponder(in: window)
    }
  }

  private func installPrintingResponder(in window: NSWindow) {
    if printingResponder == nil {
      let responder = PrintingResponder()
      responder.appDelegate = self
      printingResponder = responder
    }
    guard let printingResponder, window.nextResponder !== printingResponder else { return }
    printingResponder.nextResponder = window.nextResponder
    window.nextResponder = printingResponder
  }

  private func configurePrintMenu() {
    guard let mainMenu = NSApp.mainMenu else { return }
    for menuItem in mainMenu.items {
      guard let submenu = menuItem.submenu else { continue }
      for item in submenu.items {
        let isPrintKey = item.keyEquivalent == "p"
          && item.keyEquivalentModifierMask.contains(.command)
          && !item.keyEquivalentModifierMask.contains(.shift)
          && !item.keyEquivalentModifierMask.contains(.option)
          && !item.keyEquivalentModifierMask.contains(.control)
        let isPrintAction = item.action == Selector("print:")
          || item.action == #selector(printDocument(_:))
          || item.action == #selector(print(_:))
          || item.title == "Print…"
          || item.title == "Print..."
        guard isPrintKey || isPrintAction else { continue }
        item.target = self
        item.action = #selector(printDocument(_:))
      }
    }
  }
}
