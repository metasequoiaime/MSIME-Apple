import UIKit

enum KeyboardHostContext {
  static func documentIdentifier(for proxy: UITextDocumentProxy) -> UUID? {
    proxy.documentIdentifier
  }
}
