/// Stałe tożsamości aplikacji — muszą zgadzać się z project.yml, `Horsely.entitlements` i zmiennymi repozytorium
/// (`IOS_BUNDLE_ID`, `IOS_APP_GROUP`, contracts/ci-release.md §1).
enum AppIdentity {
    static let bundleID = "pl.glapa.horsely"
    static let appGroup = "group.pl.glapa.horsely"
    static let urlScheme = "horsely"
}
