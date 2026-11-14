import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/constants.dart';
import '../widgets/empty_state.dart';
import '../services/notification_service.dart';

class AdminOrdersScreen extends StatefulWidget {
  final VoidCallback? onOpenDrawer;
  const AdminOrdersScreen({super.key, this.onOpenDrawer});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final orders = context.watch<AppState>().orders;
    final appState = context.read<AppState>();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          leading: widget.onOpenDrawer == null ? null : IconButton(icon: const Icon(Icons.menu), onPressed: widget.onOpenDrawer),
          title: const Text('لوحة تحكم المشرف - الطلبات والدفعات 📦', style: TextStyle(color: AppConstants.gold)),
          backgroundColor: const Color(0xFF1E1E1E),
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // 🛵 قسم إدارة المناديب، حالاتهم (متاح/مشغول)، وأرباحهم وعمولاتهم
            _buildCouriersManagementSection(appState),
            const SizedBox(height: 16),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 12),
            const Text(
              'طلبات العملاء الواردة 🛒',
              style: TextStyle(color: AppConstants.gold, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            orders.isEmpty
                ? const EmptyState(
              message: 'لا توجد طلبات جديدة واردة حتى الآن\nالطلبات ستظهر هنا فور إرسالها من العملاء 📦',
              icon: Icons.admin_panel_settings_outlined,
            )
                : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index];

                final orderId = order['id']?.toString() ?? '';
                final customerName = order['customer_name']?.toString() ?? order['customerName']?.toString() ?? 'عميل';
                final phone = order['phone']?.toString() ?? '';
                final address = order['address']?.toString() ?? '';
                final itemsDesc = order['items_description']?.toString() ?? order['items_desc']?.toString() ?? order['itemsdesc']?.toString() ?? 'لا توجد تفاصيل';

                // 🎯 الاعتماد المطابق لبنية جدول orders في قاعدة البيانات
                final productsTotal = double.tryParse(order['items_price']?.toString() ?? order['products_total']?.toString() ?? '0') ?? 0.0;
                final deliveryFee = double.tryParse(order['delivery_fee']?.toString() ?? '0') ?? 0.0;

                final double dbTotalAmount = double.tryParse(order['total_amount']?.toString() ?? order['total_price']?.toString() ?? '0') ?? 0.0;
                final totalPrice = dbTotalAmount > 0 ? dbTotalAmount : (productsTotal + deliveryFee);

                final status = order['status']?.toString() ?? 'waitingForPricing';
                final assignedCourier = order['assigned_courier']?.toString() ?? 'لم يتم التعيين';
                final adminMessage = order['admin_message']?.toString() ?? '';

                final paymentMethod = order['payment_method']?.toString() ?? 'cash';
                final paymentAccount = order['payment_account']?.toString() ?? '';
                final paymentDisplay = (paymentMethod == 'cash' || paymentMethod == 'cash_on_delivery')
                    ? '💵 نقداً عند الاستلام (Cash)'
                    : '💳 محفظة إلكترونية ($paymentMethod) - حساب: $paymentAccount';

                bool isAlreadyPriced = status != 'waitingForPricing';

                // 🌟 تقييم المطعم المرتبط بالطلب إن وجد
                final restaurantRating = order['restaurant_rating'];
                final restaurantComment = order['restaurant_rating_comment']?.toString() ?? order['restaurant_review']?.toString();

                return AnimatedContainer(
                  key: ValueKey(orderId),
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

                          // 💰 عرض الأسعار المفصل (سعر المنتجات + رسوم التوصيل = الإجمالي الكلي)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('سعر المنتجات: ${productsTotal.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.white70)),
                                    Text('رسوم التوصيل: ${deliveryFee.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const Divider(color: Colors.white12, height: 8),
                                Text('الإجمالي الكلي: ${totalPrice.toStringAsFixed(0)} ر.ي', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent, fontSize: 15)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
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

                          // 🌟 عرض تقييم المطعم الصحيح
                          if (restaurantRating != null && restaurantRating > 0) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: Row(
                                children: [
                                  const Icon(Icons.restaurant, color: AppConstants.gold, size: 16),
                                  const SizedBox(width: 6),
                                  Text('تقييم المطعم: $restaurantRating / 5', style: const TextStyle(color: AppConstants.gold, fontSize: 12, fontWeight: FontWeight.bold)),
                                  if (restaurantComment != null && restaurantComment.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Expanded(child: Text('($restaurantComment)', style: const TextStyle(color: Colors.white70, fontSize: 11), overflow: TextOverflow.ellipsis)),
                                  ]
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isAlreadyPriced ? Colors.blueGrey : AppConstants.gold,
                                foregroundColor: isAlreadyPriced ? Colors.white : Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () => _showPricingDialog(context, appState, order, orderId, deliveryFee),
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
          ],
        ),
      ),
    );
  }

  // 🛵 قسم إدارة المناديب، حالاتهم (متاح/مشغول)، وإحصائيات طلباتهم وأرباحهم وعمولاتهم
  Widget _buildCouriersManagementSection(AppState appState) {
    final couriers = appState.couriers;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppConstants.gold.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('قائمة المناديب وحالاتهم والأرباح 🛵', style: TextStyle(color: AppConstants.gold, fontSize: 15, fontWeight: FontWeight.bold)),
              Text('العدد: ${couriers.length}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          couriers.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(12.0), child: Text('لا توجد مناديب مسجلين حالياً', style: TextStyle(color: Colors.grey))))
              : ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: couriers.length,
            itemBuilder: (context, index) {
              final courier = couriers[index];
              final courierName = courier['name']?.toString() ?? 'مندوب';
              final courierId = courier['id']?.toString() ?? '';

              // حساب عدد الطلبات المكتملة وأرباح هذا المندوب
              int completedCount = 0;
              double totalEarnings = 0.0;
              for (var o in appState.orders) {
                final assigned = (o['assigned_courier'] ?? '').toString().trim().toLowerCase();
                if ((assigned == courierName.toLowerCase() || assigned == courierId.toLowerCase()) && o['status'] == 'delivered') {
                  completedCount++;
                  totalEarnings += double.tryParse(o['delivery_fee']?.toString() ?? '0') ?? 0.0;
                }
              }
              double adminCommission = totalEarnings * 0.20;
              double courierNet = totalEarnings - adminCommission;

              bool isBusy = courier['is_busy'] == true || courier['status'] == 'busy';

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isBusy ? Colors.redAccent.withOpacity(0.4) : Colors.green.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(courierName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isBusy ? Colors.red.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isBusy ? '🔴 مشغول' : '🟢 متاح',
                                  style: TextStyle(color: isBusy ? Colors.redAccent : Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('الطلبات المكتملة: $completedCount | إجمالي التوصيل: ${totalEarnings.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          Text('العمولة (20%): ${adminCommission.toStringAsFixed(0)} | صافي المندوب: ${courierNet.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: AppConstants.gold, fontSize: 11)),
                        ],
                      ),
                    ),
                    // مفتاح لتغيير حالة المندوب (متاح / مشغول) مباشرة
                    Switch(
                      value: isBusy,
                      activeColor: Colors.redAccent,
                      inactiveTrackColor: Colors.green,
                      onChanged: (val) async {
                        try {
                          await appState.supabase
                              .from('couriers')
                              .update({'is_busy': val, 'status': val ? 'busy' : 'available'})
                              .eq('id', courierId);
                          appState.fetchCouriers();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تم تحديث حالة المندوب $courierName بنجاح!')),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تعذر تحديث الحالة: $e')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showPricingDialog(BuildContext context, AppState appState, Map<String, dynamic> order, dynamic orderId, double currentFee) {
    final feeController = TextEditingController(text: currentFee > 0 ? currentFee.toString() : '');
    String? selectedCourier = order['assigned_courier'] != 'لم يتم التعيين' ? order['assigned_courier'] : null;

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
                // 🛵 عرض المناديب مع حالتهم (متاح / مشغول) داخل قائمة الاختيار
                DropdownButtonFormField<String>(
                  value: selectedCourier,
                  dropdownColor: const Color(0xFF1E1E1E),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'اختر المندوب (متاح / مشغول)',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF121212),
                  ),
                  items: state.couriers.map<DropdownMenuItem<String>>((courier) {
                    String courierName = courier['name']?.toString() ?? 'مندوب';
                    bool isBusy = courier['is_busy'] == true || courier['status'] == 'busy';
                    return DropdownMenuItem<String>(
                      value: courierName,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(courierName, style: const TextStyle(color: Colors.white)),
                          Text(
                            isBusy ? '(مشغول 🔴)' : '(متاح 🟢)',
                            style: TextStyle(color: isBusy ? Colors.redAccent : Colors.greenAccent, fontSize: 11),
                          ),
                        ],
                      ),
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

              // 1. حفظ التحديثات في قاعدة البيانات
              appState.setOrderDeliveryFee(orderId, fee, selectedCourier!);

              // 2. إرسال إشعار للعميل عبر رقم الهاتف
              try {
                String customerPhone = order['phone']?.toString() ?? '';
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

              // 3. إرسال إشعار للمندوب
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