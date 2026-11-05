import Foundation
import HorselyCore
import Testing
@testable import HorselyKit

// MARK: Zaślepki

/// Źródło tokenu z zapisem wywołań (zamiast Firebase i `UIApplication`).
final class FakeTokenSource: PushTokenSource, @unchecked Sendable {
    struct NoToken: Error {}

    private let lock = NSLock()
    private var recorded: [String] = []
    private var current: String?
    private var deleteRequestsAtDeleteToken: Int?
    private let continuation: AsyncStream<String>.Continuation
    let tokenChanges: AsyncStream<String>
    /// Ile żądań `DELETE push/device` wyszło do chwili `deleteToken()` (kolejność: najpierw serwer, potem token).
    var deleteCounter: @Sendable () -> Int = { 0 }

    init(token: String? = "dGhpcyBpcyBhIHRva2Vu:APA91bTokenA") {
        current = token
        let stream = AsyncStream<String>.makeStream()
        tokenChanges = stream.stream
        continuation = stream.continuation
    }

    var calls: [String] { lock.withLock { recorded } }
    var deleteRequestsSeenByDeleteToken: Int? { lock.withLock { deleteRequestsAtDeleteToken } }

    func setToken(_ token: String?) {
        lock.withLock { current = token }
    }

    func emitTokenChange(_ token: String) {
        continuation.yield(token)
    }

    private func record(_ name: String) {
        lock.withLock { recorded.append(name) }
    }

    func configureIfNeeded() async { record("configure") }

    func token() async throws -> String {
        record("token")
        guard let value = lock.withLock({ current }) else { throw NoToken() }
        return value
    }

    func deleteToken() async {
        let seen = deleteCounter()
        lock.withLock { deleteRequestsAtDeleteToken = seen }
        record("deleteToken")
    }

    func setAutoInit(_ enabled: Bool) async { record("autoInit(\(enabled))") }
    func registerForRemoteNotifications() async { record("registerForRemote") }
    func unregisterForRemoteNotifications() async { record("unregisterForRemote") }
}

/// Ręczna kolejka ponowień: test sam wyzwala kolejne próby i widzi zaplanowane opóźnienia.
final class ManualTimer: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(id: Int, work: @Sendable () async -> Void)] = []
    private var scheduled: [TimeInterval] = []
    private var counter = 0

    var delays: [TimeInterval] { lock.withLock { scheduled } }
    var pending: Int { lock.withLock { items.count } }

    var timer: PushRegistrar.RetryTimer {
        { [self] delay, work in
            let id = lock.withLock { () -> Int in
                counter += 1
                scheduled.append(delay)
                items.append((counter, work))
                return counter
            }
            return { [self] in lock.withLock { items.removeAll { $0.id == id } } }
        }
    }

    /// Wykonuje najstarszą oczekującą próbę; `false`, gdy nic nie czeka.
    @discardableResult
    func fireNext() async -> Bool {
        let next = lock.withLock { () -> (@Sendable () async -> Void)? in
            items.isEmpty ? nil : items.removeFirst().work
        }
        guard let next else { return false }
        await next()
        return true
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var moment = Date(timeIntervalSince1970: 1_793_787_300)

    var now: Date { lock.withLock { moment } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { moment = moment.addingTimeInterval(seconds) }
    }
}

final class HarnessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var capabilitiesValue: ProgramCapabilities
    private var authorizationValue: PushAuthorization
    private var stateLog: [PushState] = []

    init(capabilities: ProgramCapabilities, authorization: PushAuthorization) {
        capabilitiesValue = capabilities
        authorizationValue = authorization
    }

    var capabilities: ProgramCapabilities {
        get { lock.withLock { capabilitiesValue } }
        set { lock.withLock { capabilitiesValue = newValue } }
    }

    var authorization: PushAuthorization {
        get { lock.withLock { authorizationValue } }
        set { lock.withLock { authorizationValue = newValue } }
    }

    var states: [PushState] { lock.withLock { stateLog } }

    func record(_ state: PushState) {
        lock.withLock { stateLog.append(state) }
    }
}

/// Rejestrator z zaślepką serwera, źródłem tokenu, zegarem i ręcznym zegarem ponowień.
final class PushHarness: @unchecked Sendable {
    static let pushCapabilities = ProgramCapabilities(names: ["push"])

    let program: FakeProgram
    let tokens: FakeTokenSource
    let timer: ManualTimer
    let clock: TestClock
    let settings: SettingsStore
    let box: HarnessBox
    let registrar: PushRegistrar
    let logs: LogBox

    final class LogBox: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        var all: [String] { lock.withLock { lines } }
        func add(_ line: String) { lock.withLock { lines.append(line) } }
    }

    init(
        mode: WorkMode = .online, push: Bool = true, authorization: PushAuthorization = .allowed, token: String? = "dGhpcyBpcyBhIHRva2Vu:APA91bTokenA",
        instantTimeout: Bool = false, network: FixedNetwork = .wifi
    ) {
        let suite = "horsely.push.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(defaults: defaults)
        settings.workMode = mode
        let program = FakeProgram()
        program.pushCapability = true
        let tokens = FakeTokenSource(token: token)
        tokens.deleteCounter = { program.requests("DELETE", "push/device").count }
        let box = HarnessBox(capabilities: push ? Self.pushCapabilities : .none, authorization: authorization)
        let clock = TestClock()
        let logs = LogBox()
        let timer = ManualTimer()
        let (client, _) = program.client(network: network)
        self.program = program
        self.tokens = tokens
        self.settings = settings
        self.box = box
        self.clock = clock
        self.logs = logs
        self.timer = timer
        registrar = PushRegistrar(
            api: PushApi(client: client), tokens: tokens, settings: settings,
            capabilities: { box.capabilities }, authorization: { box.authorization },
            now: { clock.now }, schedule: timer.timer,
            wait: instantTimeout ? { _ in } : { _ in try? await Task.sleep(for: .seconds(3600)) },
            log: { logs.add($0) }, onState: { box.record($0) }
        )
    }

    var putCount: Int { program.requests("PUT", "push/device").count }
    var deleteCount: Int { program.requests("DELETE", "push/device").count }
}

// MARK: Testy

/// Rejestrator push (spec 003, T027, T039, T045, T061): rejestracja, ponowienia, tryb awaryjny, wyrejestrowanie, dziennik.
struct PushRegistrarTests {
    private let token = "dGhpcyBpcyBhIHRva2Vu:APA91bTokenA"

    // MARK: Rejestracja (US1)

    @Test func registersAtLaunchAndStoresOnlyThePrefix() async {
        let h = PushHarness()
        await h.registrar.reconcile(.launch)
        #expect(h.putCount == 1)
        let stored = h.settings.pushRegistration
        #expect(stored.registered)
        #expect(stored.tokenPrefix == String(token.prefix(8)))
        #expect(stored.tokenPrefix?.count == 8)
        #expect(stored.registeredAt == h.clock.now)
        #expect(stored.failingSince == nil)
        #expect(h.program.registeredPushToken == token)
        #expect(h.settings.pushActive)
        #expect(h.tokens.calls == ["configure", "autoInit(true)", "registerForRemote", "token"])
        #expect(h.box.states == [.pending, .registered], "lokalne powiadomienia znikają dopiero po udanej rejestracji")
    }

    @Test func registersAfterPairingAndWhenPushAppears() async {
        let paired = PushHarness()
        await paired.registrar.reconcile(.paired)
        #expect(paired.putCount == 1)

        let appeared = PushHarness(push: false)
        await appeared.registrar.reconcile(.launch)
        #expect(appeared.putCount == 0)
        appeared.box.capabilities = PushHarness.pushCapabilities
        await appeared.registrar.reconcile(.capabilities(CapabilitiesChange(before: .none, after: PushHarness.pushCapabilities)))
        #expect(appeared.putCount == 1)
        #expect(appeared.box.states == [.fallback(.serverHasNoPush), .pending, .registered])
    }

    @Test func aFreshRegistrationIsNotRepeatedButANewTokenIs() async {
        let h = PushHarness()
        await h.registrar.reconcile(.launch)
        await h.registrar.reconcile(.launch)
        await h.registrar.reconcile(.foreground)
        await h.registrar.reconcile(.background)
        #expect(h.putCount == 1, "rejestracja młodsza niż 24 h")

        h.tokens.setToken("nowyToken:APA91bTokenB")
        await h.registrar.reconcile(.tokenChanged)
        #expect(h.putCount == 2)
        #expect(h.program.registeredPushToken == "nowyToken:APA91bTokenB")
        #expect(h.settings.pushRegistration.tokenPrefix == "nowyToke")
    }

    @Test func aRegistrationOlderThanADayIsRefreshed() async {
        let h = PushHarness()
        await h.registrar.reconcile(.launch)
        h.clock.advance(by: PushRegistrar.refreshInterval - 1)
        await h.registrar.reconcile(.foreground)
        #expect(h.putCount == 1)
        h.clock.advance(by: 2)
        await h.registrar.reconcile(.foreground)
        #expect(h.putCount == 2)
    }

    @Test func tokenChangesFromTheLibraryTriggerARegistration() async {
        let h = PushHarness()
        await h.registrar.reconcile(.launch)
        await h.registrar.startObservingTokenChanges()
        h.tokens.setToken("kolejnyToken:APA91bTokenC")
        h.tokens.emitTokenChange("kolejnyToken:APA91bTokenC")
        for _ in 0 ..< 200 where h.putCount < 2 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(h.putCount == 2)
    }

    @Test func aFailureSetsFailingSinceOnlyOnTheFirstErrorOfASeries() async {
        let h = PushHarness()
        h.program.on("PUT", "push/device", .json(503, #"{"title":"Niedostępne"}"#))
        await h.registrar.reconcile(.launch)
        let first = h.clock.now
        #expect(h.settings.pushRegistration.failingSince == first)
        #expect(!h.settings.pushRegistration.registered)
        h.clock.advance(by: 30)
        await h.timer.fireNext()
        #expect(h.settings.pushRegistration.failingSince == first, "kolejny błąd serii nie przesuwa znacznika")
        #expect(h.box.states == [.pending])
    }

    @Test func retriesFollowThe30To900SecondSchedule() async {
        let h = PushHarness()
        h.program.on("PUT", "push/device", .json(503, #"{"title":"Niedostępne"}"#))
        await h.registrar.reconcile(.launch)
        for _ in 0 ..< 6 {
            h.clock.advance(by: 1)
            await h.timer.fireNext()
        }
        #expect(h.timer.delays == [30, 60, 120, 240, 480, 900, 900])
        #expect(h.putCount == 7)
    }

    @Test func aSuccessfulRetryClearsTheFailureAndStopsRetrying() async {
        let h = PushHarness()
        h.program.on("PUT", "push/device", .json(503, #"{"title":"Niedostępne"}"#), .json(200, #"{"platform":"Ios","tokenPrefix":"dGhpcyBp","registeredAt":"2026-11-04T10:15:00.0000000Z"}"#))
        await h.registrar.reconcile(.launch)
        #expect(h.timer.pending == 1)
        await h.timer.fireNext()
        let stored = h.settings.pushRegistration
        #expect(stored.registered && stored.failingSince == nil && !stored.permanentFailure)
        #expect(h.timer.pending == 0)
        #expect(h.box.states == [.pending, .registered])
    }

    @Test func aBackgroundAttemptDoesNotScheduleRetries() async {
        let h = PushHarness()
        h.program.on("PUT", "push/device", .json(503, #"{"title":"Niedostępne"}"#))
        await h.registrar.reconcile(.background)
        #expect(h.putCount == 1)
        #expect(h.timer.pending == 0)
        #expect(!h.tokens.calls.contains("registerForRemote"), "w tle bez ponownej rejestracji w APNs")
    }

    @Test func suspendingCancelsThePendingRetry() async {
        let h = PushHarness()
        h.program.on("PUT", "push/device", .json(503, #"{"title":"Niedostępne"}"#))
        await h.registrar.reconcile(.launch)
        #expect(h.timer.pending == 1)
        await h.registrar.suspend()
        #expect(h.timer.pending == 0)
    }

    @Test func onlyOneRegistrationRunsAtATime() async {
        let h = PushHarness()
        async let first: Void = h.registrar.reconcile(.launch)
        async let second: Void = h.registrar.reconcile(.paired)
        _ = await (first, second)
        #expect(h.putCount == 1)
    }

    @Test func withoutConsentNothingTouchesTheTokenSourceOrTheServer() async {
        for authorization in [PushAuthorization.notDetermined, .denied] {
            let h = PushHarness(authorization: authorization)
            await h.registrar.reconcile(.launch)
            await h.registrar.reconcile(.foreground)
            #expect(h.tokens.calls.isEmpty, "\(authorization)")
            #expect(h.program.requests.isEmpty)
            #expect(h.box.states == [.noPermission(asked: authorization == .denied)])
        }
    }

    @Test func aMissingTokenCountsAsAFailureAndTriesAgain() async {
        let h = PushHarness(token: nil)
        await h.registrar.reconcile(.launch)
        #expect(h.putCount == 0)
        #expect(h.settings.pushRegistration.failingSince != nil)
        #expect(h.timer.pending == 1)
        #expect(h.logs.all.contains(PushDiagnostics.noToken))
        let invalid = PushHarness(token: "z białymi znakami")
        await invalid.registrar.reconcile(.launch)
        #expect(invalid.putCount == 0, "token z białymi znakami nie jest wysyłany")
    }

    @Test func registrationWorksOnCellularThroughTheOnlyRemoteAddress() async {
        let h = PushHarness(network: .cellular)
        await h.registrar.reconcile(.launch)
        #expect(h.settings.pushRegistration.registered)
    }

    // MARK: Tryb awaryjny (US2)

    @Test func aServerWithoutPushMeansLocalRemindersAndNoTokenSourceCalls() async {
        let h = PushHarness(push: false)
        await h.registrar.reconcile(.launch)
        await h.registrar.reconcile(.foreground)
        await h.registrar.reconcile(.background)
        #expect(h.tokens.calls.isEmpty)
        #expect(h.program.requests.isEmpty)
        #expect(h.box.states == [.fallback(.serverHasNoPush)])
    }

    @Test func standaloneModeMakesNoPushCalls() async {
        for mode in [WorkMode.standalone, .unset] {
            let h = PushHarness(mode: mode)
            await h.registrar.reconcile(.launch)
            await h.registrar.reconcile(.foreground)
            #expect(h.tokens.calls.isEmpty, "\(mode)")
            #expect(h.program.requests.isEmpty)
            #expect(h.box.states == [.standalone])
        }
    }

    @Test func whenPushVanishesTheLocalRemindersReturnWithoutADelete() async {
        let h = PushHarness()
        await h.registrar.reconcile(.launch)
        h.box.capabilities = .none
        await h.registrar.reconcile(.capabilities(CapabilitiesChange(before: PushHarness.pushCapabilities, after: .none)))
        #expect(!h.settings.pushRegistration.registered)
        #expect(h.deleteCount == 0, "bez DELETE (FR-011)")
        #expect(h.box.states.last == .fallback(.serverHasNoPush))

        h.box.capabilities = PushHarness.pushCapabilities
        await h.registrar.reconcile(.capabilities(CapabilitiesChange(before: .none, after: PushHarness.pushCapabilities)))
        #expect(h.putCount == 2)
        #expect(h.box.states.suffix(2) == [.pending, .registered])
    }

    @Test func anApnsRefusalGivesTheFallbackAndALaterSuccessResumesRegistration() async {
        let h = PushHarness()
        await h.registrar.didFailAPNs()
        #expect(await h.registrar.state() == .fallback(.apnsUnavailable))
        #expect(h.putCount == 0)
        await h.registrar.didRegisterAPNs()
        #expect(h.putCount == 1)
        #expect(await h.registrar.state() == .registered)
    }

    @Test func aRejectionWithA400GivesRegistrationFailedAndKeepsRetrying() async {
        let h = PushHarness()
        h.program.on("PUT", "push/device", .json(400, #"{"title":"Błąd walidacji","status":400,"errors":{"token":["Token jest wymagany."]}}"#))
        await h.registrar.reconcile(.launch)
        #expect(await h.registrar.state() == .fallback(.registrationFailed))
        #expect(h.settings.pushRegistration.permanentFailure)
        #expect(h.timer.pending == 1, "ponowienia trwają")
        #expect(h.logs.all.contains(PushDiagnostics.registrationRejected(fields: ["token"])))
        await h.timer.fireNext()
        #expect(h.putCount == 2)
    }

    @Test func aDayOfFailuresGivesRegistrationFailedAndKeepsRetrying() async {
        let h = PushHarness()
        h.program.on("PUT", "push/device", .json(503, #"{"title":"Niedostępne"}"#))
        await h.registrar.reconcile(.launch)
        #expect(await h.registrar.state() == .pending)
        h.clock.advance(by: PushRegistrar.failureThreshold)
        await h.timer.fireNext()
        #expect(await h.registrar.state() == .fallback(.registrationFailed))
        #expect(h.timer.pending == 1)
    }

    @Test func aRecoveryAfterPermanentFailureReturnsToRegistered() async {
        let h = PushHarness()
        h.program.on("PUT", "push/device", .json(400, #"{"title":"Błąd"}"#), .json(200, #"{"platform":"Ios","tokenPrefix":"dGhpcyBp","registeredAt":"2026-11-04T10:15:00.0000000Z"}"#))
        await h.registrar.reconcile(.launch)
        await h.timer.fireNext()
        #expect(await h.registrar.state() == .registered)
        #expect(!h.settings.pushRegistration.permanentFailure)
    }

    @Test func upgradingFrom202StartsPendingAndKeepsLocalRemindersUntilTheFirstRegistration() async {
        let h = PushHarness()
        // Aktualizacja z 2.0.2: ustawienia bez kluczy `push.*`, powiadomienia lokalne włączone, serwer ogłasza `push`.
        h.settings.notificationsEnabled = true
        #expect(h.settings.pushRegistration == PushRegistration())
        let initial = await h.registrar.state()
        #expect(initial == .pending)
        #expect(initial.localRemindersActive)
        await h.registrar.reconcile(.launch)
        #expect(await h.registrar.state() == .registered)
        #expect(!(await h.registrar.state()).localRemindersActive)
    }

    // MARK: Wyrejestrowanie (US3)

    @Test func unregisteringSendsTheDeleteBeforeTheTokenIsRemovedAndClearsTheLocalState() async {
        let h = PushHarness()
        h.settings.pushPermissionAsked = true
        await h.registrar.reconcile(.launch)
        await h.registrar.unregister()
        #expect(h.deleteCount == 1)
        #expect(h.program.requests("DELETE", "push/device").first?.header("X-Api-Key") == "hk_test", "DELETE z kluczem")
        #expect(h.tokens.deleteRequestsSeenByDeleteToken == 1, "najpierw serwer, potem token")
        #expect(h.tokens.calls.suffix(3) == ["deleteToken", "autoInit(false)", "unregisterForRemote"])
        #expect(h.settings.pushRegistration == PushRegistration())
        #expect(!h.settings.pushActive)
        #expect(h.settings.pushPermissionAsked, "decyzja o zgodzie zostaje")
        #expect(h.program.registeredPushToken == nil)
    }

    @Test func everyDeleteOutcomeStillFinishesTheUnregistration() async {
        let replies: [(String, FakeProgram.Reply)] = [
            ("401", .json(401, #"{"title":"Klucz odrzucony"}"#)), ("503", .json(503, #"{"title":"Niedostępne"}"#)),
            ("sieć", .fail(.networkConnectionLost)), ("404", .json(404, #"{"title":"Brak"}"#)),
        ]
        for (name, reply) in replies {
            let h = PushHarness()
            await h.registrar.reconcile(.launch)
            h.program.on("DELETE", "push/device", reply)
            await h.registrar.unregister()
            #expect(h.settings.pushRegistration == PushRegistration(), name)
            #expect(h.tokens.calls.suffix(3) == ["deleteToken", "autoInit(false)", "unregisterForRemote"], name)
        }
    }

    @Test func noAnswerWithinFiveSecondsDoesNotBlockTheUnregistration() async {
        let h = PushHarness(instantTimeout: true)
        await h.registrar.reconcile(.launch)
        h.program.on("DELETE", "push/device", .delayed(30, 204, ""))
        await h.registrar.unregister()
        #expect(h.settings.pushRegistration == PushRegistration())
        #expect(h.tokens.calls.suffix(3) == ["deleteToken", "autoInit(false)", "unregisterForRemote"])
        #expect(h.logs.all.contains(PushDiagnostics.unregistered("brak odpowiedzi w 5 s")))
    }

    @Test func revokingConsentUnregistersThePhone() async {
        let h = PushHarness()
        await h.registrar.reconcile(.launch)
        h.box.authorization = .denied
        await h.registrar.reconcile(.foreground)
        #expect(h.deleteCount == 1)
        #expect(h.settings.pushRegistration == PushRegistration())
        #expect(await h.registrar.state() == .noPermission(asked: true))
    }

    @Test func standaloneAndNoPushServersNeverTouchTheTokenSourceOnUnregister() async {
        for h in [PushHarness(mode: .standalone), PushHarness(push: false), PushHarness(authorization: .notDetermined)] {
            await h.registrar.reconcile(.launch)
            await h.registrar.unregister()
            #expect(h.tokens.calls.isEmpty)
            #expect(h.program.requests.isEmpty)
        }
    }

    // MARK: Prywatność (FR-028, SC-009)

    @Test func theDiagnosticLogNeverContainsTheTokenOnlyItsEightCharacterPrefix() async {
        let h = PushHarness()
        await h.registrar.reconcile(.launch)
        h.program.on("PUT", "push/device", .json(503, #"{"title":"Niedostępne"}"#))
        h.tokens.setToken("innyToken:APA91bTokenD")
        await h.registrar.reconcile(.tokenChanged)
        await h.registrar.unregister()
        let text = h.logs.all.joined(separator: "\n")
        #expect(text.contains("token=\(token.prefix(8))…"))
        for secret in [token, String(token.dropFirst(8)), "innyToken:APA91bTokenD", String("innyToken:APA91bTokenD".dropFirst(8))] {
            #expect(!text.contains(secret))
        }
    }
}
