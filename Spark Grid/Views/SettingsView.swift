import AppKit
import SwiftUI

struct SettingsView: View {
  @Bindable private var settings = AppSettings.shared
  @State private var recordingAction: HotkeyAction?
  @State private var recorderMonitor: Any?

  var body: some View {
    Form {
      Section("Autosave") {
        Toggle("Enable autosave", isOn: $settings.autosaveEnabled)

        if settings.autosaveEnabled {
          Picker("Save interval", selection: $settings.autosaveIntervalSeconds) {
            ForEach(AppSettings.autosaveIntervalOptions, id: \.self) { seconds in
              Text(AppSettings.label(forInterval: seconds)).tag(seconds)
            }
          }
        }
      }

      Section("Toolbar") {
        Toggle("Show icon names under toolbar buttons", isOn: $settings.showToolbarLabels)
      }

      Section("Scrolling") {
        Toggle("Invert scroll direction", isOn: $settings.invertScrollDirection)
      }

      Section("Keyboard Shortcuts") {
        ForEach(HotkeyAction.allCases) { action in
          HStack {
            Text(action.displayName)
            Spacer()
            Text(settings.shortcut(for: action).displayString)
              .foregroundStyle(.secondary)
              .monospaced()
            Button(recordingAction == action ? "Press keys…" : "Change") {
              beginRecording(action)
            }
            .buttonStyle(.bordered)
          }
        }

        Button("Reset to Defaults") {
          settings.resetShortcutsToDefaults()
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 460, height: 520)
    .padding()
    .onDisappear { stopRecording() }
  }

  private func beginRecording(_ action: HotkeyAction) {
    stopRecording()
    recordingAction = action
    recorderMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if let shortcut = StoredShortcut.from(event: event) {
        settings.setShortcut(shortcut, for: action)
        stopRecording()
        return nil
      }
      return event
    }
  }

  private func stopRecording() {
    if let monitor = recorderMonitor {
      NSEvent.removeMonitor(monitor)
      recorderMonitor = nil
    }
    recordingAction = nil
  }
}

#Preview {
  SettingsView()
}
