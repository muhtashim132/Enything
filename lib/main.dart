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
import 'services/notification_service.dart';

// Global Supabase client access
late final SupabaseClient supabase;

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
    anonKey: supabaseAnonKey, // ignore: deprecated_member_use — SDK alias still works
  );

  // Set Supabase instance locally
  supabase = Supabase.instance.client;

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
    ),
  );

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Load cart async to prevent blocking startup
  final cartProvider = CartProvider();
  cartProvider.loadCart(); // DO NOT AWAIT

  // Load platform config asynchronously to avoid blocking the Splash Screen
  final configProvider = PlatformConfigProvider();
  configProvider.load(); // DO NOT AWAIT

  // Initialize Notification Service async to prevent Android channel creation deadlocks
  NotificationService().init(); // DO NOT AWAIT

  // Deep linking: Handle notification tap when app is in background
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    _handleNotificationClick(message.data);
  });

  // Deep linking: Handle notification tap when app is terminated
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleNotificationClick(initialMessage.data);
    });
  }

  runApp(EnythingApp(
    cartProvider: cartProvider,
    configProvider: configProvider,
  ));
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void _handleNotificationClick(Map<String, dynamic> data) {
  final role = data['role'] as String?;
  final action = data['action'] as String?;

  if (role == 'seller') {
    // Go directly to the Seller Orders page (Pending tab is tab 0 by default)
    // pushNamedAndRemoveUntil keeps the seller dashboard as the base so back works
    navigatorKey.currentState
        ?.pushNamedAndRemoveUntil(AppRoutes.sellerDashboard, (route) => false);
    // Then push the orders page on top so the seller sees the Pending list immediately
    Future.microtask(() {
      navigatorKey.currentState?.pushNamed(AppRoutes.sellerOrders);
    });
  } else if (role == 'rider' || role == 'delivery' || action == 'new_order') {
    // Go to Delivery Dashboard — Available Orders section shows new orders
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
        AppRoutes.deliveryDashboard, (route) => false);
  } else if (data['order_id'] != null) {
    // Customer tap → go directly to their order tracking page
    navigatorKey.currentState?.pushNamed(
      AppRoutes.trackOrder,
      arguments: {'orderId': data['order_id']},
    );
  }
}

/// Background FCM handler — MUST be a top-level function (not a closure).
/// Called by FCM when a DATA-ONLY message arrives and the app is killed/backgrounded.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  // If the message contains a notification payload, Google Play Services will automatically
  // display a system notification. We should NOT create a duplicate local notification.
  if (message.notification != null) {
    debugPrint('FCM background: OS handling notification');
    return;
  }

  // For data-only messages, title/body come from message.data
  final title = message.data['title'] as String? ??
      message.notification?.title ??
      'Zappy';
  final body =
      message.data['body'] as String? ?? message.notification?.body ?? '';

  if (title.isEmpty || body.isEmpty) return;

  final plugin = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('ic_notification');
  await plugin
      .initialize(const InitializationSettings(android: androidSettings));

  // Create the channel here too — background isolate may not have it yet
  final androidPlugin = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      'enything_push_channel',
      'Enything Notifications',
      description: 'Push notifications for orders and updates',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    ),
  );

  await plugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'enything_push_channel',
        'Enything Notifications',
        channelDescription: 'Push notifications for orders and updates',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: 'ic_notification',
      ),
    ),
    payload: jsonEncode(message.data),
  );
  debugPrint('FCM background shown: $title');
}

class EnythingApp extends StatelessWidget {
  final CartProvider cartProvider;
  final PlatformConfigProvider configProvider;
  const EnythingApp({
    super.key,
    required this.cartProvider,
    required this.configProvider,
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
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
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
