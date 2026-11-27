import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  debugPrint('FCM Background message: ${message.messageId}');
}

class FcmPushService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'إشعارات التطبيق المهمة',
    description: 'قناة إشعارات الطلبات والتنبيهات الفورية',
    importance: Importance.max,
  );

  static String? _lastRole;
  static dynamic _lastRowId;
  static String? _cachedToken;

  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
    } catch (_) {}

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(initSettings);

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final title = message.notification?.title ??
          message.data['title']?.toString() ??
          'إشعار جديد';
      final body =
          message.notification?.body ?? message.data['body']?.toString() ?? '';
      if (title.isNotEmpty || body.isNotEmpty) {
        await _localNotifications.show(
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );
      }
    });

    messagingTokenRefreshListener();
  }

  static void messagingTokenRefreshListener() {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      final clean = newToken.trim();
      if (clean.isNotEmpty) {
        _cachedToken = clean;
        if (_lastRole != null && _lastRowId != null) {
          unawaited(
            syncTokenForCurrentUser(
              role: _lastRole,
              rowId: _lastRowId,
              explicitToken: clean,
            ),
          );
        }
      }
    });
  }

  static Future<void> requestPermissionAndSyncToken({
    String? role,
    dynamic rowId,
  }) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await syncTokenForCurrentUser(role: role, rowId: rowId);
    } catch (e) {
      debugPrint('FCM requestPermission error: $e');
    }
  }

  static Future<String?> getTokenSafe({int retries = 3}) async {
    for (int attempt = 1; attempt <= retries; attempt++) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.trim().isNotEmpty) {
          _cachedToken = token.trim();
          return _cachedToken;
        }
      } catch (e) {
        debugPrint('FCM getToken attempt $attempt failed: $e');
      }
      if (attempt < retries) {
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    return _cachedToken;
  }

  static Future<bool> syncTokenForCurrentUser({
    String? role,
    dynamic rowId,
    String? explicitToken,
  }) async {
    if (role != null) _lastRole = role;
    if (rowId != null) _lastRowId = rowId;

    final effectiveRole = role ?? _lastRole;
    final effectiveId = rowId ?? _lastRowId;
    final token = (explicitToken?.trim().isNotEmpty == true)
        ? explicitToken!.trim()
        : await getTokenSafe();

    if (token == null ||
        token.isEmpty ||
        effectiveId == null ||
        effectiveRole == null) {
      return false;
    }

    final supabase = Supabase.instance.client;
    try {
      if (effectiveRole == 'courier') {
        await supabase
            .from('couriers')
            .update({'fcm_token': token}).eq('id', effectiveId);
      } else if (effectiveRole == 'admin') {
        await supabase
            .from('admins')
            .update({'fcm_token': token}).eq('id', effectiveId);
      } else if (effectiveRole == 'customer') {
        await supabase
            .from('customers')
            .update({'fcm_token': token}).eq('id', effectiveId);
      } else {
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Error syncing FCM token to Supabase: $e');
      return false;
    }
  }

  static Future<void> sendPushToTokens({
    required List<String> tokens,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? eventType,
  }) async {
    final cleanTokens = tokens
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (cleanTokens.isEmpty) return;

    await Supabase.instance.client.functions.invoke(
      'send-fcm-push',
      body: {
        'tokens': cleanTokens,
        'title': title,
        'body': body,
        if (eventType != null) 'event_type': eventType,
        'data': data ?? {},
      },
    );
  }
}
