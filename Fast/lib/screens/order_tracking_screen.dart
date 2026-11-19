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

  const OrderTrackingScreen({super.key, this.orderMap, this.orderIdParam});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final MapController _mapController = MapController();
  LatLng? _courierPosition;
  LatLng _customerPosition =
      const LatLng(13.5795, 44.0209); // مركز تعز الافتراضي
  RealtimeChannel? _orderChannel;
  RealtimeChannel? _locationChannel;

  Map<String, dynamic>? _restaurantRatingData;
  Map<String, dynamic>? _courierRatingData;
  bool _isLoadingRatings = false;
  bool _isSubmittingOrderAction = false;

  @override
  void initState() {
    super.initState();
    final String targetId =
        widget.orderIdParam ?? widget.orderMap?['id']?.toString() ?? '';
    if (targetId.isNotEmpty) {
      Map<String, dynamic>? sourceOrder = widget.orderMap;
      if (sourceOrder == null) {
        final appState = context.read<AppState>();
        final found = appState.orders.where(
          (o) => o['id']?.toString() == targetId,
        );
        if (found.isNotEmpty && found.first is Map) {
          sourceOrder = Map<String, dynamic>.from(found.first as Map);
        }
      }

      _extractCustomerCoordinates(sourceOrder);
      _subscribeToOrderUpdates(targetId);
      _fetchOrderRatings(targetId);

      final initialCourier =
          sourceOrder?['assigned_courier']?.toString().trim() ?? '';
      if (initialCourier.isNotEmpty) {
        _fetchAndListenCourierLocation(initialCourier);
      }
    }
  }

  void _safeMoveMapTo(LatLng point, double zoom) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapController.move(point, zoom);
      } catch (e) {
        debugPrint('⚠️ تعذر تحريك الخريطة حالياً: $e');
      }
    });
  }

  Future<void> _fetchOrderRatings(String orderId) async {
    final intOrderId = int.tryParse(orderId.trim());
    if (intOrderId == null) return;

    if (mounted) {
      setState(() => _isLoadingRatings = true);
    }

    try {
      final rows = await Supabase.instance.client
          .from('ratings_and_reviews')
          .select(
              'id, order_id, target_type, target_id, rating, comment, created_at')
          .eq('order_id', intOrderId);

      Map<String, dynamic>? restRes;
      Map<String, dynamic>? courierRes;

      for (final raw in (rows as List)) {
        if (raw is Map) {
          final map = Map<String, dynamic>.from(raw);
          final targetType = map['target_type']?.toString().trim();
          if (targetType == 'restaurant') {
            restRes = map;
          } else if (targetType == 'courier') {
            courierRes = map;
          }
        }
      }

      if (mounted) {
        setState(() {
          _restaurantRatingData = restRes;
          _courierRatingData = courierRes;
          _isLoadingRatings = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في جلب التقييمات: $e');
      if (mounted) setState(() => _isLoadingRatings = false);
    }
  }

  void _extractCustomerCoordinates(Map<String, dynamic>? order) {
    if (order == null) return;
    final String address = order['address']?.toString() ?? '';
    try {
      if (address.contains('(') && address.contains(')')) {
        final coordsPart =
            address.substring(address.indexOf('(') + 1, address.indexOf(')'));
        final parts = coordsPart.split(',');
        if (parts.length >= 2) {
          final lat = double.tryParse(parts[0].trim());
          final lng = double.tryParse(parts[1].trim());
          if (lat != null &&
              lng != null &&
              lat >= -90 &&
              lat <= 90 &&
              lng >= -180 &&
              lng <= 180) {
            if (mounted) {
              setState(() {
                _customerPosition = LatLng(lat, lng);
              });
            }
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
              unawaited(context.read<AppState>().fetchOrders());
              setState(() {});
              _extractCustomerCoordinates(payload.newRecord);
              final courierName =
                  payload.newRecord['assigned_courier']?.toString().trim();
              if (courierName != null &&
                  courierName.isNotEmpty &&
                  _locationChannel == null) {
                _fetchAndListenCourierLocation(courierName);
              }
            }
          },
        )
        .subscribe();
  }

  String _resolveCourierLocationKey(String courierNameOrId) {
    final trimmed = courierNameOrId.trim();
    if (!mounted) return trimmed;
    final appState = context.read<AppState>();
    for (final c in appState.couriers) {
      if (c is Map) {
        final name = c['name']?.toString().trim() ?? '';
        final id = c['id']?.toString().trim() ?? '';
        if (name.toLowerCase() == trimmed.toLowerCase() || id == trimmed) {
          return id.isNotEmpty ? id : name;
        }
      }
    }
    return trimmed;
  }

  Future<void> _fetchAndListenCourierLocation(String courierNameOrId) async {
    try {
      final resolvedKey = _resolveCourierLocationKey(courierNameOrId);
      final keysToCheck = {courierNameOrId.trim(), resolvedKey}
          .where((k) => k.isNotEmpty)
          .toList();

      Map<String, dynamic>? foundRow;
      String activeChannelKey = resolvedKey.isNotEmpty
          ? resolvedKey
          : courierNameOrId.trim();

      for (final key in keysToCheck) {
        final res = await Supabase.instance.client
            .from('courier_locations')
            .select('courier_id, latitude, longitude, updated_at')
            .eq('courier_id', key)
            .maybeSingle();
        if (res != null && res['latitude'] != null && res['longitude'] != null) {
          foundRow = Map<String, dynamic>.from(res);
          activeChannelKey = key;
          break;
        }
      }

      if (foundRow != null && mounted) {
        final lat = (foundRow['latitude'] as num).toDouble();
        final lng = (foundRow['longitude'] as num).toDouble();
        setState(() {
          _courierPosition = LatLng(lat, lng);
        });
      }

      _locationChannel = Supabase.instance.client
          .channel('public:courier_locations:courier_id=eq.$activeChannelKey')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'courier_locations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'courier_id',
              value: activeChannelKey,
            ),
            callback: (payload) {
              final newData = payload.newRecord;
              if (newData.isNotEmpty &&
                  newData['latitude'] != null &&
                  newData['longitude'] != null &&
                  mounted) {
                final lat = (newData['latitude'] as num).toDouble();
                final lng = (newData['longitude'] as num).toDouble();
                final nextPos = LatLng(lat, lng);
                setState(() {
                  _courierPosition = nextPos;
                });
                _safeMoveMapTo(nextPos, 17.0);
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('⚠️ خطأ في متابعة موقع المندوب: $e');
    }
  }

  Future<void> _handleCustomerPricingDecision(
    BuildContext context,
    AppState appState,
    String orderId, {
    required bool approve,
  }) async {
    if (_isSubmittingOrderAction) return;
    setState(() => _isSubmittingOrderAction = true);
    try {
      if (approve) {
        await appState.customerApprovePricing(orderId);
      } else {
        await appState.customerCancelOrder(orderId);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve
                ? 'تم تأكيد السعر وإرسال الطلب للمندوب ✅'
                : 'تم إلغاء الطلب بنجاح'),
            backgroundColor: approve ? Colors.green[700] : Colors.red[700],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmittingOrderAction = false);
      }
    }
  }

  void _showRestaurantRatingDialog(
      BuildContext context, AppState appState, String orderId) {
    double rating = 5.0;
    final TextEditingController reviewController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('تقييم المطعم وجودة الوجبة 🍽️⭐',
                style: TextStyle(color: Colors.amber, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('كيف وجدت طعم وجودة الأكل من المطعم؟',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
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
                  await _fetchOrderRatings(orderId);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'شكراً لك! تم إرسال تقييم المطعم بنجاح ⭐')),
                    );
                  }
                },
                child: const Text('إرسال التقييم',
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCourierRatingDialog(BuildContext context, AppState appState,
      String orderId, String courierName) {
    double rating = 5.0;
    final TextEditingController reviewController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('تقييم أداء المندوب وسرعة التوصيل 🛵⭐',
                style: TextStyle(color: Colors.amber, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('كيف كانت سرعة والتزام المندوب بالتوصيل؟',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
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
                    courierName:
                        courierName.isEmpty ? 'مندوب عام' : courierName,
                    rating: rating,
                    reviewText: reviewController.text.trim(),
                  );
                  await _fetchOrderRatings(orderId);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'شكراً لك! تم إرسال تقييم المندوب بنجاح ⭐')),
                    );
                  }
                },
                child: const Text('إرسال التقييم',
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_orderChannel != null) {
      Supabase.instance.client.removeChannel(_orderChannel!);
    }
    if (_locationChannel != null) {
      Supabase.instance.client.removeChannel(_locationChannel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final String targetId =
        widget.orderIdParam ?? widget.orderMap?['id']?.toString() ?? '';

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
            title:
                const Text('تتبع الطلب', style: TextStyle(color: Colors.amber)),
            iconTheme: const IconThemeData(color: Colors.amber),
          ),
          body: const Center(
            child: Text('عذراً، لم يتم العثور على تفاصيل هذا الطلب ❌',
                style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
    }

    final String rawStatus =
        order['status']?.toString().trim() ?? 'waitingForPricing';

    int currentStep = 0;
    if (rawStatus == 'waitingForPricing') {
      currentStep = 0;
    } else if (rawStatus == 'pricingSentToCustomer' ||
        rawStatus == 'waitingCourierApproval' ||
        rawStatus == 'approvedByCustomer') {
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

    final String itemsDescText =
        (order['items_description'] ?? order['items_desc'] ?? '').toString();
    final bool isWaselLi =
        itemsDescText.contains('وصل لي') || itemsDescText.contains('طلب خاص');

    final double rawProductsPrice = double.tryParse(
            order['products_total']?.toString() ??
                order['total_price']?.toString() ??
                order['items_price']?.toString() ??
                order['products_price']?.toString() ??
                '0') ??
        0.0;

    final double finalProductsPrice = isWaselLi ? 0.0 : rawProductsPrice;

    final double deliveryFee =
        double.tryParse(order['delivery_fee']?.toString() ?? '0') ?? 0.0;

    final double dbTotalAmount = double.tryParse(
            order['total_amount']?.toString() ??
                order['total']?.toString() ??
                '0') ??
        0.0;

    final double grandTotal = isWaselLi
        ? deliveryFee
        : (dbTotalAmount > 0 ? dbTotalAmount : (finalProductsPrice + deliveryFee));

    final String courierName =
        order['assigned_courier']?.toString() ?? 'مندوب عام';

    final bool isManagerOrCourier =
        appState.isAdminLoggedIn || appState.currentCourier != null;

    final double? restaurantRatingVal = _restaurantRatingData != null
        ? double.tryParse(_restaurantRatingData!['rating']?.toString() ?? '')
        : null;
    final String restaurantReviewVal =
        _restaurantRatingData?['comment']?.toString() ?? '';

    final double? courierRatingVal = _courierRatingData != null
        ? double.tryParse(_courierRatingData!['rating']?.toString() ?? '')
        : null;
    final String courierReviewVal =
        _courierRatingData?['comment']?.toString() ?? '';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          elevation: 0,
          title: Text('تتبع الطلب #$targetId 📦',
              style: const TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          iconTheme: const IconThemeData(color: Colors.amber),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
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
                              border: Border.all(
                                  color: isCurrent
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 2),
                              boxShadow: isCurrent
                                  ? [
                                      BoxShadow(
                                          color: Colors.amber.withOpacity(0.6),
                                          blurRadius: 8)
                                    ]
                                  : [],
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
                              color: isCurrent
                                  ? Colors.amber
                                  : (isCompleted
                                      ? Colors.white70
                                      : Colors.grey),
                              fontSize: 10,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
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

              if (isManagerOrCourier) ...[
                Container(
                  height: 240,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.amber.withOpacity(0.4), width: 1.5),
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
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.fast.taiz',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _customerPosition,
                            width: 45,
                            height: 45,
                            child: const Icon(Icons.location_pin,
                                color: Colors.redAccent, size: 42),
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
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black.withOpacity(0.5),
                                        blurRadius: 8)
                                  ],
                                ),
                                child: const Icon(Icons.two_wheeler_rounded,
                                    color: Colors.black, size: 26),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.amber.withOpacity(0.4), width: 1.5),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle,
                              color: Colors.greenAccent, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            appState.getArabicStatus(rawStatus),
                            style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 15),
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
                            child: const Icon(Icons.two_wheeler,
                                color: Colors.black, size: 28),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        rawStatus == 'delivered'
                            ? 'بالهناء والشفاء، شكراً لتعاملكم معنا ⭐'
                            : 'جاري العمل على توصيل طلبك بأسرع وقت 🚀',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
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
                    const Text('تفاصيل الطلب والأسعار 🧾',
                        style: TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const Divider(color: Colors.white12, height: 16),
                    Text(
                        '🛒 المنتجات: ${order['items_description'] ?? order['items_desc'] ?? 'غير متوفرة'}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 8),
                    Text('📍 العنوان: ${order['address'] ?? 'غير محدد'}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12)),
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
                          if (!isWaselLi) ...[
                            Text(
                                '🛒 سعر المنتجات: ${finalProductsPrice.toStringAsFixed(0)} ر.ي',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                            const SizedBox(height: 4),
                          ],
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
                    if (!isManagerOrCourier &&
                        rawStatus == 'pricingSentToCustomer') ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _isSubmittingOrderAction
                                  ? null
                                  : () => _handleCustomerPricingDecision(
                                      context, appState, targetId,
                                      approve: true),
                              icon: _isSubmittingOrderAction
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.check_circle, size: 18),
                              label: Text(
                                _isSubmittingOrderAction
                                    ? 'جاري التأكيد...'
                                    : 'تأكيد السعر والموافقة ✅',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.redAccent),
                                foregroundColor: Colors.redAccent,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _isSubmittingOrderAction
                                  ? null
                                  : () => _handleCustomerPricingDecision(
                                      context, appState, targetId,
                                      approve: false),
                              icon: const Icon(Icons.cancel, size: 18),
                              label: const Text(
                                'إلغاء الطلب ❌',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // قسم التقييم الثنائي عند التسليم
              if (rawStatus == 'delivered') ...[
                if (_isLoadingRatings)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: CircularProgressIndicator(color: Colors.amber),
                    ),
                  )
                else if (!isManagerOrCourier) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _restaurantRatingData != null
                                ? Colors.grey[800]
                                : Colors.amber,
                            foregroundColor: _restaurantRatingData != null
                                ? Colors.white
                                : Colors.black,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: Icon(
                              _restaurantRatingData != null
                                  ? Icons.check
                                  : Icons.store,
                              size: 18),
                          label: Text(
                              _restaurantRatingData != null
                                  ? 'تم تقييم المطعم ⭐'
                                  : 'تقييم المطعم 🍽️',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12)),
                          onPressed: _restaurantRatingData != null
                              ? null
                              : () => _showRestaurantRatingDialog(
                                  context, appState, targetId),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _courierRatingData != null
                                ? Colors.grey[800]
                                : Colors.amber,
                            foregroundColor: _courierRatingData != null
                                ? Colors.white
                                : Colors.black,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: Icon(
                              _courierRatingData != null
                                  ? Icons.check
                                  : Icons.two_wheeler,
                              size: 18),
                          label: Text(
                              _courierRatingData != null
                                  ? 'تم تقييم المندوب ⭐'
                                  : 'تقييم المندوب 🛵',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12)),
                          onPressed: _courierRatingData != null
                              ? null
                              : () => _showCourierRatingDialog(
                                  context, appState, targetId, courierName),
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
                        const Text('⭐ تقييمات العميل لهذا الطلب:',
                            style: TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 10),
                        Text(
                            '🍽️ تقييم المطعم: ${restaurantRatingVal != null ? "$restaurantRatingVal / 5" : "لم يُقيم بعد"}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                        if (restaurantReviewVal.isNotEmpty)
                          Text('ملاحظة المطعم: "$restaurantReviewVal"',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        const Divider(color: Colors.white12),
                        Text(
                            '🛵 تقييم المندوب: ${courierRatingVal != null ? "$courierRatingVal / 5" : "لم يُقيم بعد"}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                        if (courierReviewVal.isNotEmpty)
                          Text('ملاحظة المندوب: "$courierReviewVal"',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
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
