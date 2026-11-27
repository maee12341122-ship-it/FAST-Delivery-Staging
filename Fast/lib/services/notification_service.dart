import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../main.dart' show navigatorKey;
import '../screens/order_tracking_screen.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('📩 [FCM Background Init Error]: $e');
  }
  debugPrint('📩 [FCM Background Message]: ${message.messageId}');
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _highImportanceChannel =
      AndroidNotificationChannel(
    'high_importance_channel',
    'تنبيهات صوتية - Fast Delivery',
    description: 'قناة مخصصة لتنبيهات الطلبات والشات مع الصوت والاهتزاز',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static void Function(Map<String, dynamic> notificationItem)?
      onNotificationReceived;

  static int _nextNotificationId() {
    return DateTime.now().microsecondsSinceEpoch % 2147483647;
  }

  static String _normalizePhone(String phone) {
    var clean = phone.trim().replaceAll(' ', '');
    if (clean.startsWith('+967')) {
      clean = clean.substring(4);
    }
    if (clean.startsWith('0')) {
      clean = clean.substring(1);
    }
    if (clean.startsWith('967')) {
      clean = clean.substring(3);
    }
    return clean;
  }

  static String? _extractOrderIdFromMap(
      Map<dynamic, dynamic>? data, String fullText) {
    if (data != null) {
      final rawId = (data['order_id'] ?? data['related_id'] ?? data['orderId'])
          ?.toString()
          .trim();
      if (rawId != null && rawId.isNotEmpty) {
        return rawId;
      }
    }
    return _extractOrderIdFromText(fullText);
  }

  static void _recordExternalNotification({
    required String? title,
    required String? body,
    Map<String, dynamic>? additionalData,
  }) {
    final cleanTitle = (title ?? '').trim();
    final cleanBody = (body ?? '').trim();
    if (cleanTitle.isEmpty && cleanBody.isEmpty) return;

    final orderId = _extractOrderIdFromMap(
      additionalData,
      '$cleanTitle $cleanBody',
    );

    final item = <String, dynamic>{
      'title': cleanTitle.isNotEmpty ? cleanTitle : 'إشعار جديد 🔔',
      'body': cleanBody,
      'time': DateTime.now().toIso8601String(),
      if (orderId != null && orderId.isNotEmpty) 'order_id': orderId,
      if (additionalData != null && additionalData.isNotEmpty)
        'additionalData': additionalData,
    };

    if (onNotificationReceived != null) {
      try {
        onNotificationReceived!(item);
      } catch (e) {
        debugPrint('⚠️ خطأ في تمرير الإشعار الخارجي لقائمة الإشعارات: $e');
      }
    }
  }

  static Future<void> loginUser(String? userId) async {
    try {
      final cleanId = (userId ?? '').trim();
      if (cleanId.isNotEmpty) {
        await getFcmTokenSafe();
      }
    } catch (e) {
      debugPrint('⚠️ تعذر تحديث جلسة FCM loginUser: $e');
    }
  }

  static Future<void> initialize({
    void Function(String playerId)? onPlayerIdChanged,
    void Function(Map<String, dynamic> notificationItem)? onExternalNotification,
  }) async {
    if (onExternalNotification != null) {
      onNotificationReceived = onExternalNotification;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
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

      final androidPlugin = _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_highImportanceChannel);

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final additionalMap = Map<String, dynamic>.from(message.data);
        final title =
            message.notification?.title ?? additionalMap['title']?.toString();
        final body =
            message.notification?.body ?? additionalMap['body']?.toString();

        _recordExternalNotification(
          title: title,
          body: body,
          additionalData: additionalMap,
        );

        final orderId = _extractOrderIdFromMap(
          additionalMap,
          '${title ?? ''} ${body ?? ''}',
        );

        unawaited(
          showLocalNotification(
            (title != null && title.trim().isNotEmpty) ? title : 'إشعار جديد 🔔',
            body ?? '',
            payload: orderId,
          ),
        );
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('🚀 [النقر على إشعار FCM]: ${message.notification?.title}');
        final additionalMap = Map<String, dynamic>.from(message.data);
        final title =
            message.notification?.title ?? additionalMap['title']?.toString();
        final body =
            message.notification?.body ?? additionalMap['body']?.toString();

        _recordExternalNotification(
          title: title,
          body: body,
          additionalData: additionalMap,
        );

        final fullText = '${title ?? ''} ${body ?? ''}';
        final orderId = _extractOrderIdFromMap(additionalMap, fullText);
        if (orderId != null && orderId.isNotEmpty) {
          navigateToOrderTracking(orderId);
        }
      });

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        final clean = newToken.trim();
        debugPrint('📱 [FCM Token الجديد]: $clean');
        if (clean.isNotEmpty && onPlayerIdChanged != null) {
          onPlayerIdChanged(clean);
        }
      });

      debugPrint('🟢 تم تهيئة نظام الإشعارات (FCM & Local) بنجاح');
    } catch (e) {
      debugPrint('⚠️ خطأ في تهيئة الإشعارات: $e');
    }
  }

  static Future<String?> requestPermissionAndFetchToken() async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return await getFcmTokenSafe();
    } catch (e) {
      debugPrint('⚠️ خطأ في طلب إذن FCM: $e');
      return null;
    }
  }

  static Future<String?> getFcmTokenSafe({int retries = 3}) async {
    for (int attempt = 1; attempt <= retries; attempt++) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.trim().isNotEmpty) {
          debugPrint('📱 [FCM Device Token]: ${token.trim()}');
          return token.trim();
        }
      } catch (e) {
        debugPrint('⚠️ محاولة $attempt لجلب FCM Token فشلت: $e');
      }
      if (attempt < retries) {
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    return null;
  }

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

  static String? _extractOrderIdFromText(String text) {
    final RegExp regExp = RegExp(r'(?:طلب|#)\s*(\d+)');
    final match = regExp.firstMatch(text);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    return null;
  }

  static Future<void> saveUserPlayerId(
    String userId,
    String tableName, {
    String? identifierValue,
  }) async {
    try {
      final String? fcmToken = await getFcmTokenSafe();
      if (fcmToken == null || fcmToken.isEmpty) return;

      final client = Supabase.instance.client;
      final cleanTable = tableName.trim();
      final cleanId = userId.trim();

      if (cleanTable == 'admins') {
        final intAdminId = int.tryParse(cleanId);
        if (intAdminId != null) {
          await client
              .from('admins')
              .update({'fcm_token': fcmToken})
              .eq('id', intAdminId);
        } else if (identifierValue != null &&
            identifierValue.trim().isNotEmpty) {
          final idVal = identifierValue.trim().toLowerCase();
          final usernameVal =
              idVal.contains('@') ? idVal.split('@').first : idVal;
          await client
              .from('admins')
              .update({'fcm_token': fcmToken})
              .eq('username', usernameVal);
        } else {
          final authUser = client.auth.currentUser;
          final email = (authUser?.email ?? '').trim().toLowerCase();
          if (email.isNotEmpty) {
            final usernameVal =
                email.contains('@') ? email.split('@').first : email;
            await client
                .from('admins')
                .update({'fcm_token': fcmToken})
                .eq('username', usernameVal);
          }
        }
      } else if (cleanTable == 'couriers') {
        final authUser = client.auth.currentUser;
        if (authUser != null && cleanId == authUser.id) {
          await client
              .from('couriers')
              .update({'fcm_token': fcmToken})
              .eq('auth_user_id', authUser.id);
        } else {
          await client
              .from('couriers')
              .update({'fcm_token': fcmToken})
              .eq('id', cleanId);
        }
      } else if (cleanTable == 'customers') {
        final normalizedPhone = _normalizePhone(cleanId);
        if (normalizedPhone.isNotEmpty) {
          final formattedPhone = '+967$normalizedPhone';
          final zeroPhone = '0$normalizedPhone';
          await client
              .from('customers')
              .update({'fcm_token': fcmToken})
              .or('phone.eq.$normalizedPhone,phone.eq.$formattedPhone,phone.eq.$zeroPhone');
        } else {
          await client
              .from('customers')
              .update({'fcm_token': fcmToken})
              .eq('id', cleanId);
        }
      } else {
        await client
            .from(cleanTable)
            .update({'fcm_token': fcmToken})
            .eq('id', cleanId);
      }

      debugPrint('✅ تم حفظ FCM Token ($fcmToken) في جدول $cleanTable بنجاح');
    } catch (e) {
      debugPrint('⚠️ خطأ في حفظ FCM Token في Supabase: $e');
    }
  }

  static Future<void> sendNotificationToUser({
    List<String>? playerIds,
    String? targetPlayerId,
    required String title,
    required String body,
    dynamic orderId,
    String? eventType,
    Map<String, dynamic>? additionalData,
  }) async {
    final ids = <String>{
      ...?playerIds?.map((e) => e.trim()).where((e) => e.isNotEmpty),
      if (targetPlayerId != null && targetPlayerId.trim().isNotEmpty)
        targetPlayerId.trim(),
    }.toList();

    if (ids.isEmpty) return;

    try {
      final dataMap = <String, dynamic>{
        if (additionalData != null) ...additionalData,
        if (orderId != null) 'order_id': orderId.toString(),
        if (eventType != null && eventType.trim().isNotEmpty)
          'event_type': eventType.trim(),
      };

      final payload = <String, dynamic>{
        'tokens': ids,
        'token': ids.first,
        'title': title.trim(),
        'body': body.trim(),
        if (orderId != null) 'order_id': orderId.toString(),
        if (eventType != null && eventType.trim().isNotEmpty)
          'event_type': eventType.trim(),
        'data': dataMap,
      };

      final res = await Supabase.instance.client.functions
          .invoke('send-fcm-push', body: payload)
          .timeout(const Duration(seconds: 12));

      debugPrint(
          '📨 استجابة send-fcm-push (${res.status}): ${jsonEncode(res.data)}');
    } catch (e) {
      debugPrint('❌ خطأ في إرسال الإشعار عبر Supabase Edge Function: $e');
    }
  }

  static Future<void> showLocalNotification(
    String title,
    String body, {
    String? payload,
  }) async {
    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'high_importance_channel',
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
        orderId: orderId,
        eventType: 'chat_message',
        additionalData: {
          'type': 'chat',
          if (orderId != null && orderId.isNotEmpty) 'order_id': orderId,
        },
      );
    }
  }
}
