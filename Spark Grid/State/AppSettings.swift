import AppKit
import Foundation
import Observation

enum HotkeyAction: String, CaseIterable, Identifiable, Codable {
  case copy
  case cut
  case paste
  case undo
  case redo
  case save
  case bold
  case italic
  case underline

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .copy: return "Copy"
    case .cut: return "Cut"
    case .paste: return "Paste"
    case .undo: return "Undo"
    case .redo: return "Redo"
    case .save: return "Save"
    case .bold: return "Bold"
    case .italic: return "Italic"
    case .underline: return "Underline"
    }
  }
}

struct StoredShortcut: Codable, Equatable {
  var key: String
  var modifiers: UInt

  static let `default` = StoredShortcut(key: "", modifiers: 0)

  var displayString: String {
    guard !key.isEmpty else { return "—" }
    var parts: [String] = []
    let flags = NSEvent.ModifierFlags(rawValue: modifiers)
    if flags.contains(.control) { parts.append("⌃") }
    if flags.contains(.option) { parts.append("⌥") }
    if flags.contains(.shift) { parts.append("⇧") }
    if flags.contains(.command) { parts.append("⌘") }
    parts.append(key.uppercased())
    return parts.joined()
  }

  func matches(_ event: NSEvent) -> Bool {
    guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else { return false }
    let first = String(chars.prefix(1))
    guard first == key.lowercased() else { return false }
    let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
    return event.modifierFlags.intersection(relevant) == NSEvent.ModifierFlags(rawValue: modifiers).intersection(relevant)
  }
}

@Observable
@MainActor
final class AppSettings {
  static let shared = AppSettings()

  private let defaults = UserDefaults.standard
  private let invertScrollKey = "invertScrollDirection"
  private let toolbarLabelsKey = "showToolbarLabels"
  private let autosaveEnabledKey = "autosaveEnabled"
  private let autosaveIntervalKey = "autosaveIntervalSeconds"
  private let shortcutsKey = "keyboardShortcuts"

  static let autosaveIntervalOptions = [10, 30, 60, 120, 300]

  var invertScrollDirection: Bool {
    didSet { defaults.set(invertScrollDirection, forKey: invertScrollKey) }
  }

  var showToolbarLabels: Bool {
    didSet { defaults.set(showToolbarLabels, forKey: toolbarLabelsKey) }
  }

  var autosaveEnabled: Bool {
    didSet { defaults.set(autosaveEnabled, forKey: autosaveEnabledKey) }
  }

  var autosaveIntervalSeconds: Int {
    didSet { defaults.set(autosaveIntervalSeconds, forKey: autosaveIntervalKey) }
  }

  private var shortcuts: [HotkeyAction: StoredShortcut]

  private init() {
    invertScrollDirection = defaults.bool(forKey: invertScrollKey)
    showToolbarLabels = defaults.bool(forKey: toolbarLabelsKey)
    if defaults.object(forKey: autosaveEnabledKey) != nil {
      autosaveEnabled = defaults.bool(forKey: autosaveEnabledKey)
    } else {
      autosaveEnabled = true
    }
    let storedInterval = defaults.integer(forKey: autosaveIntervalKey)
    autosaveIntervalSeconds = Self.autosaveIntervalOptions.contains(storedInterval) ? storedInterval : 30
    if let data = defaults.data(forKey: shortcutsKey),
       let decoded = try? JSONDecoder().decode([HotkeyAction: StoredShortcut].self, from: data)
    {
      shortcuts = decoded
    } else {
      shortcuts = Self.defaultShortcuts
    }
    mergeMissingDefaults()
  }

  func shortcut(for action: HotkeyAction) -> StoredShortcut {
    shortcuts[action] ?? Self.defaultShortcuts[action] ?? .default
  }

  func setShortcut(_ shortcut: StoredShortcut, for action: HotkeyAction) {
    shortcuts[action] = shortcut
    persistShortcuts()
  }

  func resetShortcutsToDefaults() {
    shortcuts = Self.defaultShortcuts
    persistShortcuts()
  }

  func keyEquivalent(for action: HotkeyAction) -> KeyEquivalent {
    let key = shortcut(for: action).key
    guard let first = key.first else { return KeyEquivalent("a") }
    return KeyEquivalent(first)
  }

  func eventModifiers(for action: HotkeyAction) -> EventModifiers {
    let flags = NSEvent.ModifierFlags(rawValue: shortcut(for: action).modifiers)
    var mods = EventModifiers()
    if flags.contains(.command) { mods.insert(.command) }
    if flags.contains(.shift) { mods.insert(.shift) }
    if flags.contains(.option) { mods.insert(.option) }
    if flags.contains(.control) { mods.insert(.control) }
    return mods
  }

  func matches(_ action: HotkeyAction, event: NSEvent) -> Bool {
    shortcut(for: action).matches(event)
  }

  static func label(forInterval seconds: Int) -> String {
    switch seconds {
    case 10: return "Every 10 seconds"
    case 30: return "Every 30 seconds"
    case 60: return "Every minute"
    case 120: return "Every 2 minutes"
    case 300: return "Every 5 minutes"
    default: return "Every \(seconds) seconds"
    }
  }

  private func persistShortcuts() {
    guard let data = try? JSONEncoder().encode(shortcuts) else { return }
    defaults.set(data, forKey: shortcutsKey)
  }

  private func mergeMissingDefaults() {
    for (action, shortcut) in Self.defaultShortcuts where shortcuts[action] == nil {
      shortcuts[action] = shortcut
    }
  }

  private static let defaultShortcuts: [HotkeyAction: StoredShortcut] = [
    .copy: StoredShortcut(key: "c", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .cut: StoredShortcut(key: "x", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .paste: StoredShortcut(key: "v", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .undo: StoredShortcut(key: "z", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .redo: StoredShortcut(key: "z", modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue),
    .save: StoredShortcut(key: "s", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .bold: StoredShortcut(key: "b", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .italic: StoredShortcut(key: "i", modifiers: NSEvent.ModifierFlags.command.rawValue),
    .underline: StoredShortcut(key: "u", modifiers: NSEvent.ModifierFlags.command.rawValue),
  ]
}

import SwiftUI

extension StoredShortcut {
  static func from(event: NSEvent) -> StoredShortcut? {
    guard let chars = event.charactersIgnoringModifiers?.lowercased(), let first = chars.first else { return nil }
    let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
    let mods = event.modifierFlags.intersection(relevant).rawValue
    guard mods != 0 else { return nil }
    return StoredShortcut(key: String(first), modifiers: mods)
  }
}
