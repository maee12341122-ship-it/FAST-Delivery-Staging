import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class OrderTrackingScreen extends StatelessWidget {
  // يدعم استقبال Map القديمة أو يمكن تعديله بحسب الاستدعاء
  final Map<String, dynamic>? orderMap;
  final String? orderIdParam;

  const OrderTrackingScreen({Key? key, this.orderMap, this.orderIdParam}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    // استخراج معرف الطلب أو بياناته بأمان
    final String targetId = orderIdParam ?? orderMap?['id']?.toString() ?? '';
    
    // البحث عن الطلب المحدث من الـ Provider لضمان جلب الحالة الحالية فورياً
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
    
    // تحديد الخطوة الحالية بدقة للمسار الجديد
    int currentStep = 0;
    if (rawStatus == 'waitingForPricing') currentStep = 0;
    else if (rawStatus == 'pricingSentToCustomer' || rawStatus == 'waitingCourierApproval') currentStep = 1;
    else if (rawStatus == 'acceptedByCourier' || rawStatus == 'onTheWay') currentStep = 2;
    else if (rawStatus == 'arrivedToCustomer' || rawStatus == 'arrived') currentStep = 3;
    else if (rawStatus == 'delivered') currentStep = 4;

    final steps = [
      {'title': 'تأسيس الطلب', 'icon': Icons.receipt_long, 'desc': 'تم استلام طلبك وإضافته للسلة'},
      {'title': 'التسعير وتوصيل العميل', 'icon': Icons.monetization_on, 'desc': 'تحديد رسوم التوصيل والموافقة'},
      {'title': 'المندوب في الطريق 🛵', 'icon': Icons.two_wheeler, 'desc': 'الكابتن متجه لاستلام الطلب وتوصيله'},
      {'title': 'وصل المندوب للموقع 📍', 'icon': Icons.location_pin, 'desc': 'المندوب وصل باب منزلك'},
      {'title': 'تم التسليم بنجاح ✅', 'icon': Icons.check_circle, 'desc': 'بالهناء والشفاء، نتمنى تقييمك'},
    ];

    final double productsTotal = double.tryParse(order['products_total']?.toString() ?? order['total_price']?.toString() ?? '0') ?? 0.0;
    final double deliveryFee = double.tryParse(order['delivery_fee']?.toString() ?? '0') ?? 0.0;
    final double grandTotal = productsTotal + deliveryFee;

    return Directionality(
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
              // 🌟 مسار وتتبع الطلب التفاعلي الحديث
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.amber.withOpacity(0.4), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'مسار وتتبع الطلب 🛵⚡',
                          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'المرحلة ${currentStep + 1} من 5',
                            style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: steps.length,
                      itemBuilder: (context, index) {
                        final isDone = index <= currentStep;
                        final isCurrent = index == currentStep;
                        final step = steps[index];

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 400),
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? Colors.amber
                                        : (isDone ? Colors.amber[800] : const Color(0xFF2A2A2A)),
                                    shape: BoxShape.circle,
                                    boxShadow: isCurrent
                                        ? [BoxShadow(color: Colors.amber.withOpacity(0.6), blurRadius: 8, spreadRadius: 2)]
                                        : [],
                                  ),
                                  child: Icon(
                                    isCurrent && index == 2 ? Icons.two_wheeler : (step['icon'] as IconData),
                                    color: isCurrent ? Colors.black : (isDone ? Colors.white : Colors.grey),
                                    size: 17,
                                  ),
                                ),
                                if (index < steps.length - 1)
                                  Container(
                                    width: 3,
                                    height: 35,
                                    color: index < currentStep ? Colors.amber : Colors.grey[800],
                                  ),
                              ],
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 5.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      step['title'].toString(),
                                      style: TextStyle(
                                        color: isCurrent ? Colors.amber : (isDone ? Colors.white : Colors.grey),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      step['desc'].toString(),
                                      style: TextStyle(
                                        color: isCurrent ? Colors.white70 : Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (index < steps.length - 1) const SizedBox(height: 15),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 💰 أزرار موافقة أو رفض العميل للسعر (إذا أرسلت الإدارة التسعيرة)
              if (rawStatus == 'pricingSentToCustomer') ...[
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

              // 🧾 تفاصيل الفاتورة والمنتجات
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
            ],
          ),
        ),
      ),
    );
  }
}
