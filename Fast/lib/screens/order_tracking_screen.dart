import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;
import '../providers/app_state.dart';
import '../widgets/RatingWidget.dart';

class CurvedRoutePainter extends CustomPainter {
  final double progress;

  CurvedRoutePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = Colors.grey[800]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    final paintProgress = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(30, size.height * 0.7);
    path.cubicTo(
      size.width * 0.25, size.height * 0.1,
      size.width * 0.75, size.height * 0.9,
      size.width - 30, size.height * 0.3,
    );

    canvas.drawPath(path, paintLine);

    final pathMetric = path.computeMetrics().first;
    final extractPath = pathMetric.extractPath(0.0, pathMetric.length * progress);
    canvas.drawPath(extractPath, paintProgress);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class OrderTrackingScreen extends StatelessWidget {
  final Map<String, dynamic>? orderMap;
  final String? orderIdParam;

  const OrderTrackingScreen({Key? key, this.orderMap, this.orderIdParam}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    final String targetId = orderIdParam ?? orderMap?['id']?.toString() ?? '';
    
    final order = appState.orders.firstWhere(
      (o) => o['id'].toString() == targetId,
      orElse: () => orderMap ?? {},
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
    
    double progressValue = 0.1;
    int currentStep = 0;
    
    if (rawStatus == 'waitingForPricing') {
      currentStep = 0;
      progressValue = 0.15;
    } else if (rawStatus == 'pricingSentToCustomer' || rawStatus == 'waitingCourierApproval') {
      currentStep = 1;
      progressValue = 0.35;
    } else if (rawStatus == 'acceptedByCourier' || rawStatus == 'onTheWay') {
      currentStep = 2;
      progressValue = 0.65;
    } else if (rawStatus == 'arrivedToCustomer' || rawStatus == 'arrived') {
      currentStep = 3;
      progressValue = 0.85;
    } else if (rawStatus == 'delivered') {
      currentStep = 4;
      progressValue = 1.0;
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
    final String courierId = order['courier_id']?.toString() ?? 'general_courier';

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
                Container(
                  height: 230,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber.withOpacity(0.4), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 5)),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Row(
                          children: [
                            const Icon(Icons.two_wheeler, color: Colors.amber, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              steps[currentStep]['title'].toString(),
                              style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: CurvedRoutePainter(progress: progressValue),
                        ),
                      ),
                      Positioned(
                        bottom: 45,
                        left: MediaQuery.of(context).size.width * 0.42,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.amber.withOpacity(0.6), blurRadius: 12, spreadRadius: 3),
                            ],
                          ),
                          child: const Icon(Icons.two_wheeler, color: Colors.black, size: 24),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
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
                    label: const Text('فتح الخريطة الحية لتتبع المندوب 🛵📍', style: TextStyle(fontWeight: FontWeight.bold)),
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
                            const SnackBar(content: Text('تعذر فتح الخريطة الحية 🗺️')),
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
