import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/app_state.dart';
import 'chat_screen.dart';
import 'order_tracking_screen.dart';
import 'home_screen.dart';

class CourierScreen extends StatefulWidget {
  const CourierScreen({Key? key}) : super(key: key);

  @override
  State<CourierScreen> createState() => _CourierScreenState();
}

class _CourierScreenState extends State<CourierScreen> {
  StreamSubscription<Position>? _locationSubscription;
  bool _isLoadingSession = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verifyAndRestoreCourierSession();
    });
  }

  // 🛡️ دالة ذكية للتحقق واسترجاع جلسة المندوب المحفوظة محلياً لمنع فقدان تسجيل الدخول
  Future<void> _verifyAndRestoreCourierSession() async {
    try {
      final appState = Provider.of<AppState>(context, listen: false);

      // إذا كانت الجلسة موجودة في الذاكرة
      if (appState.currentCourier != null) {
        final String courierId = (appState.currentCourier!['id'] ??
                appState.currentCourier!['name'] ??
                '')
            .toString()
            .trim();
        if (courierId.isNotEmpty) {
          _startLiveLocationUpdates(courierId);
        }
        if (mounted) setState(() => _isLoadingSession = false);
        return;
      }

      // محاولة استرجاع الجلسة المحفوظة محلياً عبر SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final String? savedCourierJson = prefs.getString('saved_courier_session');

      if (savedCourierJson != null && savedCourierJson.isNotEmpty) {
        final Map<String, dynamic> courierData =
            Map<String, dynamic>.from(jsonDecode(savedCourierJson) as Map);
        appState.currentCourier = courierData;
        final String courierId =
            (courierData['id'] ?? courierData['name'] ?? '').toString().trim();
        if (courierId.isNotEmpty) {
          _startLiveLocationUpdates(courierId);
        }
        if (mounted) setState(() => _isLoadingSession = false);
        return;
      }

      // التحقق عبر رقم الهاتف المسجل في الملف الشخصي
      final currentPhone = appState.userProfile?['phone']?.toString() ?? '';
      if (currentPhone.isEmpty) {
        _kickOutUnauthorizedUser('جلسة غير صالحة، يرجى تسجيل الدخول مجدداً ⚠️');
        return;
      }

      String cleanPhone = currentPhone.replaceAll(' ', '');
      if (cleanPhone.startsWith('0')) cleanPhone = cleanPhone.substring(1);
      if (cleanPhone.startsWith('967')) cleanPhone = cleanPhone.substring(3);
      final formattedPhone = '+967$cleanPhone';

      final courierRes = await Supabase.instance.client
          .from('couriers')
          .select()
          .or('phone.eq.$cleanPhone,phone.eq.$formattedPhone')
          .maybeSingle();

      if (courierRes == null) {
        _kickOutUnauthorizedUser(
            'عذراً، لا تمتلك صلاحيات مندوب توصيل للوصول إلى هذه اللوحة 🚫');
      } else {
        appState.currentCourier = courierRes;
        await prefs.setString('saved_courier_session', jsonEncode(courierRes));

        final String courierId =
            (courierRes['id'] ?? courierRes['name'] ?? '').toString().trim();
        if (courierId.isNotEmpty) {
          _startLiveLocationUpdates(courierId);
        }
        if (mounted) setState(() => _isLoadingSession = false);
      }
    } catch (e) {
      debugPrint('❌ خطأ في التحقق الأمني للمندوب: $e');
      if (mounted) setState(() => _isLoadingSession = false);
    }
  }

  void _kickOutUnauthorizedUser(String message) {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => HomeScreen()),
      (route) => false,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  void _startLiveLocationUpdates(String courierId) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    await _locationSubscription?.cancel();

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );

    _locationSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((Position position) async {
      try {
        await Supabase.instance.client.from('courier_locations').upsert({
          'courier_id': courierId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'courier_id');
      } catch (e) {
        debugPrint('⚠️ خطأ في رفع الموقع اللحظي: $e');
      }
    });
  }

  Future<void> _openMap(String address) async {
    final query = Uri.encodeComponent(
        address.trim().isNotEmpty ? address.trim() : 'Taiz, Yemen');
    final googleMapsUrl =
        Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$query');

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

  void _handleCourierNotificationTap(
      BuildContext context, Map<String, dynamic> notification) {
    final String? orderId = notification['order_id']?.toString() ??
        notification['related_id']?.toString() ??
        notification['additionalData']?['order_id']?.toString() ??
        _extractOrderIdFromText(
            '${notification['title'] ?? ''} ${notification['body'] ?? notification['message'] ?? ''}');

    if (orderId != null && orderId.isNotEmpty) {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              OrderTrackingScreen(orderIdParam: orderId),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('هذا الإشعار غير مرتبط برقم طلب معين 📭')),
      );
    }
  }

  String? _extractOrderIdFromText(String text) {
    final RegExp regExp = RegExp(r'(?:طلب|#)\s*(\d+)');
    final match = regExp.firstMatch(text);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    return null;
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
            style: TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final courier = appState.currentCourier;

    final pendingOrdersCount = courier != null
        ? appState.orders.where((o) {
            final assigned = (o['assigned_courier'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final courierName =
                (courier['name'] ?? '').toString().trim().toLowerCase();
            final String orderStatus = o['status']?.toString() ?? '';
            return (assigned == courierName) &&
                (orderStatus == 'waitingCourierApproval' ||
                    orderStatus == 'approvedByCustomer');
          }).length
        : 0;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E1E1E),
            elevation: 2,
            title: Text(
              courier == null
                  ? 'لوحة المندوب'
                  : 'لوحة المندوب: ${courier['name']}',
              style: const TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
            actions: [
              if (courier != null) ...[
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_active,
                          color: Colors.amber, size: 24),
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
                                  Icon(Icons.notifications,
                                      color: Colors.amber),
                                  SizedBox(width: 8),
                                  Text('إشعارات المندوب 🛎️',
                                      style: TextStyle(
                                          color: Colors.amber, fontSize: 16)),
                                ],
                              ),
                              content: SizedBox(
                                width: double.maxFinite,
                                height: 350,
                                child: appState.notifications.isEmpty
                                    ? const Center(
                                        child: Text(
                                            'لا توجد إشعارات جديدة حالياً 📭',
                                            style:
                                                TextStyle(color: Colors.grey)))
                                    : ListView.builder(
                                        itemCount: appState.notifications.length,
                                        itemBuilder: (_, idx) {
                                          final notif =
                                              appState.notifications[idx];
                                          return Card(
                                            color: const Color(0xFF121212),
                                            margin: const EdgeInsets.symmetric(
                                                vertical: 4),
                                            child: ListTile(
                                              title: Text(
                                                  notif['title']?.toString() ??
                                                      '',
                                                  style: const TextStyle(
                                                      color: Colors.amber,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 13)),
                                              subtitle: Text(
                                                  notif['body']?.toString() ??
                                                      '',
                                                  style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 12)),
                                              trailing: const Icon(
                                                  Icons.arrow_forward_ios,
                                                  color: Colors.amber,
                                                  size: 14),
                                              onTap: () {
                                                Navigator.pop(ctx);
                                                _handleCourierNotificationTap(
                                                    context, notif);
                                              },
                                            ),
                                          );
                                        },
                                      ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('إغلاق',
                                      style: TextStyle(color: Colors.grey)),
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
                          constraints:
                              const BoxConstraints(minWidth: 18, minHeight: 18),
                          child: Text(
                            '$pendingOrdersCount',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                  tooltip: 'تسجيل الخروج',
                  onPressed: () async {
                    await _locationSubscription?.cancel();
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('saved_courier_session');
                    appState.logoutCourier();
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ],
            ],
          ),
          body: Column(
            children: [
              _buildNetworkStatusBar(appState),
              Expanded(
                child: _isLoadingSession
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.amber),
                      )
                    : (courier == null
                        ? const Center(
                            child: Text(
                                'عذراً، يرجى تسجيل الدخول مجدداً ⚠️',
                                style: TextStyle(color: Colors.grey)))
                        : _buildCourierOrdersListWithTabs(appState, courier)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCourierOrdersListWithTabs(
      AppState appState, Map<String, dynamic> courier) {
    final String courierName =
        (courier['name'] ?? '').toString().trim().toLowerCase();
    final String courierId = (courier['id'] ?? '').toString().trim();

    final myOrders = appState.orders.where((o) {
      final assigned =
          (o['assigned_courier'] ?? '').toString().trim().toLowerCase();
      return assigned == courierName ||
          assigned == courierId ||
          (courierName.isNotEmpty && assigned.contains(courierName));
    }).toList();

    final completedOrders = myOrders.where((o) {
      final bool isDelivered = o['status']?.toString().trim() == 'delivered';
      final bool isSettled = o['is_settled'] == true;
      return isDelivered && !isSettled;
    }).toList();

    final activeOrders = myOrders
        .where((o) =>
            o['status'] != 'delivered' &&
            o['status'] != 'cancelled' &&
            o['status'] != 'cancelledByCustomer')
        .toList();

    final cancelledOrders = myOrders
        .where((o) =>
            o['status'] == 'cancelled' || o['status'] == 'cancelledByCustomer')
        .toList();

    double totalEarnings = 0.0;
    int completedCount = 0;
    for (var order in completedOrders) {
      completedCount++;
      totalEarnings +=
          double.tryParse(order['delivery_fee']?.toString() ?? '0') ?? 0.0;
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
                        child: Icon(Icons.delivery_dining,
                            color: Colors.black, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Text('الكابتن: ${courier['name']}',
                          style: const TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text('إجمالي الطلبات: ${myOrders.length}',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
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
                border: Border.all(
                    color: Colors.green.withOpacity(0.4), width: 1.5),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text('الطلبات المكتملة ✅',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 11)),
                          const SizedBox(height: 4),
                          Text('$completedCount',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Container(width: 1, height: 30, color: Colors.white24),
                      Column(
                        children: [
                          const Text('إجمالي التوصيل 💰',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 11)),
                          const SizedBox(height: 4),
                          Text('${totalEarnings.toStringAsFixed(0)} ر.ي',
                              style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                          'عمولة الإدارة (20%): ${adminCommission.toStringAsFixed(0)} ر.ي',
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 12)),
                      Text(
                          'صافيك (80%): ${courierNetEarnings.toStringAsFixed(0)} ر.ي',
                          style: const TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
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
                  _buildOrdersListView(
                      appState, activeOrders, 'لا توجد طلبات نشطة حالياً 📦'),
                  _buildOrdersListView(
                      appState, completedOrders, 'لا توجد طلبات مكتملة 📭'),
                  _buildOrdersListView(
                      appState, cancelledOrders, 'لا توجد طلبات ملغية 🚫'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersListView(
      AppState appState, List ordersList, String emptyMessage) {
    if (ordersList.isEmpty) {
      return Center(
          child: Text(emptyMessage,
              style: const TextStyle(color: Colors.grey, fontSize: 14)));
    }

    return ListView.builder(
      itemCount: ordersList.length,
      itemBuilder: (context, index) {
        final order = ordersList[index];
        final orderId = order['id'].toString();
        final String customerAddress = order['address']?.toString() ?? '';
        final String orderStatus = order['status']?.toString() ?? '';

        final double productsPrice =
            double.tryParse(order['total_price']?.toString() ?? '0') ?? 0.0;
        final double deliveryFee =
            double.tryParse(order['delivery_fee']?.toString() ?? '0') ?? 0.0;
        final double grandTotal = productsPrice + deliveryFee;

        return Card(
          color: const Color(0xFF1E1E1E),
          margin: const EdgeInsets.symmetric(vertical: 8),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.amber.withOpacity(0.2)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      OrderTrackingScreen(orderIdParam: orderId),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('طلب #$orderId',
                          style: const TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      Row(
                        children: [
                          IconButton(
                            style: IconButton.styleFrom(
                                backgroundColor: Colors.amber.withOpacity(0.2)),
                            icon: const Icon(Icons.map,
                                color: Colors.amber, size: 20),
                            tooltip: 'تتبع الطلب',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      OrderTrackingScreen(orderIdParam: orderId),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            style: IconButton.styleFrom(
                                backgroundColor: Colors.blueGrey[800]),
                            icon: const Icon(Icons.chat,
                                color: Colors.amber, size: 20),
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
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 1,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              OrderTrackingScreen(orderIdParam: orderId),
                        ),
                      );
                    },
                    icon: const Icon(Icons.map_rounded,
                        color: Colors.black, size: 18),
                    label: const Text(
                      '🗺️ اضغط هنا لتتبع خط سير الطلب 🚀',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 16, color: Colors.redAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'العنوان: $customerAddress',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.amber),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.map, color: Colors.amber, size: 16),
                      label: const Text(
                        'فتح اتجاهات الملاحة في خرائط جوجل 🗺️',
                        style: TextStyle(
                            color: Colors.amber,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () => _openMap(customerAddress),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.shopping_bag,
                          size: 16, color: Colors.amberAccent),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(
                              'المنتجات: ${order['items_description'] ?? order['items_desc'] ?? ''}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '🛒 سعر المنتجات: ${productsPrice.toStringAsFixed(0)} ر.ي',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                            '🏍️ رسوم التوصيل: ${deliveryFee.toStringAsFixed(0)} ر.ي',
                            style: const TextStyle(
                                color: Colors.amber,
                                fontSize: 13,
                                fontWeight: FontWeight.bold)),
                        const Divider(color: Colors.white12, height: 8),
                        Text(
                            '💰 الإجمالي الكلي: ${grandTotal.toStringAsFixed(0)} ر.ي',
                            style: const TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('📌 الحالة: ${appState.getArabicStatus(orderStatus)}',
                      style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (orderStatus == 'pricingSentToCustomer') ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Center(
                        child: Text('⏳ بانتظار موافقة العميل على السعر...',
                            style: TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ] else if (orderStatus == 'waitingCourierApproval' ||
                      orderStatus == 'approvedByCustomer') ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          try {
                            await appState.updateOrderStatus(
                                orderId, 'onTheWay');
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString())),
                            );
                          }
                        },
                        icon: const Icon(Icons.check_circle),
                        label: const Text('قبول الطلب والبدء 🚀',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ] else if (orderStatus == 'onTheWay') ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          try {
                            await appState.updateOrderStatus(
                                orderId, 'arrived');
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString())),
                            );
                          }
                        },
                        icon: const Icon(Icons.location_pin),
                        label: const Text('وصلت إلى الموقع 📍',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ] else if (orderStatus == 'arrived') ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          try {
                            await appState.updateOrderStatus(
                                orderId, 'delivered');
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString())),
                            );
                          }
                        },
                        icon: const Icon(Icons.done_all),
                        label: const Text('تم التسليم بنجاح ✅',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
