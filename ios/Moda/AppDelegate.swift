import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()

        Task { @MainActor in
            NotificationManager.shared.deviceToken = token
            NotificationManager.shared.registrationStatus = .registered
            NotificationManager.shared.saveDeviceToken(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationManager.shared.registrationStatus = .failed(error.localizedDescription)
        }
    }
}
