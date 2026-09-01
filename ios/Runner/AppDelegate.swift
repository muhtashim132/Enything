import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import flutter_background_service_ios
import flutter_local_notifications
import UniformTypeIdentifiers

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
