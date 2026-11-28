import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const AndroidNotificationChannel _bgHighImportanceChannel =
    AndroidNotificationChannel(
  'high_importance_channel',
  'إشعارات التطبيق المهمة',
  description: 'قناة إشعارات الطلبات والتنبيهات الفورية',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('FCM Background init error: $e');
  }

  try {
    if (message.notification == null && message.data.isNotEmpty) {
      final title = (message.data['title'] ?? '').toString().trim();
      final body = (message.data['body'] ?? message.data['message'] ?? '')
          .toString()
          .trim();

      if (title.isNotEmpty || body.isNotEmpty) {
        final plugin = FlutterLocalNotificationsPlugin();
        const androidInit =
            AndroidInitializationSettings('@mipmap/ic_launcher');
        await plugin.initialize(
          const InitializationSettings(android: androidInit),
        );
        final androidPlugin = plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.createNotificationChannel(_bgHighImportanceChannel);

        await plugin.show(
          DateTime.now().microsecondsSinceEpoch % 2147483647,
          title.isNotEmpty ? title : 'إشعار جديد',
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _bgHighImportanceChannel.id,
              _bgHighImportanceChannel.name,
              channelDescription: _bgHighImportanceChannel.description,
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
            ),
          ),
          payload: jsonEncode(_normalizePayloadMap(message.data)),
        );
      }
    }
  } catch (e) {
    debugPrint('FCM Background local notification display error: $e');
  }

  debugPrint('FCM Background message handled: ${message.messageId}');
}

Map<String, String> _normalizePayloadMap(Map<String, dynamic> raw) {
  final normalized = <String, String>{};
  raw.forEach((key, value) {
    if (value != null) {
      normalized[key.toString()] = value.toString();
    }
  });
  return normalized;
}

class FcmPushService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = _bgHighImportanceChannel;

  static String? _lastRole;
  static dynamic _lastRowId;
  static String? _lastPhone;
  static String? _cachedToken;
  static bool _firebaseReady = false;
  static bool _listenersInitialized = false;
  static bool _openedListenersAttached = false;
  static bool _refreshListenerAttached = false;
  static Future<void>? _initFuture;
  static void Function(Map<String, dynamic> payload)? _onTapCallback;
  static void Function(Map<String, dynamic> messageData)? _onForegroundMessage;
  static final Set<String> _handledMessageIds = <String>{};

  static String _maskToken(String token) {
    if (token.length <= 10) return '***';
    return '${token.substring(0, 6)}...${token.substring(token.length - 4)}';
  }

  static void setForegroundMessageHandler(
    void Function(Map<String, dynamic> messageData)? handler,
  ) {
    _onForegroundMessage = handler;
  }

  static bool _markMessageHandled(String? idOrKey) {
    final key = (idOrKey ?? '').trim();
    if (key.isEmpty) return false;
    if (_handledMessageIds.contains(key)) return true;
    _handledMessageIds.add(key);
    if (_handledMessageIds.length > 200) {
      _handledMessageIds.remove(_handledMessageIds.first);
    }
    return false;
  }

  static Future<void> _ensureFirebaseInitialized() async {
    if (_firebaseReady && Firebase.apps.isNotEmpty) return;
    if (_initFuture != null) {
      await _initFuture;
      return;
    }
    _initFuture = () async {
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp();
        }
        _firebaseReady = Firebase.apps.isNotEmpty;
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
    void Function(Map<String, dynamic> messageData)? onForegroundMessage,
  }) async {
    if (onNotificationTap != null) {
      _onTapCallback = onNotificationTap;
    }
    if (onForegroundMessage != null) {
      _onForegroundMessage = onForegroundMessage;
    }

    await _ensureFirebaseInitialized();

    if (!_listenersInitialized) {
      _listenersInitialized = true;

      try {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      } catch (e) {
        debugPrint('FCM onBackgroundMessage error: $e');
      }

      try {
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (e) {
        debugPrint('FCM foreground options error: $e');
      }

      try {
        const androidInit =
            AndroidInitializationSettings('@mipmap/ic_launcher');
        const initSettings = InitializationSettings(android: androidInit);
        await _localNotifications.initialize(
          initSettings,
          onDidReceiveNotificationResponse: (NotificationResponse response) {
            final raw = response.payload;
            if (raw != null && raw.isNotEmpty && _onTapCallback != null) {
              try {
                final decoded = jsonDecode(raw);
                if (decoded is Map) {
                  _onTapCallback!(Map<String, dynamic>.from(decoded));
                  return;
                }
              } catch (_) {}
              _onTapCallback!({'order_id': raw, 'raw_payload': raw});
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
        final msgKey = message.messageId ??
            '${message.notification?.title ?? message.data['title'] ?? ''}_${message.data['event_type'] ?? ''}_${message.data['order_id'] ?? ''}';
        if (_markMessageHandled(msgKey)) return;

        final combined = <String, dynamic>{
          ..._normalizePayloadMap(message.data),
          if (message.notification?.title != null)
            'title': message.notification!.title!,
          if (message.notification?.body != null)
            'body': message.notification!.body!,
          if (message.messageId != null) 'message_id': message.messageId!,
        };

        final title = combined['title']?.toString() ?? 'إشعار جديد';
        final body = combined['body']?.toString() ?? '';

        if (_onForegroundMessage != null) {
          try {
            _onForegroundMessage!(combined);
          } catch (e) {
            debugPrint('FCM onForegroundMessage callback error: $e');
          }
        }

        if (title.isNotEmpty || body.isNotEmpty) {
          try {
            await _localNotifications.show(
              DateTime.now().microsecondsSinceEpoch % 2147483647,
              title,
              body,
              NotificationDetails(
                android: AndroidNotificationDetails(
                  _channel.id,
                  _channel.name,
                  channelDescription: _channel.description,
                  importance: Importance.max,
                  priority: Priority.high,
                  playSound: true,
                  enableVibration: true,
                ),
              ),
              payload: jsonEncode(combined),
            );
          } catch (e) {
            debugPrint('FCM foreground show error: $e');
          }
        }
      });

      messagingTokenRefreshListener();
    }

    if (!_openedListenersAttached && _onTapCallback != null) {
      _openedListenersAttached = true;
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final combined = <String, dynamic>{
          ..._normalizePayloadMap(message.data),
          if (message.notification?.title != null)
            'title': message.notification!.title!,
          if (message.notification?.body != null)
            'body': message.notification!.body!,
        };
        _onTapCallback?.call(combined);
      });

      final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMsg != null) {
        final combined = <String, dynamic>{
          ..._normalizePayloadMap(initialMsg.data),
          if (initialMsg.notification?.title != null)
            'title': initialMsg.notification!.title!,
          if (initialMsg.notification?.body != null)
            'body': initialMsg.notification!.body!,
        };
        _onTapCallback?.call(combined);
      }
    }
  }

  static void messagingTokenRefreshListener() {
    if (_refreshListenerAttached) return;
    _refreshListenerAttached = true;
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      final clean = newToken.trim();
      if (clean.isNotEmpty) {
        _cachedToken = clean;
        debugPrint('FCM Token refreshed: ${_maskToken(clean)}');
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
          debugPrint(
              'FCM Token obtained (attempt $attempt): ${_maskToken(_cachedToken!)}');
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

  static String? _tableForRole(String? role) {
    final normalized = role?.trim().toLowerCase();
    if (normalized == 'courier') return 'couriers';
    if (normalized == 'admin') return 'admins';
    if (normalized == 'customer') return 'customers';
    return null;
  }

  static Future<bool> syncTokenForCurrentUser({
    String? role,
    dynamic rowId,
    String? phone,
    String? explicitToken,
  }) async {
    if (role != null && role.trim().isNotEmpty) {
      _lastRole = role.trim().toLowerCase();
    }
    if (rowId != null && rowId.toString().trim().isNotEmpty) {
      _lastRowId = rowId;
    }
    if (phone != null && phone.trim().isNotEmpty) {
      _lastPhone = phone.trim();
    }

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

    final hasValidId =
        effectiveId != null && effectiveId.toString().trim().isNotEmpty;
    final hasValidPhone =
        effectivePhone != null && effectivePhone.trim().isNotEmpty;

    final table = _tableForRole(effectiveRole);
    if (table == null || (!hasValidId && !hasValidPhone)) {
      debugPrint(
        'FCM syncTokenForCurrentUser aborted: missing role/id/phone (role=$effectiveRole, id=$effectiveId, phone=$effectivePhone)',
      );
      return false;
    }

    final supabase = Supabase.instance.client;
    try {
      if (hasValidId) {
        final idVal = effectiveId.toString().trim();
        final parsedIntId = int.tryParse(idVal);
        final filterId = parsedIntId ?? idVal;
        final updatedById = await supabase
            .from(table)
            .update({'fcm_token': token})
            .eq('id', filterId)
            .select('id');
        if (updatedById.isNotEmpty) {
          debugPrint('FCM synced to $table by id=$filterId');
          return true;
        }
        debugPrint(
            'FCM id=$filterId not matched in $table, trying phone fallback...');
      }

      if (hasValidPhone) {
        final rawPhone = effectivePhone!.trim();
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
          debugPrint(
              'FCM phone candidates=$candidates did not match any row in $table');
        }
      }

      return false;
    } catch (e) {
      debugPrint('Error syncing FCM token to Supabase ($effectiveRole): $e');
      return false;
    }
  }

  static Future<void> clearTokenForCurrentUser({
    String? role,
    dynamic rowId,
    String? phone,
  }) async {
    final targetRole = (role?.trim().isNotEmpty == true)
        ? role!.trim().toLowerCase()
        : _lastRole;
    final targetId =
        (rowId != null && rowId.toString().trim().isNotEmpty) ? rowId : _lastRowId;
    final targetPhone = (phone?.trim().isNotEmpty == true)
        ? phone!.trim()
        : _lastPhone;

    final table = _tableForRole(targetRole);
    final supabase = Supabase.instance.client;

    try {
      if (table != null) {
        if (targetId != null && targetId.toString().trim().isNotEmpty) {
          final idVal = targetId.toString().trim();
          final filterId = int.tryParse(idVal) ?? idVal;
          await supabase
              .from(table)
              .update({'fcm_token': null})
              .eq('id', filterId);
        } else if (targetPhone != null && targetPhone.trim().isNotEmpty) {
          final norm = _normalizePhoneDigits(targetPhone);
          final candidates = <String>{
            targetPhone.trim(),
            if (norm.isNotEmpty) norm,
            if (norm.isNotEmpty) '+967$norm',
            if (norm.isNotEmpty) '967$norm',
            if (norm.isNotEmpty) '0$norm',
          }.where((s) => s.isNotEmpty).toList();
          if (candidates.isNotEmpty) {
            final orFilter = candidates.map((c) => 'phone.eq.$c').join(',');
            await supabase
                .from(table)
                .update({'fcm_token': null})
                .or(orFilter);
          }
        }
      }
    } catch (e) {
      debugPrint('Error clearing FCM token in Supabase ($targetRole): $e');
    } finally {
      _lastRole = null;
      _lastRowId = null;
      _lastPhone = null;
    }
  }
}
