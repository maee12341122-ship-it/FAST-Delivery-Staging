import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static const String _appId = '60850bed-4af8-4df1-a2f5-77411630f447';

  /// 1. تهيئة الاستماع للإشعارات والنقر عليها
  static Future<void> initialize() async {
    try {
      // الاستماع للنقر على الإشعار من المستخدم
      OneSignal.Notifications.addClickListener((event) {
        debugPrint('🚀 [النقر على الإشعار]: ${event.notification.title}');
        // يمكنك هنا توجيه المستخدم للشاشة المناسبة بناءً على البيانات المرسلة
      });

      // طباعة معرف الجهاز الحالي للتأكد
      String? playerId = OneSignal.User.pushSubscription.id;
      debugPrint('📱 [OneSignal Player ID]: $playerId');

      debugPrint('🟢 تم تهيئة نظام الإشعارات (OneSignal) بنجاح');
    } catch (e) {
      debugPrint('⚠️ خطأ في تهيئة الإشعارات: $e');
    }
  }

  /// 2. حفظ معرف الجهاز الحالي في جدول Supabase للمستخدم المسجل (عميل، مندوب، مشرف)
  static Future<void> saveUserPlayerId(String userId, String tableName) async {
    try {
      String? playerId = OneSignal.User.pushSubscription.id;
      
      if (playerId != null) {
        await Supabase.instance.client
            .from(tableName) // مثل جدول profiles, drivers, customers
            .update({'onesignal_player_id': playerId})
            .eq('id', userId);
        debugPrint("✅ تم حفظ OneSignal Player ID في جدول $tableName بنجاح");
      }
    } catch (e) {
      debugPrint("⚠️ خطأ في حفظ Player ID في Supabase: $e");
    }
  }

  /// Push notifications must be sent from a trusted server/Edge Function.
  /// Never place the OneSignal REST API key in the mobile application.
  static Future<void> sendNotificationToUser({
    required String targetPlayerId,
    required String title,
    required String body,
  }) async {
    debugPrint('Push notification skipped: configure a secured server-side OneSignal sender.');
  }

  /// 4. دالة توافقية لإظهار إشعار محلي عند الحاجة
  static Future<void> showLocalNotification(String title, String body) async {
    debugPrint('📢 [FAST Notification]: $title - $body');
  }
}
