import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../main.dart' show navigatorKey;
import '../screens/order_tracking_screen.dart';
import 'api_service.dart';

class NotificationService {
  static const String _appId = '60850bed-4af8-4df1-a2f5-77411630f447';

  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static final http.Client _httpClient = http.Client();

  static Uri _buildBackendUri(String path) {
    final base = ApiService.baseUrl.endsWith('/')
        ? ApiService.baseUrl.substring(0, ApiService.baseUrl.length - 1)
        : ApiService.baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$normalizedPath');
  }

  static Map<String, String> _authHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static int _nextNotificationId() {
    return DateTime.now().microsecondsSinceEpoch % 2147483647;
  }

  /// 1. تهيئة الاستماع للإشعارات والنقر عليها والتنبيهات المحلية
  static Future<void> initialize({
    void Function(String playerId)? onPlayerIdChanged,
  }) async {
    try {
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
          if (response.payload != null && response.payload!.isNotEmpty) {
            navigateToOrderTracking(response.payload!);
          }
        },
      );

      OneSignal.initialize(_appId);

      // طلب إذن الإشعارات من المستخدم نظامياً
      await OneSignal.Notifications.requestPermission(true);

      // 🚀 الاستماع للنقر على إشعار OneSignal وتوجيه المستخدم للطلب مباشرة
      OneSignal.Notifications.addClickListener((event) {
        debugPrint(
            '🚀 [النقر على إشعار OneSignal]: ${event.notification.title}');

        final data = event.notification.additionalData;
        String? orderId;

        if (data != null) {
          orderId =
              data['order_id']?.toString() ?? data['related_id']?.toString();
        }

        if (orderId == null || orderId.isEmpty) {
          final fullText =
              '${event.notification.title ?? ''} ${event.notification.body ?? ''}';
          orderId = _extractOrderIdFromText(fullText);
        }

        if (orderId != null && orderId.isNotEmpty) {
          navigateToOrderTracking(orderId);
        }
      });

      // الاستماع لتغيير أو توفر اشتراك الجهاز وجلب الـ Player ID
      OneSignal.User.pushSubscription.addObserver((state) {
        final newId = state.current.id;
        debugPrint('📱 [OneSignal Player ID الجديد]: $newId');
        if (newId != null && newId.trim().isNotEmpty && onPlayerIdChanged != null) {
          onPlayerIdChanged(newId.trim());
        }
      });

      final String? playerId = OneSignal.User.pushSubscription.id;
      debugPrint('📱 [OneSignal Player ID الحالي]: $playerId');
      if (playerId != null && playerId.trim().isNotEmpty && onPlayerIdChanged != null) {
        onPlayerIdChanged(playerId.trim());
      }

      debugPrint('🟢 تم تهيئة نظام الإشعارات (OneSignal & Local) بنجاح');
    } catch (e) {
      debugPrint('⚠️ خطأ في تهيئة الإشعارات: $e');
    }
  }

  /// 🧭 دالة عامة للانتقال لشاشة تتبع الطلب باستخدام الـ NavigatorKey الموحد
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
    final RegExp regExp = RegExp(r'(?:طلب|#)\s*(\d+)');
    final match = regExp.firstMatch(text);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    return null;
  }

  /// 2. حفظ معرف الجهاز الحالي في جدول Supabase للمستخدم المسجل بشكل آمن ومتوافق مع المخطط
  static Future<void> saveUserPlayerId(
    String userId,
    String tableName, {
    String? identifierValue,
  }) async {
    try {
      String? playerId = OneSignal.User.pushSubscription.id;

      if (playerId == null || playerId.isEmpty) {
        await Future.delayed(const Duration(seconds: 2));
        playerId = OneSignal.User.pushSubscription.id;
      }

      if (playerId == null || playerId.isEmpty) return;

      final client = Supabase.instance.client;
      final cleanTable = tableName.trim();
      final cleanId = userId.trim();

      if (cleanTable == 'admins') {
        final intAdminId = int.tryParse(cleanId);
        if (intAdminId != null) {
          await client
              .from('admins')
              .update({'onesignal_player_id': playerId})
              .eq('id', intAdminId);
        } else if (identifierValue != null &&
            identifierValue.trim().isNotEmpty) {
          final idVal = identifierValue.trim().toLowerCase();
          final usernameVal =
              idVal.contains('@') ? idVal.split('@').first : idVal;
          await client
              .from('admins')
              .update({'onesignal_player_id': playerId})
              .eq('username', usernameVal);
        } else {
          final authUser = client.auth.currentUser;
          final email = (authUser?.email ?? '').trim().toLowerCase();
          if (email.isNotEmpty) {
            final usernameVal =
                email.contains('@') ? email.split('@').first : email;
            await client
                .from('admins')
                .update({'onesignal_player_id': playerId})
                .eq('username', usernameVal);
          }
        }
      } else if (cleanTable == 'couriers') {
        final authUser = client.auth.currentUser;
        if (authUser != null && cleanId == authUser.id) {
          await client
              .from('couriers')
              .update({'onesignal_player_id': playerId})
              .eq('auth_user_id', authUser.id);
        } else {
          await client
              .from('couriers')
              .update({'onesignal_player_id': playerId})
              .eq('id', cleanId);
        }
      } else {
        await client
            .from(cleanTable)
            .update({'onesignal_player_id': playerId})
            .eq('id', cleanId);
      }

      debugPrint(
          '✅ تم حفظ OneSignal Player ID ($playerId) في جدول $cleanTable بنجاح');
    } catch (e) {
      debugPrint('⚠️ خطأ في حفظ Player ID في Supabase: $e');
    }
  }

  /// 3. إرسال الإشعار الفوري عبر Node.js Backend (حيث تُخزن مفاتيح OneSignal السرية)
  static Future<void> sendNotificationToUser({
    required String targetPlayerId,
    required String title,
    required String body,
    Map<String, dynamic>? additionalData,
  }) async {
    final cleanPlayerId = targetPlayerId.trim();
    if (cleanPlayerId.isEmpty) return;

    try {
      final payload = <String, dynamic>{
        'target_player_id': cleanPlayerId,
        'title': title.trim(),
        'body': body.trim(),
        if (additionalData != null && additionalData.isNotEmpty)
          'additional_data': additionalData,
      };

      final response = await _httpClient
          .post(
            _buildBackendUri('/api/notifications/send'),
            headers: _authHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
            '⚠️ تعذر إرسال الإشعار عبر الخادم (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ خطأ في إرسال الإشعار عبر NotificationService: $e');
    }
  }

  /// 4. إظهار إشعار محلي مع الصوت والاهتزاز (مع تمرير رقم الطلب كـ payload)
  static Future<void> showLocalNotification(
    String title,
    String body, {
    String? payload,
  }) async {
    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'fast_delivery_sound_channel_v3',
        'تنبيهات صوتية - Fast Delivery',
        channelDescription:
            'قناة مخصصة لتنبيهات الطلبات والشات مع الصوت والاهتزاز',
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

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      final String? orderIdPayload =
          payload ?? _extractOrderIdFromText('$title $body');

      await _localNotificationsPlugin.show(
        _nextNotificationId(),
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
    String? orderId,
  }) async {
    if (targetPlayerId.isNotEmpty) {
      await sendNotificationToUser(
        targetPlayerId: targetPlayerId,
        title: orderId != null && orderId.isNotEmpty
            ? 'رسالة جديدة في الطلب #$orderId 💬'
            : 'رسالة جديدة من $senderName 💬',
        body: orderId != null && orderId.isNotEmpty
            ? '$senderName: $messageBody'
            : messageBody,
        additionalData: {
          'type': 'chat',
          if (orderId != null && orderId.isNotEmpty) 'order_id': orderId,
        },
      );
    }
  }
}
