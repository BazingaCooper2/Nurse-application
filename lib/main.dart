import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nurse_tracking_app/pages/splash_page.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- Initialize Supabase ---
  await Supabase.initialize(
    url: 'https://asbfhxdomvclwsrekdxi.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFzYmZoeGRvbXZjbHdzcmVrZHhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQzMjI3OTUsImV4cCI6MjA2OTg5ODc5NX0.0VzbWIc-uxIDhI03g04n8HSPRQ_p01UTJQ1sg8ggigU',
  );

  // --- Initialize local notifications ---
  await initLocalNotifs();

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

final supabase = Supabase.instance.client;

// Global notifications plugin
final FlutterLocalNotificationsPlugin localNotifs =
    FlutterLocalNotificationsPlugin();

Future<void> initLocalNotifs() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();

  await localNotifs.initialize(
    const InitializationSettings(android: androidInit, iOS: iosInit),
    onDidReceiveNotificationResponse: (resp) async {
      // When user taps the notification, open device Location Settings
      await Geolocator.openLocationSettings();
    },
  );

  // Android 13+ runtime notifications permission
  await localNotifs
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  // iOS permissions
  await localNotifs
      .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, badge: true, sound: true);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return MaterialApp(
      title: 'Nurse Tracking App',
      debugShowCheckedModeBanner: false,
      theme: themeProvider.lightTheme,
      darkTheme: themeProvider.darkTheme,
      themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const SplashPage(),
    );
  }
}

extension ContextExtension on BuildContext {
  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(this).colorScheme.error
            : Theme.of(this).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
