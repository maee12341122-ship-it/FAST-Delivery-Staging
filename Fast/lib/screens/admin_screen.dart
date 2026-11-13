import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state.dart';
import 'chat_screen.dart';
import 'order_tracking_screen.dart';
import 'admin/admin_products_screen.dart';
import 'admin/admin_reports_screen.dart';
import 'admin_restaurants_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({Key? key}) : super(key: key);

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  int _selectedNavIndex = 0;
  late TabController _ordersTabController;

  final Map<String, TextEditingController> _feeControllers = {};
  final Map<String, String> _selectedCouriersForOrder = {};

  @override
  void initState() {
    super.initState();
    _ordersTabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _ordersTabController.dispose();
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

  void _handleAdminNotificationTap(BuildContext context, Map<String, dynamic> notification) {
    final String? orderId = notification['order_id']?.toString() ??
        notification['related_id']?.toString() ??
        notification['additionalData']?['order_id']?.toString();

    if (orderId != null && orderId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => OrderTrackingScreen(orderIdParam: orderId)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذا الإشعار غير مرتبط برقم طلب معين 📭')),
      );
    }
  }

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
                Text('تقييمات وملاحظات المطاعم الشهرية ⭐', style: TextStyle(color: Colors.amber, fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: FutureBuilder(
                future: Supabase.instance.client
                    .from('restaurant_ratings')
                    .select()
                    .order('rating', ascending: false), // تم التصحيح ليتوافق مع العمود الموجود في الجدول
                builder: (BuildContext context, AsyncSnapshot snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.amber));
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('لا توجد تقييمات مسجلة أو خطأ في الجدول', style: const TextStyle(color: Colors.grey)));
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
                                  Text('🍽️ ${r['restaurant_name'] ?? 'مطعم'}', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
                                  Row(
                                    children: [
                                      const Icon(Icons.star, color: Colors.amber, size: 18),
                                      const SizedBox(width: 4),
                                      Text('${r['rating'] ?? r['average_rating'] ?? 5.0}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text('💬 الملاحظة: ${r['review_text'] ?? 'بدون تعليق'}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
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

  Widget _buildCouriersManagement(AppState appState) {
    return FutureBuilder<List<dynamic>>(
      future: Supabase.instance.client.from('couriers').select(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.amber));
        }
        final couriers = snapshot.data ?? [];
        if (couriers.isEmpty) {
          return const Center(child: Text('لا يوجد مناديب مسجلين حالياً 🛵', style: TextStyle(color: Colors.grey)));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: couriers.length,
          itemBuilder: (context, index) {
            final courier = couriers[index];
            final courierName = courier['name']?.toString() ?? courier['full_name']?.toString() ?? 'مندوب';

            // حساب عدد الطلبات الكل والمكتملة وعمولات التوصيل لهذا المندوب بدقة من قائمة الطلبات العامة
            final courierAllOrders = appState.orders.where((o) =>
            (o['assigned_courier']?.toString() ?? '') == courierName ||
                (o['courier_name']?.toString() ?? '') == courierName
            ).toList();

            final courierCompletedOrders = courierAllOrders.where((o) => o['status'] == 'delivered').toList();

            double totalCourierEarnings = 0.0;
            for (var order in courierCompletedOrders) {
              totalCourierEarnings += double.tryParse(order['delivery_fee']?.toString() ?? '0') ?? 0.0;
            }

            return Card(
              color: const Color(0xFF1E1E1E),
              margin: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.amber.withOpacity(0.4)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.two_wheeler, color: Colors.amber, size: 24),
                            const SizedBox(width: 10),
                            Text(courierName, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.green),
                          ),
                          child: Text('📞 ${courier['phone'] ?? 'غير متوفر'}', style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatColumn('إجمالي الطلبات', '${courierAllOrders.length} طلب', Colors.white70),
                        _buildStatColumn('الطلبات المكتملة', '${courierCompletedOrders.length} طلب', Colors.greenAccent),
                        _buildStatColumn('إجمالي عمولة التوصيل', '${totalCourierEarnings.toStringAsFixed(0)} ر.ي', Colors.amber),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatColumn(String title, String value, Color valueColor) {
    return Column(
      children: [
        Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildSettingsTab(AppState appState) {
    final startHourController = TextEditingController(text: appState.startHour.toString());
    final endHourController = TextEditingController(text: appState.endHour.toString());

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          const Text('إعدادات وقته ومواعيد عمل التطبيق ⏰', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('تحديد ساعات فتح وإغلاق التطبيق يومياً:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: startHourController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'ساعة الفتح (مثال: 8)', labelStyle: TextStyle(color: Colors.grey), border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: endHourController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'ساعة الإغلاق (مثال: 23)', labelStyle: TextStyle(color: Colors.grey), border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, minimumSize: const Size(double.infinity, 44)),
                  onPressed: () async {
                    int? newStart = int.tryParse(startHourController.text);
                    int? newEnd = int.tryParse(endHourController.text);
                    if (newStart != null && newEnd != null) {
                      await appState.updateStoreHours(newStart, newEnd);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث أوقات العمل بنجاح ✅')));
                      }
                    }
                  },
                  child: const Text('حفظ وتحديث أوقات العمل 💾', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            tileColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.star, color: Colors.amber),
            title: const Text('عرض تقييمات المطاعم الشهرية ⭐', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: () => _showRestaurantRatingsDialog(context),
          ),
          const SizedBox(height: 10),
          ListTile(
            tileColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.campaign, color: Colors.amber),
            title: const Text('إدارة البنرات الترويجية 📢', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: () => _showBannersManagementDialog(context, appState),
          ),
        ],
      ),
    );
  }

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

    final int totalCompletedOrdersCount = appState.orders.where((o) => o['status'] == 'delivered').length;

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
          title: const Text('لوحة تحكم المشرف FAST', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
          actions: [
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
                                      Navigator.pop(ctx);
                                      _handleAdminNotificationTap(context, notif);
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
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(
                        '${appState.orders.where((o) => o['status'] == 'waitingForPricing').length}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
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
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.amber.withOpacity(0.4), width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), shape: BoxShape.circle),
                            child: const Icon(Icons.remove_red_eye, color: Colors.amber, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('إجمالي الزوار', style: TextStyle(color: Colors.grey, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text('${appState.totalVisitorsCount} زائر', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.green.withOpacity(0.4), width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), shape: BoxShape.circle),
                            child: const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('الطلبات المكتملة', style: TextStyle(color: Colors.grey, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text('$totalCompletedOrdersCount طلب', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                        ],
                      ),
                    ),
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

        final bool isLocked = rawStatus != 'waitingForPricing' && rawStatus != 'pricingSentToCustomer';

        final double productsPrice = double.tryParse(
            order['products_total']?.toString() ??
                order['products_price']?.toString() ??
                order['total_price']?.toString() ?? '0'
        ) ?? 0.0;

        final double deliveryFeeAmount = double.tryParse(order['delivery_fee']?.toString() ?? '0') ?? 0.0;
        final double grandTotal = productsPrice + deliveryFeeAmount;

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
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => OrderTrackingScreen(orderIdParam: orderId),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('طلب #$orderId', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                      Row(
                        children: [
                          IconButton(
                            style: IconButton.styleFrom(backgroundColor: Colors.amber.withOpacity(0.2)),
                            icon: const Icon(Icons.map, color: Colors.amber, size: 20),
                            tooltip: 'تتبع الطلب',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => OrderTrackingScreen(orderIdParam: orderId),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 4),
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
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 16),
                  Text('👤 العميل: ${order['customer_name'] ?? 'غير معروف'} \n📞 ${order['phone'] ?? ''}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  Text('📍 العنوان: ${order['address'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 6),
                  Text('🛒 تفاصيل الطلب: ${order['items_description'] ?? 'بدون وصف'}', style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
                  const Divider(color: Colors.white12, height: 16),

                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🛒 سعر المنتجات: ${productsPrice.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('🏍️ رسوم التوصيل: ${deliveryFeeAmount.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold)),
                        const Divider(color: Colors.white12, height: 8),
                        Text('💰 الإجمالي الكلي: ${grandTotal.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductsManagement(AppState appState) {
    return const AdminProductsScreen();
  }
}
