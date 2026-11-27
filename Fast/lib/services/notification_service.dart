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
import '../screens/chat_screen.dart';

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

  static bool _isInitialized = false;
  static final Set<String> _recentlyShownKeys = <String>{};

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
    if (clean.startsWith('+967')) clean = clean.substring(4);
    if (clean.startsWith('0')) clean = clean.substring(1);
    if (clean.startsWith('967')) clean = clean.substring(3);
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

  static bool _isDuplicateEvent(String key) {
    if (key.isEmpty) return false;
    if (_recentlyShownKeys.contains(key)) return true;
    _recentlyShownKeys.add(key);
    if (_recentlyShownKeys.length > 150) {
      _recentlyShownKeys.remove(_recentlyShownKeys.first);
    }
    return false;
  }

  static void _recordExternalNotification({
    required String? title,
    required String? body,
    String? messageId,
    Map<String, dynamic>? additionalData,
  }) {
    final cleanTitle = (title ?? '').trim();
    final cleanBody = (body ?? '').trim();
    if (cleanTitle.isEmpty && cleanBody.isEmpty) return;

    final orderId = _extractOrderIdFromMap(
      additionalData,
      '$cleanTitle $cleanBody',
    );

    final dedupeKey = (messageId != null && messageId.trim().isNotEmpty)
        ? 'fcm_${messageId.trim()}'
        : '${cleanTitle}_${cleanBody}_${orderId ?? ''}';

    final item = <String, dynamic>{
      'title': cleanTitle.isNotEmpty ? cleanTitle : 'إشعار جديد 🔔',
      'body': cleanBody,
      'time': DateTime.now().toIso8601String(),
      'is_read': false,
      'dedupe_key': dedupeKey,
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
    if (_isInitialized) return;
    _isInitialized = true;

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
            handleNotificationNavigationFromPayload(response.payload!);
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
          messageId: message.messageId,
          additionalData: additionalMap,
        );

        final orderId = _extractOrderIdFromMap(
          additionalMap,
          '${title ?? ''} ${body ?? ''}',
        );

        final payloadJson = jsonEncode({
          ...additionalMap,
          if (orderId != null && orderId.isNotEmpty) 'order_id': orderId,
        });

        unawaited(
          showLocalNotification(
            (title != null && title.trim().isNotEmpty) ? title : 'إشعار جديد 🔔',
            body ?? '',
            payload: payloadJson,
            dedupeKey: message.messageId,
          ),
        );
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final additionalMap = Map<String, dynamic>.from(message.data);
        final title =
            message.notification?.title ?? additionalMap['title']?.toString();
        final body =
            message.notification?.body ?? additionalMap['body']?.toString();

        _recordExternalNotification(
          title: title,
          body: body,
          messageId: message.messageId,
          additionalData: additionalMap,
        );

        handleNotificationNavigationFromMap(additionalMap,
            fallbackText: '${title ?? ''} ${body ?? ''}');
      });

      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        final additionalMap = Map<String, dynamic>.from(initialMessage.data);
        final title = initialMessage.notification?.title ??
            additionalMap['title']?.toString();
        final body = initialMessage.notification?.body ??
            additionalMap['body']?.toString();

        _recordExternalNotification(
          title: title,
          body: body,
          messageId: initialMessage.messageId,
          additionalData: additionalMap,
        );

        Future.delayed(const Duration(milliseconds: 600), () {
          handleNotificationNavigationFromMap(additionalMap,
              fallbackText: '${title ?? ''} ${body ?? ''}');
        });
      }

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        final clean = newToken.trim();
        if (clean.isNotEmpty && onPlayerIdChanged != null) {
          onPlayerIdChanged(clean);
        }
      });

      debugPrint('🟢 تم تهيئة نظام الإشعارات الموحد بنجاح');
    } catch (e) {
      _isInitialized = false;
      debugPrint('⚠️ خطأ في تهيئة الإشعارات: $e');
    }
  }

  static void handleNotificationNavigationFromPayload(String rawPayload) {
    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is Map) {
        handleNotificationNavigationFromMap(
            Map<String, dynamic>.from(decoded));
        return;
      }
    } catch (_) {}
    navigateToOrderTracking(rawPayload);
  }

  static void handleNotificationNavigationFromMap(
    Map<String, dynamic> data, {
    String fallbackText = '',
  }) {
    final type = (data['type'] ?? data['event_type'] ?? data['screen'] ?? '')
        .toString()
        .toLowerCase();
    final orderId = _extractOrderIdFromMap(data, fallbackText);
    final chatId =
        (data['chat_id'] ?? data['chatId'] ?? data['room_id'])?.toString().trim();

    if ((type.contains('chat') || type.contains('message') || (chatId != null && chatId.isNotEmpty)) &&
        ((orderId != null && orderId.isNotEmpty) || (chatId != null && chatId.isNotEmpty))) {
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              orderId: (orderId != null && orderId.isNotEmpty) ? orderId : chatId!,
              userRole: (data['user_role'] ?? 'customer').toString(),
              targetChat: (data['target_chat'] ?? 'admin_customer').toString(),
            ),
          ),
        );
      }
      return;
    }

    if (orderId != null && orderId.isNotEmpty) {
      navigateToOrderTracking(orderId);
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
          await client.from('admins').update({'fcm_token': fcmToken}).eq('id', intAdminId);
        } else if (identifierValue != null && identifierValue.trim().isNotEmpty) {
          final idVal = identifierValue.trim().toLowerCase();
          final usernameVal = idVal.contains('@') ? idVal.split('@').first : idVal;
          await client.from('admins').update({'fcm_token': fcmToken}).eq('username', usernameVal);
        } else {
          final authUser = client.auth.currentUser;
          final email = (authUser?.email ?? '').trim().toLowerCase();
          if (email.isNotEmpty) {
            final usernameVal = email.contains('@') ? email.split('@').first : email;
            await client.from('admins').update({'fcm_token': fcmToken}).eq('username', usernameVal);
          }
        }
      } else if (cleanTable == 'couriers') {
        final authUser = client.auth.currentUser;
        if (authUser != null && cleanId == authUser.id) {
          await client.from('couriers').update({'fcm_token': fcmToken}).eq('auth_user_id', authUser.id);
        } else {
          final intCourierId = int.tryParse(cleanId);
          if (intCourierId != null) {
            await client.from('couriers').update({'fcm_token': fcmToken}).eq('id', intCourierId);
          } else {
            await client.from('couriers').update({'fcm_token': fcmToken}).eq('id', cleanId);
          }
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
          await client.from('customers').update({'fcm_token': fcmToken}).eq('id', cleanId);
        }
      } else {
        await client.from(cleanTable).update({'fcm_token': fcmToken}).eq('id', cleanId);
      }
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

      await Supabase.instance.client.functions
          .invoke('send-fcm-push', body: payload)
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('❌ خطأ في إرسال الإشعار عبر Supabase Edge Function: $e');
    }
  }

  static Future<void> showLocalNotification(
    String title,
    String body, {
    String? payload,
    String? dedupeKey,
  }) async {
    final key = (dedupeKey != null && dedupeKey.trim().isNotEmpty)
        ? dedupeKey.trim()
        : '${title.trim()}_${body.trim()}';
    if (_isDuplicateEvent(key)) return;

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
