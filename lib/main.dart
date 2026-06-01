import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';


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

  runApp(EnythingApp(
    cartProvider: cartProvider,
    configProvider: configProvider,
  ));
}

/// Background FCM handler — MUST be a top-level function (not a closure).
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // No UI work here — just log or store the notification if needed
  debugPrint('FCM background: ${message.notification?.title}');
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
