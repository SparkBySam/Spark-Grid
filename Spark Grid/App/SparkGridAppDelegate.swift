import AppKit
import SwiftUI

final class SparkGridAppDelegate: NSObject, NSApplicationDelegate {
  var onOpenFile: ((URL) -> Void)?

  func application(_ application: NSApplication, open urls: [URL]) {
    guard let url = urls.first else { return }
    onOpenFile?(url)
  }
}
