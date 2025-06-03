//
//  SceneDelegate.swift
//  GolfGPSApp
//
//  Created by Samuel Goergen on 6/1/25.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let initialViewController = storyboard.instantiateInitialViewController() {
            print("Successfully loaded initial view controller from storyboard")
            window.rootViewController = initialViewController
            window.makeKeyAndVisible()
            self.window = window
        } else {
            print("Failed to load initial view controller from storyboard")
            let fallbackVC = UIViewController()
            fallbackVC.view.backgroundColor = .red
            window.rootViewController = fallbackVC
            window.makeKeyAndVisible()
            self.window = window
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneDidBecomeActive(_ scene: UIScene) {}
    func sceneWillResignActive(_ scene: UIScene) {}
    func sceneWillEnterForeground(_ scene: UIScene) {}
    func sceneDidEnterBackground(_ scene: UIScene) {}
}


