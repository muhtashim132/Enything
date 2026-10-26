import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import flutter_background_service_ios
import flutter_local_notifications
import UniformTypeIdentifiers
#if canImport(ActivityKit)
import ActivityKit
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, UIDocumentPickerDelegate {

  private var audioPickerResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    SwiftFlutterBackgroundServicePlugin.taskIdentifier = "dev.flutter.background.refresh"

    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
        GeneratedPluginRegistrant.register(with: registry)
    }

    // ── 1. Configure Firebase ────────────────────────────────────────────────
    FirebaseApp.configure()

    // ── 2. Set FCM delegate ──────────────────────────────────────────────────
    Messaging.messaging().delegate = self

    // ── 3. Request push-notification authorisation ───────────────────────────
    UNUserNotificationCenter.current().delegate = self
    let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
    UNUserNotificationCenter.current().requestAuthorization(
      options: authOptions,
      completionHandler: { _, _ in }
    )
    application.registerForRemoteNotifications()

    // ── 4. Register MethodChannels (iOS parity with Android) ─────────────────
    let controller = window?.rootViewController as? FlutterViewController
    if let binaryMessenger = controller?.binaryMessenger {
      // Audio Picker
      let audioChannel = FlutterMethodChannel(name: "com.enything/audio_picker", binaryMessenger: binaryMessenger)
      audioChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
        guard let self = self else { return }
        if call.method == "pickAudioFile" {
          self.audioPickerResult = result
          self.presentAudioDocumentPicker()
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

      // Screen Wake & Keep Awake (parity with Android wakeScreen / releaseWakeScreen)
      let screenChannel = FlutterMethodChannel(name: "com.enything/screen_wake", binaryMessenger: binaryMessenger)
      screenChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "wakeScreen" {
          DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
          }
          result(true)
        } else if call.method == "releaseWakeScreen" {
          DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
          }
          result(true)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

      // Live Activities & Dynamic Island (ActivityKit)
      let liveActivityChannel = FlutterMethodChannel(name: "com.enything/live_activities", binaryMessenger: binaryMessenger)
      liveActivityChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
          OrderLiveActivityBridge.handle(call: call, result: result)
        } else {
          result(["supported": false, "error": "ActivityKit requires iOS 16.2 or higher"])
        }
        #else
        result(["supported": false, "error": "ActivityKit not available in this build"])
        #endif
      }
    }

    // ── 5. Register Flutter plugins ──────────────────────────────────────────
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func presentAudioDocumentPicker() {
    guard let rootVC = window?.rootViewController else {
      audioPickerResult?(nil)
      audioPickerResult = nil
      return
    }

    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      let types: [UTType] = [.audio, .mp3, .wav, .aiff]
      picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
    } else {
      let types = ["public.audio", "public.mp3", "com.microsoft.waveform-audio"]
      picker = UIDocumentPickerViewController(documentTypes: types, in: .import)
    }

    picker.delegate = self
    picker.allowsMultipleSelection = false
    rootVC.present(picker, animated: true, completion: nil)
  }

  // ── UIDocumentPickerDelegate ─────────────────────────────────────────────
  public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let pickedUrl = urls.first else {
      audioPickerResult?(nil)
      audioPickerResult = nil
      return
    }

    do {
      let fileManager = FileManager.default
      let documentsDir = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let customBellsDir = documentsDir.appendingPathComponent("CustomBells", isDirectory: true)
      if !fileManager.fileExists(atPath: customBellsDir.path) {
        try fileManager.createDirectory(at: customBellsDir, withIntermediateDirectories: true, attributes: nil)
      }

      let destUrl = customBellsDir.appendingPathComponent(pickedUrl.lastPathComponent)
      if fileManager.fileExists(atPath: destUrl.path) {
        try fileManager.removeItem(at: destUrl)
      }
      try fileManager.copyItem(at: pickedUrl, to: destUrl)

      audioPickerResult?(destUrl.path)
    } catch {
      print("[AudioPicker] Failed to copy audio file: \(error.localizedDescription)")
      audioPickerResult?(pickedUrl.path)
    }
    audioPickerResult = nil
  }

  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    audioPickerResult?(nil)
    audioPickerResult = nil
  }

  // ── APNs device token → FCM ──────────────────────────────────────────────
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("[APNs] Registration failed: \(error.localizedDescription)")
  }
}

// ── FCM token refresh ────────────────────────────────────────────────────────
extension AppDelegate: MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("[FCM] Token: \(fcmToken ?? "nil")")
    // Forward to Flutter via EventChannel / shared preferences if needed.
    let dataDict: [String: String] = ["token": fcmToken ?? ""]
    NotificationCenter.default.post(
      name: Notification.Name("FCMToken"),
      object: nil,
      userInfo: dataDict
    )
  }
}

// ── Foreground notification display ─────────────────────────────────────────
extension AppDelegate {
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if notification.request.trigger is UNPushNotificationTrigger {
      // Remote push notification received in foreground.
      // Suppress native iOS banner to avoid duplicates, because Flutter's
      // onMessage handler will manually trigger a local notification.
      completionHandler([])
    } else {
      // Local notification triggered by flutter_local_notifications
      if #available(iOS 14.0, *) {
        completionHandler([.banner, .badge, .sound])
      } else {
        completionHandler([.alert, .badge, .sound])
      }
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }
}

// ── Order Live Activities & Dynamic Island (ActivityKit) ─────────────────────
#if canImport(ActivityKit)
@available(iOS 16.2, *)
public struct OrderLiveActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    public var statusHeadline: String
    public var etaMinutes: Int
    public var etaTimestamp: Double
    public var progress: Double
    public var statusKey: String
    public var riderName: String?
    public var isMultiShop: Bool
    public var unpickedShopsCount: Int
    public var deliveryOtp: String?

    public init(
      statusHeadline: String,
      etaMinutes: Int,
      etaTimestamp: Double,
      progress: Double,
      statusKey: String,
      riderName: String? = nil,
      isMultiShop: Bool = false,
      unpickedShopsCount: Int = 0,
      deliveryOtp: String? = nil
    ) {
      self.statusHeadline = statusHeadline
      self.etaMinutes = etaMinutes
      self.etaTimestamp = etaTimestamp
      self.progress = progress
      self.statusKey = statusKey
      self.riderName = riderName
      self.isMultiShop = isMultiShop
      self.unpickedShopsCount = unpickedShopsCount
      self.deliveryOtp = deliveryOtp
    }
  }

  public var orderId: String
  public var orderNumber: String
  public var shopName: String

  public init(orderId: String, orderNumber: String, shopName: String) {
    self.orderId = orderId
    self.orderNumber = orderNumber
    self.shopName = shopName
  }
}

@available(iOS 16.2, *)
public class OrderLiveActivityBridge {
  public static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "areActivitiesEnabled":
      let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
      result(["enabled": enabled])

    case "startActivity":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Arguments must be a dictionary", details: nil))
        return
      }

      let orderId = args["orderId"] as? String ?? ""
      let orderNumber = args["orderNumber"] as? String ?? ""
      let shopName = args["shopName"] as? String ?? "Enything Store"
      let statusHeadline = args["statusHeadline"] as? String ?? "Your order is being prepared"
      let etaMinutes = args["etaMinutes"] as? Int ?? 9
      let etaTimestamp = args["etaTimestamp"] as? Double ?? Date().addingTimeInterval(Double(etaMinutes * 60)).timeIntervalSince1970
      let progress = args["progress"] as? Double ?? 0.35
      let statusKey = args["statusKey"] as? String ?? "preparing"
      let riderName = args["riderName"] as? String
      let isMultiShop = args["isMultiShop"] as? Bool ?? false
      let unpickedShopsCount = args["unpickedShopsCount"] as? Int ?? 0
      let deliveryOtp = args["deliveryOtp"] as? String

      // End any stale activity for this order first
      let existingActivities = Activity<OrderLiveActivityAttributes>.activities
      for act in existingActivities where act.attributes.orderId == orderId {
        Task {
          await act.end(nil, dismissalPolicy: .immediate)
        }
      }

      let attributes = OrderLiveActivityAttributes(
        orderId: orderId,
        orderNumber: orderNumber,
        shopName: shopName
      )
      let initialContent = OrderLiveActivityAttributes.ContentState(
        statusHeadline: statusHeadline,
        etaMinutes: etaMinutes,
        etaTimestamp: etaTimestamp,
        progress: progress,
        statusKey: statusKey,
        riderName: riderName,
        isMultiShop: isMultiShop,
        unpickedShopsCount: unpickedShopsCount,
        deliveryOtp: deliveryOtp
      )

      do {
        let activity = try Activity<OrderLiveActivityAttributes>.request(
          attributes: attributes,
          contentState: initialContent,
          pushType: nil
        )
        print("[LiveActivity] Started Activity ID: \(activity.id) for order: \(orderId)")
        result([
          "success": true,
          "activityId": activity.id,
          "orderId": orderId
        ])
      } catch {
        print("[LiveActivity] Request failed: \(error.localizedDescription)")
        result(FlutterError(code: "REQUEST_FAILED", message: error.localizedDescription, details: nil))
      }

    case "updateActivity":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Arguments must be a dictionary", details: nil))
        return
      }

      let activityId = args["activityId"] as? String
      let orderId = args["orderId"] as? String ?? ""
      let statusHeadline = args["statusHeadline"] as? String ?? "Your order is being prepared"
      let etaMinutes = args["etaMinutes"] as? Int ?? 8
      let etaTimestamp = args["etaTimestamp"] as? Double ?? Date().addingTimeInterval(Double(etaMinutes * 60)).timeIntervalSince1970
      let progress = args["progress"] as? Double ?? 0.45
      let statusKey = args["statusKey"] as? String ?? "preparing"
      let riderName = args["riderName"] as? String
      let isMultiShop = args["isMultiShop"] as? Bool ?? false
      let unpickedShopsCount = args["unpickedShopsCount"] as? Int ?? 0
      let deliveryOtp = args["deliveryOtp"] as? String

      let targetActivity = Activity<OrderLiveActivityAttributes>.activities.first { act in
        if let aid = activityId, act.id == aid { return true }
        return act.attributes.orderId == orderId
      }

      guard let activity = targetActivity else {
        // If not found, attempt to restart smoothly
        print("[LiveActivity] Target activity not found for update, attempting restart.")
        result(["success": false, "notFound": true])
        return
      }

      let updatedContent = OrderLiveActivityAttributes.ContentState(
        statusHeadline: statusHeadline,
        etaMinutes: etaMinutes,
        etaTimestamp: etaTimestamp,
        progress: progress,
        statusKey: statusKey,
        riderName: riderName,
        isMultiShop: isMultiShop,
        unpickedShopsCount: unpickedShopsCount,
        deliveryOtp: deliveryOtp
      )

      Task {
        await activity.update(using: updatedContent)
        print("[LiveActivity] Updated Activity ID: \(activity.id) to: \(statusHeadline) (ETA \(etaMinutes)m)")
      }
      result(["success": true])

    case "endActivity":
      guard let args = call.arguments as? [String: Any] else {
        // End all activities
        for act in Activity<OrderLiveActivityAttributes>.activities {
          Task {
            await act.end(nil, dismissalPolicy: .immediate)
          }
        }
        result(["success": true, "all": true])
        return
      }

      let activityId = args["activityId"] as? String
      let orderId = args["orderId"] as? String
      let policyStr = args["dismissalPolicy"] as? String ?? "immediate"
      let dismissalPolicy: ActivityUIDismissalPolicy = policyStr == "default" ? .default : .immediate

      for act in Activity<OrderLiveActivityAttributes>.activities {
        var match = false
        if let aid = activityId, act.id == aid { match = true }
        if let oid = orderId, act.attributes.orderId == oid { match = true }
        if activityId == nil && orderId == nil { match = true }

        if match {
          Task {
            await act.end(nil, dismissalPolicy: dismissalPolicy)
            print("[LiveActivity] Ended Activity ID: \(act.id)")
          }
        }
      }
      result(["success": true])

    case "getActiveActivities":
      let list = Activity<OrderLiveActivityAttributes>.activities.map { act in
        return [
          "id": act.id,
          "orderId": act.attributes.orderId,
          "shopName": act.attributes.shopName
        ]
      }
      result(["activities": list])

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
#endif

