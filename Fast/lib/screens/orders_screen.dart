import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../utils/constants.dart';
import '../widgets/empty_state.dart';
import '../services/notification_service.dart'; // 👈 استيراد خدمة الإشعارات لإرسال التنبيهات للعميل والمندوب

class AdminOrdersScreen extends StatefulWidget {
  final VoidCallback? onOpenDrawer;
  const AdminOrdersScreen({super.key, this.onOpenDrawer});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    // 👈 استخدام context.watch لجعل الشاشة بأكملها تتحدث لحظياً Real-time عند تغير الطلبات
    final orders = context.watch<AppState>().orders;
    final appState = context.read<AppState>();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          leading: widget.onOpenDrawer == null ? null : IconButton(icon: const Icon(Icons.menu), onPressed: widget.onOpenDrawer),
          title: const Text('لوحة تحكم المشرف - الطلبات والدفعات 📦', style: TextStyle(color: AppConstants.gold)),
          backgroundColor: const Color(0xFF1E1E1E),
        ),
        body: orders.isEmpty
            ? const EmptyState(
                message: 'لا توجد طلبات جديدة واردة حتى الآن\nالطلبات ستظهر هنا فور إرسالها من العملاء 📦',
                icon: Icons.admin_panel_settings_outlined,
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final itemsDesc = order['itemsDesc']?.toString() ?? 'لا توجد تفاصيل';

                  
                  final orderId = order['id']?.toString() ?? '';
                  final customerName = order['customer_name']?.toString() ?? 'عميل';
                  final phone = order['phone']?.toString() ?? '';
                  final address = order['address']?.toString() ?? '';
                  final itemsDesc = order['items_description']?.toString() ?? 'لا توجد تفاصيل';
                  final productsTotal = double.tryParse(order['products_total']?.toString() ?? '0') ?? 0.0;
                  final deliveryFee = double.tryParse(order['delivery_fee']?.toString() ?? '0') ?? 0.0;
                  final totalPrice = double.tryParse(order['total_price']?.toString() ?? '0') ?? 0.0;
                  final status = order['status']?.toString() ?? 'waitingForPricing';
                  final assignedCourier = order['assigned_courier']?.toString() ?? 'لم يتم التعيين';
                  final adminMessage = order['admin_message']?.toString() ?? '';

                  // بيانات الدفع
                  final paymentMethod = order['payment_method']?.toString() ?? 'cash';
                  final paymentAccount = order['payment_account']?.toString() ?? '';
                  final paymentDisplay = (paymentMethod == 'cash' || paymentMethod == 'cash_on_delivery')
                      ? '💵 نقداً عند الاستلام (Cash)'
                      : '💳 محفظة إلكترونية ($paymentMethod) - حساب: $paymentAccount';

                  // 👈 الاعتماد على حالة الطلب في سوبابيس لمعرفة هل تم التسعير أم لا بشكل تلقائي ولحظي
                  bool isAlreadyPriced = status != 'waitingForPricing';

                  return AnimatedContainer(
                    key: ValueKey(orderId), // 👈 مفتاح فريد لمنع تداخل الحالة واختفاء المشاكل البصرية
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: Card(
                      color: Theme.of(context).colorScheme.surface,
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
                            Row(
                              children: [
                                const Icon(Icons.person, size: 16, color: AppConstants.gold),
                                const SizedBox(width: 6),
                                Text('العميل: $customerName', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.phone, size: 16, color: Colors.grey),
                                const SizedBox(width: 6),
                                Text('الهاتف: $phone', style: const TextStyle(color: Colors.white70)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 16, color: Colors.redAccent),
                                const SizedBox(width: 6),
                                Expanded(child: Text('العنوان: $address', style: const TextStyle(color: Colors.white70))),
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
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: (paymentMethod == 'cash' || paymentMethod == 'cash_on_delivery') ? Colors.green.withOpacity(0.15) : Colors.blue.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: (paymentMethod == 'cash' || paymentMethod == 'cash_on_delivery') ? Colors.green : Colors.blueAccent),
                              ),
                              child: Text(
                                'طريقة الدفع: $paymentDisplay',
                                style: TextStyle(
                                  color: (paymentMethod == 'cash' || paymentMethod == 'cash_on_delivery') ? Colors.greenAccent : Colors.lightBlueAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const Divider(height: 20, color: Colors.white12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('سعر المنتجات: $productsTotal ر.ي', style: const TextStyle(color: Colors.white70)),
                                Text('رسوم التوصيل: $deliveryFee ر.ي', style: const TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('الإجمالي الكلي: $totalPrice ر.ي', style: const TextStyle(fontWeight: FontWeight.bold, color: AppConstants.gold, fontSize: 15)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.delivery_dining, size: 16, color: Colors.amber),
                                const SizedBox(width: 6),
                                Text('المندوب: $assignedCourier', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            if (adminMessage.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('💬 حالة المشرف: $adminMessage', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                            const SizedBox(height: 14),

                            // --- زر تحديد أو تحديث رسوم التوصيل ---
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isAlreadyPriced ? Colors.blueGrey : AppConstants.gold,
                                  foregroundColor: isAlreadyPriced ? Colors.white : Colors.black,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: () => _showPricingDialog(context, appState, orderId, deliveryFee, assignedCourier),
                                icon: Icon(isAlreadyPriced ? Icons.edit : Icons.local_shipping),
                                child: Text(
                                  isAlreadyPriced ? 'تعديل رسوم التوصيل والمندوب 🔄' : 'تحديد رسوم التوصيل وإسناد المندوب 🚀', 
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  // --- نافذة إدخال رسوم التوصيل مع إرسال التنبيهات (مدعومة بالوقت الفعلي عبر Consumer) ---
  void _showPricingDialog(BuildContext context, AppState appState, dynamic orderId, double currentFee, String currentCourier) {
    final feeController = TextEditingController(text: currentFee > 0 ? currentFee.toString() : '');
    String? selectedCourier = currentCourier != 'لم يتم التعيين' ? currentCourier : null;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('تحديد رسوم التوصيل للطلب #$orderId', style: const TextStyle(color: AppConstants.gold, fontSize: 16)),
        content: Consumer<AppState>(
          builder: (context, state, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: feeController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'رسوم التوصيل (ر.ي)',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF121212),
                  ),
                ),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  value: selectedCourier,
                  dropdownColor: const Color(0xFF1E1E1E),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'اختر المندوب للتوصيل',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF121212),
                  ),
                  items: state.couriers.map<DropdownMenuItem<String>>((courier) {
                    String courierName = courier['name']?.toString() ?? 'مندوب';
                    return DropdownMenuItem<String>(
                      value: courierName,
                      child: Text(courierName, style: const TextStyle(color: Colors.white)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    selectedCourier = val;
                  },
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.gold, 
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              double fee = double.tryParse(feeController.text) ?? 0.0;
              if (fee <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('الرجاء إدخال رسوم توصيل صحيحة!')),
                );
                return;
              }
              if (selectedCourier == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('الرجاء اختيار مندوب للطلب!')),
                );
                return;
              }

              // 1. حفظ التحديثات في قاعدة البيانات عبر الـ Provider
              appState.setOrderDeliveryFee(orderId, fee, selectedCourier!);

              // 2. جلب بيانات الطلب المحدثة لإرسال الإشعارات بدقة
              final targetOrder = appState.orders.firstWhere(
                (o) => o['id'].toString() == orderId.toString(),
                orElse: () => {},
              );

              // 3. إرسال إشعار فوري للعميل باستخدام رقم الهاتف (Phone) كمعرف في جدول customers
              try {
                String customerPhone = targetOrder['phone']?.toString() ?? '';
                if (customerPhone.isNotEmpty) {
                  final custRes = await appState.supabase
                      .from('customers')
                      .select('onesignal_player_id')
                      .eq('phone', customerPhone)
                      .maybeSingle();

                  String? customerPlayerId = custRes?['onesignal_player_id']?.toString();
                  if (customerPlayerId != null && customerPlayerId.isNotEmpty) {
                    await NotificationService.sendNotificationToUser(
                      targetPlayerId: customerPlayerId,
                      title: 'تم تسعير طلبك #${orderId} 📦',
                      body: 'رسوم التوصيل: $fee ر.ي. قم بمراجعة السعر وقبول الطلب.',
                    );
                  }
                }
              } catch (e) {
                debugPrint('⚠️ خطأ في إرسال إشعار للعميل: $e');
              }

              // 4. إرسال إشعار للمندوب بأنه تم إسناد طلب جديد إليه
              try {
                String? courierPlayerId = await appState.getCourierPlayerIdByName(selectedCourier!);
                if (courierPlayerId != null && courierPlayerId.isNotEmpty) {
                  await NotificationService.sendNotificationToUser(
                    targetPlayerId: courierPlayerId,
                    title: 'طلب جديد مسند إليك 🛵',
                    body: 'تم إسناد الطلب #${orderId} إليك للتوصيل.',
                  );
                }
              } catch (e) {
                debugPrint('⚠️ خطأ في إرسال إشعار للمندوب: $e');
              }
              
              Navigator.pop(dialogContext);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم إرسال رسوم التوصيل وإسناد المندوب للعميل بنجاح! 🚀')),
              );
            },
            child: const Text('إرسال للعميل', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'waitingForPricing': return 'بانتظار التسعير';
      case 'pricingSentToCustomer': return 'تم إرسال السعر للعميل';
      case 'waitingCourierApproval': return 'بانتظار قبول المندوب';
      case 'onTheWay': return 'المندوب في الطريق';
      case 'arrived': return 'وصل المندوب';
      case 'delivered': return 'تم التسليم بنجاح';
      case 'cancelledByCustomer': return 'ملغي من العميل';
      default: return status;
    }
  }
}
