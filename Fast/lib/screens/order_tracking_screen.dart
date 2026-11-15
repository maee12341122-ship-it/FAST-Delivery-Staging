import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state.dart';

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

  void _showRestaurantRatingDialog(BuildContext context, AppState appState, String orderId) {
    double rating = 5.0;
    final TextEditingController reviewController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('تقييم المطعم وجودة الوجبة 🍽️⭐', style: TextStyle(color: Colors.amber, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('كيف وجدت طعم وجودة الأكل من المطعم؟', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 32,
                      ),
                      onPressed: () {
                        setDialogState(() {
                          rating = (index + 1).toDouble();
                        });
                      },
                    );
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reviewController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'اكتب ملاحظتك للمطعم (اختياري)',
                    labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                    border: OutlineInputBorder(),
                  ),
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
                  await appState.submitRestaurantRating(
                    orderId: orderId,
                    rating: rating,
                    reviewText: reviewController.text.trim(),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('شكراً لك! تم إرسال تقييم المطعم بنجاح ⭐')),
                    );
                  }
                },
                child: const Text('إرسال التقييم', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCourierRatingDialog(BuildContext context, AppState appState, String orderId, String courierName) {
    double rating = 5.0;
    final TextEditingController reviewController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('تقييم أداء المندوب وسرعة التوصيل 🛵⭐', style: TextStyle(color: Colors.amber, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('كيف كانت سرعة والتزام المندوب بالتوصيل؟', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 32,
                      ),
                      onPressed: () {
                        setDialogState(() {
                          rating = (index + 1).toDouble();
                        });
                      },
                    );
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reviewController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'اكتب ملاحظتك عن المندوب (اختياري)',
                    labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                    border: OutlineInputBorder(),
                  ),
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
                  await appState.submitCourierRating(
                    orderId: orderId,
                    courierName: courierName,
                    rating: rating,
                    reviewText: reviewController.text.trim(),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('شكراً لك! تم إرسال تقييم المندوب بنجاح ⭐')),
                    );
                  }
                },
                child: const Text('إرسال التقييم', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
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

    final String courierId = order['assigned_courier']?.toString() ?? 'general_courier';
    
    // التحقق هل المستخدم الحالي هو مشرف أو مندوب؟
    final bool isManagerOrCourier = appState.isAdminLoggedIn || appState.currentCourier != null;

    final double? courierRating = double.tryParse(order['courier_rating']?.toString() ?? '');
    final String courierReview = order['courier_review']?.toString() ?? '';

    final double? restaurantRating = double.tryParse(order['restaurant_rating']?.toString() ?? '');
    final String restaurantReview = order['restaurant_review']?.toString() ?? '';

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
              // شريط التقدم الأفقي للحالات
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

              // 🗺️ الشرط الذكي: إذا كان المشرف أو المندوب تظهر الخريطة التتبعية، وإذا كان عميل يظهر تصميم الدراجة الأنيق
              if (isManagerOrCourier) ...[
                Container(
                  height: 240,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber.withOpacity(0.4), width: 1.5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: FlutterMap(
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
                ),
                const SizedBox(height: 16),
              ] else ...[
                // تصميم الدراجة التجميلي الخاص بالعميل
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber.withOpacity(0.4), width: 1.5),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            appState.getArabicStatus(rawStatus),
                            style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            height: 4,
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(horizontal: 40),
                            color: Colors.amber.withOpacity(0.3),
                          ),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: Colors.amber,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.two_wheeler, color: Colors.black, size: 28),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        rawStatus == 'delivered' ? 'بالهناء والشفاء، نتمنى تقييمك ⭐' : 'جاري العمل على توصيل طلبك بأسرع وقت 🚀',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // تفاصيل الطلب والأسعار
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
                    Text('🛒 المنتجات: ${order['items_description'] ?? order['items_desc'] ?? 'غير متوفرة'}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 8),
                    Text('📍 العنوان: ${order['address'] ?? 'غير محدد'}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 12),
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

              // قسم التقييم الثنائي عند التسليم
              if (rawStatus == 'delivered') ...[
                if (!isManagerOrCourier) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.store, size: 18),
                          label: const Text('تقييم المطعم 🍽️', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          onPressed: () => _showRestaurantRatingDialog(context, appState, targetId),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.two_wheeler, size: 18),
                          label: const Text('تقييم المندوب 🛵', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          onPressed: () => _showCourierRatingDialog(context, appState, targetId, courierId),
                        ),
                      ),
                    ],
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
                        const Text('⭐ تقييمات العميل لهذا الطلب:', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 10),
                        Text('🍽️ تقييم المطعم: ${restaurantRating != null ? "$restaurantRating / 5" : "لم يُقيم بعد"}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                        if (restaurantReview.isNotEmpty) Text('ملاحظة المطعم: "$restaurantReview"', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        const Divider(color: Colors.white12),
                        Text('🛵 تقييم المندوب: ${courierRating != null ? "$courierRating / 5" : "لم يُقيم بعد"}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                        if (courierReview.isNotEmpty) Text('ملاحظة المندوب: "$courierReview"', style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
