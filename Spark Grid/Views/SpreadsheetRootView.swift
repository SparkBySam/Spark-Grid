import SwiftUI

struct SpreadsheetRootView: View {
  @Bindable var store: SpreadsheetDocumentStore

  var body: some View {
    SpreadsheetWindowView(document: $store.document, windowTitle: store.windowTitle)
      .id(store.fileURL?.absoluteString ?? "untitled")
  }
}

#Preview {
  SpreadsheetRootView(store: SpreadsheetDocumentStore())
}
