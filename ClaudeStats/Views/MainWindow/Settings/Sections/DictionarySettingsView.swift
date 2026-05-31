import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DictionarySettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var scope: TechnicalTermEditScope = .global
    @State private var selectedCategory: TechnicalTermCategory?
    @State private var query = ""
    @State private var editor: DictionaryTermEditorPayload?
    @State private var message: DictionarySettingsMessage?

    private var store: TechnicalTermDictionaryStore { env.technicalTerms }

    private var visibleRows: [TechnicalTermDictionaryRow] {
        store.filteredRows(scope: scope, category: selectedCategory, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            statsGrid
            toolbar
            dictionaryTable
        }
        .task {
            await store.load(sessions: env.store.sessions)
        }
        .sheet(item: $editor) { payload in
            DictionaryTermEditorSheet(payload: payload) { updated in
                Task {
                    await store.saveEntry(
                        updated,
                        originalCanonical: payload.originalCanonical,
                        scope: payload.scope
                    )
                    if let error = store.errorMessage {
                        message = DictionarySettingsMessage(title: "Dictionary Update Failed", detail: error)
                    }
                }
            }
        }
        .alert(item: $message) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.detail),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var statsGrid: some View {
        let stats = store.stats
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                DictionaryStatCard(title: "Built-in", value: stats.builtInTerms)
                DictionaryStatCard(title: "Global", value: stats.globalCustomTerms)
                DictionaryStatCard(title: "Project", value: stats.projectTerms)
                DictionaryStatCard(title: "Disabled", value: stats.disabledTerms)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                DictionaryStatCard(title: "Built-in", value: stats.builtInTerms)
                DictionaryStatCard(title: "Global", value: stats.globalCustomTerms)
                DictionaryStatCard(title: "Project", value: stats.projectTerms)
                DictionaryStatCard(title: "Disabled", value: stats.disabledTerms)
            }
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("", selection: $scope) {
                    ForEach(TechnicalTermEditScope.allCases) { editScope in
                        Text(editScope.title).tag(editScope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)

                AppSelect(
                    .localized("Category"),
                    selection: $selectedCategory,
                    options: [AppSelectOption(value: Optional<TechnicalTermCategory>.none, title: .localized("All Categories"))]
                        + TechnicalTermCategory.allCases.map { category in
                            AppSelectOption(value: Optional(category), title: .localized(category.displayName))
                        },
                    width: 180,
                    size: .small
                )

                if scope == .project {
                    AppSelect(
                        .localized("Project"),
                        selection: Binding(
                            get: { store.selectedProjectPath },
                            set: { path in
                                Task { await store.selectProjectPath(path) }
                            }
                        ),
                        options: projectOptions,
                        width: 240,
                        size: .small,
                        emptyTitle: .localized("No project sessions")
                    )
                }

                Spacer(minLength: 0)

                Button {
                    presentImportPanel()
                } label: {
                    Label("Import", systemImage: AppIcon.Action.importFile)
                }
                .disabled(scope == .project && store.selectedProjectPath == nil)

                Button {
                    presentExportPanel()
                } label: {
                    Label("Export", systemImage: AppIcon.Action.exportFile)
                }
                .disabled(scope == .project && store.selectedProjectPath == nil)

                Button {
                    editor = .new(scope: scope, category: selectedCategory ?? .general)
                } label: {
                    Label("Add", systemImage: AppIcon.Action.add)
                }
                .disabled(scope == .project && store.selectedProjectPath == nil)
            }

            HStack(spacing: 8) {
                Image(systemName: AppIcon.Action.search)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                TextField("Search terms, aliases, categories, kinds, or tags", text: $query)
                    .textFieldStyle(.plain)
                    .font(.sora(12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))

            if scope == .project, let selected = store.selectedProjectPath {
                Text(selected)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var projectOptions: [AppSelectOption<String?>] {
        if store.availableProjectPaths.isEmpty {
            return [
                AppSelectOption(
                    value: Optional<String>.none,
                    title: .localized("No project sessions"),
                    isDisabled: true
                ),
            ]
        }

        return store.availableProjectPaths.map { path in
            AppSelectOption(value: Optional(path), title: .verbatim(URL(fileURLWithPath: path).lastPathComponent))
        }
    }

    private var dictionaryTable: some View {
        VStack(spacing: 0) {
            DictionaryTableHeader()
            Divider().opacity(0.45)

            if visibleRows.isEmpty {
                ContentUnavailableView {
                    Label("No Terms", systemImage: AppIcon.Resource.dictionary)
                } description: {
                    Text(query.isEmpty && selectedCategory == nil ? "Add or import dictionary terms for this scope." : "No dictionary terms match the active filters.")
                }
                .font(.sora(12))
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(visibleRows) { row in
                        DictionaryTermRow(
                            row: row,
                            editableScope: scope,
                            canEditProject: store.selectedProjectPath != nil,
                            onEdit: {
                                editor = .edit(row: row, scope: row.source == .project ? .project : .global)
                            },
                            onDelete: {
                                Task {
                                    await store.deleteEntry(
                                        canonical: row.entry.canonical,
                                        scope: row.source == .project ? .project : .global
                                    )
                                }
                            },
                            onDisable: {
                                Task {
                                    await store.disableBuiltIn(row.entry, scope: scope)
                                }
                            },
                            onDuplicate: {
                                editor = .duplicate(row: row, scope: scope)
                            }
                        )
                        if row.id != visibleRows.last?.id {
                            Divider().opacity(0.32)
                        }
                    }
                }
            }
        }
        .appSurface(.compactCard(radius: 8), padding: nil)
    }

    private func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            guard let result = await store.importTerms(from: url, scope: scope) else {
                message = DictionarySettingsMessage(
                    title: "Import Failed",
                    detail: store.errorMessage ?? "The selected file could not be imported."
                )
                return
            }
            let detail = ([result.summary] + result.messages.prefix(8)).joined(separator: "\n")
            message = DictionarySettingsMessage(title: "Import Complete", detail: detail)
        }
    }

    private func presentExportPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = scope == .global ? "user_terms.json" : "terms.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            let ok = await store.exportTerms(to: url, scope: scope)
            message = DictionarySettingsMessage(
                title: ok ? "Export Complete" : "Export Failed",
                detail: ok ? "The selected dictionary was exported." : (store.errorMessage ?? "The dictionary could not be exported.")
            )
        }
    }
}

private struct DictionaryStatCard: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.sora(9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.stxMuted)
            Text("\(value)")
                .font(.sora(18, weight: .semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .appSurface(.compactCard(radius: 8), padding: nil)
    }
}

private struct DictionaryTableHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("Enabled").frame(width: 52, alignment: .leading)
            Text("Term").frame(maxWidth: .infinity, alignment: .leading)
            Text("Category").frame(width: 112, alignment: .leading)
            Text("Kind").frame(width: 76, alignment: .leading)
            Text("Aliases").frame(maxWidth: .infinity, alignment: .leading)
            Text("Weight").frame(width: 58, alignment: .trailing)
            Text("Source").frame(width: 72, alignment: .leading)
            Text("").frame(width: 148)
        }
        .font(.sora(10, weight: .semibold))
        .foregroundStyle(Color.stxMuted)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct DictionaryTermRow: View {
    let row: TechnicalTermDictionaryRow
    let editableScope: TechnicalTermEditScope
    let canEditProject: Bool
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onDisable: () -> Void
    var onDuplicate: () -> Void

    private var canWrite: Bool {
        editableScope == .global || canEditProject
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.entry.enabled ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(row.entry.enabled ? Color.stxAccent : Color.stxMuted)
                .frame(width: 52, alignment: .leading)

            Text(row.entry.canonical)
                .font(.sora(12, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.entry.category.displayName)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
                .frame(width: 112, alignment: .leading)

            Text(row.entry.kind.displayName)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 76, alignment: .leading)

            Text(row.entry.aliases.joined(separator: ", "))
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.1f", row.entry.weight))
                .font(.sora(10).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
                .frame(width: 58, alignment: .trailing)

            Text(row.source.displayName)
                .font(.sora(10, weight: .medium))
                .foregroundStyle(row.source == .builtIn ? Color.stxMuted : Color.primary)
                .frame(width: 72, alignment: .leading)

            HStack(spacing: 6) {
                switch row.source {
                case .builtIn:
                    Button {
                        onDisable()
                    } label: {
                        Image(systemName: AppIcon.Status.disabled)
                    }
                    .help(row.entry.enabled ? "Disable in selected dictionary" : "Already disabled")
                    .disabled(!canWrite || !row.entry.enabled)

                    Button {
                        onDuplicate()
                    } label: {
                        Image(systemName: AppIcon.Action.copy)
                    }
                    .help("Duplicate to selected dictionary")
                    .disabled(!canWrite)
                case .globalUser, .project:
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: AppIcon.Action.edit)
                    }
                    .help("Edit")

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: AppIcon.Action.delete)
                    }
                    .help("Delete")
                }
            }
            .buttonStyle(.borderless)
            .frame(width: 148, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct DictionaryTermEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let payload: DictionaryTermEditorPayload
    var onSave: (TechnicalTermEntry) -> Void

    @State private var canonical: String
    @State private var kind: TranscriptTermKind
    @State private var category: TechnicalTermCategory
    @State private var aliasesText: String
    @State private var tagsText: String
    @State private var weight: Double
    @State private var enabled: Bool

    init(payload: DictionaryTermEditorPayload, onSave: @escaping (TechnicalTermEntry) -> Void) {
        self.payload = payload
        self.onSave = onSave
        _canonical = State(initialValue: payload.entry.canonical)
        _kind = State(initialValue: payload.entry.kind)
        _category = State(initialValue: payload.entry.category)
        _aliasesText = State(initialValue: payload.entry.aliases.joined(separator: "\n"))
        _tagsText = State(initialValue: payload.entry.tags.joined(separator: "\n"))
        _weight = State(initialValue: payload.entry.weight)
        _enabled = State(initialValue: payload.entry.enabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(payload.title)
                .font(.sora(18, weight: .semibold))

            VStack(alignment: .leading, spacing: 12) {
                fieldLabel("Canonical")
                TextField("MenuBarExtra", text: $canonical)

                fieldLabel("Category")
                AppSelect(
                    .localized("Category"),
                    selection: $category,
                    options: TechnicalTermCategory.allCases.map { category in
                        AppSelectOption(value: category, title: .localized(category.displayName))
                    },
                    width: 220
                )

                fieldLabel("Kind")
                AppSelect(
                    .localized("Kind"),
                    selection: $kind,
                    options: TranscriptTermKind.allCases.map { kind in
                        AppSelectOption(value: kind, title: .localized(kind.displayName))
                    },
                    width: 220
                )

                fieldLabel("Aliases")
                TextEditor(text: $aliasesText)
                    .font(.sora(12))
                    .frame(height: 86)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))

                fieldLabel("Tags")
                TextEditor(text: $tagsText)
                    .font(.sora(12))
                    .frame(height: 64)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 14) {
                    Stepper(value: $weight, in: 0.2 ... 5.0, step: 0.1) {
                        Text("Weight \(String(format: "%.1f", weight))")
                            .font(.sora(12))
                    }
                    Toggle("Enabled", isOn: $enabled)
                        .toggleStyle(.appSwitch)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(entry)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(canonical.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var entry: TechnicalTermEntry {
        TechnicalTermEntry(
            canonical: canonical.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            category: category,
            aliases: splitList(aliasesText),
            weight: weight,
            enabled: enabled,
            tags: splitList(tagsText)
        )
    }

    private func fieldLabel(_ value: String) -> some View {
        Text(value.uppercased())
            .font(.sora(9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Color.stxMuted)
    }

    private func splitList(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: "\n,|"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct DictionaryTermEditorPayload: Identifiable {
    let id = UUID()
    let title: String
    let entry: TechnicalTermEntry
    let scope: TechnicalTermEditScope
    let originalCanonical: String?

    static func new(
        scope: TechnicalTermEditScope,
        category: TechnicalTermCategory = .general
    ) -> DictionaryTermEditorPayload {
        DictionaryTermEditorPayload(
            title: "Add \(scope.title) Term",
            entry: TechnicalTermEntry(canonical: "", kind: .general, category: category),
            scope: scope,
            originalCanonical: nil
        )
    }

    static func edit(row: TechnicalTermDictionaryRow, scope: TechnicalTermEditScope) -> DictionaryTermEditorPayload {
        DictionaryTermEditorPayload(
            title: "Edit \(row.entry.canonical)",
            entry: row.entry,
            scope: scope,
            originalCanonical: row.entry.canonical
        )
    }

    static func duplicate(row: TechnicalTermDictionaryRow, scope: TechnicalTermEditScope) -> DictionaryTermEditorPayload {
        DictionaryTermEditorPayload(
            title: "Duplicate \(row.entry.canonical)",
            entry: row.entry,
            scope: scope,
            originalCanonical: nil
        )
    }
}

private struct DictionarySettingsMessage: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

#if DEBUG
#Preview("Dictionary settings") {
    AppScrollView {
        DictionarySettingsView()
            .padding()
    }
    .environment(AppEnvironment.preview())
    .frame(width: 900, height: 700)
}
#endif
