import Foundation
import UserNotifications

public actor NotificationService {
    public static let shared = NotificationService()

    public func ensureAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    public func toast(title: String, body: String) async {
        await ensureAuthorization()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }
}
