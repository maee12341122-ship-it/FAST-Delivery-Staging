import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart'; // 👈 استيراد مكتبة الخرائط الحية
import 'package:latlong2/latlong.dart';       // 👈 استيراد الإحداثيات الجغرافية
import 'package:supabase_flutter/supabase_flutter.dart'; // 👈 سوبابيس للـ Realtime
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
  // 🗺️ متغيرات خريطة التتبع اللحظي
  final MapController _mapController = MapController();
  LatLng? _courierPosition;
  RealtimeChannel? _orderChannel;
  RealtimeChannel? _locationChannel;
  static const LatLng _taizCenter = LatLng(13.5795, 44.0209); // مركز تعز الافتراضي

  @override
  void initState() {
    super.initState();
    final String targetId = widget.orderIdParam ?? widget.orderMap?['id']?.toString() ?? '';
    if (targetId.isNotEmpty) {
      _subscribeToOrderUpdates(targetId);
    }
  }

  // 📡 الاستماع لتحديثات الطلب وموقع المندوب لحظياً عبر سوبابيس
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
      {'title': 'تأسيس الطلب', 'desc': 'تم استلام طلبك وإضافته للسلة'},
      {'title': 'التسعير والموافقة', 'desc': 'تحديد رسوم التوصيل والموافقة'},
      {'title': 'المندوب في الطريق 🛵', 'desc': 'الكابتن متجه لاستلام وتوصيل الطلب'},
      {'title': 'وصل المندوب للموقع 📍', 'desc': 'المندوب وصل باب منزلك'},
      {'title': 'تم التسليم بنجاح ✅', 'desc': 'بالهناء والشفاء، شكراً لاستخدامك فاست'},
    ];

    final double productsTotal = double.tryParse(order['products_total']?.toString() ?? order['total_price']?.toString() ?? '0') ?? 0.0;
    final double deliveryFee = double.tryParse(order['delivery_fee']?.toString() ?? '0') ?? 0.0;
    final double grandTotal = productsTotal + deliveryFee;

    final int numericOrderId = int.tryParse(targetId) ?? 0;
    final String customerPhone = order['phone'] ?? appState.userProfile?['phone'] ?? '';
    final String courierId = order['assigned_courier']?.toString() ?? order['courier_id']?.toString() ?? 'general_courier';

    // 🔍 التحقق هل المستخدم الحالي هو مشرف أو مندوب أم العميل العادي
    final bool isManagerOrCourier = appState.isAdminLoggedIn || appState.currentCourier != null;
    
    // جلب تقييم العميل إذا وجد في بيانات الطلب
    final double? courierRating = double.tryParse(order['courier_rating']?.toString() ?? '');
    final String courierReview = order['courier_review']?.toString() ?? '';

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E1E1E),
            title: Text('تتبع الطلب #$targetId 📦', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
            iconTheme: const IconThemeData(color: Colors.amber),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🗺️ خريطة التتبع الحي الحقيقية بدلاً من الخط الرسومي الثابت
                Container(
                  height: 230,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber.withOpacity(0.4), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 5)),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _courierPosition ?? _taizCenter,
                          initialZoom: 16.5,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.fast.taiz',
                          ),
                          if (_courierPosition != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _courierPosition!,
                                  width: 50,
                                  height: 50,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.amber,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 6, offset: const Offset(0, 3)),
                                      ],
                                    ),
                                    child: const Icon(Icons.two_wheeler_rounded, color: Colors.black, size: 26),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                                  const Icon(Icons.two_wheeler, color: Colors.amber, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    steps[currentStep]['title'].toString(),
                                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                              const Text('📡 تتبع حي مباشر', style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        left: 8,
                        right: 8,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              steps[currentStep]['desc'].toString(),
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

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
                      String mapsQuery = 'Taiz, Yemen';
                      
                      if (addressText.contains('13.') && addressText.contains('44.')) {
                        mapsQuery = addressText;
                      }

                      final Uri googleMapsUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$mapsQuery');
                      
                      if (await canLaunchUrl(googleMapsUrl)) {
                        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تعذر فتح خرائط جوجل 🗺️')),
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                if (rawStatus == 'pricingSentToCustomer' && !isManagerOrCourier) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.amber.withOpacity(0.5), width: 1.5),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'تم تحديد رسوم التوصيل، يرجى الموافقة للمتابعة 🚀',
                          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () async {
                                  await appState.customerConfirmOrder(targetId);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('تم تأكيد السعر بنجاح وجاري إرساله للمندوب ✅')),
                                    );
                                  }
                                },
                                child: const Text('موافقة ✅', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () async {
                                  await appState.customerCancelOrder(targetId);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('تم إلغاء الطلب ❌')),
                                    );
                                  }
                                },
                                child: const Text('إلغاء ❌', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('تفاصيل الطلب 🧾', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
                      const Divider(color: Colors.white12, height: 16),
                      Text('🛒 المنتجات: ${order['items_description'] ?? order['items_desc'] ?? 'غير متوفرة'}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 8),
                      Text('📍 العنوان: ${order['address'] ?? 'غير محدد'}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      const Divider(color: Colors.white12, height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('الإجمالي الكلي:', style: TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold)),
                          Text('$grandTotal ر.ي', style: const TextStyle(color: Colors.amber, fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ⭐ إدارة عرض التقييم حسب نوع المستخدم (عميل أم مندوب/مشرف)
                if (rawStatus == 'delivered') ...[
                  if (!isManagerOrCourier) ...[
                    // 👤 العميل: يظهر له زر التقييم لتقييم المندوب
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
                    // 🛵 المندوب أو المشرف: يرى تقييم العميل لهذا الطلب (بدون زر تقييم)
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
      ),
    );
  }
}
