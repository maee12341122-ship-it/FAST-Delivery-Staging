import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/fcm_push_service.dart';
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

  final appState = AppState();

  void handleNotificationData(Map<String, dynamic> data, String title, String body) {
    final String? orderId = data['order_id']?.toString() ??
        data['related_id']?.toString() ??
        _extractOrderIdFromNotification(title, body);

    if (orderId != null && orderId.isNotEmpty) {
      final String eventType =
          data['type']?.toString() ?? data['event_type']?.toString() ?? '';
      final bool isChatNotification = eventType == 'chat' ||
          eventType == 'chat_message' ||
          title.contains('رسالة جديدة');

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
  }

  try {
    await FcmPushService.initialize(
      onNotificationTap: (payload) {
        final String title = payload['title']?.toString() ?? '';
        final String body = payload['body']?.toString() ?? '';
        handleNotificationData(payload, title, body);
      },
    );
  } catch (e) {
    debugPrint('⚠️ خطأ في تهيئة إشعارات FCM: $e');
  }

  // طلب إذن الإشعارات ومزامنة التوكن فور توفر بيانات المستخدم
  unawaited(FcmPushService.requestPermissionSafe());
  unawaited(appState.syncFcmTokenForCurrentUsers());

  try {
    // فتح التطبيق من إشعار وهو في الخلفية
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final String title =
          message.notification?.title ?? message.data['title']?.toString() ?? '';
      final String body =
          message.notification?.body ?? message.data['body']?.toString() ?? '';
      handleNotificationData(message.data, title, body);
    });

    // فتح التطبيق من إشعار والتطبيق مغلق تماماً (Terminated)
    final RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final String title = initialMessage.notification?.title ??
            initialMessage.data['title']?.toString() ??
            '';
        final String body = initialMessage.notification?.body ??
            initialMessage.data['body']?.toString() ??
            '';
        handleNotificationData(initialMessage.data, title, body);
      });
    }

    debugPrint('✅ تم تسجيل مستمع النقر الموحد على إشعارات FCM بنجاح');
  } catch (e) {
    debugPrint('⚠️ خطأ في تسجيل مستمع النقر لـ FCM: $e');
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
