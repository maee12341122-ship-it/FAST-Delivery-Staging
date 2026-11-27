import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('FCM Background init error: $e');
  }
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
  static String? _lastPhone;
  static String? _cachedToken;
  static bool _initialized = false;
  static Future<void>? _initFuture;

  static Future<void> _ensureFirebaseInitialized() async {
    if (_initialized && Firebase.apps.isNotEmpty) return;
    if (_initFuture != null) {
      await _initFuture;
      return;
    }
    _initFuture = () async {
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp();
        }
        _initialized = true;
      } catch (e) {
        debugPrint('FCM Firebase.initializeApp error: $e');
      } finally {
        _initFuture = null;
      }
    }();
    await _initFuture;
  }

  static Future<void> initialize({
    void Function(Map<String, dynamic> payload)? onNotificationTap,
  }) async {
    await _ensureFirebaseInitialized();

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('FCM onBackgroundMessage error: $e');
    }

    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          if (onNotificationTap != null && response.payload != null) {
            onNotificationTap({'raw_payload': response.payload});
          }
        },
      );

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_channel);
    } catch (e) {
      debugPrint('FCM local notifications init error: $e');
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final title = message.notification?.title ??
          message.data['title']?.toString() ??
          'إشعار جديد';
      final body =
          message.notification?.body ?? message.data['body']?.toString() ?? '';
      if (title.isNotEmpty || body.isNotEmpty) {
        try {
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
        } catch (e) {
          debugPrint('FCM foreground show error: $e');
        }
      }
    });

    if (onNotificationTap != null) {
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final combined = <String, dynamic>{
          ...message.data,
          if (message.notification?.title != null)
            'title': message.notification!.title,
          if (message.notification?.body != null)
            'body': message.notification!.body,
        };
        onNotificationTap(combined);
      });

      final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMsg != null) {
        final combined = <String, dynamic>{
          ...initialMsg.data,
          if (initialMsg.notification?.title != null)
            'title': initialMsg.notification!.title,
          if (initialMsg.notification?.body != null)
            'body': initialMsg.notification!.body,
        };
        onNotificationTap(combined);
      }
    }

    messagingTokenRefreshListener();
  }

  static void messagingTokenRefreshListener() {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      final clean = newToken.trim();
      if (clean.isNotEmpty) {
        _cachedToken = clean;
        debugPrint('FCM Token refreshed: $clean');
        if (_lastRole != null || _lastRowId != null || _lastPhone != null) {
          unawaited(
            syncTokenForCurrentUser(
              role: _lastRole,
              rowId: _lastRowId,
              phone: _lastPhone,
              explicitToken: clean,
            ),
          );
        }
      }
    });
  }

  static Future<NotificationSettings?> requestPermissionSafe() async {
    try {
      await _ensureFirebaseInitialized();
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('FCM permission status: ${settings.authorizationStatus}');
      return settings;
    } catch (e) {
      debugPrint('FCM requestPermission error: $e');
      return null;
    }
  }

  static Future<void> requestPermissionAndSyncToken({
    String? role,
    dynamic rowId,
    String? phone,
  }) async {
    await requestPermissionSafe();
    await syncTokenForCurrentUser(
      role: role,
      rowId: rowId,
      phone: phone,
    );
  }

  static Future<String?> getTokenSafe({int retries = 3}) async {
    await _ensureFirebaseInitialized();
    await requestPermissionSafe();

    for (int attempt = 1; attempt <= retries; attempt++) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.trim().isNotEmpty) {
          _cachedToken = token.trim();
          debugPrint('FCM Token obtained (attempt $attempt): $_cachedToken');
          return _cachedToken;
        }
        debugPrint('FCM getToken returned null/empty on attempt $attempt');
      } catch (e) {
        debugPrint('FCM getToken attempt $attempt failed: $e');
      }
      if (attempt < retries) {
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }

    if (_cachedToken == null || _cachedToken!.isEmpty) {
      debugPrint('FCM final token is still null/empty after $retries attempts');
    }
    return _cachedToken;
  }

  static String _normalizePhoneDigits(String phone) {
    var digitsOnly = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.startsWith('967') && digitsOnly.length > 9) {
      digitsOnly = digitsOnly.substring(3);
    }
    if (digitsOnly.startsWith('0') && digitsOnly.length > 9) {
      digitsOnly = digitsOnly.substring(1);
    }
    return digitsOnly.trim();
  }

  static Future<bool> syncTokenForCurrentUser({
    String? role,
    dynamic rowId,
    String? phone,
    String? explicitToken,
  }) async {
    if (role != null && role.trim().isNotEmpty) _lastRole = role.trim().toLowerCase();
    if (rowId != null && rowId.toString().trim().isNotEmpty) {
      _lastRowId = rowId;
    }
    if (phone != null && phone.trim().isNotEmpty) _lastPhone = phone.trim();

    final effectiveRole = _lastRole;
    final effectiveId = _lastRowId;
    final effectivePhone = _lastPhone;

    final token = (explicitToken?.trim().isNotEmpty == true)
        ? explicitToken!.trim()
        : await getTokenSafe();

    if (token == null || token.isEmpty) {
      debugPrint('FCM syncTokenForCurrentUser aborted: token is null/empty');
      return false;
    }

    if (effectiveRole == null ||
        (effectiveId == null &&
            (effectivePhone == null || effectivePhone.trim().isEmpty))) {
      debugPrint(
        'FCM syncTokenForCurrentUser aborted: missing role/id/phone (role=$effectiveRole, id=$effectiveId, phone=$effectivePhone)',
      );
      return false;
    }

    final supabase = Supabase.instance.client;
    try {
      String table;
      if (effectiveRole == 'courier') {
        table = 'couriers';
      } else if (effectiveRole == 'admin') {
        table = 'admins';
      } else if (effectiveRole == 'customer') {
        table = 'customers';
      } else {
        debugPrint('FCM syncTokenForCurrentUser unknown role: $effectiveRole');
        return false;
      }

      if (effectiveId != null) {
        final updatedById = await supabase
            .from(table)
            .update({'fcm_token': token})
            .eq('id', effectiveId)
            .select('id');
        if (updatedById.isNotEmpty) {
          debugPrint('FCM synced to $table by id=$effectiveId');
          return true;
        }
        debugPrint('FCM id=$effectiveId not matched in $table, trying phone fallback...');
      }

      if (effectivePhone != null && effectivePhone.trim().isNotEmpty) {
        final rawPhone = effectivePhone.trim();
        final norm = _normalizePhoneDigits(rawPhone);
        final candidates = <String>{
          rawPhone,
          if (norm.isNotEmpty) norm,
          if (norm.isNotEmpty) '+967$norm',
          if (norm.isNotEmpty) '967$norm',
          if (norm.isNotEmpty) '0$norm',
        }.where((s) => s.isNotEmpty).toList();

        if (candidates.isNotEmpty) {
          final orFilter = candidates.map((c) => 'phone.eq.$c').join(',');
          final updatedByPhone = await supabase
              .from(table)
              .update({'fcm_token': token})
              .or(orFilter)
              .select('id');
          if (updatedByPhone.isNotEmpty) {
            debugPrint('FCM synced to $table by phone candidates=$candidates');
            return true;
          }
          debugPrint('FCM phone candidates=$candidates did not match any row in $table');
        }
      }

      return false;
    } catch (e) {
      debugPrint('Error syncing FCM token to Supabase ($effectiveRole): $e');
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
