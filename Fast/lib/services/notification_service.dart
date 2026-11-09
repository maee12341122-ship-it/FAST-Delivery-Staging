import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // 👈 استيراد مكتبة الإشعارات المحلية للصوت

class NotificationService {
  static const String _appId = '60850bed-4af8-4df1-a2f5-77411630f447';
  static const String _restApiKey = 'mzt7cwtzrud7vgcher53kfn6x'; // 👈 مفتاحك الحقيقي لإرسال الإشعارات

  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// 1. تهيئة الاستماع للإشعارات والنقر عليها والتنبيهات المحلية
  static Future<void> initialize() async {
    try {
      // إعدادات الإشعارات المحلية للصوت والاهتزاز
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);
      await _localNotificationsPlugin.initialize(initializationSettings);

      // طلب إذن الإشعارات من المستخدم نظامياً
      await OneSignal.Notifications.requestPermission(true);

      // الاستماع للنقر على الإشعار من المستخدم
      OneSignal.Notifications.addClickListener((event) {
        debugPrint('🚀 [النقر على الإشعار]: ${event.notification.title}');
      });

      // الاستماع لتغيير أو توفر اشتراك الجهاز وجلب الـ Player ID
      OneSignal.User.pushSubscription.addObserver((state) {
        debugPrint('📱 [OneSignal Player ID الجديد]: ${state.current.id}');
      });

      String? playerId = OneSignal.User.pushSubscription.id;
      debugPrint('📱 [OneSignal Player ID الحالي]: $playerId');

      debugPrint('🟢 تم تهيئة نظام الإشعارات (OneSignal) بنجاح');
    } catch (e) {
      debugPrint('⚠️ خطأ في تهيئة الإشعارات: $e');
    }
  }

  /// 2. حفظ معرف الجهاز الحالي في جدول Supabase للمستخدم المسجل (عميل، مندوب، مشرف)
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
      } else {
        debugPrint("⚠️ لم يتم العثور على Player ID للجهاز بعد، يرجى التحقق من الاتصال.");
      }
    } catch (e) {
      debugPrint("⚠️ خطأ في حفظ Player ID في Supabase: $e");
    }
  }

  /// 3. إرسال الإشعار الفوري (للشات أو التنبيهات) عبر OneSignal REST API
  static Future<void> sendNotificationToUser({
    required String targetPlayerId,
    required String title,
    required String body,
  }) async {
    if (targetPlayerId.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Basic $_restApiKey',
        },
        body: jsonEncode({
          'app_id': _appId,
          'include_player_ids': [targetPlayerId],
          'headings': {'en': title, 'ar': title},
          'contents': {'en': body, 'ar': body},
          'android_sound': 'default', // 👈 التأكد من تشغيل صوت أندرويد الافتراضي
          'ios_sound': 'default',     // 👈 التأكد من تشغيل صوت آيفون الافتراضي
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ تم إرسال إشعار الشات بنجاح عبر NotificationService');
      } else {
        debugPrint('⚠️ فشل إرسال إشعار الشات: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ خطأ في إرسال الإشعار عبر NotificationService: $e');
    }
  }

  /// 4. إظهار إشعار محلي مع الصوت والاهتزاز عند الحاجة داخل التطبيق
  static Future<void> showLocalNotification(String title, String body) async {
    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'fast_delivery_sound_channel_v3',
        'تنبيهات صوتية - Fast Delivery',
        channelDescription: 'قناة مخصصة لتنبيهات الطلبات مع الصوت والاهتزاز',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true, // 👈 تفعيل الصوت
        enableVibration: true, // 👈 تفعيل الاهتزاز
      );

      const NotificationDetails platformChannelSpecifics =
          NotificationDetails(android: androidPlatformChannelSpecifics);

      await _localNotificationsPlugin.show(
        DateTime.now().millisecond,
        title,
        body,
        platformChannelSpecifics,
      );
      debugPrint('📢 [تم عرض الإشعار المحلي الصوتي]: $title - $body');
    } catch (e) {
      debugPrint('❌ خطأ في إظهار الإشعار المحلي: $e');
    }
  }
}
