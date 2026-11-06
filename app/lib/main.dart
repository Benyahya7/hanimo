// Hanimo 2.0 — from-scratch rebuild. Animeify only, layered, and nothing
// fails silently: every load/action returns a Result with a readable
// message, and the screens always show it.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:animeapp/firebase_options.dart';
import 'package:animeapp/l10n/gen/app_localizations.dart';
import 'package:animeapp/presentation/app_state.dart';
import 'package:animeapp/presentation/theme.dart';
import 'package:animeapp/presentation/screens/root_page.dart';
import 'package:animeapp/presentation/screens/updates_page.dart';

final _notifications = FlutterLocalNotificationsPlugin();

Future<void> _setupNotifications() async {
  // Android-only: no local-notifications plugin or notification
  // permission on web — skip entirely there.
  if (kIsWeb) return;
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _notifications.initialize(settings: const InitializationSettings(android: android));
  const channel = AndroidNotificationChannel('hanimo_updates', 'Hanimo updates', importance: Importance.high);
  await _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
  // Ask exactly once per install.
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('notifPermAsked') != true) {
    await Permission.notification.request();
    await prefs.setBool('notifPermAsked', true);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    // Never white-screen: the app runs on local data and every screen
    // shows the real error with Retry (the 2.0 "nothing fails silently" rule).
    debugPrint('Firebase init failed, continuing local-only: $e');
  }
  await _setupNotifications();
  runApp(const HanimoApp());
}

class HanimoApp extends StatelessWidget {
  const HanimoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: Consumer<AppState>(
        builder: (context, d, _) => MaterialApp(
          title: 'Hanimo',
          debugShowCheckedModeBanner: false,
          locale: Locale(d.langIsArabic ? 'ar' : 'en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: HanimoColors.background,
            colorScheme: const ColorScheme.dark(
              primary: HanimoColors.violet,
              secondary: HanimoColors.pink,
              surface: HanimoColors.surface,
            ),
            appBarTheme: const AppBarTheme(backgroundColor: HanimoColors.background, elevation: 0),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(backgroundColor: HanimoColors.surface),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(backgroundColor: HanimoColors.violet, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            ),
          ),
          routes: {
            '/': (_) => const RootPage(),
            '/updates': (_) => const UpdatesPage(),
          },
          initialRoute: '/',
        ),
      ),
    );
  }
}
