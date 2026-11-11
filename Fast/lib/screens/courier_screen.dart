import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state.dart';
import 'chat_screen.dart';

class CourierScreen extends StatefulWidget {
  const CourierScreen({Key? key}) : super(key: key);

  @override
  State<CourierScreen> createState() => _CourierScreenState();
}

class _CourierScreenState extends State<CourierScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // تحسين السلاسة والانتقال عبر الكيبورد
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // تعديل رابط الخريطة لفتح الاتجاهات مباشرة
  Future<void> _openMap(String address) async {
    final query = Uri.encodeComponent(address.isNotEmpty ? address : 'Taiz, Yemen');
    final googleMapsUrl = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$query');
    
    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح الخريطة حالياً ❌')),
        );
      }
    }
  }

  // 🌐 شريط تنبيه انقطاع الإنترنت العائم
  Widget _buildNetworkStatusBar(AppState appState) {
    if (appState.isConnectedToInternet) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.red[800],
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text(
            'تنبيه: انقطع الاتصال بالإنترنت! يرجى التحقق من الشبكة ⚠️',
            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final courier = appState.currentCourier;

    // حساب الطلبات التي تنتظر موافقة أو استجابة المندوب
    final pendingOrdersCount = courier != null 
        ? appState.orders.where((o) {
            final assigned = (o['assigned_courier'] ?? '').toString().trim().toLowerCase();
            final courierName = (courier['name'] ?? '').toString().trim().toLowerCase();
            final String orderStatus = o['status'] ?? '';
            return (assigned == courierName) && (orderStatus == 'waitingCourierApproval' || orderStatus == 'approvedByCustomer');
          }).length
        : 0;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(), // إغلاق الكيبورد بسلاسة عند الضغط في أي مكان فارغ
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E1E1E),
            elevation: 2,
            title: Text(
              courier == null ? 'تسجيل دخول الكابتن' : 'لوحة المندوب: ${courier['name']}', 
              style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            actions: [
              if (courier != null) ...[
                // 🛎️ أيقونة الإشعارات مع نافذة سجل الإشعارات الفورية للمندوب
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_active, color: Colors.amber, size: 24),
                      tooltip: 'سجل الإشعارات الفورية',
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => Directionality(
                            textDirection: TextDirection.rtl,
                            child: AlertDialog(
                              backgroundColor: const Color(0xFF1E1E1E),
                              title: const Row(
                                children: [
                                  Icon(Icons.notifications, color: Colors.amber),
                                  SizedBox(width: 8),
                                  Text('إشعارات المندوب 🛎️', style: TextStyle(color: Colors.amber, fontSize: 16)),
                                ],
                              ),
                              content: SizedBox(
                                width: double.maxFinite,
                                height: 350,
                                child: appState.notifications.isEmpty
                                    ? const Center(child: Text('لا توجد إشعارات جديدة حالياً 📭', style: TextStyle(color: Colors.grey)))
                                    : ListView.builder(
                                        itemCount: appState.notifications.length,
                                        itemBuilder: (_, idx) {
                                          final notif = appState.notifications[idx];
                                          return Card(
                                            color: const Color(0xFF121212),
                                            margin: const EdgeInsets.symmetric(vertical: 4),
                                            child: ListTile(
                                              title: Text(notif['title'] ?? '', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
                                              subtitle: Text(notif['body'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    if (pendingOrdersCount > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            '$pendingOrdersCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                  tooltip: 'تسجيل الخروج',
                  onPressed: () => appState.logoutCourier(),
                ),
              ],
            ],
          ),
          body: Column(
            children: [
              _buildNetworkStatusBar(appState),
              Expanded(
                child: courier == null
                    ? Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                                    ),
                                    child: const Icon(Icons.two_wheeler, size: 60, color: Colors.amber),
                                  ),
                                  const SizedBox(height: 24),
                                  const Text('بوابة تسجيل دخول الكابتن', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  const Text('أدخل بيانات الاعتماد الخاصة بك للوصول للطلبات', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                  const SizedBox(height: 30),
                                  // حقل اسم المستخدم مع الانتقال السلس للكيبورد
                                  TextField(
                                    controller: _usernameController,
                                    focusNode: _usernameFocus,
                                    textInputAction: TextInputAction.next,
                                    onSubmitted: (_) {
                                      FocusScope.of(context).requestFocus(_passwordFocus);
                                    },
                                    style: const TextStyle(color: Colors.white),
                                    decoration: const InputDecoration(
                                      labelText: 'اسم المستخدم',
                                      labelStyle: TextStyle(color: Colors.grey),
                                      filled: true,
                                      fillColor: Color(0xFF1E1E1E),
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.person_outline, color: Colors.amber),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  // حقل كلمة السر مع الانتقال السلس للكيبورد
                                  TextField(
                                    controller: _passwordController,
                                    focusNode: _passwordFocus,
                                    obscureText: true,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) async {
                                      // تنفيذ تسجيل الدخول مباشرة عند الضغط على تم
                                      await _performLogin(appState);
                                    },
                                    style: const TextStyle(color: Colors.white),
                                    decoration: const InputDecoration(
                                      labelText: 'كلمة السر',
                                      labelStyle: TextStyle(color: Colors.grey),
                                      filled: true,
                                      fillColor: Color(0xFF1E1E1E),
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.lock_outline, color: Colors.amber),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.amber, 
                                      minimumSize: const Size(double.infinity, 48),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: () => _performLogin(appState),
                                    child: const Text('دخول لوحة الطلبات 🚀', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : _buildCourierOrdersListWithTabs(appState, courier),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // دالة تسجيل الدخول لتجنب تكرار الكود
  Future<void> _performLogin(AppState appState) async {
    bool success = await appState.loginCourier(_usernameController.text.trim(), _passwordController.text.trim());
    if (success) {
      try {
        String? playerId = OneSignal.User.pushSubscription.id;
        if (playerId != null && playerId.isNotEmpty && appState.currentCourier != null) {
          String courierId = appState.currentCourier!['id']?.toString() ?? appState.currentCourier!['delivery_man_id']?.toString() ?? '';
          if (courierId.isNotEmpty) {
            await Supabase.instance.client
                .from('couriers')
                .update({'onesignal_player_id': playerId})
                .eq('id', courierId);
          }
        }
      } catch (e) {
        debugPrint('⚠️ خطأ: $e');
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل الدخول: بيانات غير صحيحة! ❌')),
        );
      }
    }
  }

  Widget _buildCourierOrdersListWithTabs(AppState appState, Map<String, dynamic> courier) {
    final String courierName = (courier['name'] ?? '').toString().trim().toLowerCase();
    final String courierId = (courier['id'] ?? '').toString().trim();

    final myOrders = appState.orders.where((o) {
      final assigned = (o['assigned_courier'] ?? '').toString().trim().toLowerCase();
      return assigned == courierName || assigned == courierId || assigned.contains(courierName);
    }).toList();

    final activeOrders = myOrders.where((o) => o['status'] != 'delivered' && o['status'] != 'cancelled' && o['status'] != 'cancelledByCustomer').toList();
    final completedOrders = myOrders.where((o) => o['status'] == 'delivered').toList();
    final cancelledOrders = myOrders.where((o) => o['status'] == 'cancelled' || o['status'] == 'cancelledByCustomer').toList();

    double totalEarnings = 0.0;
    int completedCount = 0;
    for (var order in myOrders) {
      if (order['status'] == 'delivered') {
        completedCount++;
        totalEarnings += double.tryParse(order['delivery_fee']?.toString() ?? '0') ?? 0.0;
      }
    }

    double adminCommission = totalEarnings * 0.20;
    double courierNetEarnings = totalEarnings - adminCommission;

    return DefaultTabController(
      length: 3,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E), 
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Colors.amber,
                        radius: 18,
                        child: Icon(Icons.delivery_dining, color: Colors.black, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Text('الكابتن: ${courier['name']}', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('إجمالي الطلبات: ${myOrders.length}', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.withOpacity(0.4), width: 1.5),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text('الطلبات المكتملة ✅', style: TextStyle(color: Colors.grey, fontSize: 11)),
                          const SizedBox(height: 4),
                          Text('$completedCount', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Container(width: 1, height: 30, color: Colors.white24),
                      Column(
                        children: [
                          const Text('إجمالي التوصيل 💰', style: TextStyle(color: Colors.grey, fontSize: 11)),
                          const SizedBox(height: 4),
                          Text('${totalEarnings.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.amber, fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('عمولة الإدارة (20%): ${adminCommission.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                      Text('صافيك (80%): ${courierNetEarnings.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),

            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                labelColor: Colors.amber,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.amber,
                tabs: [
                  Tab(text: 'النشطة (${activeOrders.length})'),
                  Tab(text: 'المكتملة (${completedOrders.length})'),
                  Tab(text: 'الملغية (${cancelledOrders.length})'),
                ],
              ),
            ),
            const SizedBox(height: 10),

            Expanded(
              child: TabBarView(
                children: [
                  _buildOrdersListView(appState, activeOrders, 'لا توجد طلبات نشطة حالياً 📦'),
                  _buildOrdersListView(appState, completedOrders, 'لا توجد طلبات مكتملة 📭'),
                  _buildOrdersListView(appState, cancelledOrders, 'لا توجد طلبات ملغية 🚫'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersListView(AppState appState, List ordersList, String emptyMessage) {
    if (ordersList.isEmpty) {
      return Center(child: Text(emptyMessage, style: const TextStyle(color: Colors.grey, fontSize: 14)));
    }

    return ListView.builder(
      itemCount: ordersList.length,
      itemBuilder: (context, index) {
        final order = ordersList[index];
        final orderId = order['id'].toString();
        final String customerAddress = order['address'] ?? '';
        final String orderStatus = order['status'] ?? '';

        final String productsPrice = order['total_price']?.toString() ?? '0';
        final String deliveryFee = order['delivery_fee']?.toString() ?? '0';
        final double finalTotal = (double.tryParse(productsPrice) ?? 0.0) + (double.tryParse(deliveryFee) ?? 0.0);

        // بيانات التقييم إن وجدت
        final ratingValue = order['rating'];
        final ratingComment = order['rating_comment']?.toString();

        return Card(
          color: const Color(0xFF1E1E1E),
          margin: const EdgeInsets.symmetric(vertical: 8),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.amber.withOpacity(0.2)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('طلب #$orderId', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                    IconButton(
                      style: IconButton.styleFrom(backgroundColor: Colors.blueGrey[800]),
                      icon: const Icon(Icons.chat, color: Colors.amber, size: 20),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(
                              orderId: orderId,
                              userRole: 'courier',
                              targetChat: 'admin_courier',
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 16),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 16, color: Colors.redAccent),
                    const SizedBox(width: 6),
                    Expanded(child: Text('العنوان: $customerAddress', style: const TextStyle(color: Colors.white70, fontSize: 13))),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.amber),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.map, color: Colors.amber, size: 16),
                    label: const Text('فتح اتجاهات الملاحة في خرائط جوجل 🗺️', style: TextStyle(color: Colors.amber, fontSize: 12)),
                    onPressed: () => _openMap(customerAddress),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.shopping_bag, size: 16, color: Colors.amberAccent),
                    const SizedBox(width: 6),
                    Expanded(child: Text('المنتجات: ${order['items_description'] ?? order['items_desc'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 13))),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🛍️ سعر المنتجات: $productsPrice ر.ي', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      Text('🏍️ رسوم التوصيل: $deliveryFee ر.ي', style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold)),
                      const Divider(color: Colors.white12, height: 8),
                      Text('💰 الإجمالي الكلي المطلوب من العميل: ${finalTotal.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text('📌 الحالة: ${appState.getArabicStatus(orderStatus)}', style: const TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                
                // عرض التقييم داخل صفحة الطلب ليصل للمشرف والمندوب بوضوح
                if (ratingValue != null) ...[
                  const Divider(color: Colors.white12, height: 16),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 16),
                            const SizedBox(width: 6),
                            Text('تقييم العميل: $ratingValue / 5', style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        if (ratingComment != null && ratingComment.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('ملاحظة العميل: $ratingComment', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ],
                    ),
                  ),
                ],

                const Divider(color: Colors.white12, height: 20),
                _buildOrderActions(appState, orderId, orderStatus),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrderActions(AppState appState, String orderId, String orderStatus) {
    if (orderStatus == 'waitingCourierApproval' || orderStatus == 'approvedByCustomer') {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () => appState.courierRespondToOrder(orderId, true),
              child: const Text('قبول الطلب ✅', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => appState.courierRespondToOrder(orderId, false),
              child: const Text('رفض الطلب ❌', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      );
    } else if (orderStatus == 'acceptedByCourier' || orderStatus == 'onTheWay') {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 40)),
        onPressed: () => appState.courierUpdateArrival(orderId),
        child: const Text('تحديث الحالة (تم الوصول للموقع) 📍', style: TextStyle(fontWeight: FontWeight.bold)),
      );
    } else if (orderStatus == 'arrivedToCustomer' || orderStatus == 'arrived') {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 40)),
        onPressed: () => appState.markOrderDelivered(orderId),
        child: const Text('تأكيد تسليم الطلب وتحصيل المبلغ ✅', style: TextStyle(fontWeight: FontWeight.bold)),
      );
    }
    return const SizedBox.shrink();
  }
}
