import Foundation
import UserNotifications
import Cocoa

/// Manages update notifications using macOS UserNotification framework
///
/// `UpdateNotifier` handles:
/// - Requesting notification permission
/// - Sending local notifications when an update is available
/// - Handling notification click actions (opening the release page)
///
/// ## Usage
/// ```swift
/// await UpdateNotifier.shared.notifyUpdateAvailable(update)
/// ```
///
/// ## Thread Safety
/// This class is designed for main-thread use but async methods are safe from any context.
public final class UpdateNotifier: NSObject, @unchecked Sendable, UNUserNotificationCenterDelegate {
    
    // MARK: - Singleton
    
    public static let shared = UpdateNotifier()
    
    // MARK: - Constants
    
    private let categoryIdentifier = "PRITYPE_UPDATE"
    private let actionIdentifier = "DOWNLOAD_ACTION"
    
    // MARK: - State
    
    /// The URL to open when the user clicks the notification
    private var pendingReleaseURL: URL?
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
    }
    
    // MARK: - Setup
    
    /// Configure the notification center and register action categories
    ///
    /// Call this once during app startup (in `applicationDidFinishLaunching`)
    public func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        // Define the "Download" action button
        let downloadAction = UNNotificationAction(
            identifier: actionIdentifier,
            title: L10n.update.download,
            options: [.foreground]
        )
        
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [downloadAction],
            intentIdentifiers: [],
            options: []
        )
        
        center.setNotificationCategories([category])
        
        // Request permission (non-blocking)
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                DebugLogger.log("UpdateNotifier: Permission error - \(error.localizedDescription)")
            } else {
                DebugLogger.log("UpdateNotifier: Permission \(granted ? "granted" : "denied")")
            }
        }
    }
    
    // MARK: - Send Notification
    
    /// Post a local notification informing the user about an available update
    ///
    /// - Parameter update: The update information to display
    public func notifyUpdateAvailable(_ update: UpdateChecker.UpdateInfo) {
        // Store the URL for when the user interacts with the notification
        self.pendingReleaseURL = update.releasePageURL
        
        let content = UNMutableNotificationContent()
        content.title = L10n.update.notificationTitle
        content.body = String(format: L10n.update.notificationBody, update.version)
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        
        // Store the release URL in userInfo for the delegate callback
        content.userInfo = ["releaseURL": update.releasePageURL.absoluteString]
        
        // Deliver immediately (no trigger = immediate)
        let request = UNNotificationRequest(
            identifier: "pritype-update-\(update.version)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                DebugLogger.log("UpdateNotifier: Failed to send - \(error.localizedDescription)")
            } else {
                DebugLogger.log("UpdateNotifier: Notification sent for v\(update.version)")
            }
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    /// Handle notification tap (user clicked the notification banner)
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        if let urlString = userInfo["releaseURL"] as? String,
           let url = URL(string: urlString) {
            DebugLogger.log("UpdateNotifier: Opening release page")
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        }
        
        completionHandler()
    }
    
    /// Show notifications even when the app is in the foreground
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
