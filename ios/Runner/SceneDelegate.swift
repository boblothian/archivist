import UIKit
import Flutter

@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {

        guard let windowScene = scene as? UIWindowScene else { return }

        // Re-use the **same** engine from AppDelegate
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        let flutterEngine = appDelegate.flutterEngine

        let flutterViewController = FlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = flutterViewController
        self.window = window
        window.makeKeyAndVisible()
    }

    // Optional: forward lifecycle to Flutter (helps with hot-reload)
    func sceneDidBecomeActive(_ scene: UIScene) {
        (window?.rootViewController as? FlutterViewController)?.engine?.notifyAppIsResumed()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        (window?.rootViewController as? FlutterViewController)?.engine?.notifyAppIsInactive()
    }
}