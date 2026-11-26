import HorselyCore
import HorselyKit
import SwiftUI

// Ekran nagrywania (Task 17 = Android 3.0.2 `RideRecordingScreen.kt`, NAG-07): koń, czas, dystans, prędkość, chód, mały ślad trasy
// (`RideTrackPreview` — do Task 23, w którym wchodzi mapa MapKit), „Pauza / Wznów”, „Zdjęcie / film” (ZAT-05) i „Zakończ”
// z potwierdzeniem. Nagrywa kontroler (`RideRecordingController`) — ekran tylko pokazuje stan ze sklepu sesji i wysyła polecenia.

/// Stan ekranu nagrywania (Android `RideRecordingViewModel`): jazda z JEDYNEGO sklepu sesji (`observeActiveRide`), zegar sekundowy
/// między zapisami (migawka odświeża się co 5 s), ślad trasy czytany najwyżej co 10 s.
@MainActor
@Observable
final class RideRecordingModel {
    private(set) var loading = true
    private(set) var ride: ActiveRide?
    private(set) var seconds = 0
    private(set) var track: Track?
    /// Jazda zakończyła się i czeka na zapis — ekran przechodzi do zakończenia.
    private(set) var finishSessionId: String?
    /// Sesja zniknęła (odrzucona) — ekran się zamyka.
    private(set) var gone = false
    var message: String?

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private var snapshotAt = Date()
    @ObservationIgnored private var trackLoadedAt: Date?
    @ObservationIgnored private var hadRide = false
    @ObservationIgnored private var finishing = false

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Obserwacja jazdy i zegar; działa, dopóki ekran jest widoczny (`.task`).
    func run() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                for await ride in self.environment.rideSessions.observeActiveRide() { await self.onRide(ride) }
            }
            group.addTask { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    self.onTick()
                }
            }
        }
    }

    private func onRide(_ next: ActiveRide?) async {
        if let next {
            hadRide = true
            ride = next
            loading = false
            snapshotAt = Date()
            seconds = next.snapshot.activeSeconds
            let now = Date()
            if trackLoadedAt.map({ now.timeIntervalSince($0) >= 10 }) ?? true {
                trackLoadedAt = now
                if let loaded = try? await environment.rideSessions.load(sessionId: next.sessionId).track { track = loaded }
            }
            return
        }
        loading = false
        guard hadRide else { return }
        hadRide = false
        let previous = ride
        ride = nil
        // Jazda zniknęła z niezakończonych: zakończyła się (ręcznie, z Live Activity, po 8 h) albo została odrzucona.
        if let pending = try? await environment.rideSessions.unfinished(), pending.state == .finished, pending.sessionId == previous?.sessionId {
            if finishSessionId == nil { finishSessionId = pending.sessionId }
        } else if finishSessionId == nil {
            gone = true
        }
    }

    private func onTick() {
        guard let ride else { return }
        seconds = RideStartPolicy.displayedSeconds(snapshot: ride.snapshot, snapshotAt: snapshotAt, now: Date())
    }

    func pause() {
        Task { await environment.ride.pause() }
    }

    func resume() {
        Task { await environment.ride.resume() }
    }

    /// „Zakończ” po potwierdzeniu. Jazdę nagrywaną w tym procesie kończy kontroler; przerwaną (bez nagrywania) zamyka odzyskiwanie jak
    /// „Zapisz”. `finish()` zwraca id także po nieudanym zapisie końcowym (sesja `.interrupted` bez ostatnich punktów) — wtedy
    /// `closeAfterFinish` zamyka ją z tym, co już jest w bazie, a ekran i tak przechodzi do zakończenia; gdy i to się nie uda, sesja zostaje
    /// przerwana i przy następnym starcie aplikacji wraca pytanie „Zapisz / Odrzuć”.
    func finish() async {
        guard let ride, !finishing else { return }
        finishing = true
        defer { finishing = false }
        let controller = environment.ride
        if ride.snapshot.state == .interrupted || controller.activeSessionId != ride.sessionId {
            let unfinished = UnfinishedRide(
                sessionId: ride.sessionId, horseName: ride.horseName, startedAt: ride.startedAt, distanceMeters: ride.snapshot.distanceMeters,
                state: ride.snapshot.state
            )
            if let id = try? await environment.rideRecovery.save(unfinished) { finishSessionId = id }
            return
        }
        guard let id = await controller.finish() else { return }
        await environment.rideRecovery.closeAfterFinish(sessionId: id)
        if finishSessionId == nil { finishSessionId = id }
    }

    /// Aparat zwrócił plik dla sesji `sessionId` (zapamiętanej przy otwarciu aparatu): zapis z chwilą i ostatnim punktem GPS (ZAT-05).
    /// Gdy sesji już nie ma, plik jest usuwany i ekran pokazuje komunikat.
    func mediaTaken(sessionId: String, _ media: RideCapturedMedia?) async {
        guard let media else {
            message = tr("ride_media_failed")
            return
        }
        let fallback = ride?.sessionId == sessionId ? track : nil
        let last = ((try? await environment.rideSessions.load(sessionId: sessionId).track) ?? fallback)?.points.last
        do {
            try await environment.rideSessions.addMedia(
                sessionId: sessionId, uri: media.uri, contentType: media.contentType, capturedAt: Date(), lat: last?.lat, lon: last?.lon
            )
            message = tr("ride_media_added")
        } catch {
            environment.rideMedia.delete([media.uri])
            message = tr("ride_media_failed")
        }
    }
}

/// Ekran nagrywania z modelem, aparatem i komunikatami.
struct RideRecordingView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: RideRecordingModel
    @State private var camera: RideCameraMode?
    @State private var cameraSessionId: String?
    let onClose: () -> Void
    let onFinish: (String) -> Void

    init(model: RideRecordingModel, onClose: @escaping () -> Void, onFinish: @escaping (String) -> Void) {
        self._model = State(initialValue: model)
        self.onClose = onClose
        self.onFinish = onFinish
    }

    var body: some View {
        RideRecordingScreen(
            ride: model.ride, loading: model.loading, seconds: model.seconds, track: model.track,
            actions: RideRecordingActions(
                onBack: onClose, onPause: { model.pause() }, onResume: { model.resume() }, onFinish: { Task { await model.finish() } },
                onMedia: openCamera
            )
        )
        .overlay(alignment: .bottom) {
            if let message = model.message {
                SaveBanner(message: message, undo: nil) { model.message = nil }
                    .id(message)
                    .padding(.bottom, 140)
            }
        }
        .animation(.default, value: model.message)
        .fullScreenCover(item: $camera) { mode in
            RideCameraPicker(mode: mode, files: environment.rideMedia) { media in
                camera = nil
                if let id = cameraSessionId { Task { await model.mediaTaken(sessionId: id, media) } }
            } onCancel: {
                camera = nil
            }
            .ignoresSafeArea()
        }
        .task { await model.run() }
        .onChange(of: model.finishSessionId) { _, id in if let id { onFinish(id) } }
        .onChange(of: model.gone) { _, gone in if gone { onClose() } }
    }

    private func openCamera(_ mode: RideCameraMode) {
        if let key = RideCameraPicker.unavailableMessageKey() {
            model.message = tr(key)
            return
        }
        cameraSessionId = model.ride?.sessionId
        camera = mode
    }
}

/// Polecenia ekranu nagrywania.
struct RideRecordingActions {
    var onBack: () -> Void = {}
    var onPause: () -> Void = {}
    var onResume: () -> Void = {}
    /// „Zakończ” po potwierdzeniu w alercie.
    var onFinish: () -> Void = {}
    var onMedia: (RideCameraMode) -> Void = { _ in }
}

/// Ekran nagrywania bez stanu (migawki podają stałe wartości).
struct RideRecordingScreen: View {
    let ride: ActiveRide?
    let loading: Bool
    let seconds: Int
    let track: Track?
    var actions = RideRecordingActions()

    @State private var confirmFinish = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.screenEdge) {
                if let ride {
                    RideRecordingContent(ride: ride, seconds: seconds, track: track)
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("ride_none").font(.body).foregroundStyle(HorselyColor.onBackground)
                }
            }
            .padding(Spacing.screenEdge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(HorselyColor.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let ride { RideControls(ride: ride, actions: actions) { confirmFinish = true } }
        }
        .navigationTitle("ride_screen_title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { RideBackButton(action: actions.onBack) }
        }
        .alert(tr("ride_finish_title"), isPresented: $confirmFinish) {
            Button(tr("ride_finish_confirm"), role: .destructive) { actions.onFinish() }
            Button(tr("ride_finish_back"), role: .cancel) {}
        } message: {
            Text("ride_finish_text")
        }
    }
}

/// Treść ekranu: koń, komunikat stanu, zegar, dystans / prędkość / chód i ślad trasy.
struct RideRecordingContent: View {
    let ride: ActiveRide
    let seconds: Int
    let track: Track?

    private var snapshot: RideSnapshot { ride.snapshot }

    var body: some View {
        Text(ride.horseName).font(.headline).foregroundStyle(HorselyColor.onSurfaceVariant)
        if let notice {
            Text(LocalizedStringKey(notice))
                .font(.subheadline)
                .foregroundStyle(HorselyColor.onSecondaryContainer)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Spacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HorselyColor.secondaryContainer, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("ride-notice")
        }
        VStack(spacing: 2) {
            Text("ride_time").font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant)
            Text(RideStartPolicy.clock(seconds))
                .font(.largeTitle.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(HorselyColor.onBackground)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) { stats(spaced: true) }
            VStack(alignment: .leading, spacing: Spacing.between) { stats(spaced: false) }
        }
        RideTrackPreview(track: track ?? Track(startedAtMillis: Int64(ride.startedAt.timeIntervalSince1970 * 1000), points: [], pauses: []))
            .frame(height: 240)
            .frame(maxWidth: .infinity)
            .background(HorselyColor.surfaceVariant)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cardRadius))
    }

    /// Komunikat stanu: przerwana, wstrzymana, słaby GPS (w tej kolejności, jak w Androidzie).
    private var notice: String? {
        if snapshot.state == .interrupted { return "ride_interrupted_notice" }
        if snapshot.state == .paused { return "ride_paused_notice" }
        if snapshot.weakGps { return "ride_notification_weak_gps" }
        return nil
    }

    @ViewBuilder private func stats(spaced: Bool) -> some View {
        stat("ride_distance", RideText.distance(snapshot.distanceMeters))
        if spaced { Spacer(minLength: Spacing.between) }
        stat("ride_speed", snapshot.speedKmh.map(RideText.speed) ?? tr("ride_value_none"))
        if spaced { Spacer(minLength: Spacing.between) }
        stat("ride_gait", snapshot.gait.map(RideText.gait) ?? tr("ride_value_none"))
    }

    private func stat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(HorselyColor.onSurfaceVariant)
            Text(value).font(.title2.weight(.semibold)).foregroundStyle(HorselyColor.onBackground).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Przyciski na dole ekranu, zawsze widoczne (jazda trwa — nie ma czasu przewijać): „Pauza / Wznów”, „Zdjęcie / film” i „Zakończ”.
/// Przerwana jazda nie daje się wstrzymać ani fotografować — zostaje „Zakończ” (zapis tego, co już jest).
private struct RideControls: View {
    let ride: ActiveRide
    let actions: RideRecordingActions
    let onAskFinish: () -> Void

    private var interrupted: Bool { ride.snapshot.state == .interrupted }
    private var paused: Bool { ride.snapshot.state == .paused }

    var body: some View {
        VStack(spacing: Spacing.between) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { pauseButton; mediaMenu }
                VStack(spacing: Spacing.between) { pauseButton; mediaMenu }
            }
            Button(action: onAskFinish) {
                HStack(spacing: Spacing.between) {
                    HIcon(name: "stop", size: 22)
                    Text("ride_finish").font(.headline)
                }
                .foregroundStyle(HorselyColor.onError)
                .frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget + 4)
                .background(HorselyColor.error, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ride-finish")
        }
        .padding(Spacing.screenEdge)
        .background(HorselyColor.background)
    }

    private var pauseButton: some View {
        Button(action: paused ? actions.onResume : actions.onPause) {
            tonalLabel(icon: paused ? "play_arrow" : "pause", text: paused ? "ride_resume" : "ride_pause")
        }
        .buttonStyle(.plain)
        .disabled(interrupted)
        .opacity(interrupted ? 0.4 : 1)
        .accessibilityIdentifier("ride-pause")
    }

    private var mediaMenu: some View {
        Menu {
            Button(tr("ride_media_photo")) { actions.onMedia(.photo) }
            Button(tr("ride_media_video")) { actions.onMedia(.video) }
        } label: {
            tonalLabel(icon: "photo_camera", text: "ride_media")
        }
        .disabled(interrupted)
        .opacity(interrupted ? 0.4 : 1)
        .accessibilityIdentifier("ride-media")
    }

    private func tonalLabel(icon: String, text: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.between) {
            HIcon(name: icon, size: 22)
            Text(text).font(.body.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(HorselyColor.onSecondaryContainer)
        .padding(.horizontal, Spacing.cardPadding)
        .frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget + 4)
        .background(HorselyColor.secondaryContainer, in: Capsule())
        .contentShape(Capsule())
    }
}

/// Mały ślad jazdy (Android `TrackCanvas` sprzed mapy, decyzja R4): linia przez zapisane punkty, dopasowana do ramki, z kropką startu
/// i bieżącego położenia. Bez współrzędnych w opisie dla czytnika ekranu — tylko „Ślad jazdy”. Mapa MapKit — Task 23.
struct RideTrackPreview: View {
    let track: Track

    var body: some View {
        Canvas { context, size in
            let points = track.points
            guard let first = points.first else { return }
            let inset: CGFloat = 16
            let latitudes = points.map(\.lat)
            let longitudes = points.map(\.lon)
            let minLat = latitudes.min() ?? first.lat, maxLat = latitudes.max() ?? first.lat
            let minLon = longitudes.min() ?? first.lon, maxLon = longitudes.max() ?? first.lon
            // Rzut równoodległościowy: stopień długości jest krótszy o cos(szerokości).
            let lonScale = cos((minLat + maxLat) / 2 * .pi / 180)
            let spanX = max((maxLon - minLon) * lonScale, 1e-9)
            let spanY = max(maxLat - minLat, 1e-9)
            let width = max(size.width - 2 * inset, 1), height = max(size.height - 2 * inset, 1)
            let scale = min(width / spanX, height / spanY)
            let offsetX = inset + (width - spanX * scale) / 2
            let offsetY = inset + (height - spanY * scale) / 2
            func position(_ point: TrackPoint) -> CGPoint {
                CGPoint(x: offsetX + (point.lon - minLon) * lonScale * scale, y: offsetY + (maxLat - point.lat) * scale)
            }
            var path = Path()
            path.move(to: position(first))
            for point in points.dropFirst() { path.addLine(to: position(point)) }
            context.stroke(path, with: .color(HorselyColor.primary), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            let start = position(first)
            context.fill(Path(ellipseIn: CGRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10)), with: .color(HorselyColor.primary))
            if let last = points.last, points.count > 1 {
                let end = position(last)
                context.fill(Path(ellipseIn: CGRect(x: end.x - 6, y: end.y - 6, width: 12, height: 12)), with: .color(HorselyColor.error))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(tr("ride_map_description"))
    }
}
