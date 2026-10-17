import Foundation
import Testing
@testable import HorselyKit

/// Maszyna stanów blokady aplikacji (poprawka 2.0.2, FR-001…FR-005): pętla „odblokuj → zablokowane” nie może wrócić.
struct AppLockMachineTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func after(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// Zimny start z włączoną blokadą, odblokowanie kodem (okno uwierzytelniania przełącza scenę inactive → active).
    private func unlockedAfterLaunch() -> AppLockMachine {
        var machine = AppLockMachine(enabled: true)
        machine.launch()
        machine.authenticationStarted()
        machine.willResignActive()
        machine.didBecomeActive(at: start)
        machine.authenticationFinished(success: true)
        return machine
    }

    @Test func unlockingDoesNotLockAgainWhenTheSceneBecomesActiveAfterwards() {
        var machine = AppLockMachine(enabled: true)
        machine.launch()
        #expect(machine.locked)
        #expect(machine.autoPromptAvailable)
        machine.authenticationStarted()
        #expect(machine.authenticating)
        #expect(!machine.autoPromptAvailable)
        machine.willResignActive()
        machine.didBecomeActive(at: start)
        #expect(machine.locked)
        machine.authenticationFinished(success: true)
        #expect(!machine.locked)
        // Regresja pętli: kolejna aktywacja sceny tuż po odblokowaniu nie blokuje.
        machine.didBecomeActive(at: after(1))
        #expect(!machine.locked)
        #expect(!machine.covered)
        #expect(!machine.autoPromptAvailable)
    }

    @Test func fourMinutesFiftyNineSecondsInTheBackgroundDoesNotLock() {
        var machine = unlockedAfterLaunch()
        machine.willResignActive()
        machine.didEnterBackground(at: after(10))
        #expect(machine.covered)
        machine.didBecomeActive(at: after(10 + 299))
        #expect(!machine.locked)
        #expect(!machine.covered)
    }

    @Test func fiveMinutesAndOneSecondInTheBackgroundLocksOnce() {
        var machine = unlockedAfterLaunch()
        machine.willResignActive()
        machine.didEnterBackground(at: after(10))
        machine.didBecomeActive(at: after(10 + 301))
        #expect(machine.locked)
        #expect(machine.autoPromptAvailable)
        #expect(!machine.covered)
    }

    @Test func aCancelledAuthenticationKeepsTheLockWithoutOpeningTheWindowAgain() {
        var machine = AppLockMachine(enabled: true)
        machine.launch()
        machine.authenticationStarted()
        machine.authenticationFinished(success: false)
        #expect(machine.locked)
        #expect(!machine.authenticating)
        #expect(!machine.autoPromptAvailable)
        // Przycisk „Odblokuj” zawsze może ponowić próbę.
        machine.authenticationStarted()
        #expect(machine.authenticating)
        machine.authenticationFinished(success: true)
        #expect(!machine.locked)
    }

    @Test func oneUnlockIsEnoughAfterALongStayInTheBackgroundWhileLocked() {
        var machine = AppLockMachine(enabled: true)
        machine.launch()
        machine.willResignActive()
        machine.didEnterBackground(at: after(5))
        machine.didBecomeActive(at: after(5 + 600))
        #expect(machine.locked)
        #expect(machine.backgroundedAt == nil)
        machine.authenticationStarted()
        machine.willResignActive()
        machine.didBecomeActive(at: after(5 + 601))
        machine.authenticationFinished(success: true)
        #expect(!machine.locked)
        machine.didBecomeActive(at: after(5 + 602))
        #expect(!machine.locked)
    }

    @Test func becomingActiveWithoutEnteringTheBackgroundNeverLocks() {
        var machine = unlockedAfterLaunch()
        machine.willResignActive()
        #expect(machine.covered)
        machine.didBecomeActive(at: after(3600))
        #expect(!machine.locked)
        #expect(!machine.covered)
    }

    @Test func aPhoneWithoutAScreenLockTurnsTheLockOffWithANotice() {
        var machine = unlockedAfterLaunch()
        machine.didBecomeActive(at: after(60), passcodeAvailable: false)
        #expect(!machine.enabled)
        #expect(!machine.locked)
        #expect(machine.disabledNotice)
        machine.acknowledgeNotice()
        #expect(!machine.disabledNotice)
    }

    @Test func resigningActiveWhileAuthenticatingDoesNotCoverTheScreen() {
        var machine = AppLockMachine(enabled: true)
        machine.launch()
        machine.authenticationStarted()
        machine.willResignActive()
        #expect(!machine.covered)
        machine.authenticationFinished(success: false)
        machine.willResignActive()
        #expect(machine.covered)
    }

    @Test func aDisabledLockNeverLocksNorCovers() {
        var machine = AppLockMachine(enabled: false)
        machine.launch()
        #expect(!machine.locked)
        machine.willResignActive()
        machine.didEnterBackground(at: start)
        #expect(!machine.covered)
        machine.didBecomeActive(at: after(3600))
        #expect(!machine.locked)
        #expect(!machine.covered)
    }

    @Test func turningTheLockOnInSettingsDoesNotLockTheRunningSession() {
        var machine = AppLockMachine(enabled: false)
        machine.launch()
        machine.setEnabled(true)
        #expect(!machine.locked)
        machine.didBecomeActive(at: after(1))
        #expect(!machine.locked)
        machine.willResignActive()
        machine.didEnterBackground(at: after(2))
        machine.didBecomeActive(at: after(2 + 301))
        #expect(machine.locked)
    }
}
