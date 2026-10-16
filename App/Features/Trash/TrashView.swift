import HorselyCore
import HorselyKit
import SwiftUI

/// Kosz trybu samodzielnego (T126, FR-SAM-04): partie od najnowszej z opisem, koniem, czasem usunięcia i liczbą powiązanych;
/// „Przywróć” (reguły programu — rodzic w koszu blokuje), „Usuń trwale” i „Opróżnij kosz” z potwierdzeniem.
struct TrashView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var entries: [TrashEntry]?
    @State private var purging: TrashEntry?
    @State private var emptying = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            if let entries {
                if entries.isEmpty {
                    SectionEmpty(title: "trash_empty_title", hint: "trash_empty_hint")
                } else {
                    DividedList(entries) { entry in row(entry) }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
            }
        }
        .background(HorselyColor.background)
        .navigationTitle(tr("trash_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(tr("trash_empty_action"), role: .destructive) { emptying = true }
                    .disabled(entries?.isEmpty ?? true)
                    .accessibilityIdentifier("trash-empty")
            }
        }
        .task(id: environment.dataRevision) { entries = try? await environment.trash.list() }
        .confirmationDialog(tr("trash_confirm_purge_title"), isPresented: Binding(get: { purging != nil }, set: { if !$0 { purging = nil } }), titleVisibility: .visible) {
            Button(tr("trash_purge"), role: .destructive) {
                if let entry = purging { purge(entry) }
                purging = nil
            }
        } message: {
            if let entry = purging { Text(tr("trash_confirm_purge_text", entry.description, entry.dependentCount)) }
        }
        .confirmationDialog(tr("trash_confirm_empty_title"), isPresented: $emptying, titleVisibility: .visible) {
            Button(tr("trash_empty_action"), role: .destructive) { emptyTrash() }
        } message: {
            Text(tr("trash_confirm_empty_text", entries?.count ?? 0))
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(tr("common_ok")) { message = nil }
        }
    }

    private func row(_ entry: TrashEntry) -> some View {
        HStack(alignment: .top, spacing: Spacing.between) {
            HIcon(name: "delete", size: 24).foregroundStyle(SectionAccent.trash.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.description).font(.body.weight(.semibold)).foregroundStyle(HorselyColor.onBackground)
                if let horse = entry.horseName { Text(horse).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant) }
                Text(tr("trash_deleted_at", Formats.dateTime(entry.deletedAt))).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                if entry.dependentCount > 0 {
                    Text(tr("trash_dependents", entry.dependentCount)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                }
                HStack(spacing: Spacing.between) {
                    Button(tr("trash_restore")) { restore(entry) }
                        .buttonStyle(.bordered)
                        .tint(HorselyColor.primary)
                        .accessibilityIdentifier("trash-restore")
                    Button(tr("trash_purge"), role: .destructive) { purging = entry }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("trash-purge")
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.screenEdge)
        .padding(.vertical, Spacing.between)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("trash_row_actions", entry.description))
        .accessibilityIdentifier("trash-row")
    }

    private func restore(_ entry: TrashEntry) {
        Task {
            switch try? await environment.trash.restore(batchId: entry.id) {
            case .saved?: environment.router.banner = BannerMessage(text: tr("trash_restored"))
            case let .rejected(problem)?: message = problem.message
            case nil: message = tr("trash_failed")
            }
            entries = try? await environment.trash.list()
        }
    }

    private func purge(_ entry: TrashEntry) {
        Task {
            do {
                try await environment.trash.purge(batchId: entry.id)
                environment.router.banner = BannerMessage(text: tr("trash_purged"))
            } catch {
                message = error.localizedDescription
            }
            entries = try? await environment.trash.list()
        }
    }

    private func emptyTrash() {
        Task {
            do {
                try await environment.trash.empty()
                environment.router.banner = BannerMessage(text: tr("trash_emptied"))
            } catch {
                message = error.localizedDescription
            }
            entries = try? await environment.trash.list()
        }
    }
}
