import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import 'order_tracking_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _badgeAnimController;
  late Animation<double> _scaleAnimation;
  int _previousCount = 0;

  @override
  void initState() {
    super.initState();
    _badgeAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _badgeAnimController,
      curve: Curves.elasticOut,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final count = context.read<AppState>().notifications.length;
      _previousCount = count;
      if (count > 0) {
        _badgeAnimController.forward(from: 0.0);
      }
    });
  }

  @override
  void dispose() {
    _badgeAnimController.dispose();
    super.dispose();
  }

  String? _extractOrderIdFromNotification(Map<String, dynamic> notif) {
    final directId = notif['order_id']?.toString().trim() ??
        notif['related_id']?.toString().trim();
    if (directId != null && directId.isNotEmpty) return directId;

    final additional = notif['additionalData'] ?? notif['additional_data'];
    if (additional is Map) {
      final addId = (additional['order_id'] ??
              additional['related_id'] ??
              additional['orderId'])
          ?.toString()
          .trim();
      if (addId != null && addId.isNotEmpty) return addId;
    }

    final combinedText = '${notif['title'] ?? ''} ${notif['body'] ?? ''}';
    final match = RegExp(r'(?:طلب|#)\s*(\d+)').firstMatch(combinedText);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    return null;
  }

  void _handleNotificationTap(
      BuildContext context, Map<String, dynamic> notif) {
    final orderId = _extractOrderIdFromNotification(notif);
    if (orderId != null && orderId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrderTrackingScreen(orderIdParam: orderId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final notifications = appState.notifications;
    final isDark = appState.isDarkMode;

    if (notifications.length > _previousCount) {
      _badgeAnimController.forward(from: 0.0);
      _previousCount = notifications.length;
    } else if (notifications.length < _previousCount) {
      _previousCount = notifications.length;
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF121212) : const Color(0xFFF0F2F5),
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          title: Row(
            children: [
              const Text(
                'الإشعارات والتنبيهات 🔔',
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              if (notifications.isNotEmpty)
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber[700],
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt, size: 14, color: Colors.black),
                        const SizedBox(width: 4),
                        Text(
                          'جديد (${notifications.length})',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          iconTheme: const IconThemeData(color: Colors.amber),
        ),
        body: notifications.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.notifications_off_outlined,
                        size: 60, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      'لا توجد إشعارات جديدة حالياً 📭',
                      style: TextStyle(color: Colors.grey, fontSize: 15),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: notifications.length,
                itemBuilder: (context, index) {
                  final notif = Map<String, dynamic>.from(notifications[index]);
                  final String title =
                      notif['title']?.toString() ?? 'إشعار جديد';
                  final String body = notif['body']?.toString() ?? '';
                  final DateTime? time = notif['time'] is DateTime
                      ? notif['time'] as DateTime
                      : DateTime.tryParse(notif['time']?.toString() ?? '');
                  final String? linkedOrderId =
                      _extractOrderIdFromNotification(notif);

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.amber.withOpacity(0.2)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ListTile(
                      onTap: linkedOrderId != null
                          ? () => _handleNotificationTap(context, notif)
                          : null,
                      contentPadding: const EdgeInsets.all(12),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.notifications_active,
                            color: Colors.amber, size: 22),
                      ),
                      title: Text(
                        title,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            body,
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                          if (time != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${time.hour}:${time.minute.toString().padLeft(2, '0')} - ${time.year}/${time.month}/${time.day}',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 10),
                            ),
                          ],
                        ],
                      ),
                      trailing: linkedOrderId != null
                          ? const Icon(Icons.arrow_forward_ios,
                              color: Colors.amber, size: 15)
                          : null,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
