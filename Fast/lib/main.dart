import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/notification_service.dart';
import 'providers/app_state.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/order_tracking_screen.dart';
import 'screens/chat_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final bool hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

  try {
    await Supabase.initialize(
      url: 'https://pzokmpthkpuofrntufyp.supabase.co',
      anonKey: 'sb_publishable_uI01Ippgs8yXi9k18JO8DQ_Zm74RqQf',
    );
  } catch (e) {
    debugPrint('⚠️ خطأ في اتصال Supabase: $e');
  }

  try {
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('⚠️ خطأ في تهيئة الإشعارات المحلية: $e');
  }

  final appState = AppState();

  try {
    OneSignal.initialize("60850bed-4af8-4df1-a2f5-77411630f447");
    await OneSignal.Notifications.requestPermission(true);

    OneSignal.Notifications.addClickListener((event) {
      final data = event.notification.additionalData;
      final String title = event.notification.title ?? '';
      final String body = event.notification.body ?? '';
      final String? orderId = data?['order_id']?.toString() ??
          data?['related_id']?.toString() ??
          _extractOrderIdFromNotification(title, body);

      if (orderId != null && orderId.isNotEmpty) {
        final bool isChatNotification =
            data?['type']?.toString() == 'chat' || title.contains('رسالة جديدة');

        if (isChatNotification) {
          final String role = appState.isAdminLoggedIn
              ? 'admin'
              : (appState.currentCourier != null ? 'courier' : 'customer');
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                orderId: orderId,
                userRole: role,
                targetChat: 'unified_order_chat',
              ),
            ),
          );
        } else {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (context) => OrderTrackingScreen(orderIdParam: orderId),
            ),
          );
        }
      }
    });

    debugPrint("✅ تمت تهيئة OneSignal ومستمع النقر بنجاح");
  } catch (e) {
    debugPrint('⚠️ خطأ في تهيئة OneSignal: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
      ],
      child: FastApp(hasSeenOnboarding: hasSeenOnboarding),
    ),
  );
}

String? _extractOrderIdFromNotification(String title, String body) {
  final RegExp regExp = RegExp(r'(?:طلب|#)\s*(\d+)');
  final match = regExp.firstMatch('$title $body');
  if (match != null && match.groupCount >= 1) {
    return match.group(1);
  }
  return null;
}

class FastApp extends StatelessWidget {
  final bool hasSeenOnboarding;
  const FastApp({super.key, required this.hasSeenOnboarding});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return MaterialApp(
      title: 'Fast',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      themeMode: appState.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.grey[100],
        primaryColor: Colors.amber,
        colorScheme: const ColorScheme.light(
          primary: Colors.amber,
          secondary: Colors.amber,
          surface: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.amber,
        colorScheme: const ColorScheme.dark(
          primary: Colors.amber,
          secondary: Colors.amber,
          surface: Color(0xFF1E1E1E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          foregroundColor: Colors.amber,
        ),
      ),
      home: hasSeenOnboarding ? const SplashScreen() : const OnboardingScreen(),
    );
  }
}
