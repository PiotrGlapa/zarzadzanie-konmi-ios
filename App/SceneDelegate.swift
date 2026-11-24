import UIKit

/// Minimalny SceneDelegate — wymagany przez Xcode 26 (iOS 26 SDK) gdy aplikacja ma URL schemes,
/// ale używa SwiftUI App lifecycle (brak własnej logiki sceny).
final class SceneDelegate: UIResponder {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {}
    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneDidBecomeActive(_ scene: UIScene) {}
    func sceneWillResignActive(_ scene: UIScene) {}
    func sceneWillEnterForeground(_ scene: UIScene) {}
    func sceneDidEnterBackground(_ scene: UIScene) {}
}
