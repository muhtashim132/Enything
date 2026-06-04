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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Disable runtime fetching to prevent ClientException when network is unstable
  // or blocked. This avoids "Connection closed before full header was received" errors.
  GoogleFonts.config.allowRuntimeFetching = false;

  await dotenv.load(fileName: '.env');

  // Initialize Firebase (used only for FCM push notifications — NOT for auth)
  await Firebase.initializeApp();

  // Must be a top-level function for background FCM handling
  FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);


  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
    ),
  );

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Bug #20: load persisted cart before first frame
  final cartProvider = CartProvider();
  await cartProvider.loadCart();

  // Load platform config
  final configProvider = PlatformConfigProvider();
  await configProvider.load();

  // Initialize Notification Service
  await NotificationService().init();

  runApp(EnythingApp(
    cartProvider: cartProvider,
    configProvider: configProvider,
  ));
}

/// Background FCM handler — MUST be a top-level function (not a closure).
/// Called by FCM when a DATA-ONLY message arrives and the app is killed/backgrounded.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  // For data-only messages, title/body come from message.data
  final title = message.data['title'] as String? ??
      message.notification?.title ??
      'Zappy';
  final body = message.data['body'] as String? ??
      message.notification?.body ??
      '';

  if (title.isEmpty || body.isEmpty) return;

  final plugin = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidSettings));

  // Create the channel here too — background isolate may not have it yet
  final androidPlugin = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      'zappy_push_channel',
      'Zappy Notifications',
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
        'zappy_push_channel',
        'Zappy Notifications',
        channelDescription: 'Push notifications for orders and updates',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: 'ic_launcher',
      ),
    ),
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
        ChangeNotifierProvider<PlatformConfigProvider>.value(value: configProvider),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
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
