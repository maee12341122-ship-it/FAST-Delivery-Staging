import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'order_tracking_screen.dart';

class ChatScreen extends StatefulWidget {
  final String orderId;
  final String userRole; // 'customer', 'admin', 'courier'
  final String targetChat; // 'admin_customer', 'admin_courier', 'courier_customer'

  const ChatScreen({
    super.key,
    required this.orderId,
    required this.userRole,
    required this.targetChat,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final FocusNode _msgFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  int _lastMessageCount = 0;
  bool _isSending = false;

  @override
  void dispose() {
    _msgController.dispose();
    _msgFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottomIfNeeded(int currentCount) {
    if (currentCount == _lastMessageCount) return;
    _lastMessageCount = currentCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String _buildChatTitle() {
    if (widget.targetChat == 'admin_courier') {
      return 'المشرف ↔ المندوب • طلب #${widget.orderId}';
    }
    if (widget.targetChat == 'courier_customer') {
      return 'المندوب ↔ العميل • طلب #${widget.orderId}';
    }
    return 'المشرف ↔ العميل • طلب #${widget.orderId}';
  }

  Future<void> _sendMessage() async {
    if (_isSending) return;
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    final appState = context.read<AppState>();
    HapticFeedback.lightImpact();

    try {
      await appState.sendChatMessage(
        widget.orderId,
        widget.userRole,
        widget.targetChat,
        text,
      );

      _msgController.clear();

      if (!mounted) return;
      _msgFocus.requestFocus();

      try {
        final String? receiverPlayerId =
            await appState.getReceiverPlayerIdForChat(
          orderId: widget.orderId,
          senderRole: widget.userRole,
          targetChat: widget.targetChat,
        );

        final String senderName = widget.userRole == 'admin'
            ? 'الإدارة'
            : (widget.userRole == 'courier' ? 'المندوب' : 'العميل');

        if (receiverPlayerId != null && receiverPlayerId.isNotEmpty) {
          await appState.sendAutoNotification(
            targetPlayerId: receiverPlayerId,
            title: 'رسالة جديدة في الطلب #${widget.orderId} 💬',
            body: '$senderName: $text',
          );
        }
      } catch (e) {
        debugPrint('⚠️ خطأ في إرسال إشعار الشات: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Widget _buildLinkedOrderBanner(BuildContext context, AppState appState) {
    final matched = appState.orders.where(
      (o) => o is Map && o['id']?.toString() == widget.orderId,
    );
    if (matched.isEmpty) return const SizedBox.shrink();

    final order = Map<String, dynamic>.from(matched.first as Map);
    final statusRaw = order['status']?.toString() ?? '';
    final statusLabel =
        statusRaw.isNotEmpty ? appState.getArabicStatus(statusRaw) : '';
    final itemsText =
        (order['items_description'] ?? order['items_desc'] ?? '').toString();
    final addressText = (order['address'] ?? '').toString();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long, color: Colors.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'طلب #${widget.orderId}${statusLabel.isNotEmpty ? ' • $statusLabel' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                if (itemsText.isNotEmpty || addressText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (itemsText.isNotEmpty) itemsText,
                      if (addressText.isNotEmpty) addressText,
                    ].join(' — '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OrderTrackingScreen(
                    orderMap: order,
                    orderIdParam: widget.orderId,
                  ),
                ),
              );
            },
            child: const Text(
              'تتبع الطلب',
              style: TextStyle(
                color: Colors.amber,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E1E1E),
            title: Text(
              _buildChatTitle(),
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            iconTheme: const IconThemeData(color: Colors.amber),
          ),
          body: Column(
            children: [
              _buildLinkedOrderBanner(context, appState),
              Expanded(
                child: StreamBuilder(
                  stream: appState.getMessagesForOrder(
                    widget.orderId,
                    widget.targetChat,
                  ),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData &&
                        snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.amber),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'خطأ في تحميل الرسائل: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      );
                    }

                    final messages = (snapshot.data as List?) ?? [];

                    if (messages.isEmpty) {
                      _lastMessageCount = 0;
                      return const Center(
                        child: Text(
                          'لا توجد رسائل بعد، ابدأ المحادثة الآن 💬',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      );
                    }

                    _scrollToBottomIfNeeded(messages.length);

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final raw = messages[index];
                        final msg = raw is Map
                            ? Map<String, dynamic>.from(raw)
                            : <String, dynamic>{};
                        final String senderType =
                            msg['sender_type']?.toString() ?? '';
                        final String messageText =
                            msg['message_text']?.toString() ?? '';
                        final bool isMe = senderType == widget.userRole;

                        final String senderLabel = senderType == 'admin'
                            ? 'الإدارة'
                            : (senderType == 'courier' ? 'المندوب' : 'العميل');

                        return Align(
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(10),
                            constraints: const BoxConstraints(maxWidth: 280),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? Colors.amber[800]
                                  : const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.amber.withOpacity(0.2),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  senderLabel,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  messageText,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
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
                        focusNode: _msgFocus,
                        enabled: !_isSending,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
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
                      icon: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.amber,
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.amber),
                      onPressed: _isSending ? null : _sendMessage,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
