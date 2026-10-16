import HorselyCore
import HorselyKit
import SwiftUI

/// Kolejka wysyłki (T088, FR-M-SYN-12/13): operacje czekające, wysyłane i wymagające poprawy z opisem bez treści wpisu, stanem
/// i kolejną próbą; usunięcie operacji czekającej (z zależnymi, po potwierdzeniu); „Wyślij teraz”; historia z 30 dni.
struct QueueView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var tab = 0
    @State private var history: [QueueHistoryEntry] = []
    @State private var sending = false
    @State private var resultText: String?
    @State private var deleting: OutboxOperation?

    var body: some View {
        let operations = environment.queue.operations.filter(\.state.isUnsent)
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("queue_tab_queue").tag(0)
                Text("queue_tab_history").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(Spacing.screenEdge)
            if tab == 0 {
                UploadProgressCard(operations: operations)
                queueList(operations)
            } else {
                historyList
            }
        }
        .background(HorselyColor.background)
        .navigationTitle(tr("nav_queue"))
        .navigationBarTitleDisplayMode(.inline)
        .connectionChrome()
        .task(id: environment.queue) { history = (try? await environment.store.read { try $0.history() }) ?? [] }
        .confirmationDialog(tr("queue_delete_title"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(tr("queue_delete"), role: .destructive) {
                if let operation = deleting { delete(operation) }
                deleting = nil
            }
        } message: {
            if let operation = deleting { Text(deleteMessage(operation)) }
        }
    }

    @ViewBuilder private func queueList(_ operations: [OutboxOperation]) -> some View {
        if operations.isEmpty {
            VStack(spacing: Spacing.between) {
                Spacer()
                Text("queue_empty_title").font(.title3.weight(.semibold))
                Text("queue_empty_hint").font(.body).foregroundStyle(HorselyColor.onSurfaceVariant)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("queue-empty")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.beforeSection) {
                    if let resultText {
                        InfoCard(tone: .neutral) { Text(resultText).font(.subheadline) }
                    }
                    Button {
                        sendNow()
                    } label: {
                        Group {
                            if sending { ProgressView() } else { Text("queue_send_now").font(.headline) }
                        }
                        .frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                    }
                    .buttonStyle(.primaryFilled)
                    .tint(HorselyColor.primary)
                    .disabled(sending)
                    .accessibilityIdentifier("queue-send-now")
                    DividedList(operations) { operation in
                        QueueRow(operation: operation) { deleting = operation }
                    }
                }
                .padding(.vertical, Spacing.screenEdge)
            }
        }
    }

    @ViewBuilder private var historyList: some View {
        if history.isEmpty {
            VStack {
                Spacer()
                Text("queue_history_empty").font(.body).foregroundStyle(HorselyColor.onSurfaceVariant)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                DividedList(history.indices.map { HistoryItem(index: $0, entry: history[$0]) }) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.entry.summary).font(.body)
                        Text("\(tr(Self.outcomeKey(item.entry.outcome))) · \(ConnectionTexts.stamp(item.entry.at) ?? "")")
                            .font(.footnote)
                            .foregroundStyle(HorselyColor.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.screenEdge)
                    .padding(.vertical, Spacing.between)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private struct HistoryItem: Identifiable {
        let index: Int
        let entry: QueueHistoryEntry
        var id: Int { index }
    }

    static func outcomeKey(_ outcome: HistoryOutcome) -> String {
        switch outcome {
        case .sent: "queue_history_sent"
        case .alreadyHandled: "queue_history_already_handled"
        case .deleted, .conflictResolved: "queue_history_deleted"
        }
    }

    private func deleteMessage(_ operation: OutboxOperation) -> String {
        let dependents = OperationCoalescer.withDependents(operation.id, in: environment.queue.operations).count - 1
        let base = tr("queue_delete_message")
        return dependents > 0 ? base + "\n" + trPlural("queue_delete_dependents", dependents) : base
    }

    private func delete(_ operation: OutboxOperation) {
        Task {
            let removed = try? await environment.store.writeQuietly { access in
                try access.deleteOperation(operation.id, allowed: OutboxState.editable)
            }
            removed?.files.forEach { try? FileManager.default.removeItem(atPath: $0.path) }
            if removed?.removed.isEmpty ?? true { resultText = tr("queue_delete_blocked") }
        }
    }

    private func sendNow() {
        sending = true
        Task {
            // „Wyślij teraz”: odstępy ponowień nie obowiązują.
            try? await environment.store.writeQuietly { access in
                for op in try access.operations() where op.state == .pending && op.nextAttemptAt != nil {
                    try access.updateOperation(op.id, expected: [.pending]) { current in
                        var next = current
                        next.nextAttemptAt = nil
                        return next
                    }
                }
            }
            let summary = await environment.sendQueue()
            resultText = tr("queue_send_result", summary.sent, summary.needsFix, summary.pending)
            sending = false
        }
    }
}

/// Wiersz operacji: opis, stan (z komunikatem programu przy „Wymaga poprawy”), kolejna próba i usunięcie dla edytowalnych.
struct QueueRow: View {
    let operation: OutboxOperation
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.between) {
            VStack(alignment: .leading, spacing: 2) {
                Text(operation.summary).font(.body).foregroundStyle(HorselyColor.onBackground)
                Text(LocalizedStringKey(Self.stateKey(operation.state)))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(operation.state == .needsFix || operation.state == .conflict || operation.state == .held ? HorselyColor.warning : HorselyColor.onSurfaceVariant)
                if operation.state == .needsFix, let message = operation.problem?.firstMessage {
                    Text(message).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                }
                if operation.state == .pending, let next = operation.nextAttemptAt {
                    Text(tr("queue_next_attempt", ConnectionTexts.time(next))).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                }
                if !operation.state.isEditable {
                    Text("queue_locked_hint").font(.caption).foregroundStyle(HorselyColor.onSurfaceVariant)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if operation.state.isEditable {
                Button(action: onDelete) {
                    HIcon(name: "delete", size: 22).foregroundStyle(HorselyColor.error)
                        .frame(width: Spacing.minTouchTarget, height: Spacing.minTouchTarget)
                }
                .accessibilityLabel(tr("queue_delete"))
            }
        }
        .padding(.horizontal, Spacing.screenEdge)
        .padding(.vertical, Spacing.between)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("queue-row")
    }

    static func stateKey(_ state: OutboxState) -> String {
        switch state {
        case .pending: "queue_state_pending"
        case .sending: "queue_state_sending"
        case .unknown: "queue_state_unknown"
        case .needsFix: "queue_state_needs_fix"
        case .held: "queue_state_held"
        case .sent: "queue_state_sent"
        case .alreadyHandled: "queue_state_already_handled"
        case .conflict: "queue_state_conflict"
        }
    }
}

/// „Wysyłanie plików do programu”: postęp bieżącego pliku i jego numer wśród plików w kolejce (FR-M-ZAL-04).
struct UploadProgressCard: View {
    let operations: [OutboxOperation]
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let files = operations.filter { $0.kind == .createAttachment }
        if let current = environment.uploadProgress.operationId, let index = files.firstIndex(where: { $0.id == current }) {
            InfoCard(tone: .neutral) {
                VStack(alignment: .leading, spacing: Spacing.between) {
                    Text("attachments_upload_title").font(.subheadline.weight(.semibold))
                    if let fraction = environment.uploadProgress.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView()
                    }
                    Text(tr("attachments_upload_progress", index + 1, files.count)).font(.footnote)
                }
            }
            .padding(.horizontal, Spacing.screenEdge)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("upload-progress")
        }
    }
}
