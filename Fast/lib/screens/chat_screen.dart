import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state.dart';
import 'order_tracking_screen.dart';

class ChatScreen extends StatefulWidget {
  final String orderId;
  final String userRole; // 'customer', 'admin', 'courier'
  final String targetChat; // موحد لكل أطراف الطلب

  const ChatScreen({
    super.key,
    required this.orderId,
    required this.userRole,
    this.targetChat = 'unified_order_chat',
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final FocusNode _msgFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  bool _isLoadingInitial = true;
  bool _isSending = false;
  String? _loadError;

  Timer? _pollingTimer;
  RealtimeChannel? _chatChannel;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _initChatSync();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    if (_chatChannel != null) {
      unawaited(Supabase.instance.client.removeChannel(_chatChannel!));
    }
    _msgController.dispose();
    _msgFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  dynamic get _parsedOrderId => int.tryParse(widget.orderId) ?? widget.orderId;

  Future<void> _initChatSync() async {
    await _fetchMessagesHttp(showLoader: true);
    _subscribeRealtimeSafely();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        unawaited(_fetchMessagesHttp(showLoader: false));
      }
    });
  }

  Future<void> _fetchMessagesHttp({required bool showLoader}) async {
    if (showLoader && mounted && _messages.isEmpty) {
      setState(() {
        _isLoadingInitial = true;
        _loadError = null;
      });
    }

    try {
      final rows = await Supabase.instance.client
          .from('messages')
          .select()
          .eq('order_id', _parsedOrderId)
          .order('created_at', ascending: true)
          .timeout(const Duration(seconds: 12));

      final list = rows.map((row) => Map<String, dynamic>.from(row)).toList();

      if (!mounted) return;
      setState(() {
        _messages = list;
        _isLoadingInitial = false;
        _loadError = null;
      });
      _scrollToBottomIfNeeded(list.length);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingInitial = false;
        if (_messages.isEmpty) {
          _loadError = 'تعذر تحميل الرسائل حالياً، جاري إعادة المحاولة...';
        }
      });
    }
  }

  void _subscribeRealtimeSafely() {
    try {
      final client = Supabase.instance.client;
      _chatChannel = client
          .channel('order_chat_${widget.orderId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'order_id',
              value: _parsedOrderId.toString(),
            ),
            callback: (payload) {
              if (!mounted) return;
              final newMsg = Map<String, dynamic>.from(payload.newRecord);
              final newId = newMsg['id']?.toString();
              final exists = newId != null &&
                  _messages.any((m) => m['id']?.toString() == newId);
              if (!exists) {
                setState(() {
                  _messages.add(newMsg);
                });
                _scrollToBottomIfNeeded(_messages.length);
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('تعذر تفعيل Realtime للشات، الاعتماد على التحديث الدوري: $e');
    }
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
    return 'محادثة الطلب الموحدة • طلب #${widget.orderId}';
  }

  Color _getSenderBadgeColor(String senderType) {
    switch (senderType) {
      case 'admin':
        return Colors.amberAccent;
      case 'courier':
        return Colors.lightBlueAccent;
      default:
        return Colors.greenAccent;
    }
  }

  Future<void> _sendMessage() async {
    if (_isSending) return;
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    final appState = context.read<AppState>();
    HapticFeedback.lightImpact();

    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
    final optimisticMsg = <String, dynamic>{
      'id': tempId,
      'order_id': _parsedOrderId,
      'sender_type': widget.userRole,
      'target_chat': 'unified_order_chat',
      'message_text': text,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    setState(() {
      _messages.add(optimisticMsg);
      _msgController.clear();
    });
    _scrollToBottomIfNeeded(_messages.length);

    try {
      await appState.sendChatMessage(
        widget.orderId,
        widget.userRole,
        'unified_order_chat',
        text,
      );

      if (!mounted) return;
      _msgFocus.requestFocus();
      unawaited(_fetchMessagesHttp(showLoader: false));

      unawaited(() async {
        try {
          final String senderName = widget.userRole == 'admin'
              ? 'الإدارة'
              : (widget.userRole == 'courier' ? 'المندوب' : 'العميل');

          final Set<String> targetPlayerIds = {};

          final customerOrOtherId = await appState.getReceiverPlayerIdForChat(
            orderId: widget.orderId,
            senderRole: widget.userRole,
            targetChat: 'admin_customer',
          );
          if (customerOrOtherId != null && customerOrOtherId.isNotEmpty) {
            targetPlayerIds.add(customerOrOtherId);
          }

          final courierId = await appState.getReceiverPlayerIdForChat(
            orderId: widget.orderId,
            senderRole: widget.userRole,
            targetChat: 'admin_courier',
          );
          if (courierId != null && courierId.isNotEmpty) {
            targetPlayerIds.add(courierId);
          }

          if (widget.userRole != 'admin') {
            final adminIds = await appState.getAllAdminPlayerIds();
            targetPlayerIds.addAll(adminIds.where((id) => id.isNotEmpty));
          }

          for (final playerId in targetPlayerIds) {
            await appState.sendAutoNotification(
              targetPlayerId: playerId,
              title: 'رسالة جديدة في الطلب #${widget.orderId} 💬',
              body: '$senderName: $text',
              orderId: widget.orderId,
              eventType: 'chat_message',
            );
          }
        } catch (e) {
          debugPrint('⚠️ خطأ في إرسال إشعار الشات: $e');
        }
      }());
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m['id'] == tempId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر إرسال الرسالة، تحقق من الاتصال وحاول مجدداً'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Widget _buildLinkedOrderBanner(BuildContext context, AppState appState) {
    final matched = appState.orders.where(
      (o) => o['id']?.toString() == widget.orderId,
    );
    if (matched.isEmpty) return const SizedBox.shrink();

    final order = Map<String, dynamic>.from(matched.first);
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

  Widget _buildMessagesBody() {
    if (_isLoadingInitial && _messages.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.amber),
      );
    }

    if (_loadError != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.amber, fontSize: 13),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _fetchMessagesHttp(showLoader: true),
                icon: const Icon(Icons.refresh, color: Colors.black),
                label: const Text(
                  'إعادة المحاولة',
                  style: TextStyle(color: Colors.black),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد رسائل بعد، ابدأ المحادثة الآن 💬',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final String senderType = msg['sender_type']?.toString() ?? '';
        final String messageText = msg['message_text']?.toString() ?? '';
        final bool isMe = senderType == widget.userRole;

        final String senderLabel = senderType == 'admin'
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
              border: Border.all(
                color: Colors.amber.withOpacity(0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  senderLabel,
                  style: TextStyle(
                    color:
                        isMe ? Colors.white : _getSenderBadgeColor(senderType),
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
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E1E1E),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _buildChatTitle(),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                const Text(
                  'تجمع المشرف والعميل والمندوب',
                  style: TextStyle(color: Colors.amber, fontSize: 10),
                ),
              ],
            ),
            iconTheme: const IconThemeData(color: Colors.amber),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.amber, size: 20),
                tooltip: 'تحديث الرسائل',
                onPressed: () => _fetchMessagesHttp(showLoader: false),
              ),
            ],
          ),
          body: Column(
            children: [
              _buildLinkedOrderBanner(context, appState),
              Expanded(child: _buildMessagesBody()),
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
                          hintText: 'اكتب رسالتك للجميع هنا...',
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
