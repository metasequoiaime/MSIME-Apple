import UIKit

@objc private protocol NullableKeyboardDocumentIdentifier: NSObjectProtocol {
  @objc optional var documentIdentifier: NSUUID? { get }
}

enum KeyboardHostContext {
  static func documentIdentifier(for proxy: UITextDocumentProxy) -> UUID? {
    guard let provider = proxy as? NullableKeyboardDocumentIdentifier,
          let identifier = provider.documentIdentifier ?? nil else { return nil }
    return identifier as UUID
  }
}
