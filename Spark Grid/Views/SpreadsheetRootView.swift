import SwiftUI

struct SpreadsheetRootView: View {
  @Bindable var store: SpreadsheetDocumentStore
  @Bindable private var settings = AppSettings.shared
  @State private var showAbout = false

  var body: some View {
    SpreadsheetWindowView(store: store) {
      store.documentDidChange()
    }
    .id(store.fileURL?.absoluteString ?? "untitled")
    .preferredColorScheme(settings.appearanceMode.colorScheme)
    .aboutPanel(isPresented: $showAbout)
    .onReceive(NotificationCenter.default.publisher(for: AppUINotifications.showAbout)) { _ in
      showAbout = true
    }
    .onChange(of: store.displayTitle) { _, title in
      WindowTitleUpdater.apply(title: title)
    }
    .onChange(of: store.isDirty) { _, _ in
      WindowTitleUpdater.apply(title: store.displayTitle)
    }
    .onChange(of: settings.autosaveEnabled) { _, _ in
      store.restartAutosave()
    }
    .onChange(of: settings.autosaveIntervalSeconds) { _, _ in
      store.restartAutosave()
    }
  }
}

#Preview {
  SpreadsheetRootView(store: SpreadsheetDocumentStore())
}
