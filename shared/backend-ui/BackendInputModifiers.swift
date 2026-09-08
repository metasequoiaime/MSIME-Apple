import SwiftUI

extension View {
  @ViewBuilder func backendCodeInput() -> some View {
    #if os(iOS)
    self.textInputAutocapitalization(.never).autocorrectionDisabled()
    #else
    self.disableAutocorrection(true)
    #endif
  }
  @ViewBuilder func backendNumberInput() -> some View {
    #if os(iOS)
    self.keyboardType(.numberPad)
    #else
    self
    #endif
  }
}
