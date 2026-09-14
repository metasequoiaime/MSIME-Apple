import Foundation
import Tauri
import UIKit

private struct SetAppIconArgs: Decodable {
  let style: String
}

final class MobilePlatformPlugin: Plugin {
  private func onMain(_ action: @escaping () -> Void) {
    if Thread.isMainThread {
      action()
    } else {
      DispatchQueue.main.async(execute: action)
    }
  }

  private func iconName(for style: String) -> String?? {
    switch style {
    case "classic": return .some(nil)
    case "forest": return .some("AppIconForest")
    case "sky": return .some("AppIconSky")
    case "dusk": return .some("AppIconDusk")
    case "vermilion": return .some("AppIconVermilion")
    default: return nil
    }
  }

  private func selectedStyle(for iconName: String?) -> String {
    switch iconName {
    case "AppIconForest": return "forest"
    case "AppIconSky": return "sky"
    case "AppIconDusk": return "dusk"
    case "AppIconVermilion": return "vermilion"
    default: return "classic"
    }
  }

  private func resolveInfo(_ invoke: Invoke, application: UIApplication) {
    invoke.resolve([
      "supported": application.supportsAlternateIcons,
      "selected": selectedStyle(for: application.alternateIconName),
    ])
  }

  @objc public func appIconInfo(_ invoke: Invoke) {
    onMain { [self] in
      resolveInfo(invoke, application: UIApplication.shared)
    }
  }

  @objc public func setAppIcon(_ invoke: Invoke) {
    let args: SetAppIconArgs
    do {
      args = try invoke.parseArgs(SetAppIconArgs.self)
    } catch {
      invoke.reject("invalid_app_icon", code: "invalid_app_icon")
      return
    }
    guard let requestedName = iconName(for: args.style) else {
      invoke.reject("invalid_app_icon", code: "invalid_app_icon")
      return
    }

    onMain { [self] in
      let application = UIApplication.shared
      guard application.supportsAlternateIcons else {
        resolveInfo(invoke, application: application)
        return
      }
      application.setAlternateIconName(requestedName) { error in
        self.onMain {
          // Simulator runtimes may report an I/O failure after applying the icon.
          // Trust the state the OS exposes after completion before rejecting.
          if error != nil && application.alternateIconName != requestedName {
            invoke.reject("app_icon", code: "app_icon")
          } else {
            self.resolveInfo(invoke, application: application)
          }
        }
      }
    }
  }
}

@_cdecl("init_plugin_msime_mobile_platform")
func initPlugin() -> Plugin {
  MobilePlatformPlugin()
}
