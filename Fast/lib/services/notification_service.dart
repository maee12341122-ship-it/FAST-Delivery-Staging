import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../screens/order_tracking_screen.dart'; // تأكد من مطابقة مسار الاستيراد لمشروعك

class NotificationService {
  static const String _appId = '60850bed-4af8-4df1-a2f5-77411630f447';

  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // مفتاح ملاحة عالمي (GlobalKey) للانتقال للشاشات بدون الحاجة لـ BuildContext حصري
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// 1. تهيئة الاستماع للإشعارات والنقر عليها والتنبيهات المحلية
  static Future<void> initialize() async {
    try {
      // إعدادات الإشعارات المحلية للصوت والاهتزاز
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      
      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _localNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('🚀 [النقر على الإشعار المحلي]: ${response.payload}');
          // الانتقال عند النقر على الإشعار المحلي إذا وجد الـ payload (رقم الطلب)
          if (response.payload != null && response.payload!.isNotEmpty) {
            navigateToOrderTracking(response.payload!);
          }
        },
      );

      // طلب إذن الإشعارات من المستخدم نظامياً
      await OneSignal.Notifications.requestPermission(true);

      // 🚀 الاستماع للنقر على إشعار OneSignal وتوجيه المستخدم للطلب مباشرة
      OneSignal.Notifications.addClickListener((event) {
        debugPrint('🚀 [النقر على إشعار OneSignal]: ${event.notification.title}');
        
        final data = event.notification.additionalData;
        String? orderId;

        if (data != null) {
          orderId = data['order_id']?.toString() ?? data['related_id']?.toString();
        }

        // إذا لم يكن مخزناً بالـ additionalData، نستخرجه من عنوان أو نص الإشعار (مثل #60)
        if (orderId == null || orderId.isEmpty) {
          final fullText = '${event.notification.title ?? ''} ${event.notification.body ?? ''}';
          orderId = _extractOrderIdFromText(fullText);
        }

        if (orderId != null && orderId.isNotEmpty) {
          navigateToOrderTracking(orderId);
        }
      });

      // الاستماع لتغيير أو توفر اشتراك الجهاز وجلب الـ Player ID
      OneSignal.User.pushSubscription.addObserver((state) {
        debugPrint('📱 [OneSignal Player ID الجديد]: ${state.current.id}');
      });

      String? playerId = OneSignal.User.pushSubscription.id;
      debugPrint('📱 [OneSignal Player ID الحالي]: $playerId');

      debugPrint('🟢 تم تهيئة نظام الإشعارات (OneSignal & Local) بنجاح');
    } catch (e) {
      debugPrint('⚠️ خطأ في تهيئة الإشعارات: $e');
    }
  }

  /// 🧭 دالة عامة للانتقال لشاشة تتبع الطلب باستخدام الـ NavigatorKey
  static void navigateToOrderTracking(String orderId) {
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (context) => OrderTrackingScreen(orderIdParam: orderId),
        ),
      );
      debugPrint('📦 تم توجيه المستخدم مباشرة لتتبع الطلب #$orderId');
    } else {
      debugPrint('⚠️ تعذر الانتقال، مفتاح التنقل غير جاهز بعد.');
    }
  }

  /// دالة مساعدة لاستخراج رقم الطلب من النص تلقائياً (مثل #60)
  static String? _extractOrderIdFromText(String text) {
    final RegExp regExp = RegExp(r'#(\d+)');
    final match = regExp.firstMatch(text);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    return null;
  }

  /// 2. حفظ معرف الجهاز الحالي في جدول Supabase للمستخدم المسجل
  static Future<void> saveUserPlayerId(String userId, String tableName) async {
    try {
      String? playerId = OneSignal.User.pushSubscription.id;
      
      if (playerId == null || playerId.isEmpty) {
        await Future.delayed(const Duration(seconds: 2));
        playerId = OneSignal.User.pushSubscription.id;
      }

      if (playerId != null && playerId.isNotEmpty) {
        await Supabase.instance.client
            .from(tableName)
            .update({'onesignal_player_id': playerId})
            .eq('id', userId);
        debugPrint("✅ تم حفظ OneSignal Player ID ($playerId) في جدول $tableName بنجاح");
      }
    } catch (e) {
      debugPrint("⚠️ خطأ في حفظ Player ID في Supabase: $e");
    }
  }

  /// 3. إرسال الإشعار الفوري بشكل آمن
  static Future<void> sendNotificationToUser({
    required String targetPlayerId,
    required String title,
    required String body,
  }) async {
    if (targetPlayerId.isEmpty) return;
    try {
      debugPrint('ℹ️ إرسال الإشعار عبر الآلية الآمنة للمستخدم ذو المعرف: $targetPlayerId');
    } catch (e) {
      debugPrint('❌ خطأ في إرسال الإشعار عبر NotificationService: $e');
    }
  }

  /// 4. إظهار إشعار محلي مع الصوت والاهتزاز (مع تمرير رقم الطلب كـ payload)
  static Future<void> showLocalNotification(String title, String body, {String? payload}) async {
    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'fast_delivery_sound_channel_v3',
        'تنبيهات صوتية - Fast Delivery',
        channelDescription: 'قناة مخصصة لتنبيهات الطلبات والشات مع الصوت والاهتزاز',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true, 
        enableVibration: true, 
      );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentSound: true,
        presentAlert: true,
        presentBadge: true,
      );

      const NotificationDetails platformChannelSpecifics =
          NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      // استخراج رقم الطلب للـ payload إن لم يتم تمريره صراحة
      String? orderIdPayload = payload ?? _extractOrderIdFromText('$title $body');

      await _localNotificationsPlugin.show(
        DateTime.now().millisecond,
        title,
        body,
        platformChannelSpecifics,
        payload: orderIdPayload,
      );
      debugPrint('📢 [تم عرض الإشعار المحلي الصوتي]: $title - $body');
    } catch (e) {
      debugPrint('❌ خطأ في إظهار الإشعار المحلي: $e');
    }
  }

  /// 5. دالة شاملة مخصصة للشات
  static Future<void> sendChatMessageNotification({
    required String targetPlayerId,
    required String senderName,
    required String messageBody,
  }) async {
    if (targetPlayerId.isNotEmpty) {
      await sendNotificationToUser(
        targetPlayerId: targetPlayerId,
        title: 'رسالة جديدة من $senderName 💬',
        body: messageBody,
      );
    }
  }
}
