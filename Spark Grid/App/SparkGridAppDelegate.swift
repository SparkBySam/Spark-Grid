import AppKit
import SwiftUI

final class SparkGridAppDelegate: NSObject, NSApplicationDelegate {
  var onOpenFile: ((URL) -> Void)?
  weak var documentStore: SpreadsheetDocumentStore?

  func application(_ application: NSApplication, open urls: [URL]) {
    guard let url = urls.first else { return }
    onOpenFile?(url)
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    documentStore?.autosaveIfNeeded()
    return .terminateNow
  }
}
