import SwiftUI
import UIKit

/// Rozszerzenie „Udostępnij → Horsely” (T116, contracts/app-entry-points-ios.md): przepływ w SwiftUI (`ShareFlowView`).
final class ShareViewController: UIViewController {
    private var model: ShareFlowModel?

    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareFlowModel(items: extensionContext?.inputItems as? [NSExtensionItem] ?? []) { [weak self] cancelled in
            if cancelled {
                self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
            } else {
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        }
        self.model = model
        let host = UIHostingController(rootView: ShareFlowView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        Task { await model.start() }
    }
}
