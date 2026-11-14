import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state.dart';
import '../widgets/RatingWidget.dart';

class OrderTrackingScreen extends StatefulWidget {
  final Map<String, dynamic>? orderMap;
  final String? orderIdParam;

  const OrderTrackingScreen({Key? key, this.orderMap, this.orderIdParam}) : super(key: key);

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final MapController _mapController = MapController();
  LatLng? _courierPosition;
  LatLng _customerPosition = const LatLng(13.5795, 44.0209); // مركز تعز الافتراضي
  RealtimeChannel? _orderChannel;
  RealtimeChannel? _locationChannel;

  @override
  void initState() {
    super.initState();
    final String targetId = widget.orderIdParam ?? widget.orderMap?['id']?.toString() ?? '';
    if (targetId.isNotEmpty) {
      _extractCustomerCoordinates(widget.orderMap);
      _subscribeToOrderUpdates(targetId);
    }
  }

  void _extractCustomerCoordinates(Map<String, dynamic>? order) {
    if (order == null) return;
    final String address = order['address']?.toString() ?? '';
    try {
      if (address.contains('(') && address.contains(')')) {
        final coordsPart = address.substring(address.indexOf('(') + 1, address.indexOf(')'));
        final parts = coordsPart.split(',');
        if (parts.length >= 2) {
          final lat = double.tryParse(parts[1].trim());
          final lng = double.tryParse(parts[0].trim());
          if (lat != null && lng != null) {
            setState(() {
              _customerPosition = LatLng(lat, lng);
            });
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ استخدام موقع تعز الافتراضي: $e');
    }
  }

  void _subscribeToOrderUpdates(String orderId) {
    _orderChannel = Supabase.instance.client
        .channel('public:orders:id=eq.$orderId')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'orders',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: orderId,
      ),
      callback: (payload) {
        if (payload.newRecord.isNotEmpty && mounted) {
          setState(() {});
          _extractCustomerCoordinates(payload.newRecord);
          final courierName = payload.newRecord['assigned_courier']?.toString();
          if (courierName != null && courierName.isNotEmpty && _locationChannel == null) {
            _fetchAndListenCourierLocation(courierName);
          }
        }
      },
    )
        .subscribe();
  }

  Future<void> _fetchAndListenCourierLocation(String courierId) async {
    try {
      final res = await Supabase.instance.client
          .from('courier_locations')
          .select()
          .eq('courier_id', courierId)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          _courierPosition = LatLng(res['latitude'], res['longitude']);
        });
      }

      _locationChannel = Supabase.instance.client
          .channel('public:courier_locations:courier_id=eq.$courierId')
          .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'courier_locations',
        callback: (payload) {
          final newData = payload.newRecord;
          if (newData.isNotEmpty && mounted) {
            final lat = newData['latitude'] as double;
            final lng = newData['longitude'] as double;
            setState(() {
              _courierPosition = LatLng(lat, lng);
            });
            _mapController.move(_courierPosition!, 17.0);
          }
        },
      )
          .subscribe();
    } catch (e) {
      debugPrint('⚠️ خطأ في متابعة موقع المندوب: $e');
    }
  }

  @override
  void dispose() {
    if (_orderChannel != null) Supabase.instance.client.removeChannel(_orderChannel!);
    if (_locationChannel != null) Supabase.instance.client.removeChannel(_locationChannel!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final String targetId = widget.orderIdParam ?? widget.orderMap?['id']?.toString() ?? '';

    // جلب الطلب المحدث لحظياً من الـ AppState أو الـ widgetMap
    final order = appState.orders.firstWhere(
          (o) => o['id'].toString() == targetId,
      orElse: () => widget.orderMap ?? {},
    );

    if (order.isEmpty) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text('تتبع الطلب', style: TextStyle(color: Colors.amber)),
            iconTheme: const IconThemeData(color: Colors.amber),
          ),
          body: const Center(
            child: Text('عذراً، لم يتم العثور على تفاصيل هذا الطلب ❌', style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
    }

    final String rawStatus = order['status'] ?? 'waitingForPricing';

    int currentStep = 0;
    if (rawStatus == 'waitingForPricing') {
      currentStep = 0;
    } else if (rawStatus == 'pricingSentToCustomer' || rawStatus == 'waitingCourierApproval') {
      currentStep = 1;
    } else if (rawStatus == 'acceptedByCourier' || rawStatus == 'onTheWay') {
      currentStep = 2;
    } else if (rawStatus == 'arrivedToCustomer' || rawStatus == 'arrived') {
      currentStep = 3;
    } else if (rawStatus == 'delivered') {
      currentStep = 4;
    }

    final steps = [
      {'title': 'التأسيس', 'icon': Icons.receipt_long},
      {'title': 'التسعير', 'icon': Icons.local_offer},
      {'title': 'في الطريق', 'icon': Icons.two_wheeler},
      {'title': 'الوصول', 'icon': Icons.location_on},
      {'title': 'التسليم', 'icon': Icons.check_circle},
    ];

    // 🛒 منطق الأسعار الموحد
    final double productsPrice = double.tryParse(
        order['total_price']?.toString() ??
            order['items_price']?.toString() ??
            order['products_total']?.toString() ??
            order['products_price']?.toString() ?? '0'
    ) ?? 0.0;

    final double deliveryFee = double.tryParse(
        order['delivery_fee']?.toString() ?? '0'
    ) ?? 0.0;

    final double dbTotalAmount = double.tryParse(
        order['total_amount']?.toString() ??
            order['total']?.toString() ?? '0'
    ) ?? 0.0;

    final double finalProductsPrice = (productsPrice <= 0 && dbTotalAmount > deliveryFee)
        ? (dbTotalAmount - deliveryFee)
        : productsPrice;

    final double grandTotal = dbTotalAmount > 0
        ? dbTotalAmount
        : (finalProductsPrice + deliveryFee);

    final int numericOrderId = int.tryParse(targetId) ?? 0;
    final String customerPhone = order['phone'] ?? appState.userProfile?['phone'] ?? '';
    final String courierId = order['assigned_courier']?.toString() ?? 'general_courier';
    
    // 🛑 التحقق مما إذا كان المستخدم الحالي مشرفاً أو مندوباً (هم فقط من يرون التتبع الحي)
    final bool isManagerOrCourier = appState.isAdminLoggedIn || appState.currentCourier != null;

    final double? courierRating = double.tryParse(order['courier_rating']?.toString() ?? '');
    final String courierReview = order['courier_review']?.toString() ?? '';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          elevation: 0,
          title: Text('تتبع الطلب #$targetId 📦', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
          iconTheme: const IconThemeData(color: Colors.amber),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🌟 شريط التقدم الأفقي (يظهر للجميع)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(steps.length, (index) {
                    bool isCompleted = index <= currentStep;
                    bool isCurrent = index == currentStep;
                    return Expanded(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isCompleted ? Colors.amber : Colors.black45,
                              shape: BoxShape.circle,
                              border: Border.all(color: isCurrent ? Colors.white : Colors.transparent, width: 2),
                              boxShadow: isCurrent ? [BoxShadow(color: Colors.amber.withOpacity(0.6), blurRadius: 8)] : [],
                            ),
                            child: Icon(
                              steps[index]['icon'] as IconData,
                              size: 16,
                              color: isCompleted ? Colors.black : Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            steps[index]['title'].toString(),
                            style: TextStyle(
                              color: isCurrent ? Colors.amber : (isCompleted ? Colors.white70 : Colors.grey),
                              fontSize: 10,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 16),

              // 🛑 🗺️ الخريطة الحية ومسار التتبع الميداني (تظهر حصرياً للمشرف والمندوب فقط، وتختفي تماماً عن العميل)
              if (isManagerOrCourier) ...[
                Container(
                  height: 240,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber.withOpacity(0.4), width: 1.5),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 12, offset: const Offset(0, 6))],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _courierPosition ?? _customerPosition,
                          initialZoom: 16.5,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.fast.taiz',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _customerPosition,
                                width: 45,
                                height: 45,
                                child: const Icon(Icons.location_pin, color: Colors.redAccent, size: 42),
                              ),
                              if (_courierPosition != null)
                                Marker(
                                  point: _courierPosition!,
                                  width: 50,
                                  height: 50,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.amber,
                                      shape: BoxShape.circle,
                                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 8)],
                                    ),
                                    child: const Icon(Icons.two_wheeler_rounded, color: Colors.black, size: 26),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.withOpacity(0.4)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.radar, color: Colors.amber, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    appState.getArabicStatus(rawStatus),
                                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ],
                              ),
                              const Text('📡 مباشر (خاص بالمشرف والمندوب)', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // زر خرائط جوجل للمشرف/المندوب
                if (rawStatus == 'acceptedByCourier' || rawStatus == 'onTheWay') ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('فتح اتجاهات الملاحة في خرائط جوجل 🗺️', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      final String addressText = order['address']?.toString() ?? '';
                      String mapsQuery = addressText.contains('13.') ? addressText : 'Taiz, Yemen';
                      final Uri googleMapsUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$mapsQuery');
                      if (await canLaunchUrl(googleMapsUrl)) {
                        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ] else ...[
                // رسالة توضيحية للعميل أن الطلب تحت المتابعة دون الحاجة للخريطة الميدانية
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.greenAccent, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'حالة طلبك الحالية: ${appState.getArabicStatus(rawStatus)} ✅',
                          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 🧾 بطاقة تفاصيل الطلب المالية والمنتجات
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('تفاصيل الطلب والأسعار 🧾', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
                    const Divider(color: Colors.white12, height: 16),
                    Text('🛒 المنتجات: ${order['items_description'] ?? order['items_desc'] ?? order['itemsdesc'] ?? 'غير متوفرة'}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 8),
                    Text('📍 العنوان: ${order['address'] ?? 'غير محدد'}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 12),

                    // 📦 صندوق الأسعار
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('🛒 سعر المنتجات: ${finalProductsPrice.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text('🏍️ رسوم التوصيل: ${deliveryFee.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold)),
                          const Divider(color: Colors.white12, height: 8),
                          Text('💰 الإجمالي الكلي: ${grandTotal.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ⭐ قسم التقييم عند التسليم
              if (rawStatus == 'delivered') ...[
                if (!isManagerOrCourier) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.star, color: Colors.black),
                    label: const Text('تقييم التجربة والمندوب ⭐', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => RatingDialogWidget(
                          orderId: numericOrderId,
                          customerPhone: customerPhone,
                          targetId: courierId,
                          targetType: 'courier',
                        ),
                      );
                    },
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('⭐ تقييم العميل لهذا الطلب:', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 8),
                        if (courierRating != null) ...[
                          Row(
                            children: [
                              Text('$courierRating / 5', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(width: 8),
                              Row(
                                children: List.generate(5, (index) {
                                  return Icon(
                                    index < courierRating ? Icons.star : Icons.star_border,
                                    color: Colors.amber,
                                    size: 18,
                                  );
                                }),
                              ),
                            ],
                          ),
                          if (courierReview.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text('ملاحظة العميل: "$courierReview"', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                          ],
                        ] else ...[
                          const Text('لم يتم تقييم هذا الطلب من قبل العميل بعد ⏳', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
