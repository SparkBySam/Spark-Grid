import SwiftUI

struct SpreadsheetPrintSetupView: View {
  @Bindable var viewModel: SpreadsheetViewModel
  @State private var options: SpreadsheetPrintOptions
  @State private var formattingExpanded = true
  @State private var headersExpanded = true
  let onCancel: () -> Void
  let onPrint: (SpreadsheetPrintOptions) -> Void

  init(
    viewModel: SpreadsheetViewModel,
    options: SpreadsheetPrintOptions,
    onCancel: @escaping () -> Void,
    onPrint: @escaping (SpreadsheetPrintOptions) -> Void
  ) {
    self._viewModel = Bindable(wrappedValue: viewModel)
    _options = State(initialValue: options)
    self.onCancel = onCancel
    self.onPrint = onPrint
  }

  private var pages: [SpreadsheetPrintPage] {
    viewModel.commitEditIfNeeded()
    return options.pages(for: viewModel)
  }

  private var previewContent: SpreadsheetPrintPreviewContent {
    SpreadsheetPrintPreviewContent(
      contentRevision: viewModel.contentRevision,
      options: options,
      pages: pages,
      workbook: viewModel.workbook
    )
  }

  private var rangeSummary: String {
    guard let page = pages.first else { return "No content" }
    let range = page.range.normalized
    let start = CellAddress(row: range.minRow, col: range.minCol).a1
    let end = CellAddress(row: range.maxRow, col: range.maxCol).a1
    if start == end { return start }
    return "\(start):\(end)"
  }

  private var hasFrozenRows: Bool { viewModel.activeSheet.frozenRows > 0 }
  private var hasFrozenColumns: Bool { viewModel.activeSheet.frozenColumns > 0 }

  var body: some View {
    HStack(spacing: 0) {
      previewPane
      Divider()
      settingsPane
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var previewPane: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Print settings")
          .font(.title3.weight(.semibold))
        Spacer()
        Text(scopeLabel)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 20)
      .padding(.top, 16)
      .padding(.bottom, 8)

      if pages.isEmpty {
        ContentUnavailableView(
          "Nothing to print",
          systemImage: "printer",
          description: Text("Choose a different print range.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        SpreadsheetPrintPagePreview(content: previewContent)
          .id(previewContent.renderToken)
          .padding(.bottom, 8)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var scopeLabel: String {
    switch options.scope {
    case .selectedCells:
      return "Printing \(rangeSummary)"
    case .populatedCells:
      return "Printing current sheet"
    case .wholeSheet:
      return "Printing whole sheet"
    case .workbook:
      return "Printing workbook"
    }
  }

  private var settingsPane: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          settingsField("Print") {
            Picker("Print", selection: $options.scope) {
              ForEach(SpreadsheetPrintScope.allCases) { scope in
                if options.canUseScope(scope, viewModel: viewModel) {
                  Text(scope.rawValue).tag(scope)
                }
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
          }

          settingsField("Paper size") {
            Picker("Paper size", selection: $options.paper) {
              ForEach(SpreadsheetPrintPaper.allCases) { paper in
                Text(paper.rawValue).tag(paper)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
          }

          settingsField("Page orientation") {
            Picker("Page orientation", selection: $options.isLandscape) {
              Text("Portrait").tag(false)
              Text("Landscape").tag(true)
            }
            .pickerStyle(.radioGroup)
          }

          settingsField("Scale") {
            Picker("Scale", selection: $options.scale) {
              ForEach(SpreadsheetPrintScale.allCases) { scale in
                Text(scale.rawValue).tag(scale)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
          }

          settingsField("Margins") {
            Picker("Margins", selection: $options.margins) {
              ForEach(SpreadsheetPrintMarginPreset.allCases) { preset in
                Text(preset.rawValue).tag(preset)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
          }

          Divider()

          disclosureSection("Formatting", isExpanded: $formattingExpanded) {
            Toggle("Show gridlines", isOn: $options.showGridlines)
            settingsField("Page order") {
              Picker("Page order", selection: $options.pageOrder) {
                ForEach(SpreadsheetPrintPageOrder.allCases) { order in
                  Text(order.rawValue).tag(order)
                }
              }
              .labelsHidden()
              .pickerStyle(.menu)
            }
          }

          Divider()

          VStack(alignment: .leading, spacing: 10) {
            Text("Alignment")
              .font(.subheadline.weight(.semibold))

            settingsField("Horizontal") {
              Picker("Horizontal", selection: $options.horizontalAlign) {
                ForEach(SpreadsheetPrintHorizontalAlign.allCases) { align in
                  Text(align.rawValue).tag(align)
                }
              }
              .labelsHidden()
              .pickerStyle(.menu)
            }

            settingsField("Vertical") {
              Picker("Vertical", selection: $options.verticalAlign) {
                ForEach(SpreadsheetPrintVerticalAlign.allCases) { align in
                  Text(align.rawValue).tag(align)
                }
              }
              .labelsHidden()
              .pickerStyle(.menu)
            }
          }

          Divider()

          disclosureSection("Headers & footers", isExpanded: $headersExpanded) {
            Toggle("Page numbers", isOn: $options.headersFooters.pageNumbers)
            Toggle("Workbook title", isOn: $options.headersFooters.workbookTitle)
            Toggle("Sheet name", isOn: $options.headersFooters.sheetName)
            Toggle("Current date", isOn: $options.headersFooters.currentDate)
            Toggle("Current time", isOn: $options.headersFooters.currentTime)
          }

          Divider()

          VStack(alignment: .leading, spacing: 8) {
            Text("Row & column headers")
              .font(.subheadline.weight(.semibold))
            Text("Go to Sheet → Freeze to choose which rows/columns repeat on every page.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            Toggle("Repeat frozen rows", isOn: $options.repeatFrozenRows)
              .disabled(!hasFrozenRows)
            Toggle("Repeat frozen columns", isOn: $options.repeatFrozenColumns)
              .disabled(!hasFrozenColumns)
          }

          GroupBox {
            VStack(alignment: .leading, spacing: 6) {
              LabeledContent("Range", value: rangeSummary)
              if options.scope == .workbook {
                LabeledContent("Sheets", value: "\(pages.count)")
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(20)
      }

      Divider()

      HStack {
        Button("Cancel", action: onCancel)
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Print…") {
          onPrint(options)
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(pages.isEmpty)
      }
      .padding(16)
    }
    .frame(width: 320)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private func settingsField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.subheadline.weight(.semibold))
      content()
    }
  }

  private func disclosureSection<Content: View>(
    _ title: String,
    isExpanded: Binding<Bool>,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Button {
        withAnimation(.easeInOut(duration: 0.15)) {
          isExpanded.wrappedValue.toggle()
        }
      } label: {
        HStack {
          Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
          Spacer()
          Image(systemName: "chevron.up")
            .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : 180))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
      }
      .buttonStyle(.plain)

      if isExpanded.wrappedValue {
        VStack(alignment: .leading, spacing: 8) {
          content()
        }
      }
    }
  }
}
