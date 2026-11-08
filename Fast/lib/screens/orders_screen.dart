import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/constants.dart';
import '../widgets/empty_state.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final orders = List>.from(appState.orders);

    // 🔄 ترتيب الطلبات بحيث يكون الطلب الأخير (الأحدث/الأكبر في الـ ID) في الأعلى دائماً
    orders.sort((a, b) {
      final idA = int.tryParse(a['id']?.toString() ?? '0') ?? 0;
      final idB = int.tryParse(b['id']?.toString() ?? '0') ?? 0;
      return idB.compareTo(idA);
    });

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          title: const Text('طلباتي النشطة والمكتملة 📦', style: TextStyle(color: AppConstants.gold, fontSize: 16)),
          backgroundColor: const Color(0xFF1E1E1E),
          iconTheme: const IconThemeData(color: AppConstants.gold),
        ),
        body: orders.isEmpty
            ? const EmptyState(
                message: 'لا توجد طلبات سابقة حتى الآن\nطلباتك ستظهر هنا بمجرد إرسالها 🚀',
                icon: Icons.receipt_long_outlined,
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final order = orders[index];
                  final orderId = order['id']?.toString() ?? '';
                  final status = order['status']?.toString() ?? 'waitingForPricing';
                  final address = order['address']?.toString() ?? '';
                  final itemsDesc = order['items_description']?.toString() ?? order['itemsDesc']?.toString() ?? 'لا توجد تفاصيل';
                  final productsTotal = double.tryParse(order['products_total']?.toString() ?? '0') ?? 0.0;
                  final deliveryFee = double.tryParse(order['delivery_fee']?.toString() ?? '0') ?? 0.0;
                  final totalPrice = double.tryParse(order['total_price']?.toString() ?? '0') ?? (productsTotal + deliveryFee);
                  
                  return Card(
                    color: const Color(0xFF1E1E1E),
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: AppConstants.gold.withOpacity(0.3), width: 1.5),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // رأس الكارت (رقم الطلب وحالته)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'طلب #$orderId',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppConstants.gold, fontSize: 16),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppConstants.gold.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: AppConstants.gold.withOpacity(0.4)),
                                ),
                                child: Text(
                                  _getStatusText(status),
                                  style: const TextStyle(fontSize: 11, color: AppConstants.gold, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20, color: Colors.white12),
                          
                          // تفاصيل العنوان والمنتجات
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 16, color: Colors.redAccent),
                              const SizedBox(width: 6),
                              Expanded(child: Text('العنوان: $address', style: const TextStyle(color: Colors.white70, fontSize: 13))),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('🛒 المنتجات: $itemsDesc', style: const TextStyle(color: Colors.white, fontSize: 13)),
                          ),
                          const SizedBox(height: 10),
                          
                          // الأسعار
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('سعر المنتجات: $productsTotal ر.ي', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              Text('رسوم التوصيل: $deliveryFee ر.ي', style: const TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('الإجمالي الكلي:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
                              Text('$totalPrice ر.ي', style: const TextStyle(fontWeight: FontWeight.bold, color: AppConstants.gold, fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // 💰 أزرار موافقة العميل على السعر (تظهر مباشرة إذا كانت الحالة بانتظار الموافقة)
                          if (status == 'pricingSentToCustomer') ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppConstants.gold.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppConstants.gold.withOpacity(0.5)),
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    'يرجى مراجعة رسوم التوصيل والموافقة للمتابعة 🚀',
                                    style: TextStyle(color: AppConstants.gold, fontSize: 12, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 10),
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
                                            await appState.customerApprovePricing(orderId);
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
                                            await appState.customerCancelOrder(orderId);
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('تم إلغاء الطلب ❌')),
                                              );
                                            }
                                          },
                                          child: const Text('إلغاء الطلب ❌', style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          // 🔍 زر التفاصيل الاحتياطي المرتبط بالنافذة المنبثقة للعميل
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppConstants.gold,
                                side: const BorderSide(color: AppConstants.gold),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () => _showClientOrderDetailsDialog(context, order),
                              icon: const Icon(Icons.info_outline, size: 18),
                              label: const Text('عرض تفاصيل الطلب والمتابعة 🔍', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  // نافذة منبثقة تفاعلية للعميل لعرض التفاصيل
  void _showClientOrderDetailsDialog(BuildContext context, Map<String, dynamic> order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('تفاصيل طلبك #${order['id']} 📋', style: const TextStyle(color: AppConstants.gold)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('📍 العنوان: ${order['address']}', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 10),
              const Divider(color: Colors.white24),
              Text('🛒 المنتجات:\n${order['items_description'] ?? order['itemsDesc'] ?? 'لا توجد'}', style: const TextStyle(color: Colors.amberAccent)),
              const SizedBox(height: 10),
              const Divider(color: Colors.white24),
              Text('💰 سعر المنتجات: ${order['products_total']} ر.ي', style: const TextStyle(color: Colors.white70)),
              Text('🛵 رسوم التوصيل: ${order['delivery_fee']} ر.ي', style: const TextStyle(color: Colors.white70)),
              Text('🏷️ الإجمالي الكلي: ${order['total_price']} ر.ي', style: const TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text('حالة الطلب: ${_getStatusText(order['status']?.toString() ?? '')}', style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.gold, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'waitingForPricing': return 'بانتظار تحديد السعر من الإدارة ⏳';
      case 'pricingSentToCustomer': return 'تم إرسال التسعيرة - بانتظار موافقتك 🔔';
      case 'waitingCourierApproval': return 'بانتظار قبول المندوب';
      case 'onTheWay': return 'المندوب في الطريق إليك 🛵';
      case 'arrived': return 'وصل المندوب إلى موقعك 📍';
      case 'delivered': return 'تم التسليم بنجاح ✅';
      case 'cancelledByCustomer': return 'ملغي من العميل ❌';
      default: return status;
    }
  }
}
