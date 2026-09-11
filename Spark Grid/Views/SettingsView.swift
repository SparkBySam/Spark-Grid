import AppKit
import SwiftUI

struct SettingsView: View {
  @Bindable private var settings = AppSettings.shared
  @State private var recordingAction: HotkeyAction?
  @State private var recorderMonitor: Any?
  @State private var showAbout = false

  var body: some View {
    Form {
      Section("Appearance") {
        Picker("Color scheme", selection: $settings.appearanceMode) {
          ForEach(AppearanceMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }

        Toggle("Show icon names under toolbar buttons", isOn: $settings.showToolbarLabels)
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

      Section("About") {
        Button("About Spark Grid…") {
          showAbout = true
        }
        Button("Send Feedback…") {
          LegalLinks.openFeedback()
        }
        Button("Terms of Use & Licenses") {
          LegalLinks.openTermsOfUse()
        }
        Button("Spark Suite") {
          LegalLinks.openSparkSuite()
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 460, height: 520)
    .padding()
    .preferredColorScheme(settings.appearanceMode.colorScheme)
    .aboutPanel(isPresented: $showAbout)
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
