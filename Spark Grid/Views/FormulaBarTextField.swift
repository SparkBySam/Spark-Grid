import AppKit
import SwiftUI

/// AppKit formula bar using NSTextView so ref colors survive focus/editing.
struct FormulaBarTextField: NSViewRepresentable {
  @Binding var text: String
  /// Observed copy of the formula bar contents so in-cell typing mirrors here live.
  var liveText: String
  var namedRanges: [String]
  var highlights: [FormulaRefHighlight]
  var focusedHighlightIndex: Int?
  var visibleHeight: CGFloat = 18
  var onSubmit: (String) -> Void
  var onTextChange: () -> Void
  var onBeginEditing: () -> Void
  var onCaretMoved: (Int) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> FormulaBarContainerView {
    let container = FormulaBarContainerView()
    container.textView.delegate = context.coordinator
    context.coordinator.textView = container.textView
    container.textView.string = liveText
    container.setVisibleHeight(visibleHeight)
    context.coordinator.applyAttributes(force: true)
    return container
  }

  func updateNSView(_ nsView: FormulaBarContainerView, context: Context) {
    context.coordinator.parent = self
    context.coordinator.textView = nsView.textView
    nsView.setVisibleHeight(visibleHeight)

    let textView = nsView.textView
    let isFocused = textView.window?.firstResponder === textView

    // Mirror selection / in-cell typing whenever the bar isn't focused.
    if !isFocused, textView.string != liveText {
      textView.string = liveText
      context.coordinator.lastAppliedKey = ""
    }

    context.coordinator.applyAttributes(force: false)
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: FormulaBarTextField
    weak var textView: FormulaBarNSTextView?
    private var isApplyingAttributes = false
    private var isSubmitting = false
    var lastAppliedKey = ""
    private var didBeginEditing = false

    init(_ parent: FormulaBarTextField) {
      self.parent = parent
    }

    private func highlightKey(for text: String) -> String {
      let spans = parent.highlights.map {
        "\($0.utf16Range.location):\($0.utf16Range.length):\($0.colorIndex)"
      }.joined(separator: ",")
      return "\(text)|\(parent.focusedHighlightIndex ?? -1)|\(spans)"
    }

    func applyAttributes(force: Bool) {
      guard let textView, let storage = textView.textStorage else { return }
      let raw = textView.string
      let key = highlightKey(for: raw)
      if !force, key == lastAppliedKey { return }
      guard !isApplyingAttributes else { return }

      isApplyingAttributes = true
      defer { isApplyingAttributes = false }

      let font = textView.font
        ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
      let color = NSColor.labelColor
      let attributed = FormulaReferenceScanner.attributedFormula(
        raw,
        highlights: parent.highlights,
        focusedIndex: parent.focusedHighlightIndex,
        baseFont: font,
        baseColor: color
      )

      let selected = textView.selectedRange
      storage.beginEditing()
      storage.setAttributedString(attributed)
      storage.endEditing()
      textView.typingAttributes = [
        .font: font,
        .foregroundColor: color,
        .backgroundColor: NSColor.clear,
      ]

      let maxLen = storage.length
      let loc = min(selected.location, maxLen)
      let len = min(selected.length, max(0, maxLen - loc))
      let next = NSRange(location: loc, length: len)
      if textView.selectedRange != next {
        textView.setSelectedRange(next)
      }
      lastAppliedKey = key
    }

    func textDidBeginEditing(_ notification: Notification) {
      guard !didBeginEditing else { return }
      didBeginEditing = true
      parent.onBeginEditing()
      lastAppliedKey = ""
      applyAttributes(force: true)
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.lastAppliedKey = ""
        self.applyAttributes(force: true)
        self.emitCaret()
      }
    }

    func textDidEndEditing(_ notification: Notification) {
      didBeginEditing = false
      guard !isSubmitting, let textView else { return }
      let value = textView.string
      parent.text = value
      parent.onSubmit(value)
    }

    func textDidChange(_ notification: Notification) {
      guard let textView, !isApplyingAttributes else { return }
      parent.text = textView.string
      parent.onTextChange()
      lastAppliedKey = ""
      applyAttributes(force: true)
      emitCaret()
      maybeOfferCompletions()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard !isApplyingAttributes else { return }
      emitCaret()
      DispatchQueue.main.async { [weak self] in
        self?.applyAttributes(force: false)
      }
    }

    func textView(
      _ textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      if commandSelector == #selector(NSResponder.insertNewline(_:))
        || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
      {
        // Option+Return inserts a line break (Excel Alt+Enter); Return commits.
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
          textView.insertText("\n", replacementRange: textView.selectedRange)
          return true
        }
        submit()
        return true
      }
      if commandSelector == #selector(NSResponder.insertTab(_:)) {
        return applyTabCompletion()
      }
      return false
    }

    func textView(
      _ textView: NSTextView,
      completions words: [String],
      forPartialWordRange charRange: NSRange,
      indexOfSelectedItem index: UnsafeMutablePointer<Int>?
    ) -> [String] {
      guard textView.string.hasPrefix("=") else { return [] }
      guard FormulaAutocomplete.shouldOfferPopup(
        in: textView.string,
        utf16Cursor: charRange.location + charRange.length,
        namedRanges: parent.namedRanges
      ) else { return [] }
      let partial = (textView.string as NSString).substring(with: charRange)
      index?.pointee = 0
      return FormulaAutocomplete.suggestions(
        matching: partial,
        namedRanges: parent.namedRanges
      )
    }

    private func emitCaret() {
      guard let textView else { return }
      parent.onCaretMoved(textView.selectedRange.location)
    }

    private func submit() {
      guard let textView else { return }
      let value = textView.string
      parent.text = value
      isSubmitting = true
      parent.onSubmit(value)
      resignToGrid()
      isSubmitting = false
      didBeginEditing = false
    }

    private func resignToGrid() {
      guard let window = textView?.window else { return }
      if let grid = findSpreadsheetGrid(in: window.contentView) {
        window.makeFirstResponder(grid)
      } else {
        window.makeFirstResponder(nil)
      }
    }

    private func findSpreadsheetGrid(in view: NSView?) -> NSView? {
      guard let view else { return nil }
      if view is SpreadsheetGridNSView { return view }
      for child in view.subviews {
        if let found = findSpreadsheetGrid(in: child) { return found }
      }
      return nil
    }

    private func applyTabCompletion() -> Bool {
      guard let textView else { return false }
      guard let result = FormulaAutocomplete.tabComplete(
        text: textView.string,
        utf16Cursor: textView.selectedRange.location,
        namedRanges: parent.namedRanges
      ) else { return false }
      textView.string = result.text
      textView.setSelectedRange(NSRange(location: result.cursor, length: 0))
      parent.text = result.text
      parent.onTextChange()
      lastAppliedKey = ""
      applyAttributes(force: true)
      emitCaret()
      return true
    }

    private func maybeOfferCompletions() {
      guard let textView else { return }
      let cursor = textView.selectedRange.location
      guard FormulaAutocomplete.shouldOfferPopup(
        in: textView.string,
        utf16Cursor: cursor,
        namedRanges: parent.namedRanges
      ) else {
        NSObject.cancelPreviousPerformRequests(
          withTarget: self,
          selector: #selector(triggerComplete),
          object: nil
        )
        return
      }
      NSObject.cancelPreviousPerformRequests(
        withTarget: self,
        selector: #selector(triggerComplete),
        object: nil
      )
      perform(#selector(triggerComplete), with: nil, afterDelay: 0.12)
    }

    @objc private func triggerComplete() {
      guard let textView, !isApplyingAttributes else { return }
      textView.complete(nil)
    }
  }
}

/// Hosts the formula-bar text view with a stable width in SwiftUI stacks.
final class FormulaBarContainerView: NSView {
  let textView = FormulaBarNSTextView()
  private var visibleHeight: CGFloat = 18

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    setup()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setVisibleHeight(_ height: CGFloat) {
    let next = max(18, height)
    guard abs(visibleHeight - next) > 0.5 else { return }
    visibleHeight = next
    // Document can grow taller than the viewport so multiline cells scroll when collapsed.
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    invalidateIntrinsicContentSize()
    needsLayout = true
  }

  private func setup() {
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.backgroundColor = .clear
    scroll.borderType = .noBorder
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = false
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    scroll.translatesAutoresizingMaskIntoConstraints = false

    textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    textView.textColor = .labelColor
    textView.backgroundColor = .clear
    textView.drawsBackground = false
    textView.isRichText = true
    textView.allowsUndo = true
    textView.isEditable = true
    textView.isSelectable = true
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.textContainer?.lineFragmentPadding = 2
    textView.textContainerInset = NSSize(width: 0, height: 1)
    textView.minSize = .zero
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.insertionPointColor = .labelColor
    textView.focusRingType = .none
    textView.autoresizingMask = [.width]

    scroll.documentView = textView
    addSubview(scroll)

    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
      scroll.topAnchor.constraint(equalTo: topAnchor),
      scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: visibleHeight)
  }

  override func layout() {
    super.layout()
    // Keep the text view as wide as the visible clip so wrapping/clipping is correct.
    if let clip = textView.enclosingScrollView?.contentView {
      var frame = textView.frame
      frame.size.width = max(clip.bounds.width, 1)
      let usedHeight: CGFloat
      if let container = textView.textContainer,
         let layoutManager = textView.layoutManager {
        usedHeight = layoutManager.usedRect(for: container).height
      } else {
        usedHeight = visibleHeight
      }
      frame.size.height = max(visibleHeight, usedHeight)
      textView.frame = frame
      textView.textContainer?.containerSize = NSSize(
        width: max(clip.bounds.width - 4, 1),
        height: CGFloat.greatestFiniteMagnitude
      )
    }
  }
}

final class FormulaBarNSTextView: NSTextView {
  override var acceptsFirstResponder: Bool { true }

  override func becomeFirstResponder() -> Bool {
    let ok = super.becomeFirstResponder()
    if ok {
      isRichText = true
    }
    return ok
  }

  override func paste(_ sender: Any?) {
    pasteAsPlainText(sender)
  }
}
