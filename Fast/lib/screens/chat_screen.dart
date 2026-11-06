import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/notification_service.dart'; // 👈 استيراد خدمة الإشعارات لإرسال التنبيهات الفورية

class ChatScreen extends StatefulWidget {
  final String orderId;
  final String userRole; // 'customer', 'admin', 'courier'
  final String targetChat; // 'admin_customer' أو 'admin_courier'

  const ChatScreen({
    Key? key,
    required this.orderId,
    required this.userRole,
    required this.targetChat,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    String chatTitle = widget.targetChat == 'admin_courier'
        ? 'محادثة المشرف مع المندوب (طلب #${widget.orderId})'
        : 'محادثة المشرف مع العميل (طلب #${widget.orderId})';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(chatTitle, style: const TextStyle(color: Colors.white, fontSize: 13)),
          iconTheme: const IconThemeData(color: Colors.amber),
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamBuilder(
                stream: appState.getMessagesForOrder(widget.orderId, widget.targetChat),
                builder: (context, snapshot) {
                  if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.amber));
                  }

                  if (snapshot.hasError) {
                    return Center(child: Text('خطأ في تحميل الرسائل: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                  }

                  final messages = (snapshot.data as List?) ?? [];

                  if (messages.isEmpty) {
                    return const Center(
                      child: Text(
                        'لا توجد رسائل بعد، ابدأ المحادثة الآن 💬',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index] as Map<String, dynamic>;
                      String senderType = msg['sender_type']?.toString() ?? '';
                      String messageText = msg['message_text']?.toString() ?? '';
                      bool isMe = senderType == widget.userRole;

                      String senderLabel = senderType == 'admin'
                          ? 'الإدارة'
                          : (senderType == 'courier' ? 'المندوب' : 'العميل');

                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(10),
                          constraints: const BoxConstraints(maxWidth: 280),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.amber[800] : const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.withOpacity(0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                senderLabel,
                                style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(messageText, style: const TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              color: const Color(0xFF1E1E1E),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'اكتب رسالتك هنا...',
                        hintStyle: TextStyle(color: Colors.grey),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.amber),
                    onPressed: () async {
                      final text = _msgController.text.trim();
                      if (text.isNotEmpty) {
                        // 1. إرسال وحفظ الرسالة في قاعدة البيانات عبر الـ Provider
                        await appState.sendChatMessage(
                          widget.orderId,
                          widget.userRole,
                          widget.targetChat,
                          text,
                        );

                        _msgController.clear();

                        // 2. 👈 [الإضافة الجديدة]: جلب معرف الطرف الآخر وإرسال إشعار فوري عبر OneSignal
                        try {
                          String? receiverPlayerId = await appState.getReceiverPlayerIdForChat(
                            orderId: widget.orderId,
                            senderRole: widget.userRole,
                            targetChat: widget.targetChat,
                          );

                          if (receiverPlayerId != null && receiverPlayerId.isNotEmpty) {
                            String senderName = widget.userRole == 'admin' 
                                ? 'الإدارة' 
                                : (widget.userRole == 'courier' ? 'المندوب' : 'العميل');

                            await NotificationService.sendNotificationToUser(
                              targetPlayerId: receiverPlayerId,
                              title: 'رسالة جديدة في الطلب #${widget.orderId} 💬',
                              body: '$senderName: $text',
                            );
                          }
                        } catch (e) {
                          debugPrint('⚠️ خطأ في إرسال إشعار الشات: $e');
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
