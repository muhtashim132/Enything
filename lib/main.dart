import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';

import 'theme/app_theme.dart';
import 'config/routes.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/location_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/rbac_provider.dart';
import 'providers/team_provider.dart';
import 'providers/audit_provider.dart';
import 'providers/platform_config_provider.dart';
import 'providers/coupon_provider.dart';
import 'providers/recently_viewed_provider.dart';
import 'providers/referral_provider.dart';

import 'services/notification_service.dart';
import 'services/rider_background_service.dart';
import 'config/route_observer.dart';
import 'widgets/customer/multi_shop_cart_bubble.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Always allow runtime fetching as a fallback to prevent UI crashes if local fonts fail to map.
  GoogleFonts.config.allowRuntimeFetching = true;

  await dotenv.load(fileName: '.env');

  // APP1 FIX: Replace assert() with runtime checks — assert() is stripped in
  // release builds, leaving the app to crash silently if .env is misconfigured.
  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  if (supabaseUrl.isEmpty) {
    throw StateError(
      '❌ SUPABASE_URL is missing from .env — ensure the file is declared in Flutter assets.',
    );
  }
  if (supabaseAnonKey.isEmpty) {
    throw StateError(
      '❌ SUPABASE_ANON_KEY is missing from .env',
    );
  }

  // Initialize Firebase (used only for FCM push notifications — NOT for auth)
  await Firebase.initializeApp();

  // Must be a top-level function for background FCM handling
  FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
  );

  // All code uses Supabase.instance.client directly — no global alias needed.

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
    ),
  );

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Load platform config asynchronously to avoid blocking the Splash Screen
  final configProvider = PlatformConfigProvider();
  configProvider.load(); // DO NOT AWAIT

  // Load cart async to prevent blocking startup
  final cartProvider = CartProvider();
  cartProvider.loadCart(); // DO NOT AWAIT

  // Load recently viewed products from SharedPreferences (non-blocking)
  final recentlyViewedProvider = RecentlyViewedProvider();
  recentlyViewedProvider.init(); // DO NOT AWAIT

  // Initialize Notification Service async to prevent Android channel creation deadlocks
  NotificationService().init(); // DO NOT AWAIT

  // Initialize Background Service synchronously to ensure it's ready before login
  await RiderBackgroundService.instance.initialize();

  // Deep linking: Handle notification tap when app is in background
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    handleNotificationClick(message.data);
  });

  // CallKit has been removed.

  // Deep linking: Handle notification tap when app is terminated.
  // We do NOT call _handleNotificationClick() directly here because the
  // navigator isn't ready yet and the SplashPage's own async navigation
  // (1.8 s delay) would override any route we push. Instead, we store the
  // data in a global and let SplashPage._navigate() process it once the
  // navigator stack is fully established.
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null && initialMessage.data.isNotEmpty) {
    pendingNotificationData = initialMessage.data;
  }

  // Also check if the app was launched by tapping a *local* notification
  // (e.g. from the background handler).
  if (pendingNotificationData == null) {
    try {
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      final launchDetails = await flutterLocalNotificationsPlugin
          .getNotificationAppLaunchDetails();
      if (launchDetails != null &&
          launchDetails.didNotificationLaunchApp &&
          launchDetails.notificationResponse?.payload != null) {
        pendingNotificationData =
            jsonDecode(launchDetails.notificationResponse!.payload!)
                as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Failed to parse local notification launch payload: $e');
    }
  }

  runApp(EnythingApp(
    cartProvider: cartProvider,
    configProvider: configProvider,
    recentlyViewedProvider: recentlyViewedProvider,
  ));

  // REMOVED: cancelAll() was here but it was killing background FCM notifications
  // the instant the user tapped them. The background handler creates a notification
  // with FSI + sound, but when the app launches (via tap or FSI), main() runs and
  // cancelAll() fires — killing the notification before the user can interact.
  // Individual notification cancellation (e.g. for cancelled orders) still works
  // via plugin.cancel(orderId.hashCode) in _fcmBackgroundHandler.
  // To restore: await FlutterLocalNotificationsPlugin().cancelAll();
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Holds the FCM notification data from a terminated-app launch so that the
/// SplashPage can process it AFTER its own navigation completes — preventing
/// the race where handleNotificationClick fires before the navigator stack
/// is ready and gets silently overridden by the splash's own route push.
Map<String, dynamic>? pendingNotificationData;

/// Routes a notification tap to the correct screen for each user role.
///
/// Called from three places:
///   1. [FirebaseMessaging.onMessageOpenedApp] — app was backgrounded.
///   2. SplashPage._processPendingNotification — app was terminated (safe timing).
///   3. NotificationService.onDidReceiveNotificationResponse — local buzz tap.
void handleNotificationClick(Map<String, dynamic> data) {
  final role = data['role'] as String?;
  final action = data['action'] as String?;
  final orderId = data['order_id'] as String?;

  if (role == 'seller') {
    // Go directly to the Seller Orders page (Pending tab is tab 0 by default).
    // pushNamedAndRemoveUntil keeps the seller dashboard as the base so back works.
    navigatorKey.currentState
        ?.pushNamedAndRemoveUntil(AppRoutes.sellerDashboard, (route) => false);
    // Then push the orders page on top so the seller sees the Pending list immediately.
    Future.microtask(() {
      navigatorKey.currentState?.pushNamed(AppRoutes.sellerOrders);
    });
  } else if (role == 'rider' || role == 'delivery' || action == 'new_order') {
    // Go to Delivery Dashboard — Available Orders section shows new orders.
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
        AppRoutes.deliveryDashboard, (route) => false);
  } else if (role == 'customer' || (role == null && orderId != null)) {
    // Customer tap (role == 'customer') OR unroled tap with an order_id —
    // always go to the order tracking page.
    //
    // Strategy: push customerHome as the base (so back-navigation works
    // correctly), then push trackOrder on top via microtask.
    // pushNamedAndRemoveUntil clears any stale routes beneath.
    if (orderId != null) {
      navigatorKey.currentState
          ?.pushNamedAndRemoveUntil(AppRoutes.customerHome, (route) => false);
      Future.microtask(() {
        navigatorKey.currentState?.pushNamed(
          AppRoutes.trackOrder,
          arguments: {'orderId': orderId},
        );
      });
    } else {
      // No order_id — fall back to customer home.
      navigatorKey.currentState
          ?.pushNamedAndRemoveUntil(AppRoutes.customerHome, (route) => false);
    }
  }
}

/// Top-level background handler for action button taps (e.g. Decline) on the lock screen
@pragma('vm:entry-point')
void notificationTapBackground(
    NotificationResponse notificationResponse) async {
  // Fix #1: Connect isolate to OS before doing any platform channel work
  WidgetsFlutterBinding.ensureInitialized();

  if (notificationResponse.actionId == 'decline' &&
      notificationResponse.payload != null) {
    try {
      await dotenv.load(fileName: '.env');
      final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
      final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
      await Supabase.initialize(
          url: supabaseUrl, publishableKey: supabaseAnonKey);

      final data =
          jsonDecode(notificationResponse.payload!) as Map<String, dynamic>;
      final orderId = data['order_id'] as String?;
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;

      if (orderId != null && currentUserId != null) {
        await Supabase.instance.client.rpc('rider_reject_order',
            params: {'p_order_id': orderId, 'p_rider_id': currentUserId});
        debugPrint('Order $orderId explicitly declined from lock screen.');
      }
      // Cancel the notification after declining
      await FlutterLocalNotificationsPlugin()
          .cancel(notificationResponse.id ?? 0);
    } catch (e) {
      debugPrint('Failed to handle background decline: $e');
    }
  }
}

/// Background FCM handler — MUST be a top-level function (not a closure).
/// Called by FCM when a DATA-ONLY message arrives and the app is killed/backgrounded.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  // Fix #1: Connect isolate to OS before doing any platform channel work
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // For data-only messages, title/body come from message.data
  final title = message.data['title'] as String? ?? 'Enything';
  final body =
      message.data['body'] as String? ?? message.notification?.body ?? '';

  if (title.isEmpty || body.isEmpty) return;

  final role = message.data['role'] as String?;
  final action = message.data['action'] as String?;
  final orderId = message.data['order_id'] as String?;

  final plugin = FlutterLocalNotificationsPlugin();

  // Additive: Kill ghost notifications if order cancelled or reassigned
  if ((action == 'cancel_order' || action == 'order_reassigned') &&
      orderId != null) {
    await plugin.cancel(orderId.hashCode);
    return;
  }

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  await plugin.initialize(
    const InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    ),
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  final androidPlugin = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();

  // SAMSUNG FIX: Samsung ignores RawResourceAndroidNotificationSound on channels
  // and always plays the default system notification sound. The solution:
  // 1. Use a SILENT channel (playSound: false) so Samsung doesn't play its bell
  // 2. Play enything_bell.wav via AudioPlayer — same approach as BellAlertService
  // To revert: switch back to enything_bell_channel_v4 with playSound: true
  final bool isUrgent = (role == 'rider' ||
      role == 'delivery' ||
      role == 'seller' ||
      role == 'delivery_partner' ||
      action == 'new_order');
  const String channelId = 'enything_bg_silent_v1';
  const String channelName = 'Order Alerts (Background)';
  const String channelDesc =
      'Background order notifications — sound handled by AudioPlayer';

  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDesc,
      importance: Importance.max, // max = heads-up + FSI support
      playSound: false, // SILENT — AudioPlayer handles the bell
      enableVibration: true,
      showBadge: true,
    ),
  );

  final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    channelId,
    channelName,
    channelDescription: channelDesc,
    importance: Importance.max,
    priority: Priority.high,
    playSound: false, // SILENT — AudioPlayer handles the bell
    enableVibration: true,
    fullScreenIntent:
        isUrgent, // THIS WAKES THE SCREEN AND BYPASSES LOCKSCREEN!
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
    icon: '@mipmap/ic_launcher',
    timeoutAfter: isUrgent ? 30000 : null,
    actions: isUrgent
        ? <AndroidNotificationAction>[
            const AndroidNotificationAction('accept', 'Accept',
                showsUserInterface: true),
            const AndroidNotificationAction('decline', 'Decline',
                showsUserInterface: false),
          ]
        : null,
  );

  await plugin.show(
    orderId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentSound: true,
        presentBadge: true,
        presentAlert: true,
        sound: 'enything_bell.wav',
      ),
    ),
    payload: jsonEncode(message.data),
  );

  // SAMSUNG FIX: Play the bell sound via AudioPlayer (bypasses broken channel sound).
  // This is the same approach BellAlertService uses when the app is in the foreground.
  // DartPluginRegistrant is already initialized via WidgetsFlutterBinding above.
  try {
    final player = AudioPlayer();
    await player.setReleaseMode(ReleaseMode.release); // play once, then stop
    await player.play(AssetSource('sounds/enything_bell.wav'));
    debugPrint('FCM background: enything_bell.wav playing via AudioPlayer');
    // Auto-dispose player after bell finishes (max 15s safety net)
    player.onPlayerComplete.listen((_) => player.dispose());
    Future.delayed(const Duration(seconds: 15), () {
      try {
        player.dispose();
      } catch (_) {}
    });
  } catch (e) {
    debugPrint('FCM background: AudioPlayer bell failed: $e');
  }

  if (isUrgent) {
    debugPrint('FCM background shown via Full-Screen Intent: $title');
  } else {
    debugPrint('FCM background shown via LocalNotifications: $title');
  }
}

class EnythingApp extends StatelessWidget {
  final CartProvider cartProvider;
  final PlatformConfigProvider configProvider;
  final RecentlyViewedProvider recentlyViewedProvider;
  const EnythingApp({
    super.key,
    required this.cartProvider,
    required this.configProvider,
    required this.recentlyViewedProvider,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(), lazy: false),
        // Bug #20: use the pre-loaded cartProvider instance
        ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => RbacProvider()),
        ChangeNotifierProvider(create: (_) => TeamProvider()),
        ChangeNotifierProvider(create: (_) => AuditProvider()),
        ChangeNotifierProvider<PlatformConfigProvider>.value(
            value: configProvider),
        ChangeNotifierProvider(create: (_) => CouponProvider()),
        ChangeNotifierProvider<RecentlyViewedProvider>.value(
            value: recentlyViewedProvider),
        ChangeNotifierProvider(create: (_) => ReferralProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            scaffoldMessengerKey: scaffoldMessengerKey,
            navigatorKey: navigatorKey,
            navigatorObservers: [GlobalRouteObserver()],
            builder: (context, child) =>
                MultiShopCartBubbleOverlay(child: child!),
            title: 'Enything',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            initialRoute: AppRoutes.splash,
            onGenerateRoute: AppRoutes.generateRoute,
          );
        },
      ),
    );
  }
}
