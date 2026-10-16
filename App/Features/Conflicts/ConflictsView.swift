import HorselyCore
import HorselyKit
import SwiftUI

/// Lista konfliktów (T089, FR-SYN2-06/07): nierozstrzygnięte od najstarszego, rodzaj i rekord; akcje zbiorcze z potwierdzeniem
/// i liczbą; wynik zbiorczy (także częściowy przy braku połączenia).
struct ConflictsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var confirm: ConflictResolution?
    @State private var resultText: String?
    @State private var working = false

    var body: some View {
        let conflicts = environment.queue.openConflicts
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.beforeSection) {
                if conflicts.isEmpty {
                    Text("conflicts_empty").font(.body).foregroundStyle(HorselyColor.onSurfaceVariant).accessibilityIdentifier("conflicts-empty")
                } else {
                    Text("conflicts_intro").font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant)
                    if let resultText { InfoCard(tone: .neutral) { Text(resultText).font(.subheadline) } }
                    DividedList(conflicts) { conflict in
                        NavigationLink {
                            ConflictDetailView(conflictId: conflict.id)
                        } label: {
                            ConflictRow(conflict: conflict)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, -Spacing.screenEdge)
                    HStack(spacing: Spacing.between) {
                        Button { confirm = .keepMine } label: {
                            Text("conflicts_keep_all").frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("conflicts-keep-all")
                        Button { confirm = .acceptTheirs } label: {
                            Text("conflicts_accept_all").frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("conflicts-accept-all")
                    }
                    .tint(HorselyColor.primary)
                    .disabled(working)
                }
            }
            .padding(Spacing.screenEdge)
        }
        .background(HorselyColor.background)
        .navigationTitle(tr("conflicts_title"))
        .navigationBarTitleDisplayMode(.inline)
        .connectionChrome()
        .alert(tr("conflicts_title"), isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button(tr("conflicts_confirm_yes")) {
                if let choice = confirm { resolveAll(choice) }
                confirm = nil
            }
            Button(tr("common_cancel"), role: .cancel) { confirm = nil }
        } message: {
            Text(confirm == .keepMine ? tr("conflicts_confirm_keep_all", conflicts.count) : tr("conflicts_confirm_accept_all", conflicts.count))
        }
    }

    private func resolveAll(_ resolution: ConflictResolution) {
        working = true
        Task {
            let result = await environment.resolver.resolveAll(resolution)
            resultText = result.failed == 0 ? tr("conflicts_resolved_all", result.resolved) : tr("conflicts_resolved_some_failed", result.resolved, result.failed)
            working = false
            await environment.sendQueue()
        }
    }
}

struct ConflictRow: View {
    let conflict: Conflict

    var body: some View {
        HStack(spacing: Spacing.between) {
            HIcon(name: "sync_problem", size: 24).foregroundStyle(HorselyColor.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(ConflictTexts.title(conflict)).font(.body.weight(.semibold)).foregroundStyle(HorselyColor.onBackground)
                Text(LocalizedStringKey(ConflictTexts.kindKey(conflict.kind))).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(HorselyColor.onSurfaceVariant).accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.screenEdge)
        .padding(.vertical, Spacing.between)
        .frame(minHeight: Spacing.minTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("conflict-row")
    }
}

enum ConflictTexts {
    static func kindKey(_ kind: ConflictKind) -> String {
        switch kind {
        case .editEdit: "conflicts_kind_edit_edit"
        case .editDelete: "conflicts_kind_edit_delete"
        case .deleteEdit: "conflicts_kind_delete_edit"
        }
    }

    /// Tytuł rekordu z treści (imię, tytuł, nazwa) albo rodzaj rekordu.
    static func title(_ conflict: Conflict) -> String {
        for text in [conflict.mine, conflict.theirs].compactMap({ $0 }) {
            guard let object = JSONValue.object(text) else { continue }
            for key in ["name", "title", "productName"] {
                if let value = object[key]?.stringValue, !value.isEmpty { return value }
            }
        }
        return conflict.recordType.rawValue
    }
}

/// Szczegóły konfliktu: kolumny „Moja” i „Z programu”, różnice wyróżnione tłem i ikoną; „Zachowaj moją” / „Przyjmij z programu”.
struct ConflictDetailView: View {
    let conflictId: String
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var confirmRestore: Int?
    @State private var working = false

    var body: some View {
        let conflict = environment.queue.openConflicts.first { $0.id == conflictId }
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.beforeSection) {
                if let conflict {
                    Text(ConflictTexts.title(conflict)).font(.title3.weight(.semibold))
                    Text(LocalizedStringKey(ConflictTexts.kindKey(conflict.kind))).font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant)
                    if let message { InfoCard(tone: .warning) { Text(message).font(.subheadline) } }
                    comparison(conflict)
                    VStack(spacing: Spacing.between) {
                        Button { resolve(.keepMine, confirmed: false) } label: {
                            Text("conflicts_keep_mine").font(.headline).frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                        }
                        .buttonStyle(.primaryFilled)
                        .accessibilityIdentifier("conflict-keep-mine")
                        Button { resolve(.acceptTheirs, confirmed: false) } label: {
                            Text("conflicts_accept_theirs").frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("conflict-accept-theirs")
                    }
                    .tint(HorselyColor.primary)
                    .disabled(working)
                } else {
                    Text("conflicts_gone").font(.body).foregroundStyle(HorselyColor.onSurfaceVariant)
                }
            }
            .padding(Spacing.screenEdge)
        }
        .background(HorselyColor.background)
        .navigationTitle(tr("conflicts_detail_title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(tr("conflicts_restore_title"), isPresented: Binding(get: { confirmRestore != nil }, set: { if !$0 { confirmRestore = nil } })) {
            Button(tr("conflicts_restore_yes")) {
                confirmRestore = nil
                resolve(.keepMine, confirmed: true)
            }
            Button(tr("common_cancel"), role: .cancel) { confirmRestore = nil }
        } message: {
            Text(tr("conflicts_restore_text", confirmRestore ?? 0))
        }
    }

    private func comparison(_ conflict: Conflict) -> some View {
        let rows = ConflictDiff.fields(mine: conflict.mine, theirs: conflict.theirs)
        return VStack(spacing: 0) {
            HStack {
                Text("conflicts_column_field").frame(maxWidth: .infinity, alignment: .leading)
                Text("conflicts_column_mine").frame(maxWidth: .infinity, alignment: .leading)
                Text("conflicts_column_theirs").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(HorselyColor.onSurfaceVariant)
            .padding(.vertical, Spacing.between)
            ForEach(rows, id: \.field) { row in
                HStack(alignment: .top) {
                    HStack(spacing: 4) {
                        if row.differs { HIcon(name: "warning", size: 14).foregroundStyle(HorselyColor.warning) }
                        Text(row.field)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(conflict.mine == nil ? tr("conflicts_deleted_mine") : (row.mine ?? "—")).frame(maxWidth: .infinity, alignment: .leading)
                    Text(conflict.theirs == nil ? tr("conflicts_deleted_theirs") : (row.theirs ?? "—")).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.footnote)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .background(row.differs ? HorselyColor.warningContainer : Color.clear)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(row.differs ? "\(row.field), \(tr("conflicts_difference"))" : row.field)
            }
        }
    }

    private func resolve(_ resolution: ConflictResolution, confirmed: Bool) {
        working = true
        Task {
            defer { working = false }
            switch await environment.resolver.resolve(conflictId, resolution, confirmed: confirmed) {
            case .done:
                await environment.sendQueue()
                dismiss()
            case let .needsConfirmation(records):
                confirmRestore = records
            case .failed:
                message = tr("conflicts_failed")
            case .gone:
                message = tr("conflicts_gone")
            }
        }
    }
}
