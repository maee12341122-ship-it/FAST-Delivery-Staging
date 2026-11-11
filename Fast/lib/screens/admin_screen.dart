import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state.dart';
import 'chat_screen.dart';
import 'order_tracking_screen.dart'; // 👈 استيراد شاشة تتبع الطلب للربط المباشر بالإشعارات
import 'admin/admin_products_screen.dart';
import 'admin/admin_reports_screen.dart';
import '../admin_restaurants_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({Key? key}) : super(key: key);

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  int _selectedNavIndex = 0;
  late TabController _ordersTabController;

  final TextEditingController _courierNameController = TextEditingController();
  final TextEditingController _courierPhoneController = TextEditingController();
  final TextEditingController _courierUsernameController = TextEditingController();
  final TextEditingController _courierPasswordController = TextEditingController();

  final Map<String, TextEditingController> _feeControllers = {};

  @override
  void initState() {
    super.initState();
    _ordersTabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _ordersTabController.dispose();
    _courierNameController.dispose();
    _courierPhoneController.dispose();
    _courierUsernameController.dispose();
    _courierPasswordController.dispose();
    for (var controller in _feeControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _getArabicStatus(String status) {
    switch (status) {
      case 'waitingForPricing': return '⏳ بانتظار التسعير';
      case 'pricingSentToCustomer': return '🔔 بانتظار موافقة العميل';
      case 'waitingCourierApproval': return '🛵 بانتظار قبول المندوب';
      case 'acceptedByCourier': return '🚀 وافق المندوب';
      case 'onTheWay': return '🟢 المندوب في الطريق';
      case 'arrived':
      case 'arrivedToCustomer': return '📍 وصل المندوب للموقع';
      case 'delivered': return '✅ تم التسليم';
      case 'cancelled':
      case 'cancelledByCustomer': return '❌ ملغى';
      default: return status;
    }
  }

  // 🔔 دالة ذكية لمعالجة النقر على إشعار المشرف وتوجيهه للطلب المحدد فوراً
  void _handleAdminNotificationTap(BuildContext context, Map<String, dynamic> notification) {
    final String? orderId = notification['order_id']?.toString() ?? 
                            notification['related_id']?.toString() ?? 
                            notification['additionalData']?['order_id']?.toString() ??
                            _extractOrderIdFromText((notification['title'] ?? '') + ' ' + (notification['body'] ?? notification['message'] ?? ''));

    if (orderId != null && orderId.isNotEmpty) {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => OrderTrackingScreen(orderIdParam: orderId),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذا الإشعار غير مرتبط برقم طلب معين 📭')),
      );
    }
  }

  // 🔍 دالة لاستخراج رقم الطلب من نص الإشعار
  String? _extractOrderIdFromText(String text) {
    final RegExp regExp = RegExp(r'(?:طلب|#)\s*(\d+)');
    final match = regExp.firstMatch(text);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    return null;
  }

  // 📢 نافذة إضافة أو تعديل البنر الترويجي
  void _showAddOrEditBannerDialog(BuildContext context, AppState appState, Map<String, dynamic>? banner) {
    final titleController = TextEditingController(text: banner?['title'] ?? '');
    final subtitleController = TextEditingController(text: banner?['subtitle'] ?? '');
    final codeController = TextEditingController(text: banner?['code'] ?? '');

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(banner == null ? 'إضافة بنر ترويجي جديد 📢' : 'تعديل البنر الترويجي ✏️', style: const TextStyle(color: Colors.amber)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'عنوان البنر', labelStyle: TextStyle(color: Colors.grey)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: subtitleController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'الوصف أو التفاصيل', labelStyle: TextStyle(color: Colors.grey)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: codeController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'كود الخصم (اختياري)', labelStyle: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              onPressed: () async {
                if (titleController.text.isNotEmpty) {
                  if (banner == null) {
                    await Supabase.instance.client.from('promo_banners').insert({
                      'title': titleController.text.trim(),
                      'subtitle': subtitleController.text.trim(),
                      'code': codeController.text.trim(),
                      'is_active': true,
                    });
                  } else {
                    await Supabase.instance.client.from('promo_banners').update({
                      'title': titleController.text.trim(),
                      'subtitle': subtitleController.text.trim(),
                      'code': codeController.text.trim(),
                    }).eq('id', banner['id']);
                  }
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ البنر بنجاح ✅')));
                }
              },
              child: const Text('حفظ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // 📢 نافذة إدارة البنرات الترويجية للمشرف
  void _showBannersManagementDialog(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('إدارة البنرات الترويجية 📢', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('إضافة بنر'),
                  onPressed: () {
                    Navigator.pop(context);
                    _showAddOrEditBannerDialog(context, appState, null);
                  },
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: FutureBuilder<List<dynamic>>(
                future: Supabase.instance.client.from('promo_banners').select().order('id', ascending: false),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.amber));
                  }
                  final banners = snapshot.data ?? [];
                  if (banners.isEmpty) {
                    return const Center(child: Text('لا توجد بنرات مضافة حالياً 📭', style: TextStyle(color: Colors.grey)));
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: banners.length,
                    itemBuilder: (context, index) {
                      final banner = banners[index];
                      return Card(
                        color: const Color(0xFF121212),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.amber.withOpacity(0.3))),
                        child: ListTile(
                          title: Text(banner['title'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text('${banner['subtitle']}\nكود الخصم: ${banner['code'] ?? "لا يوجد"}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blueAccent, size: 20),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showAddOrEditBannerDialog(context, appState, banner);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                                onPressed: () async {
                                  await Supabase.instance.client.from('promo_banners').delete().eq('id', banner['id']);
                                  setDialogState(() {});
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف البنر بنجاح 🗑️')));
                                  }
                                },
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🌟 نافذة عرض تقييمات وملاحظات المطاعم للمشرف
  void _showRestaurantRatingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.star, color: Colors.amber),
                SizedBox(width: 8),
                Text('تقييمات وملاحظات المطاعم ⭐', style: TextStyle(color: Colors.amber, fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: FutureBuilder(
                future: Supabase.instance.client
                    .from('restaurant_ratings')
                    .select()
                    .order('created_at', ascending: false),
                builder: (BuildContext context, AsyncSnapshot snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.amber));
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('خطأ في جلب التقييمات: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                  }
                  
                  final dynamic rawData = snapshot.data;
                  if (rawData == null || (rawData is List && rawData.isEmpty)) {
                    return const Center(child: Text('لا توجد تقييمات مطاعم مسجلة حتى الآن 📭', style: TextStyle(color: Colors.grey)));
                  }

                  final List<dynamic> listData = rawData as List<dynamic>;

                  return ListView.builder(
                    itemCount: listData.length,
                    itemBuilder: (BuildContext context, int index) {
                      final dynamic item = listData[index];
                      final Map<String, dynamic> r = item is Map<String, dynamic> ? item : {};
                      
                      return Card(
                        color: const Color(0xFF121212),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.amber.withOpacity(0.3)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('🍽️ ${r['restaurant_name'] ?? 'مطعم'}', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
                                  Row(
                                    children: [
                                      const Icon(Icons.star, color: Colors.amber, size: 16),
                                      const SizedBox(width: 4),
                                      Text('${r['rating'] ?? 5.0}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text('📦 رقم الطلب: #${r['order_id'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              Text('📞 هاتف العميل: ${r['customer_phone'] ?? 'غير معروف'}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              if (r['review_text'] != null && r['review_text'].toString().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text('💬 الملاحظة: "${r['review_text']}"', style: const TextStyle(color: Colors.amberAccent, fontSize: 13)),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        );
      },
    );
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
    final appState = context.watch<AppState>();

    final List<Widget> adminPages = [
      _buildOrdersManagementWithTabs(appState),
      _buildProductsManagement(appState),
      _buildCouriersManagement(appState),
      _buildSettingsTab(appState),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          elevation: 2,
          title: const Text('لوحة تحكم المشرف - FAST', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
          actions: [
            // 🛎️ أيقونة الإشعارات المنبثقة وسجل إشعارات المشرف القابل للنقر والانتقال للطلب
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_active, color: Colors.amber, size: 24),
                  tooltip: 'سجل الإشعارات والطلبات الجديدة',
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
                              Text('إشعارات النظام الفورية 🛎️', style: TextStyle(color: Colors.amber, fontSize: 16)),
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
                                          trailing: const Icon(Icons.arrow_forward_ios, color: Colors.amber, size: 14),
                                          onTap: () {
                                            Navigator.pop(ctx); // إغلاق الحوار
                                            _handleAdminNotificationTap(context, notif); // الانتقال للطلب المحدد
                                          },
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
                if (appState.orders.where((o) => o['status'] == 'waitingForPricing').isNotEmpty)
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
                        '${appState.orders.where((o) => o['status'] == 'waitingForPricing').length}',
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
              tooltip: 'تسجيل خروج المشرف',
              onPressed: () {
                appState.logoutAdmin();
                Navigator.pop(context);
              },
            ),
          ],
        ),
        body: Column(
          children: [
            _buildNetworkStatusBar(appState),
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.withOpacity(0.4), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.remove_red_eye, color: Colors.amber, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('إجمالي زوار التطبيق والموقع 📊', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          SizedBox(height: 2),
                          Text('إجمالي مرات الدخول وزيارات العملاء', style: TextStyle(color: Colors.grey, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                  Text(
                    '${appState.totalVisitorsCount} زائر',
                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: adminPages[_selectedNavIndex],
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedNavIndex,
          onTap: (index) => setState(() => _selectedNavIndex = index),
          backgroundColor: const Color(0xFF1E1E1E),
          selectedItemColor: Colors.amber,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'الطلبات'),
            BottomNavigationBarItem(icon: Icon(Icons.fastfood), label: 'المنتجات'),
            BottomNavigationBarItem(icon: Icon(Icons.delivery_dining), label: 'المناديب'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'الإعدادات'),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersManagementWithTabs(AppState appState) {
    final activeOrders = appState.orders.where((o) => o['status'] != 'delivered' && o['status'] != 'cancelled' && o['status'] != 'cancelledByCustomer').toList();
    final completedOrders = appState.orders.where((o) => o['status'] == 'delivered').toList();
    final cancelledOrders = appState.orders.where((o) => o['status'] == 'cancelled' || o['status'] == 'cancelledByCustomer').toList();

    return Column(
      children: [
        Container(
          color: const Color(0xFF1E1E1E),
          child: TabBar(
            controller: _ordersTabController,
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
        Expanded(
          child: TabBarView(
            controller: _ordersTabController,
            children: [
              _buildOrdersList(appState, activeOrders, 'لا توجد طلبات نشطة حالياً 📦'),
              _buildOrdersList(appState, completedOrders, 'لا توجد طلبات مكتملة 📭'),
              _buildOrdersList(appState, cancelledOrders, 'لا توجد طلبات ملغية 🚫'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOrdersList(AppState appState, List ordersList, String emptyMessage) {
    if (ordersList.isEmpty) {
      return Center(child: Text(emptyMessage, style: const TextStyle(color: Colors.grey, fontSize: 15)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: ordersList.length,
      itemBuilder: (context, index) {
        final order = ordersList[index];
        final orderId = order['id'].toString();
        final rawStatus = order['status'] ?? '';
        final arabicStatus = _getArabicStatus(rawStatus);
        final assignedCourier = order['assigned_courier']?.toString() ?? 'لم يتم التعيين';

        final paymentMethod = order['payment_method'] ?? 'cash';
        final paymentAccount = order['payment_account'] ?? '';
        final paymentDisplay = (paymentMethod == 'cash' || paymentMethod == 'cash_on_delivery')
            ? '💵 نقداً عند الاستلام'
            : '💳 محفظة ($paymentMethod) - حساب: $paymentAccount';

        final bool isLocked = rawStatus != 'waitingForPricing' && rawStatus != 'pricingSentToCustomer';

        if (!_feeControllers.containsKey(orderId)) {
          _feeControllers[orderId] = TextEditingController(text: order['delivery_fee']?.toString() ?? '0');
        }

        return Card(
          color: const Color(0xFF1E1E1E),
          margin: const EdgeInsets.symmetric(vertical: 8),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isLocked ? Colors.green.withOpacity(0.4) : Colors.amber.withOpacity(0.3), width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('طلب #$orderId', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isLocked ? Colors.green.withOpacity(0.2) : Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isLocked ? Colors.green : Colors.amber.withOpacity(0.3)),
                      ),
                      child: Text(arabicStatus, style: TextStyle(color: isLocked ? Colors.greenAccent : Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 20),
                Text('👤 العميل: ${order['customer_name']} (${order['phone']})', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('📍 العنوان: ${order['address']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text('🛒 المنتجات: ${order['items_description']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text('💰 سعر المنتجات: ${order['total_price']} ر.ي', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                  child: Text('طريقة الدفع: $paymentDisplay', style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                Text('🛵 المندوب الحالي: $assignedCourier', style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey[800],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.chat, size: 16, color: Colors.amber),
                        label: const Text('شات العميل', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(orderId: orderId, userRole: 'admin', targetChat: 'admin_customer'),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo[900],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.delivery_dining, size: 16, color: Colors.amber),
                        label: const Text('شات المندوب', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(orderId: orderId, userRole: 'admin', targetChat: 'admin_courier'),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _feeControllers[orderId],
                        keyboardType: TextInputType.number,
                        enabled: !isLocked,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: isLocked ? 'رسوم التوصيل (مقفل 🔒)' : 'رسوم التوصيل (ر.ي)',
                          labelStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF121212),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        dropdownColor: const Color(0xFF1E1E1E),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: isLocked ? 'المندوب (مقفل 🔒)' : 'اختر المندوب',
                          labelStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF121212),
                          border: const OutlineInputBorder(),
                        ),
                        value: appState.couriers.any((c) => c['name'] == order['assigned_courier'])
                            ? order['assigned_courier']
                            : null,
                        items: appState.couriers.map<DropdownMenuItem<String>>((courier) {
                          final cName = courier['name'].toString();
                          final cStatus = courier['status']?.toString() ?? 'available';
                          
                          int activeCount = appState.orders.where((o) {
                            return o['assigned_courier'] == cName && 
                                   o['status'] != 'delivered' && 
                                   o['status'] != 'cancelled' && 
                                   o['status'] != 'cancelledByCustomer';
                          }).length;

                          String statusLabel = cStatus == 'busy' || activeCount >= 2 ? ' 🔴 (مشغول - لديه $activeCount طلب)' : ' 🟢 (متاح)';

                          return DropdownMenuItem<String>(
                            value: cName,
                            child: Text('$cName$statusLabel', style: TextStyle(color: activeCount >= 2 ? Colors.orangeAccent : Colors.white, fontSize: 12)),
                          );
                        }).toList(),
                        onChanged: isLocked ? null : (val) {
                          setState(() {
                            order['assigned_courier'] = val;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isLocked ? Colors.grey[800] : Colors.amber,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isLocked ? null : () async {
                    final fee = double.tryParse(_feeControllers[orderId]?.text ?? '0') ?? 0.0;
                    final courierName = order['assigned_courier'] ?? 'لم يتم التعيين';
                    
                    if (courierName == 'لم يتم التعيين') {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء اختيار مندوب أولاً ⚠️')));
                      return;
                    }

                    int courierActiveOrders = appState.orders.where((o) {
                      return o['assigned_courier'] == courierName && 
                             o['status'] != 'delivered' && 
                             o['status'] != 'cancelled' && 
                             o['status'] != 'cancelledByCustomer';
                    }).length;

                    if (courierActiveOrders >= 2) {
                      bool? confirmAssign = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => Directionality(
                          textDirection: TextDirection.rtl,
                          child: AlertDialog(
                            backgroundColor: const Color(0xFF1E1E1E),
                            title: const Text('تنبيه: المندوب مشغول! ⚠️', style: TextStyle(color: Colors.amber)),
                            content: Text('الكابتن ($courierName) لديه بالفعل ($courierActiveOrders) طلبات نشطة حالياً. هل أنت متأكد من إسناد طلب إضافي له أم تود اختيار مندوب آخر؟', style: const TextStyle(color: Colors.white70)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('اختيار غيره ❌', style: TextStyle(color: Colors.grey))),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                                onPressed: () => Navigator.pop(ctx, true), 
                                child: const Text('إسناد رغم ذلك 🚀', style: TextStyle(color: Colors.black)),
                              ),
                            ],
                          ),
                        ),
                      );
                      if (confirmAssign != true) return;
                    }
                    
                    appState.setOrderDeliveryFee(orderId, fee, courierName);

                    try {
                      final customerPhone = order['phone']?.toString() ?? '';
                      if (customerPhone.isNotEmpty) {
                        String? customerPlayerId = await appState.getPlayerIdForUser(customerPhone, 'customers');
                        if (customerPlayerId != null && customerPlayerId.isNotEmpty) {
                          await appState.sendAutoNotification(
                            targetPlayerId: customerPlayerId,
                            title: 'تم تحديث طلبك #$orderId 💰',
                            body: 'تم تحديد رسوم التوصيل ($fee ر.ي). يرجى تأكيد الطلب للمتابعة!',
                          );
                        }
                      }
                    } catch (e) {
                      debugPrint('⚠️ خطأ في إرسال الإشعار التلقائي للعميل: $e');
                    }

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديد الرسوم وإسناد الطلب للمندوب بنجاح! ✅')));
                    }
                  },
                  child: Text(
                    isLocked ? 'الطلب مؤكد ومقفل 🔒' : 'إرسال التسعيرة وإسناد الطلب للمندوب 🚀',
                    style: TextStyle(color: isLocked ? Colors.grey : Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductsManagement(AppState appState) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.restaurant_menu, size: 75, color: Colors.amber),
          const SizedBox(height: 16),
          const Text(
            'إدارة وتعديل منتجات وأصناف المتجر 🍔',
            style: TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          const Text(
            'تحكم كامل بقائمة الطعام والسلع: تعديل الأسعار، تبديل حالة التوفر (متوفر/غير متوفر), حذف أو إضافة منتجات جديدة بكل سهولة.',
            style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 35),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AdminProductsScreen()),
              );
            },
            icon: const Icon(Icons.edit_note, size: 22),
            label: const Text('فتح لوحة إدارة المنتجات والأصناف 🚀', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ],
      ),
    );
  }

  Widget _buildCouriersManagement(AppState appState) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          const Text('حسابات المناديب ومستحقات المشرف (20%)', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (appState.couriers.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: Text('لا يوجد مناديب مسجلين حالياً', style: TextStyle(color: Colors.grey))))
          else
            ...appState.couriers.map((courier) {
              final courierName = courier['name'].toString();
              final courierId = courier['id']?.toString() ?? courier['delivery_man_id']?.toString() ?? '';
              double totalDeliveryFees = 0.0;
              int completedOrdersCount = 0;
              for (var order in appState.orders) {
                if (order['assigned_courier'] == courierName && order['status'] == 'delivered') {
                  completedOrdersCount++;
                  totalDeliveryFees += double.tryParse(order['delivery_fee']?.toString() ?? '0') ?? 0.0;
                }
              }
              double adminCommission = totalDeliveryFees * 0.20;
              return Card(
                color: const Color(0xFF1E1E1E),
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.amber.withOpacity(0.3))),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('🛵 المندوب: $courierName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                                child: Text('العمولة: ${adminCommission.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.notifications_active, color: Colors.amberAccent, size: 20),
                                tooltip: 'ربط وتحديث OneSignal Player ID للمندوب',
                                onPressed: () async {
                                  try {
                                    String? playerId = OneSignal.User.pushSubscription.id;
                                    if (playerId != null && playerId.isNotEmpty && courierId.isNotEmpty) {
                                      await Supabase.instance.client
                                          .from('couriers')
                                          .update({'onesignal_player_id': playerId})
                                          .eq('id', courierId);
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('تم تحديث OneSignal Player ID للمندوب بنجاح! 🔔')),
                                      );
                                    } else {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('لم يتم العثور على معرّف OneSignal للجهاز حالياً ❌')),
                                      );
                                    }
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('خطأ: $e')),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white12),
                      Text('📞 الهاتف: ${courier['phone'] ?? 'غير محدد'}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      Text('📦 الطلبات المكتملة: $completedOrdersCount', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      Text('💰 إجمالي دخل التوصيل: ${totalDeliveryFees.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 6),
                      Text('📌 المبلغ الواجب تسليمه للإدارة (20%): ${adminCommission.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                ),
              );
            }).toList(),
          const SizedBox(height: 25),
          const Divider(color: Colors.amber),
          const SizedBox(height: 10),
          const Text('إضافة مندوب توصيل جديد', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          TextField(controller: _courierNameController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'اسم المندوب الكامل', labelStyle: TextStyle(color: Colors.grey), filled: true, fillColor: Color(0xFF1E1E1E), border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _courierPhoneController, keyboardType: TextInputType.phone, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'رقم الهاتف', labelStyle: TextStyle(color: Colors.grey), filled: true, fillColor: Color(0xFF1E1E1E), border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _courierUsernameController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'اسم المستخدم للدخول', labelStyle: TextStyle(color: Colors.grey), filled: true, fillColor: Color(0xFF1E1E1E), border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _courierPasswordController, obscureText: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'كلمة المرور', labelStyle: TextStyle(color: Colors.grey), filled: true, fillColor: Color(0xFF1E1E1E), border: OutlineInputBorder())),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, minimumSize: const Size(double.infinity, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              final name = _courierNameController.text.trim();
              final phone = _courierPhoneController.text.trim();
              final username = _courierUsernameController.text.trim();
              final password = _courierPasswordController.text.trim();

              if (name.isEmpty || username.isEmpty || password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('الرجاء إدخال الاسم، اسم المستخدم، وكلمة المرور ⚠️')),
                );
                return;
              }

              if (password.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('كلمة مرور المندوب يجب ألا تقل عن 6 أحرف 🔒')),
                );
                return;
              }

              try {
                await appState.addCourier(name, phone, username, password);
                
                _courierNameController.clear();
                _courierPhoneController.clear();
                _courierUsernameController.clear();
                _courierPasswordController.clear();

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تمت إضافة المندوب بنجاح! 🛵🎉')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('فشل إضافة المندوب: $e ❌')),
                  );
                }
              }
            },
            child: const Text('حفظ المندوب', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab(AppState appState) {
    final startController = TextEditingController(text: appState.startHour.toString());
    final endController = TextEditingController(text: appState.endHour.toString());

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          const Text('إعدادات أوقات الدوام الرسمي للمتجر', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          TextField(controller: startController, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'ساعة الفتح', labelStyle: TextStyle(color: Colors.grey), filled: true, fillColor: Color(0xFF1E1E1E), border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: endController, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'ساعة الإغلاق', labelStyle: TextStyle(color: Colors.grey), filled: true, fillColor: Color(0xFF1E1E1E), border: OutlineInputBorder())),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, minimumSize: const Size(double.infinity, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              final start = int.tryParse(startController.text) ?? 8;
              final end = int.tryParse(endController.text) ?? 24;
              appState.updateStoreSettings(start, end);

              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث أوقات الدوام وحفظها سحابياً بنجاح! ✅')));
            },
            child: const Text('حفظ وتحديث أوقات الدوام', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 30),
          const Divider(color: Colors.white24),
          const SizedBox(height: 15),
          const Text('إدارة العروض والتقارير الشاملة', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          
          // 📢 زر إدارة البنرات والعروض الترويجية
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[800],
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _showBannersManagementDialog(context, appState),
            icon: const Icon(Icons.campaign, size: 22, color: Colors.white),
            label: const Text('إدارة البنرات والعروض الترويجية 📢', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(height: 12),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AdminReportsScreen()),
              );
            },
            icon: const Icon(Icons.analytics, size: 22),
            label: const Text('عرض تقارير الأرباح والمبيعات الشاملة 📈', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(height: 12),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey[800],
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AdminRestaurantsScreen()),
              );
            },
            icon: const Icon(Icons.storefront, size: 22, color: Colors.amber),
            label: const Text('إدارة المطاعم ومبيعاتها 🍽️', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(height: 12),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo[900],
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: BorderSide(color: Colors.amber.withOpacity(0.5)),
            ),
            onPressed: () => _showRestaurantRatingsDialog(context),
            icon: const Icon(Icons.star_rate, size: 22, color: Colors.amber),
            label: const Text('عرض تقييمات وملاحظات المطاعم ⭐', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
