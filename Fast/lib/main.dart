import 'dart:async';
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

  void pushRouteSafely(Route<dynamic> route) {
    final nav = navigatorKey.currentState;
    if (nav != null) {
      nav.push(route);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(route);
    });
  }

  void handleNotificationData(
    Map<String, dynamic> data,
    String title,
    String body,
  ) {
    final String? orderId = data['order_id']?.toString().trim() ??
        data['related_id']?.toString().trim() ??
        _extractOrderIdFromNotification(title, body);

    if (orderId != null && orderId.isNotEmpty) {
      final String eventType =
          (data['type'] ?? data['event_type'] ?? '').toString().trim().toLowerCase();
      final String chatId =
          (data['chat_id'] ?? data['chatId'] ?? '').toString().trim();
      final bool isChatNotification = eventType == 'chat' ||
          eventType == 'chat_message' ||
          chatId.isNotEmpty ||
          title.contains('رسالة جديدة');

      if (isChatNotification) {
        final String role = appState.isAdminLoggedIn
            ? 'admin'
            : (appState.currentCourier != null ? 'courier' : 'customer');
        final String targetChat =
            (data['target_chat']?.toString().trim().isNotEmpty == true)
                ? data['target_chat'].toString().trim()
                : (role == 'courier' ? 'admin_courier' : 'unified_order_chat');
        pushRouteSafely(
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              orderId: orderId,
              userRole: role,
              targetChat: targetChat,
            ),
          ),
        );
      } else {
        pushRouteSafely(
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
        final String title = (payload['title'] ?? 'إشعار جديد').toString();
        final String body = (payload['body'] ?? '').toString();
        appState.recordExternalPushNotification(
          title: title,
          body: body,
          data: payload,
        );
        handleNotificationData(payload, title, body);
      },
      onForegroundMessage: (messageData) {
        final String title = (messageData['title'] ?? 'إشعار جديد').toString();
        final String body = (messageData['body'] ?? '').toString();
        appState.recordExternalPushNotification(
          title: title,
          body: body,
          data: messageData,
        );
      },
    );
  } catch (e) {
    debugPrint('⚠️ خطأ في تهيئة إشعارات FCM: $e');
  }

  unawaited(FcmPushService.requestPermissionSafe());
  unawaited(appState.syncFcmTokenForCurrentUsers());

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
