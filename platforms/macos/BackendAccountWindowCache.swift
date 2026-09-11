/// Owns one account's windows. Never returns a view created for another account.
@MainActor
final class BackendAccountWindowCache<Window> {
  private var accountID: String?
  private var windows: [String: Window] = [:]

  func window(for key: String, accountID: String, reusable: (Window) -> Bool,
              close: (Window) -> Void, create: () -> Window) -> Window {
    if self.accountID != accountID {
      let previous = Array(windows.values)
      windows.removeAll()
      self.accountID = accountID
      previous.forEach(close)
    }
    if let existing = windows[key] {
      if reusable(existing) { return existing }
      windows.removeValue(forKey: key)
      close(existing)
    }
    let window = create()
    windows[key] = window
    return window
  }
}
