//
//  Spark_GridApp.swift
//  Spark Grid
//

import SwiftUI

@main
struct Spark_GridApp: App {
  @NSApplicationDelegateAdaptor(SparkGridAppDelegate.self) private var appDelegate
  @State private var store = SpreadsheetDocumentStore()

  var body: some Scene {
    WindowGroup(id: "main") {
      SpreadsheetRootView(store: store)
        .environment(\.sparkGridAppDelegate, appDelegate)
        .onAppear {
          appDelegate.documentStore = store
          store.restartAutosave()
          appDelegate.onOpenFile = { url in
            Task { @MainActor in
              try? store.load(from: url)
            }
          }
        }
        .onOpenURL { url in
          Task { @MainActor in
            try? store.load(from: url)
          }
        }
    }
    .defaultSize(width: 1280, height: 800)
    .commands {
      SpreadsheetCommands()
      SpreadsheetStructureCommands()
      SpreadsheetFileCommands(store: store)
    }

    Settings {
      SettingsView()
    }
  }
}
