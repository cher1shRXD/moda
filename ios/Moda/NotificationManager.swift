import SwiftUI
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    enum RegistrationStatus: Equatable {
        case idle
        case requestingPermission
        case denied
        case registering
        case registered
        case failed(String)

        var label: String {
            switch self {
            case .idle:
                return "대기 중"
            case .requestingPermission:
                return "권한 요청 중"
            case .denied:
                return "알림 권한 꺼짐"
            case .registering:
                return "APNs 등록 중"
            case .registered:
                return "APNs 등록 완료"
            case .failed:
                return "APNs 등록 실패"
            }
        }
    }

    static let shared = NotificationManager()

    @Published var registrationStatus: RegistrationStatus = .idle
    @Published var deviceToken: String?

    private let tokenKey = "apnsDeviceToken"
    private let backend = BackendClient()

    private init() {
        deviceToken = UserDefaults.standard.string(forKey: tokenKey)
        if deviceToken != nil {
            registrationStatus = .registered
        }
    }

    func requestAuthorizationAndRegister() async {
        registrationStatus = .requestingPermission

        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )

            guard granted else {
                registrationStatus = .denied
                return
            }

            registrationStatus = .registering
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            registrationStatus = .failed(error.localizedDescription)
        }
    }

    func saveDeviceToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        Task {
            await registerDeviceTokenWithServer(token)
        }
    }

    private func registerDeviceTokenWithServer(_ token: String) async {
        do {
            #if DEBUG
            let environment = "sandbox"
            #else
            let environment = "production"
            #endif
            _ = try await backend.registerDeviceToken(token, environment: environment)
        } catch {
            registrationStatus = .failed(error.localizedDescription)
        }
    }
}
