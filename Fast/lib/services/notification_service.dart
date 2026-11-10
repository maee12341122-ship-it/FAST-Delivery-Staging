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
        },
      );

      // طلب إذن الإشعارات من المستخدم نظامياً
      await OneSignal.Notifications.requestPermission(true);

      // الاستماع للنقر على الإشعار من المستخدم (OneSignal)
      OneSignal.Notifications.addClickListener((event) {
        debugPrint('🚀 [النقر على إشعار OneSignal]: ${event.notification.title}');
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

  /// 3. إرسال الإشعار الفوري (للشات أو التنبيهات) عبر OneSignal REST API (خارجي)
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
          'android_sound': 'default', 
          'ios_sound': 'default',     
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ تم إرسال الإشعار الخارجي بنجاح عبر OneSignal');
      } else {
        debugPrint('⚠️ فشل إرسال الإشعار الخارجي: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ خطأ في إرسال الإشعار عبر NotificationService: $e');
    }
  }

  /// 4. إظهار إشعار محلي مع الصوت والاهتزاز (داخلي - يعمل عندما التطبيق مفتوح)
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

      await _localNotificationsPlugin.show(
        DateTime.now().millisecond,
        title,
        body,
        platformChannelSpecifics,
        payload: payload,
      );
      debugPrint('📢 [تم عرض الإشعار المحلي الصوتي]: $title - $body');
    } catch (e) {
      debugPrint('❌ خطأ في إظهار الإشعار المحلي: $e');
    }
  }

  /// 5. دالة شاملة مخصصة للشات (ترسل إشعار خارجي عبر OneSignal + تظهر محلياً إذا تطلب الأمر)
  static Future<void> sendChatMessageNotification({
    required String targetPlayerId,
    required String senderName,
    required String messageBody,
  }) async {
    // 1. إرسال الإشعار الخارجي للطرف الآخر عبر OneSignal
    if (targetPlayerId.isNotEmpty) {
      await sendNotificationToUser(
        targetPlayerId: targetPlayerId,
        title: 'رسالة جديدة من $senderName 💬',
        body: messageBody,
      );
    }
  }
}
