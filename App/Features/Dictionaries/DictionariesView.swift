import HorselyCore
import HorselyKit
import SwiftUI

extension DictionaryType {
    /// Nazwa słownika (`dictionary_*` ze `strings.xml`).
    var titleKey: String {
        switch self {
        case .vetVisitType: "dictionary_vet_visit_type"
        case .farrierService: "dictionary_farrier_service"
        case .physioBodyArea: "dictionary_physio_body_area"
        case .physioTechnique: "dictionary_physio_technique"
        case .specialistType: "dictionary_specialist_type"
        case .competitionRank: "dictionary_competition_rank"
        case .competitionDiscipline: "dictionary_competition_discipline"
        case .purchaseCategory: "dictionary_purchase_category"
        case .unit: "dictionary_unit"
        case .trainingType: "dictionary_training_type"
        }
    }
}

/// Słowniki trybu samodzielnego (T126, FR-SAM-05): rodzaje słowników z liczbą wartości.
struct DictionariesView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var counts: [DictionaryType: Int] = [:]

    var body: some View {
        List {
            Section {
                ForEach(DictionaryType.allCases, id: \.self) { type in
                    NavigationLink(value: type) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(type.titleKey))
                            Text(tr("dictionaries_value_count", counts[type] ?? 0)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                        }
                        .frame(minHeight: Spacing.minTouchTarget, alignment: .leading)
                    }
                    .accessibilityIdentifier("dictionary-\(type.rawValue)")
                }
            } footer: {
                Text("dictionaries_hint")
            }
        }
        .scrollContentBackground(.hidden)
        .background(HorselyColor.background)
        .navigationTitle(tr("dictionaries_title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: DictionaryType.self) { DictionaryValuesView(type: $0) }
        .task(id: environment.dataRevision) {
            let items = (try? await environment.entries.allDictionaryItems()) ?? []
            counts = Dictionary(grouping: items, by: \.dictionaryType).mapValues(\.count)
        }
    }
}

/// Wartości słownika: dodaj, zmień nazwę, przesuń wyżej/niżej (także przeciągnięciem), ukryj/pokaż, usuń (do kosza). Wartości
/// systemowych nie da się ukryć ani usunąć; używanych — usunąć.
struct DictionaryValuesView: View {
    let type: DictionaryType

    @Environment(AppEnvironment.self) private var environment
    @State private var items: [LocalDictionaryItem] = []
    @State private var editing: Editing?
    @State private var text = ""
    @State private var deleting: LocalDictionaryItem?
    @State private var message: String?

    private enum Editing: Identifiable {
        case add
        case rename(LocalDictionaryItem)

        var id: String {
            switch self {
            case .add: "add"
            case let .rename(item): item.id
            }
        }
    }

    var body: some View {
        List {
            if items.isEmpty {
                Text("dictionaries_empty").foregroundStyle(HorselyColor.onSurfaceVariant)
            }
            ForEach(items) { item in
                row(item)
            }
            .onMove(perform: move)
        }
        .scrollContentBackground(.hidden)
        .background(HorselyColor.background)
        .navigationTitle(LocalizedStringKey(type.titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    text = ""
                    editing = .add
                } label: {
                    Label(tr("dictionaries_add"), systemImage: "plus")
                }
                .accessibilityIdentifier("dictionary-add")
            }
            ToolbarItem(placement: .secondaryAction) { EditButton() }
        }
        .task(id: environment.dataRevision) { await load() }
        .alert(editingTitle, isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField(tr("dictionaries_value_label"), text: $text)
            Button(tr("common_save")) { save() }
            Button(tr("common_cancel"), role: .cancel) { editing = nil }
        }
        .confirmationDialog(tr("dictionaries_confirm_delete_title"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(tr("dictionaries_delete"), role: .destructive) {
                if let item = deleting { perform { try await environment.entries.deleteDictionaryValue(id: item.id) } }
                deleting = nil
            }
        } message: {
            if let item = deleting { Text(tr("dictionaries_confirm_delete_text", item.value)) }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(tr("common_ok")) { message = nil }
        }
    }

    private var editingTitle: String {
        if case .rename = editing { return tr("dictionaries_rename_title") }
        return tr("dictionaries_add_title")
    }

    private func row(_ item: LocalDictionaryItem) -> some View {
        HStack(spacing: Spacing.between) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.value).foregroundStyle(item.isActive ? HorselyColor.onBackground : HorselyColor.onSurfaceVariant)
                let tags = [item.isSystem ? tr("dictionaries_system") : nil, item.isActive ? nil : tr("dictionaries_hidden")].compactMap { $0 }
                if !tags.isEmpty { Text(tags.joined(separator: " · ")).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button(tr("dictionaries_rename")) {
                    text = item.value
                    editing = .rename(item)
                }
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    if index > 0 { Button(tr("dictionaries_move_up", item.value)) { reorder(from: index, to: index - 1) } }
                    if index < items.count - 1 { Button(tr("dictionaries_move_down", item.value)) { reorder(from: index, to: index + 1) } }
                }
                if !item.isSystem {
                    Button(item.isActive ? tr("dictionaries_hide") : tr("dictionaries_show")) {
                        perform { try await environment.entries.setDictionaryValueActive(id: item.id, value: item.value, active: !item.isActive) }
                    }
                    Button(tr("dictionaries_delete"), role: .destructive) { deleting = item }
                }
            } label: {
                Image(systemName: "ellipsis.circle").frame(minWidth: Spacing.minTouchTarget, minHeight: Spacing.minTouchTarget)
            }
            .accessibilityLabel(tr("dictionaries_row_actions", item.value))
        }
        .accessibilityIdentifier("dictionary-value")
    }

    private func load() async {
        items = (try? await environment.entries.dictionaryValues(type)) ?? []
    }

    private func save() {
        let value = text
        switch editing {
        case .add: perform { try await environment.entries.addDictionaryValue(type, value: value) }
        case let .rename(item): perform { try await environment.entries.renameDictionaryValue(id: item.id, value: value) }
        case nil: break
        }
        editing = nil
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        items = reordered
        let ids = reordered.map(\.id)
        let type = type
        perform { try await environment.entries.reorderDictionary(type, orderedIds: ids) }
    }

    private func reorder(from index: Int, to target: Int) {
        move(from: IndexSet(integer: index), to: target > index ? target + 1 : target)
    }

    private func perform(_ work: @escaping @MainActor () async throws -> EntryResult) {
        Task {
            do {
                if let problem = try await work().problem { message = problem.message }
            } catch {
                message = error.localizedDescription
            }
            await load()
        }
    }
}
