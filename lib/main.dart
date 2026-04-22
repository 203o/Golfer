import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/auth_service.dart';
import 'services/auth_provider.dart';
import 'services/subscription_provider.dart';
import 'services/draw_provider.dart';
import 'services/charity_provider.dart';
import 'services/admin_analytics_provider.dart';
import 'services/admin_user_management_provider.dart';
import 'services/tournament_provider.dart';
import 'firebase_options.dart';

// === SCREENS ===
import 'screens/landing_screen.dart';
import 'screens/onboarding_gate_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("dotenv load skipped: $e");
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase Initialization Error: $e");
    runApp(const ErrorApp());
    return;
  }

  try {
    final authService = AuthService();
    final authProvider = AuthProvider(authService: authService);

    await authProvider.initialize();

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: authService),
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider(create: (context) => SubscriptionProvider()),
          ChangeNotifierProvider(create: (context) => DrawProvider()),
          ChangeNotifierProvider(create: (context) => CharityProvider()),
          ChangeNotifierProvider(create: (context) => AdminAnalyticsProvider()),
          ChangeNotifierProvider(
            create: (context) => AdminUserManagementProvider(),
          ),
          ChangeNotifierProvider(create: (context) => TournamentProvider()),
        ],
        child: const GolfCharityDrawApp(),
      ),
    );
  } catch (e) {
    debugPrint('FATAL ERROR during initialization: $e');
    runApp(const ErrorApp());
  }
}

class GolfCharityDrawApp extends StatelessWidget {
  const GolfCharityDrawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Golf Charity Draw',
          theme: ThemeData(
            useMaterial3: true,
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            scaffoldBackgroundColor: const Color(0xFFF3F5F7),
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1993D1),
              secondary: Color(0xFF2FB67A),
              surface: Colors.white,
              onSurface: Color(0xFF0F172A),
              onPrimary: Colors.white,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF3F5F7),
              foregroundColor: Color(0xFF0F172A),
              surfaceTintColor: Colors.transparent,
              elevation: 0,
            ),
            cardTheme: CardThemeData(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFD9DEE5)),
              ),
            ),
            chipTheme: ChipThemeData(
              backgroundColor: const Color(0xFFEAF4FB),
              selectedColor: const Color(0xFFD6ECFA),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
                side: const BorderSide(color: Color(0xFFD0DFEA)),
              ),
              labelStyle: const TextStyle(
                color: Color(0xFF235A7A),
                fontWeight: FontWeight.w600,
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFD5DEE8)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFD5DEE8)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF1993D1)),
              ),
              labelStyle: const TextStyle(color: Color(0xFF5B677B)),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1993D1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1B4E6B),
                side: const BorderSide(color: Color(0xFFD0D9E4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            textTheme: const TextTheme(
              bodyLarge: TextStyle(color: Color(0xFF102033)),
              bodyMedium: TextStyle(color: Color(0xFF243449)),
              titleLarge: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
              ),
              titleMedium: TextStyle(
                color: Color(0xFF1B2A3C),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          home: _buildHomeScreen(context, auth),
        );
      },
    );
  }

  Widget _buildHomeScreen(BuildContext context, AuthProvider auth) {
    if (auth.isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F5F7),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/icons/app_icon.png',
                width: 96,
                height: 96,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.golf_course,
                  color: Color(0xFF607289),
                  size: 72,
                ),
              ),
              const SizedBox(height: 20),
              const CircularProgressIndicator(color: Color(0xFF1993D1)),
            ],
          ),
        ),
      );
    }

    if (auth.isAuthenticated) {
      return const OnboardingGateScreen();
    }

    return const LandingScreen();
  }
}

// === HELPER CLASSES ===

class ErrorApp extends StatelessWidget {
  const ErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        backgroundColor: Color(0xFFF3F5F7),
        body: Center(
            child: Text('Startup Error',
                style: TextStyle(color: Color(0xFF1B5D86)))),
      ),
    );
  }
}
