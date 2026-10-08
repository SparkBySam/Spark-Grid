import AppKit

/// System spell checking for text being typed in the cell editor and formula bar.
/// `NSTextView` draws the Mac underline and the standard suggestions / Ignore / Learn menu.
/// No word list ships with the app.
enum EditorSpellCheck {
  /// Prose is checked. A formula that starts with `=` and a numeric literal are not.
  /// Callers pass the edit string, never a calculated formula result.
  static func shouldCheck(_ text: String) -> Bool {
    if FormulaSyntax.isFormula(text) { return false }
    if case .number = CellValue.fromLiteralRaw(text) { return false }
    return true
  }

  /// Turns continuous spell checking on or off for `text`.
  /// Automatic correction stays off so a suggestion never rewrites the cell by itself.
  /// `refresh` asks the system checker to mark the current text again after attributes were replaced.
  static func apply(to textView: NSTextView, text: String, refresh: Bool = false) {
    let enabled = shouldCheck(text)
    if textView.isAutomaticSpellingCorrectionEnabled {
      textView.isAutomaticSpellingCorrectionEnabled = false
    }
    if textView.isGrammarCheckingEnabled {
      textView.isGrammarCheckingEnabled = false
    }
    if textView.isContinuousSpellCheckingEnabled != enabled {
      textView.isContinuousSpellCheckingEnabled = enabled
    }
    guard enabled else {
      clearMarks(on: textView)
      return
    }
    if refresh {
      refreshMarks(on: textView)
    }
  }

  private static func clearMarks(on textView: NSTextView) {
    guard let layout = textView.layoutManager else { return }
    let length = (textView.string as NSString).length
    guard length > 0 else { return }
    layout.removeTemporaryAttribute(
      .spellingState,
      forCharacterRange: NSRange(location: 0, length: length)
    )
  }

  private static func refreshMarks(on textView: NSTextView) {
    let length = (textView.string as NSString).length
    guard length > 0 else { return }
    textView.checkText(
      in: NSRange(location: 0, length: length),
      types: NSTextCheckingResult.CheckingType.spelling.rawValue,
      options: [:]
    )
  }
}
