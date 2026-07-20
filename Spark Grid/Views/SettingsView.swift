import AppKit
import SwiftUI

struct SettingsView: View {
  @Bindable private var settings = AppSettings.shared
  @State private var recordingAction: HotkeyAction?
  @State private var recorderMonitor: Any?

  var body: some View {
    Form {
      Section("About") {
        LabeledContent("Spark Grid") {
          Text(versionLabel)
            .foregroundStyle(.secondary)
        }
        Text("Native Mac spreadsheet for Excel (.xlsx) and CSV files.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Section("Appearance") {
        Picker("Color scheme", selection: $settings.appearanceMode) {
          ForEach(AppearanceMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }

        Toggle("Show icon names under toolbar buttons", isOn: $settings.showToolbarLabels)
      }

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
    .frame(width: 460, height: 580)
    .padding()
    .preferredColorScheme(settings.appearanceMode.colorScheme)
    .onDisappear { stopRecording() }
  }

  private var versionLabel: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    return "Version \(version) (\(build))"
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
