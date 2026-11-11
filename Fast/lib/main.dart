import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/notification_service.dart';
import 'providers/app_state.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/customer/order_tracking_screen.dart'; // 👈 استيراد شاشة تتبع الطلب الموحدة

// 🔑 مفتاح التنقل العام (NavigatorKey) لتوجيه المستخدم من الإشعارات الخارجية من أي مكان
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 0. التحقق مما إذا كانت هذه هي المرة الأولى لتثبيت التطبيق
  final prefs = await SharedPreferences.getInstance();
  final bool hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

  // 1. تهيئة OneSignal للإشعارات الخارجية وتفعيل مستمع النقر لتوجيه المستخدم للطلب المحدد
  try {
    OneSignal.initialize("60850bed-4af8-4df1-a2f5-77411630f447");
    
    // طلب إذن الإشعارات من المستخدم
    await OneSignal.Notifications.requestPermission(true);
    
    // 🛎️ مستمع النقر على الإشعار الخارجي (عندما يكون التطبيق في الخلفية أو مغلقاً)
    OneSignal.Notifications.addClickListener((event) {
      final data = event.notification.additionalData;
      // استخراج رقم الطلب من البيانات الإضافية أو النص
      final String? orderId = data?['order_id']?.toString() ?? 
                              data?['related_id']?.toString() ?? 
                              _extractOrderIdFromNotification(event.notification.title ?? '', event.notification.body ?? '');
      
      if (orderId != null && orderId.isNotEmpty) {
        // الانتقال الفوري لشاشة تتبع الطلب باستخدام المفتاح العام
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => OrderTrackingScreen(orderIdParam: orderId),
          ),
        );
      }
    });

    debugPrint("✅ تمت تهيئة OneSignal ومستمع النقر بنجاح");
  } catch (e) {
    debugPrint('⚠️ خطأ في تهيئة OneSignal: $e');
  }

  // 2. تهيئة Supabase
  try {
    await Supabase.initialize(
      url: 'https://pzokmpthkpuofrntufyp.supabase.co',
      anonKey: 'sb_publishable_uI01Ippgs8yXi9k18JO8DQ_Zm74RqQf',
    );
  } catch (e) {
    debugPrint('⚠️ خطأ في اتصال Supabase: $e');
  }

  // 3. تهيئة خدمة الإشعارات المحلية
  try {
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('⚠️ خطأ في تهيئة الإشعارات المحلية: $e');
  }

  // 4. إنشاء AppState وتهيئة الجلسة المحفوظة تلقائياً
  final appState = AppState();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
      ],
      child: FastApp(hasSeenOnboarding: hasSeenOnboarding),
    ),
  );
}

// 🔍 دالة مساعدة لاستخراج رقم الطلب من عنوان أو نص الإشعار الخارجي
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
  const FastApp({Key? key, required this.hasSeenOnboarding}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return MaterialApp(
      title: 'Fast',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey, // 👈 ربط مفتاح التنقل العام هنا ليعمل بانتظام
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
      // 👈 إذا شاهدها من قبل يذهب للـ SplashScreen، وإذا كانت أول مرة يذهب للـ OnboardingScreen
      home: hasSeenOnboarding ? const SplashScreen() : const OnboardingScreen(),
    );
  }
}
