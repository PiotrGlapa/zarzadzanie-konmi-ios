import Foundation
import Testing
@testable import HorselyCore

/// Stan push wyliczany z danych wejściowych (spec 003, T008, data-model.md §2) — także kolejność warunków.
struct PushPolicyTests {
    private func decide(
        _ mode: WorkMode = .online, push: Bool = true, _ authorization: PushAuthorization = .allowed, _ registration: PushRegistration = PushRegistration()
    ) -> PushState {
        PushPolicy.decide(PushInput(workMode: mode, serverHasPush: push, authorization: authorization, registration: registration))
    }

    @Test func standaloneAndUnsetModesNeverUsePush() {
        #expect(decide(.standalone) == .standalone)
        #expect(decide(.unset) == .standalone)
        #expect(decide(.standalone, push: true, .allowed, PushRegistration(registered: true)) == .standalone)
    }

    @Test func aServerWithoutPushMeansLocalReminders() {
        #expect(decide(push: false) == .fallback(.serverHasNoPush))
        #expect(decide(push: false).localRemindersActive)
    }

    @Test func permissionStatesDifferInWhetherTheUserAlreadyAnswered() {
        #expect(decide(.online, .notDetermined) == .noPermission(asked: false))
        #expect(decide(.online, .denied) == .noPermission(asked: true))
    }

    @Test func registrationProgressIsPendingThenRegistered() {
        #expect(decide() == .pending)
        #expect(decide(.online, push: true, .allowed, PushRegistration(registered: true)) == .registered)
        #expect(decide(.online, push: true, .allowed, PushRegistration(failingSince: Date(timeIntervalSince1970: 10))) == .pending)
    }

    @Test func fallbackReasonsFromApnsAndFromTheServer() {
        #expect(decide(.online, push: true, .allowed, PushRegistration(apnsRefused: true)) == .fallback(.apnsUnavailable))
        #expect(decide(.online, push: true, .allowed, PushRegistration(permanentFailure: true)) == .fallback(.registrationFailed))
    }

    // MARK: Kolejność warunków

    @Test func missingPushWinsOverMissingPermission() {
        #expect(decide(push: false, .denied) == .fallback(.serverHasNoPush))
        #expect(decide(push: false, .notDetermined) == .fallback(.serverHasNoPush))
    }

    @Test func missingPermissionWinsOverApnsAndRegistrationState() {
        let broken = PushRegistration(registered: true, permanentFailure: true, apnsRefused: true)
        #expect(decide(.online, push: true, .denied, broken) == .noPermission(asked: true))
    }

    @Test func apnsRefusedWinsOverAPermanentFailureAndARegistration() {
        #expect(decide(.online, push: true, .allowed, PushRegistration(permanentFailure: true, apnsRefused: true)) == .fallback(.apnsUnavailable))
        #expect(decide(.online, push: true, .allowed, PushRegistration(registered: true, apnsRefused: true)) == .fallback(.apnsUnavailable))
    }

    @Test func aPermanentFailureWinsOverAStaleRegistration() {
        #expect(decide(.online, push: true, .allowed, PushRegistration(registered: true, permanentFailure: true)) == .fallback(.registrationFailed))
    }

    // MARK: Pochodne

    @Test func localRemindersAreOffOnlyWhenRegistered() {
        let states: [PushState] = [
            .standalone, .fallback(.serverHasNoPush), .fallback(.apnsUnavailable), .fallback(.registrationFailed),
            .noPermission(asked: false), .noPermission(asked: true), .pending,
        ]
        for state in states { #expect(state.localRemindersActive, "\(state)") }
        #expect(!PushState.registered.localRemindersActive)
    }

    @Test func registrationIsAllowedOnlyWhenPendingRegisteredOrAfterAFailure() {
        #expect(PushState.pending.registrationAllowed)
        #expect(PushState.registered.registrationAllowed)
        #expect(PushState.fallback(.registrationFailed).registrationAllowed)
        #expect(!PushState.standalone.registrationAllowed)
        #expect(!PushState.fallback(.serverHasNoPush).registrationAllowed)
        #expect(!PushState.fallback(.apnsUnavailable).registrationAllowed)
        #expect(!PushState.noPermission(asked: false).registrationAllowed)
        #expect(!PushState.noPermission(asked: true).registrationAllowed)
    }
}
