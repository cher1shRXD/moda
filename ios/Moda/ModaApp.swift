import SwiftUI

@main
struct ModaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = FinanceStore()
    @StateObject private var notifications = NotificationManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(notifications)
        }
    }
}
