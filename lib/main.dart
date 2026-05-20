import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme/app_theme.dart';
import 'config/routes.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/location_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/rbac_provider.dart';
import 'providers/team_provider.dart';
import 'providers/audit_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Disable runtime fetching to prevent ClientException when network is unstable
  // or blocked. This avoids "Connection closed before full header was received" errors.
  GoogleFonts.config.allowRuntimeFetching = false;

  await dotenv.load(fileName: '.env');

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

  runApp(EnythingApp(cartProvider: cartProvider));
}

class EnythingApp extends StatelessWidget {
  final CartProvider cartProvider;
  const EnythingApp({super.key, required this.cartProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        // Bug #20: use the pre-loaded cartProvider instance
        ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => RbacProvider()),
        ChangeNotifierProvider(create: (_) => TeamProvider()),
        ChangeNotifierProvider(create: (_) => AuditProvider()),
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
