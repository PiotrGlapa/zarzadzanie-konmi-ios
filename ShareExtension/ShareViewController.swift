import UIKit

/// Szkielet rozszerzenia „Udostępnij → Horsely” (T005). Przebieg (kopia plików do App Group, wybór konia i wpisu)
/// powstaje w zadaniu T116; na razie rozszerzenie od razu kończy działanie bez dotykania plików.
final class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
