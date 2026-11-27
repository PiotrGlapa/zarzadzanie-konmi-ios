### 2. Elementy Różniące się (Specyficzne dla Platformy) [W]

Poniższe elementy są implementowane zgodnie ze specyfiką platformy i nie wymagają identycznego zachowania, o ile nie narusza to kontraktu danych (punkt 1).

#### 2.1 Mechanizmy Systemowe
- **Lokalizacja**:
  - Android: Foreground Service (`location`).
  - iOS: `CLLocationUpdate.liveUpdates` + `CLBackgroundActivitySession` (wymagana zgoda "podczas używania").
- **Praca w tle**:
  - Android: Usługa `START_STICKY`.
  - iOS: Live Activity (Dynamic Island) jako główny wskaźnik; odzyskiwanie sesji przy starcie po zamknięciu aplikacji przez system.
- **Zarządzanie Procesem**:
  - Android: Odporność na zabicie procesu (restart usługi).
  - iOS: Zamknięcie przez użytkownika (swipe away) = koniec nagrywania; odzyskiwanie danych (Zapisz/Odrzuć) przy starcie aplikacji.
- **Mapa**:
  - Android: Google Maps SDK.
  - iOS: Apple MapKit.

#### 2.2 Multimedia i Sensory
- **Wideo**:
  - Android: Media3 Transformer.
  - iOS: `AVAssetExportSession` (preset 720p).
- **Sensory**:
  - Android: `SensorManager` (akcelerometr).
  - iOS: `Core Motion` (`CMMotionManager`).
- **Zdjęcia/Filmy**:
  - Android: Systemowy wybór plików.
  - iOS: `PhotosPicker` z zachowaniem metadanych (jeśli dostępne) lub manualnym odczytem.

#### 2.3 Inne
- **Bateria**: `BatteryManager` (Android) vs `UIDevice.isBatteryMonitoringEnabled` (iOS).
- **Powiadomienia**: Stałe powiadomienie (Android) vs Live Activity (iOS) + powiadomienia lokalne dla ostrzeżeń.
