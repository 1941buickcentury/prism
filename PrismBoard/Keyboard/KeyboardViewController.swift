import UIKit
import SwiftUI

class KeyboardViewController: UIInputViewController {
    private var model: KeyboardModel!
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        let dark = traitCollection.userInterfaceStyle == .dark
        let model = KeyboardModel(
            engine: WordEngine(),
            proxy: ProxyBridge(controller: self),
            hasFullAccess: hasFullAccess,
            systemDark: dark
        )
        model.onGlobe = { [weak self] in self?.advanceToNextInputMode() }
        model.onHeightChange = { [weak self] in self?.updateHeight() }
        self.model = model

        let host = UIHostingController(rootView: KeyboardRootView(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        updateHeight()
    }

    private func updateHeight() {
        let target = model.keyboardHeight
        if let heightConstraint {
            heightConstraint.constant = target
        } else {
            let c = view.heightAnchor.constraint(equalToConstant: target)
            c.priority = UILayoutPriority(999)
            c.isActive = true
            heightConstraint = c
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model?.syncContext()
    }
}

/// Bridges the keyboard model to the host app's text field.
final class ProxyBridge: KeyboardProxy {
    weak var controller: UIInputViewController?
    init(controller: UIInputViewController) { self.controller = controller }

    var contextBefore: String { controller?.textDocumentProxy.documentContextBeforeInput ?? "" }
    func insert(_ text: String) { controller?.textDocumentProxy.insertText(text) }
    func deleteBackward() { controller?.textDocumentProxy.deleteBackward() }
}
