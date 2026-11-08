import 'package:flutter/material.dart';

class OrderTrackingScreen extends StatelessWidget {
  final Map<String, dynamic> order;

  const OrderTrackingScreen({Key? key, required this.order}) : super(key: key);

  // تحديد رقم المرحلة بناءً على حالة الطلب القادمة من قاعدة البيانات
  int _getCurrentStep(String status) {
    switch (status) {
      case 'waitingForPricing': return 0;
      case 'pricingSentToCustomer': return 1;
      case 'waitingCourierApproval': return 2;
      case 'onTheWay': return 3;
      case 'arrived': return 4;
      case 'delivered': return 5;
      default: return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final String status = order['status'] ?? 'waitingForPricing';
    final int currentStep = _getCurrentStep(status);

    final List> steps = [
      {'title': 'تم استلام طلبك', 'subtitle': 'جارٍ مراجعة الأسعار وتجهيز الأصناف'},
      {'title': 'تم تحديد التسعيرة', 'subtitle': 'بانتظار موافقتك لإرسال الطلب للمندوب'},
      {'title': 'تم إسناد الطلب للمندوب', 'subtitle': 'المندوب في طريقه لاستلام الطلب'},
      {'title': 'المندوب في الطريق إليك', 'subtitle': 'طلبك يتحرك نحو عنوانك الآن 🛵'},
      {'title': 'وصل المندوب لموقعك', 'subtitle': 'الرجاء الاستعداد لاستلام طلبك 📍'},
      {'title': 'تم التسليم بنجاح', 'subtitle': 'شكراً لاستخدامك FAST ❤️'},
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text('تتبع الطلب #${order['id']}', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
          iconTheme: const IconThemeData(color: Colors.amber),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 📦 بطاقة ملخص تفاصيل الطلب
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🛒 المنتجات: ${order['items_description'] ?? 'لا توجد تفاصيل'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 6),
                    Text('💰 إجمالي السعر: ${order['products_total'] ?? 0} ر.ي', style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text('📍 العنوان: ${order['address'] ?? 'غير محدد'}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 25),
              const Text('حالة خط سير الطلب 🚀', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              
              // 📋 قائمة خطوات التتبع التفاعلية
              Expanded(
                child: ListView.builder(
                  itemCount: steps.length,
                  itemBuilder: (context, index) {
                    bool isCompleted = index <= currentStep;
                    bool isCurrent = index == currentStep;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isCompleted ? Colors.amber : Colors.grey[800],
                                border: Border.all(color: isCurrent ? Colors.white : Colors.transparent, width: 2),
                              ),
                              child: Center(
                                child: isCompleted
                                    ? const Icon(Icons.check, color: Colors.black, size: 18)
                                    : Text('${index + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                              ),
                            ),
                            if (index < steps.length - 1)
                              Container(
                                width: 2,
                                height: 45,
                                color: index < currentStep ? Colors.amber : Colors.grey[800],
                              ),
                          ],
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                steps[index]['title']!,
                                style: TextStyle(
                                  color: isCompleted ? Colors.white : Colors.grey,
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                steps[index]['subtitle']!,
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                              const SizedBox(height: 25),
                            ],
                          ),
                        ),
                      ],
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
