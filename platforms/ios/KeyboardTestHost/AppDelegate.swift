import UIKit

// A separate host gives ML Kit access to the system download service during integration tests,
// without loading a second copy of the production app's Objective-C bridge classes.
//
// 走 UIScene 生命周期:iOS 26 SDK 起不接 scene 的宿主根本起不来,测试会在建立连接前就崩。
// Building against the iOS 26 SDK makes the scene life cycle mandatory, and a host that still
// creates its window in didFinishLaunching dies with "Early unexpected exit, operation never
// finished bootstrapping" before a single case runs. CI has not seen it only because its simulator
// runtime predates the requirement.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   configurationForConnecting session: UISceneSession,
                   options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
    configuration.delegateClass = SceneDelegate.self
    return configuration
  }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
             options: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    self.window = window
  }
}
