import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../main.dart' show navigatorKey;
import '../screens/order_tracking_screen.dart';

class NotificationService {
  static const String _appId = '60850bed-4af8-4df1-a2f5-77411630f447';

  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static int _nextNotificationId() {
    return DateTime.now().microsecondsSinceEpoch % 2147483647;
  }

  /// ربط المستخدم الحالي بـ OneSignal عبر External ID لتسهيل الاستهداف
  static Future<void> loginUser(String? userId) async {
    try {
      final cleanId = (userId ?? '').trim();
      if (cleanId.isNotEmpty) {
        await OneSignal.login(cleanId);
      } else {
        await OneSignal.logout();
      }
    } catch (e) {
      debugPrint('⚠️ تعذر تحديث جلسة OneSignal login/logout: $e');
    }
  }

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
      await OneSignal.Notifications.requestPermission(true);

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

      OneSignal.User.pushSubscription.addObserver((state) {
        final newId = state.current.id;
        debugPrint('📱 [OneSignal Subscription ID الجديد]: $newId');
        if (newId != null &&
            newId.trim().isNotEmpty &&
            onPlayerIdChanged != null) {
          onPlayerIdChanged(newId.trim());
        }
      });

      final String? playerId = OneSignal.User.pushSubscription.id;
      debugPrint('📱 [OneSignal Subscription ID الحالي]: $playerId');
      if (playerId != null &&
          playerId.trim().isNotEmpty &&
          onPlayerIdChanged != null) {
        onPlayerIdChanged(playerId.trim());
      }

      debugPrint('🟢 تم تهيئة نظام الإشعارات (OneSignal & Local) بنجاح');
    } catch (e) {
      debugPrint('⚠️ خطأ في تهيئة الإشعارات: $e');
    }
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
          '✅ تم حفظ OneSignal Subscription ID ($playerId) في جدول $cleanTable بنجاح');
    } catch (e) {
      debugPrint('⚠️ خطأ في حفظ Player ID في Supabase: $e');
    }
  }

  /// إرسال الإشعار مباشرة عبر Supabase Edge Function (send-onesignal-push) بدون الحاجة لـ Node.js
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
        'player_ids': [cleanPlayerId],
        'target_player_id': cleanPlayerId,
        'title': title.trim(),
        'body': body.trim(),
        if (additionalData != null && additionalData.isNotEmpty)
          'additional_data': additionalData,
      };

      final res = await Supabase.instance.client.functions
          .invoke('send-onesignal-push', body: payload)
          .timeout(const Duration(seconds: 10));

      debugPrint(
          '📨 استجابة send-onesignal-push (${res.status}): ${jsonEncode(res.data)}');
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
