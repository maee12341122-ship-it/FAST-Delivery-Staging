import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // 👈 استدعاء حزمة خرائط جوجل للعرض المصغر
import '../providers/app_state.dart';
import '../utils/constants.dart';
import 'package:fast/screens/chat_screen.dart';

class DeliveryDashboard extends StatefulWidget {
  final String courierId;
  final String courierName;

  const DeliveryDashboard({
    Key? key,
    required this.courierId,
    required this.courierName,
  }) : super(key: key);

  @override
  State<DeliveryDashboard> createState() => _DeliveryDashboardState();
}

class _DeliveryDashboardState extends State<DeliveryDashboard> {
  String _status = 'available';

  // 🗺️ دالة لفتح خرائط جوجل الخارجية وإرشاد المندوب للإحداثيات المستهدفة
  Future<void> _openNavigation(String addressText) async {
    final regExp = RegExp(r'الإحداثيات:\s*([0-9\.]+),\s*([0-9\.]+)');
    final match = regExp.firstMatch(addressText);

    Uri url;
    if (match != null) {
      final lat = match.group(1);
      final lng = match.group(2);
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    } else {
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(addressText)}');
    }

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح تطبيق خرائط جوجل')),
        );
      }
    }
  }

  // 📍 دالة مساعدة لاستخراج خطوط الطول والعرض من نص العنوان لعرضها في الخريطة المصغرة
  LatLng? _extractLatLng(String addressText) {
    final regExp = RegExp(r'الإحداثيات:\s*([0-9\.]+),\s*([0-9\.]+)');
    final match = regExp.firstMatch(addressText);
    if (match != null) {
      final lat = double.tryParse(match.group(1) ?? '');
      final lng = double.tryParse(match.group(2) ?? '');
      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }
    // الإحداثيات الافتراضية لمدينة تعز إن لم توجد إحداثيات مخزنة بالطلب
    return const LatLng(13.5779, 44.0219);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final allOrders = appState.orders;

    final courierOrders = allOrders.where((order) {
      String assigned = order['assigned_courier']?.toString().trim() ?? '';
      return assigned == widget.courierName.trim() || assigned == widget.courierId;
    }).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          elevation: 2,
          title: Text(
            'لوحة المندوب: ${widget.courierName}',
            style: const TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Card(
                color: const Color(0xFF1E1E1E),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: AppConstants.gold.withOpacity(0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.toggle_on, color: AppConstants.gold, size: 22),
                          SizedBox(width: 8),
                          Text(
                            'تحديث حالة التوفر:',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SegmentedButton<String>(
                        style: SegmentedButton.styleFrom(
                          backgroundColor: const Color(0xFF121212),
                          foregroundColor: Colors.white70,
                          selectedBackgroundColor: AppConstants.gold,
                          selectedForegroundColor: Colors.black,
                        ),
                        segments: const [
                          ButtonSegment(value: 'available', label: Text('متاح', style: TextStyle(fontWeight: FontWeight.bold)), icon: Icon(Icons.check_circle_outline, size: 16)),
                          ButtonSegment(value: 'busy', label: Text('مشغول', style: TextStyle(fontWeight: FontWeight.bold)), icon: Icon(Icons.hourglass_empty, size: 16)),
                          ButtonSegment(value: 'offline', label: Text('خارج الخدمة', style: TextStyle(fontWeight: FontWeight.bold)), icon: Icon(Icons.offline_bolt_outlined, size: 16)),
                        ],
                        selected: {_status},
                        onSelectionChanged: (Set<String> newSelection) {
                          setState(() {
                            _status = newSelection.first;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تم تحديث حالتك إلى: ${_status == 'available' ? 'متاح 🟢' : _status == 'busy' ? 'مشغول 🟡' : 'خارج الخدمة 🔴'}')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('الطلبات المسندة إليك 📦', style: TextStyle(color: AppConstants.gold, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: courierOrders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(color: AppConstants.gold.withOpacity(0.1), shape: BoxShape.circle),
                              child: const Icon(Icons.local_shipping_outlined, size: 50, color: AppConstants.gold),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'لا توجد طلبات مسندة لك حالياً\nستظهر الطلبات هنا فور إرسالها من المشرف 🚀',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: courierOrders.length,
                        itemBuilder: (context, index) {
                          final order = courierOrders[index];
                          final orderId = order['id']?.toString() ?? '';
                          final customerName = order['customer_name']?.toString() ?? 'عميل';
                          final phone = order['phone']?.toString() ?? '';
                          final address = order['address']?.toString() ?? '';
                          final itemsDesc = order['items_description']?.toString() ?? '';
                          final totalPrice = order['total_price']?.toString() ?? '0';
                          final status = order['status']?.toString() ?? '';

                          final paymentMethod = order['payment_method']?.toString() ?? 'cash';
                          final paymentAccount = order['payment_account']?.toString() ?? '';
                          final paymentDisplay = (paymentMethod == 'cash' || paymentMethod == 'cash_on_delivery')
                              ? '💵 تحصيل نقدي عند الاستلام ($totalPrice ر.ي)'
                              : '💳 مدفوع مسبقاً عبر ($paymentMethod) - حساب: $paymentAccount (لا تحصل نقداً)';

                          final orderLatLng = _extractLatLng(address);

                          return Card(
                            color: const Color(0xFF1E1E1E),
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: AppConstants.gold.withOpacity(0.3)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('طلب #$orderId', style: const TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold, fontSize: 15)),
                                      Text('$totalPrice ر.ي', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  const Divider(color: Colors.white12),
                                  Text('العميل: $customerName', style: const TextStyle(color: Colors.white70)),
                                  Text('الهاتف: $phone', style: const TextStyle(color: Colors.white70)),
                                  Text('العنوان: $address', style: const TextStyle(color: Colors.white70)),
                                  const SizedBox(height: 6),
                                  Text('المنتجات: $itemsDesc', style: const TextStyle(color: Colors.white, fontSize: 13)),
                                  const SizedBox(height: 10),

                                  // 🗺️ عنصر خريطة مصغرة تفاعلية (Lite Mode) داخل بطاقة الطلب للمندوب
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(
                                      height: 130,
                                      width: double.infinity,
                                      child: GoogleMap(
                                        initialCameraPosition: CameraPosition(
                                          target: orderLatLng ?? const LatLng(13.5779, 44.0219),
                                          zoom: 15,
                                        ),
                                        markers: {
                                          Marker(
                                            markerId: MarkerId(orderId),
                                            position: orderLatLng ?? const LatLng(13.5779, 44.0219),
                                            infoWindow: InfoWindow(title: 'موقع العميل: $customerName'),
                                          ),
                                        },
                                        liteModeEnabled: true, // خريطة خفيفة ومناسبة داخل القوائم الطويلة
                                        zoomControlsEnabled: false,
                                        myLocationButtonEnabled: false,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  // 🧭 زر التوجيه عبر خرائط جوجل للمندوب
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.lightBlueAccent,
                                        side: const BorderSide(color: Colors.lightBlueAccent),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: () => _openNavigation(address),
                                      icon: const Icon(Icons.navigation, size: 16),
                                      label: const Text('التوجيه إلى موقع العميل عبر الخريطة 🧭', style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // حاوية توضيح طريقة الدفع للمندوب
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: (paymentMethod == 'cash' || paymentMethod == 'cash_on_delivery') ? Colors.green.withOpacity(0.15) : Colors.blue.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: (paymentMethod == 'cash' || paymentMethod == 'cash_on_delivery') ? Colors.green : Colors.blueAccent),
                                    ),
                                    child: Text(
                                      paymentDisplay,
                                      style: TextStyle(
                                        color: (paymentMethod == 'cash' || paymentMethod == 'cash_on_delivery') ? Colors.greenAccent : Colors.lightBlueAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  // زر شات المندوب مع الإدارة
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppConstants.gold,
                                        side: const BorderSide(color: AppConstants.gold),
                                      ),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ChatScreen(
                                              orderId: orderId,
                                              userRole: 'courier',
                                              targetChat: 'admin_courier',
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.chat, size: 16),
                                      label: const Text('محادثة المشرف 💬'),
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (status == 'waitingCourierApproval')
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                          onPressed: () => appState.courierRespondToOrder(orderId, true),
                                          icon: const Icon(Icons.check, size: 16),
                                          label: const Text('قبول الطلب'),
                                        ),
                                      if (status == 'onTheWay')
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                                          onPressed: () => appState.courierUpdateArrival(orderId),
                                          icon: const Icon(Icons.location_pin, size: 16),
                                          label: const Text('وصلت لموقع العميل'),
                                        ),
                                      if (status == 'arrived')
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                                          onPressed: () => appState.markOrderDelivered(orderId),
                                          icon: const Icon(Icons.done_all, size: 16),
                                          label: const Text('تم التسليم بنجاح ✅'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
