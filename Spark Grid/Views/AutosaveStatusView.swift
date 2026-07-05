import SwiftUI

struct AutosaveStatusView: View {
  @Bindable var store: SpreadsheetDocumentStore
  @Bindable private var settings = AppSettings.shared

  var body: some View {
    Group {
      if !settings.autosaveEnabled {
        Image(systemName: "icloud.slash")
          .foregroundStyle(.secondary)
      } else if store.isAutosaving {
        ProgressView()
          .controlSize(.small)
          .scaleEffect(0.75)
      } else if !store.hasOpenFile {
        Image(systemName: "icloud")
          .foregroundStyle(.tertiary)
      } else if store.isDirty {
        Image(systemName: "icloud.and.arrow.up")
          .foregroundStyle(.secondary)
          .symbolEffect(.pulse, options: .repeating)
      } else {
        Image(systemName: "checkmark.icloud")
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 20, height: 20)
    .help(helpText)
  }

  private var helpText: String {
    if !settings.autosaveEnabled {
      return "Autosave is off"
    }
    if store.isAutosaving {
      return "Autosaving…"
    }
    if !store.hasOpenFile {
      return "Save this document to enable autosave"
    }
    if store.isDirty {
      return "Unsaved changes — autosaves \(AppSettings.label(forInterval: settings.autosaveIntervalSeconds).lowercased())"
    }
    return "All changes saved — autosaves \(AppSettings.label(forInterval: settings.autosaveIntervalSeconds).lowercased())"
  }
}

#Preview {
  AutosaveStatusView(store: SpreadsheetDocumentStore())
    .padding()
}
