import HorselyCore
import HorselyKit
import Observation
import SwiftUI
import UIKit

/// Stan widoku komunikatu o połączeniu (contracts/android/connection-behavior.md §4a): ukryty, rozwinięty samoczynnie (zwija się po
/// 3 s, dłużej przy VoiceOver), zwinięty do ikonki w pasku tytułu, rozwinięty przypięty (do ✕). Jeden dla całej aplikacji —
/// zmiana ekranu nie rozwija komunikatu ponownie.
enum ConnectionIndicatorState: Equatable {
    case hidden
    case expandedAuto
    case collapsed
    case expandedPinned

    var isExpanded: Bool { self == .expandedAuto || self == .expandedPinned }

    /// Samoczynne rozwinięcie tylko przy przejściu „brak problemu → problem” albo zmianie rodzaju problemu.
    static func next(_ current: ConnectionIndicatorState, from old: ConnectionProblem?, to new: ConnectionProblem?) -> ConnectionIndicatorState {
        guard let new = visible(new) else { return .hidden }
        guard let old = visible(old) else { return .expandedAuto }
        return old.variant == new.variant ? current : .expandedAuto
    }

    /// Ciche odczekanie (`Retry-After` ≤ 60 s) nie jest pokazywane.
    static func visible(_ problem: ConnectionProblem?) -> ConnectionProblem? {
        if case .denied(.rateLimited, _)? = problem { return nil }
        return problem
    }

    /// Czas do zwinięcia: 3 s, przy VoiceOver dłużej (odpowiednik `calculateRecommendedTimeoutMillis`).
    @MainActor static var autoCollapseDelay: TimeInterval { UIAccessibility.isVoiceOverRunning ? 10 : 3 }
}

@MainActor
@Observable
final class ConnectionIndicator {
    private(set) var state: ConnectionIndicatorState = .hidden
    @ObservationIgnored private var collapseTask: Task<Void, Never>?

    func problemChanged(from old: ConnectionProblem?, to new: ConnectionProblem?) {
        let next = ConnectionIndicatorState.next(state, from: old, to: new)
        if next != state { set(next) }
    }

    func set(_ value: ConnectionIndicatorState) {
        state = value
        collapseTask?.cancel()
        guard value == .expandedAuto else { return }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ConnectionIndicatorState.autoCollapseDelay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.state == .expandedAuto else { return }
            withAnimation { self.state = .collapsed }
        }
    }

    func collapse() {
        if state.isExpanded { set(.collapsed) }
    }
}

/// Teksty komunikatu i przycisku dla problemu (teksty `connection_*` ze `strings.xml`).
@MainActor
enum ConnectionTexts {
    static func stamp(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "dd.MM HH:mm"
        return formatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func message(_ problem: ConnectionProblem, status: ConnectionStatus) -> String {
        let dataFrom = stamp(status.dataFrom)
        switch problem {
        case .noNetwork:
            return dataFrom.map { tr("connection_no_network", $0) } ?? tr("connection_no_network_no_data")
        case .offline:
            if status.checking { return tr("connection_checking") }
            if let failed = status.failedCheckAt { return tr("connection_still_not_responding", time(failed)) }
            let head = dataFrom.map { tr("connection_computer_not_responding", $0) } ?? tr("connection_computer_not_responding_no_data")
            return head + "\n" + tr("connection_offline_hints")
        case let .denied(reason, until):
            switch reason {
            case .keyRejected: return tr("connection_key_rejected")
            case .keyHomeOnly: return tr("connection_key_home_only")
            case .remoteAccessDisabled: return tr("connection_remote_disabled")
            case .addressBlocked: return tr("connection_address_blocked", until.map(time) ?? "—")
            case .certificateChanged: return tr("connection_certificate_changed")
            case .rateLimited: return tr("connection_checking")
            }
        }
    }

    static func actionKey(_ problem: ConnectionProblem) -> String? {
        switch problem {
        case .noNetwork: nil
        case .offline: "connection_action_refresh"
        case .denied: problem.needsRepairing ? "connection_action_pair_again" : "connection_action_check"
        }
    }
}

/// Nakładka u góry treści (nie zmienia układu ekranu) z komunikatem i przyciskiem działania; ogłaszana przez VoiceOver przy
/// rozwinięciu. Dotknięcie poza przyciskiem zwija ją do ikonki.
struct ConnectionOverlay: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let connection = environment.connection
        if environment.workMode == .online, environment.indicator.state.isExpanded, let problem = ConnectionIndicatorState.visible(connection.problem) {
            VStack(alignment: .leading, spacing: Spacing.between) {
                HStack(alignment: .top, spacing: Spacing.between) {
                    HIcon(name: problem.isDenial ? "error" : "cloud_off", size: 24)
                        .foregroundStyle(problem.isDenial ? HorselyColor.error : HorselyColor.warning)
                    Text(ConnectionTexts.message(problem, status: connection))
                        .font(.subheadline)
                        .foregroundStyle(HorselyColor.onBackground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("connection-message")
                    if environment.indicator.state == .expandedPinned {
                        Button {
                            environment.indicator.set(.collapsed)
                        } label: {
                            Image(systemName: "xmark").frame(width: Spacing.minTouchTarget, height: Spacing.minTouchTarget)
                        }
                        .accessibilityLabel(tr("connection_indicator_close"))
                    }
                }
                if let key = ConnectionTexts.actionKey(problem) {
                    Button {
                        Task { await ConnectionActions.perform(problem, environment: environment) }
                    } label: {
                        Text(LocalizedStringKey(key)).frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                    }
                    .buttonStyle(.bordered)
                    .tint(HorselyColor.primary)
                    .disabled(connection.checking)
                    .accessibilityIdentifier("connection-action")
                }
            }
            .padding(Spacing.cardPadding)
            .background(HorselyColor.background, in: RoundedRectangle(cornerRadius: Spacing.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Spacing.cardRadius).strokeBorder(problem.isDenial ? HorselyColor.error : HorselyColor.warning, lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .padding(.horizontal, Spacing.screenEdge)
            .padding(.top, Spacing.between)
            .contentShape(Rectangle())
            .onTapGesture { environment.indicator.collapse() }
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("connection-overlay")
            .onAppear { UIAccessibility.post(notification: .announcement, argument: ConnectionTexts.message(problem, status: connection)) }
        }
    }
}

/// Ikonka problemu jako ostatnia akcja paska tytułu: pomarańczowa (brak połączenia) — dotknięcie sprawdza połączenie; czerwona
/// (odmowa) — rozwija przypięty komunikat. Podczas sprawdzania — wskaźnik postępu.
struct ConnectionStatusButton: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let connection = environment.connection
        if environment.workMode == .online, let problem = ConnectionIndicatorState.visible(connection.problem) {
            if connection.checking {
                ProgressView()
                    .frame(width: Spacing.minTouchTarget, height: Spacing.minTouchTarget)
                    .accessibilityLabel(tr("connection_indicator_checking_cd"))
            } else {
                Button {
                    if problem.isDenial {
                        environment.indicator.set(.expandedPinned)
                    } else {
                        Task {
                            await connection.checkNow(userInitiated: true)
                            environment.indicator.set(connection.problem == nil ? .hidden : .expandedAuto)
                        }
                    }
                } label: {
                    HIcon(name: problem.isDenial ? "error" : "cloud_off", size: 24)
                        .foregroundStyle(problem.isDenial ? HorselyColor.error : HorselyColor.warning)
                        .frame(width: Spacing.minTouchTarget, height: Spacing.minTouchTarget)
                }
                .accessibilityLabel(label(problem, connection))
                .accessibilityIdentifier("connection-icon")
            }
        }
    }

    private func label(_ problem: ConnectionProblem, _ connection: ConnectionStatus) -> String {
        switch problem {
        case .offline: tr("connection_indicator_offline_cd")
        case .noNetwork: tr("connection_indicator_no_network_cd")
        case .denied: tr("connection_indicator_problem_cd", ConnectionTexts.message(problem, status: connection))
        }
    }
}

/// Działania przycisku komunikatu.
@MainActor
enum ConnectionActions {
    static func perform(_ problem: ConnectionProblem, environment: AppEnvironment) async {
        if problem.needsRepairing {
            environment.router.showPairing = true
            return
        }
        let ok = await environment.connection.checkNow(userInitiated: true)
        if ok {
            environment.connection.clearDenial()
            environment.indicator.set(.hidden)
            await environment.refresh(force: true)
        } else {
            environment.indicator.set(.expandedAuto)
        }
    }
}

/// Podtytuł „Dane z dd.MM HH:mm” pod tytułem ekranu z danymi, gdy jest problem z połączeniem (FR-POL2-15).
struct DataFromSubtitle: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if environment.workMode == .online, ConnectionIndicatorState.visible(environment.connection.problem) != nil {
            Text(ConnectionTexts.stamp(environment.connection.dataFrom).map { tr("stale_data_from", $0) } ?? tr("stale_no_data"))
                .font(.caption)
                .foregroundStyle(HorselyColor.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.screenEdge)
                .accessibilityIdentifier("data-from")
        }
    }
}

extension View {
    /// Elementy stanu połączenia na ekranie z paskiem tytułu: ikonka (ostatnia akcja), nakładka u góry treści, podtytuł „Dane z …”.
    func connectionChrome() -> some View {
        modifier(ConnectionChromeModifier())
    }
}

private struct ConnectionChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) { DataFromSubtitle() }
            .overlay(alignment: .top) { ConnectionOverlay() }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ConnectionStatusButton() } }
    }
}
