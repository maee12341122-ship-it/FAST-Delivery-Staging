import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  bool _isUpdatingStatus = false;

  @override
  void initState() {
    super.initState();
    final currentCourier = context.read<AppState>().currentCourier;
    final initialStatus = currentCourier?['status']?.toString().trim();
    if (initialStatus == 'available' ||
        initialStatus == 'busy' ||
        initialStatus == 'offline') {
      _status = initialStatus!;
    }
    _syncCourierLocationToSupabase(const LatLng(13.5779, 44.0219));
  }

  Future<void> _syncCourierLocationToSupabase(LatLng position) async {
    try {
      final identifier = widget.courierName.trim().isNotEmpty
          ? widget.courierName.trim()
          : widget.courierId.trim();
      if (identifier.isEmpty) return;

      await Supabase.instance.client.from('courier_locations').upsert({
        'courier_id': identifier,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'courier_id');
    } catch (e) {
      debugPrint('⚠️ تعذر مزامنة موقع المندوب: $e');
    }
  }

  Future<void> _updateCourierStatus(
      BuildContext context, AppState appState, String newStatus) async {
    if (_isUpdatingStatus || newStatus == _status) return;
    final previousStatus = _status;

    setState(() {
      _status = newStatus;
      _isUpdatingStatus = true;
    });

    try {
      final intId = int.tryParse(widget.courierId.trim());
      if (intId != null) {
        await Supabase.instance.client
            .from('couriers')
            .update({'status': newStatus})
            .eq('id', intId);
      } else if (widget.courierName.trim().isNotEmpty) {
        await Supabase.instance.client
            .from('couriers')
            .update({'status': newStatus})
            .eq('name', widget.courierName.trim());
      }

      if (appState.currentCourier != null) {
        appState.currentCourier = {
          ...appState.currentCourier!,
          'status': newStatus,
        };
      }

      if (!mounted) return;
      final label = newStatus == 'available'
          ? 'متاح 🟢'
          : newStatus == 'busy'
              ? 'مشغول 🟡'
              : 'خارج الخدمة 🔴';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تحديث حالتك إلى: $label')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = previousStatus);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديث الحالة: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
      }
    }
  }

  // 🗺️ دالة محسنة لاستخراج الإحداثيات بدقة عالية وتجاوز الأقواس والأسطر
  LatLng? _extractLatLng(String addressText) {
    final regExp = RegExp(r'([0-9]+\.[0-9]+)');
    final matches = regExp.allMatches(addressText).toList();

    if (matches.length >= 2) {
      double? num1 = double.tryParse(matches[0].group(0) ?? '');
      double? num2 = double.tryParse(matches[1].group(0) ?? '');

      if (num1 != null && num2 != null) {
        double lat, lng;
        if (num1 >= 13.0 && num1 < 15.0 && num2 >= 43.0 && num2 < 46.0) {
          lat = num1;
          lng = num2;
        } else if (num2 >= 13.0 &&
            num2 < 15.0 &&
            num1 >= 43.0 &&
            num1 < 46.0) {
          lat = num2;
          lng = num1;
        } else {
          lat = num1;
          lng = num2;
        }
        return LatLng(lat, lng);
      }
    }
    return const LatLng(13.5779, 44.0219); // افتراضي لتعز
  }

  // 🧭 دالة فتح خرائط جوجل بالإحداثيات الدقيقة المباشرة
  Future<void> _openNavigation(String addressText) async {
    final latLng = _extractLatLng(addressText);
    Uri url;
    if (latLng != null) {
      url = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${latLng.latitude},${latLng.longitude}');
    } else {
      url = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(addressText)}');
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

  bool _isOrderAssignedToCourier(Map<String, dynamic> order) {
    final assigned =
        order['assigned_courier']?.toString().trim().toLowerCase() ?? '';
    final driver = order['driver_name']?.toString().trim().toLowerCase() ?? '';
    final courierIdField =
        order['courier_id']?.toString().trim().toLowerCase() ?? '';
    final targetName = widget.courierName.trim().toLowerCase();
    final targetId = widget.courierId.trim().toLowerCase();

    return (targetName.isNotEmpty &&
            (assigned == targetName || driver == targetName)) ||
        (targetId.isNotEmpty &&
            (assigned == targetId || courierIdField == targetId));
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final allOrders = appState.orders;

    final courierOrders = allOrders.where(_isOrderAssignedToCourier).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          elevation: 2,
          title: Text(
            'لوحة المندوب: ${widget.courierName}',
            style: const TextStyle(
                color: AppConstants.gold,
                fontWeight: FontWeight.bold,
                fontSize: 16),
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
                          Icon(Icons.toggle_on,
                              color: AppConstants.gold, size: 22),
                          SizedBox(width: 8),
                          Text(
                            'تحديث حالة التوفر:',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
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
                          ButtonSegment(
                            value: 'available',
                            label: Text('متاح',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            icon: Icon(Icons.check_circle_outline, size: 16),
                          ),
                          ButtonSegment(
                            value: 'busy',
                            label: Text('مشغول',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            icon: Icon(Icons.hourglass_empty, size: 16),
                          ),
                          ButtonSegment(
                            value: 'offline',
                            label: Text('خارج الخدمة',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            icon: Icon(Icons.offline_bolt_outlined, size: 16),
                          ),
                        ],
                        selected: {_status},
                        onSelectionChanged: _isUpdatingStatus
                            ? null
                            : (Set<String> newSelection) {
                                _updateCourierStatus(
                                    context, appState, newSelection.first);
                              },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('الطلبات المسندة إليك 📦',
                    style: TextStyle(
                        color: AppConstants.gold,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
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
                              decoration: BoxDecoration(
                                  color: AppConstants.gold.withOpacity(0.1),
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.local_shipping_outlined,
                                  size: 50, color: AppConstants.gold),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'لا توجد طلبات مسندة لك حالياً\nستظهر الطلبات هنا فور إرسالها من المشرف 🚀',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: courierOrders.length,
                        itemBuilder: (context, index) {
                          final order = courierOrders[index];
                          final orderId = order['id']?.toString() ?? '';
                          final customerName =
                              order['customer_name']?.toString() ?? 'عميل';
                          final phone = order['phone']?.toString() ?? '';
                          final address = order['address']?.toString() ?? '';
                          final itemsDesc =
                              order['items_description']?.toString() ?? '';

                          final totalPrice =
                              order['total_price']?.toString() ?? '0';
                          final itemsPrice =
                              order['items_price']?.toString() ??
                                  order['subtotal']?.toString() ??
                                  'غير متوفر';
                          final deliveryFee =
                              order['delivery_fee']?.toString() ??
                                  order['delivery_cost']?.toString() ??
                                  '0';

                          final status = order['status']?.toString() ?? '';

                          final paymentMethod =
                              order['payment_method']?.toString() ?? 'cash';
                          final paymentAccount =
                              order['payment_account']?.toString() ?? '';
                          final isCash = paymentMethod == 'cash' ||
                              paymentMethod == 'cash_on_delivery';
                          final paymentDisplay = isCash
                              ? '💵 تحصيل نقدي عند الاستلام (الإجمالي: $totalPrice ر.ي)'
                              : '💳 مدفوع مسبقاً عبر ($paymentMethod) - حساب: $paymentAccount (لا تحصل نقداً)';

                          final orderLatLng = _extractLatLng(address);

                          return Card(
                            color: const Color(0xFF1E1E1E),
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                  color: AppConstants.gold.withOpacity(0.3)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('طلب #$orderId',
                                          style: const TextStyle(
                                              color: AppConstants.gold,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15)),
                                      Text('الإجمالي: $totalPrice ر.ي',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15)),
                                    ],
                                  ),
                                  const Divider(color: Colors.white12),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('🛍️ سعر المنتجات: $itemsPrice ر.ي',
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13)),
                                      Text('🏍️ رسوم التوصيل: $deliveryFee ر.ي',
                                          style: const TextStyle(
                                              color: AppConstants.gold,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text('العميل: $customerName',
                                      style: const TextStyle(
                                          color: Colors.white70)),
                                  Text('الهاتف: $phone',
                                      style: const TextStyle(
                                          color: Colors.white70)),
                                  Text('العنوان: $address',
                                      style: const TextStyle(
                                          color: Colors.white70)),
                                  const SizedBox(height: 6),
                                  Text('المنتجات: $itemsDesc',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 13)),
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(
                                      height: 130,
                                      width: double.infinity,
                                      child: GoogleMap(
                                        initialCameraPosition: CameraPosition(
                                          target: orderLatLng ??
                                              const LatLng(13.5779, 44.0219),
                                          zoom: 15,
                                        ),
                                        markers: {
                                          Marker(
                                            markerId: MarkerId(orderId),
                                            position: orderLatLng ??
                                                const LatLng(13.5779, 44.0219),
                                            infoWindow: InfoWindow(
                                                title:
                                                    'موقع العميل: $customerName'),
                                          ),
                                        },
                                        liteModeEnabled: true,
                                        zoomControlsEnabled: false,
                                        myLocationButtonEnabled: false,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.lightBlueAccent,
                                        side: const BorderSide(
                                            color: Colors.lightBlueAccent),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                      ),
                                      onPressed: () => _openNavigation(address),
                                      icon: const Icon(Icons.navigation,
                                          size: 16),
                                      label: const Text(
                                          'التوجيه الدقيق إلى موقع العميل عبر الخريطة 🧭',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isCash
                                          ? Colors.green.withOpacity(0.15)
                                          : Colors.blue.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: isCash
                                              ? Colors.green
                                              : Colors.blueAccent),
                                    ),
                                    child: Text(
                                      paymentDisplay,
                                      style: TextStyle(
                                        color: isCash
                                            ? Colors.greenAccent
                                            : Colors.lightBlueAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppConstants.gold,
                                        side: const BorderSide(
                                            color: AppConstants.gold),
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
                                      if (status == 'waitingCourierApproval') ...[
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red,
                                              foregroundColor: Colors.white),
                                          onPressed: () async {
                                            try {
                                              await appState
                                                  .courierRespondToOrder(
                                                      orderId, false);
                                            } catch (e) {
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(e.toString())),
                                              );
                                            }
                                          },
                                          icon: const Icon(Icons.close,
                                              size: 16),
                                          label: const Text('رفض الطلب'),
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white),
                                          onPressed: () async {
                                            try {
                                              await appState
                                                  .courierRespondToOrder(
                                                      orderId, true);
                                              if (orderLatLng != null) {
                                                await _syncCourierLocationToSupabase(
                                                    orderLatLng);
                                              }
                                            } catch (e) {
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(e.toString())),
                                              );
                                            }
                                          },
                                          icon:
                                              const Icon(Icons.check, size: 16),
                                          label: const Text('قبول الطلب'),
                                        ),
                                      ],
                                      if (status == 'onTheWay' ||
                                          status == 'acceptedByCourier')
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.amber,
                                              foregroundColor: Colors.black),
                                          onPressed: () async {
                                            try {
                                              await appState
                                                  .courierUpdateArrival(
                                                      orderId);
                                            } catch (e) {
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(e.toString())),
                                              );
                                            }
                                          },
                                          icon: const Icon(Icons.location_pin,
                                              size: 16),
                                          label: const Text('وصلت لموقع العميل'),
                                        ),
                                      if (status == 'arrived' ||
                                          status == 'arrivedToCustomer')
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.blueAccent,
                                              foregroundColor: Colors.white),
                                          onPressed: () async {
                                            try {
                                              await appState
                                                  .markOrderDelivered(orderId);
                                            } catch (e) {
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(e.toString())),
                                              );
                                            }
                                          },
                                          icon: const Icon(Icons.done_all,
                                              size: 16),
                                          label:
                                              const Text('تم التسليم بنجاح ✅'),
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
