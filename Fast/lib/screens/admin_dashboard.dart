import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart'; // 👈 استيراد مكتبة OneSignal
import 'package:supabase_flutter/supabase_flutter.dart'; // 👈 استيراد سوبابيس لتحديث الـ Player ID

import '../models/delivery_model.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import '../providers/app_state.dart';
import '../utils/constants.dart';
import '../utils/validators.dart';
import '../widgets/empty_state.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('إدارة تعز إكسبرس - FAST', style: TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF1E1E1E),
            bottom: const TabBar(
              isScrollable: true,
              labelColor: AppConstants.gold,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppConstants.gold,
              tabs: [
                Tab(icon: Icon(Icons.shopping_bag), text: 'الطلبات'),
                Tab(icon: Icon(Icons.delivery_dining), text: 'المندوبون'),
                Tab(icon: Icon(Icons.inventory_2), text: 'المنتجات والإعدادات'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [AdminOrdersTab(), AdminCouriersTab(), AdminProductsSettingsTab()],
          ),
        ),
      ),
    );
  }
}

class AdminOrdersTab extends StatelessWidget {
  const AdminOrdersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<AppState>().orders
        .whereType()
        .map((row) => OrderModel.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    if (orders.isEmpty) return const EmptyState(message: 'لا توجد طلبات محفوظة حالياً 📦', icon: Icons.receipt_long);
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: orders.length,
      itemBuilder: (context, index) => _AdminOrderCard(order: orders[index]),
    );
  }
}

class _AdminOrderCard extends StatelessWidget {
  final OrderModel order;
  const _AdminOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final courier = state.couriers.whereType().map((row) => DeliveryModel(
      id: row['id']?.toString() ?? '', name: row['name']?.toString() ?? '',
      phone: row['phone']?.toString() ?? '',
      isAvailable: row['status']?.toString() == 'available',
      isEnabled: row['status']?.toString() != 'disabled',
    )).where((item) => item.name == order.assignedCourier).firstOrNull;
    
    // تفاصيل الدفع والمحافظ الإلكترونية
    final paymentMethod = order.paymentMethod ?? 'cash';
    final paymentAccount = order.paymentAccount ?? '';
    final paymentDisplay = (paymentMethod == 'cash' || paymentMethod == 'cash_on_delivery') 
        ? '💵 نقداً عند الاستلام' 
        : '💳 محفظة إلكترونية ($paymentMethod) - حساب: $paymentAccount';

    return Card(
      color: Theme.of(context).colorScheme.surface,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: AppConstants.gold.withOpacity(0.3))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('طلب #${order.id}', style: const TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold, fontSize: 16)),
                Text(OrderStatuses.label(order.status), style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
            const Divider(color: Colors.white12),
            Text('👤 العميل: ${order.customerName} • ${order.customerPhone}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('📍 العنوان: ${order.address.area} - ${order.address.details}', style: const TextStyle(color: Colors.white70)),
            if (order.address.hasCoordinates)
              Text('الإحداثيات: ${order.address.latitude}, ${order.address.longitude}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 8),
            ...order.items.map((item) => Text('• ${item.name} × ${item.quantity} = ${item.lineTotal} ر.ي', style: const TextStyle(color: Colors.white70, fontSize: 13))),
            const Divider(color: Colors.white12),
            Text('💰 المجموع: ${order.subtotal} + التوصيل: ${order.deliveryFee} = ${order.total} ر.ي', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
              child: Text('طريقة الدفع: $paymentDisplay', style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            if (courier != null) ...[
              const SizedBox(height: 4),
              Text('🛵 المندوب المسند: ${courier.name} • ${courier.phone}', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (order.status == OrderStatuses.pending)
                  _action(context, 'قبول الطلب', () => state.updateOrderStatus(order.id, OrderStatuses.accepted)),
                if (order.status == OrderStatuses.accepted)
                  _action(context, 'بدء التجهيز', () => state.updateOrderStatus(order.id, OrderStatuses.preparing)),
                if (order.status == OrderStatuses.preparing)
                  _action(context, 'جاهز للاستلام', () => state.updateOrderStatus(order.id, OrderStatuses.ready)),
                if (order.status == OrderStatuses.ready && order.deliveryManId == null)
                  _action(context, 'تعيين مندوب 🛵', () => _assignCourier(context, order.id)),
                if (order.status != OrderStatuses.delivered && order.status != OrderStatuses.cancelled)
                  _action(context, 'إلغاء الطلب ❌', () => _cancelOrder(context, order.id), danger: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(BuildContext context, String label, VoidCallback onPressed, {bool danger = false}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: danger ? Colors.red[900] : AppConstants.gold,
        foregroundColor: danger ? Colors.white : Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Future<void> _assignCourier(BuildContext context, String orderId) async {
    final state = context.read<AppState>();
    final available = state.couriers.whereType().map((row) => DeliveryModel(
      id: row['id']?.toString() ?? '', name: row['name']?.toString() ?? '',
      phone: row['phone']?.toString() ?? '', isAvailable: row['status']?.toString() == 'available',
      isEnabled: row['status']?.toString() != 'disabled',
    )).where((courier) => courier.canReceiveOrders).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد مندوب متاح حالياً. أضف مندوباً أو غيّر حالته!')));
      return;
    }
    final selectedId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('اختيار المندوب التوصيل', style: TextStyle(color: AppConstants.gold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: available
              .map((courier) => ListTile(
                    leading: const Icon(Icons.delivery_dining, color: AppConstants.gold),
                    title: Text(courier.name, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(courier.phone, style: const TextStyle(color: Colors.white70)),
                    onTap: () => Navigator.pop(dialogContext, courier.id),
                  ))
              .toList(),
        ),
      ),
    );
    if (selectedId == null || !context.mounted) return;
    try {
      state.assignOrderToCourier(orderId, selectedId);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تعيين الطلب للمندوب بنجاح! ✅')));
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _cancelOrder(BuildContext context, String orderId) async {
    final shouldCancel = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text('إلغاء الطلب', style: TextStyle(color: Colors.redAccent)),
            content: const Text('هل أنت متأكد من إلغاء هذا الطلب؟', style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('تراجع', style: TextStyle(color: Colors.grey))),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(dialogContext, true), 
                child: const Text('إلغاء الطلب'),
              ),
            ],
          ),
        ) ??
        false;
    if (shouldCancel && context.mounted) context.read<AppState>().updateOrderStatus(orderId, OrderStatuses.cancelled);
  }
}

class AdminCouriersTab extends StatelessWidget {
  const AdminCouriersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppConstants.gold,
        foregroundColor: Colors.black,
        onPressed: () => _addCourier(context),
        icon: const Icon(Icons.person_add),
        label: const Text('إضافة مندوب', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: state.couriers.isEmpty
          ? const EmptyState(message: 'لم تتم إضافة مندوبين بعد 🛵', icon: Icons.delivery_dining)
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 85, top: 8),
              itemCount: state.couriers.length,
              itemBuilder: (context, index) {
                final row = state.couriers[index] as Map;
                final courier = DeliveryModel(
                  id: row['id']?.toString() ?? '', name: row['name']?.toString() ?? '',
                  phone: row['phone']?.toString() ?? '', isAvailable: row['status']?.toString() == 'available',
                  isEnabled: row['status']?.toString() != 'disabled',
                  completedToday: (row['completed_orders'] as num?)?.toInt() ?? 0,
                );
                
                // حساب عمولة المشرف 20% وعدد الطلبات المكتملة
                double totalDeliveryFees = 0.0;
                int completedCount = 0;
                for (var order in state.orders) {
                  if (order is Map && order['assigned_courier']?.toString() == courier.name && order['status'] == OrderStatuses.delivered) {
                    completedCount++;
                    totalDeliveryFees += (double.tryParse(order['delivery_fee']?.toString() ?? '0') ?? 0.0);
                  }
                }
                double adminCommission = totalDeliveryFees * 0.20;

                return Card(
                  color: Theme.of(context).colorScheme.surface,
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: courier.canReceiveOrders ? Colors.green : Colors.red,
                      child: const Icon(Icons.delivery_dining, color: Colors.white),
                    ),
                    title: Text(courier.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      '📞 ${courier.phone}\n'
                      'الحالة: ${courier.isEnabled ? (courier.isAvailable ? 'متاح 🟢' : 'مشغول 🟡') : 'موقوف 🔴'}\n'
                      '📦 الطلبات المكتملة: $completedCount | عمولة المشرف (20%): ${adminCommission.toStringAsFixed(0)} ر.ي',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      color: const Color(0xFF1E1E1E),
                      onSelected: (value) async {
                        if (value == 'toggle') {
                          try {
                            state.updateCourier(courier.copyWith(isEnabled: !courier.isEnabled));
                          } catch (error) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
                          }
                        } else if (value == 'edit') {
                          _editCourier(context, courier);
                        } else if (value == 'available') {
                          state.setCourierAvailability(courier.id, !courier.isAvailable);
                        } else if (value == 'delete') {
                          state.removeCourier(courier.id);
                        } else if (value == 'update_token') {
                          try {
                            String? playerId = OneSignal.User.pushSubscription.id;
                            if (playerId != null && playerId.isNotEmpty) {
                              await Supabase.instance.client
                                  .from('couriers')
                                  .update({'onesignal_player_id': playerId})
                                  .eq('id', courier.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم تحديث OneSignal Player ID للمندوب بنجاح! 🔔')),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('لم يتم العثور على معرّف OneSignal للجهاز حالياً ❌')),
                              );
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('خطأ: $e')),
                            );
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('تعديل البيانات', style: TextStyle(color: Colors.white))),
                        PopupMenuItem(value: 'toggle', child: Text(courier.isEnabled ? 'تعطيل المندوب' : 'تفعيل المندوب', style: TextStyle(color: Colors.white))),
                        PopupMenuItem(value: 'available', child: Text(courier.isAvailable ? 'جعله مشغولاً' : 'جعله متاحاً', style: TextStyle(color: Colors.white))),
                        const PopupMenuItem(value: 'update_token', child: Text('ربط OneSignal Player ID 🔔', style: TextStyle(color: Colors.amberAccent))),
                        const PopupMenuItem(value: 'delete', child: Text('حذف المندوب', style: TextStyle(color: Colors.redAccent))),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _editCourier(BuildContext context, DeliveryModel courier) async {
    final nameController = TextEditingController(text: courier.name);
    final phoneController = TextEditingController(text: courier.phone);
    final formKey = GlobalKey<FormState>();

    // موجهات التركيز للانتقال السلس عبر الكيبورد
    final FocusNode nameFocus = FocusNode();
    final FocusNode phoneFocus = FocusNode();

    final saved = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => GestureDetector(
            onTap: () => FocusScope.of(dialogContext).unfocus(),
            child: AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text('تعديل بيانات المندوب', style: TextStyle(color: AppConstants.gold)),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      focusNode: nameFocus,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(dialogContext).requestFocus(phoneFocus),
                      decoration: const InputDecoration(labelText: 'اسم المندوب'),
                      validator: Validators.requiredText,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: phoneController,
                      focusNode: phoneFocus,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (formKey.currentState!.validate()) {
                          Navigator.pop(dialogContext, true);
                        }
                      },
                      decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                      validator: Validators.yemeniPhone,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء', style: TextStyle(color: Colors.grey))),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppConstants.gold, foregroundColor: Colors.black),
                  onPressed: () => Navigator.pop(dialogContext, formKey.currentState!.validate()),
                  child: const Text('حفظ'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (saved && context.mounted) {
      try {
        context.read<AppState>().updateCourier(courier.copyWith(
              name: nameController.text.trim(),
              phone: phoneController.text,
            ));
      } catch (error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
    nameController.dispose();
    phoneController.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
  }

  Future<void> _addCourier(BuildContext context) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    // موجهات التركيز للانتقال السلس عبر الكيبورد
    final FocusNode nameFocus = FocusNode();
    final FocusNode phoneFocus = FocusNode();
    final FocusNode usernameFocus = FocusNode();
    final FocusNode passwordFocus = FocusNode();

    final saved = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => GestureDetector(
            onTap: () => FocusScope.of(dialogContext).unfocus(),
            child: AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text('إضافة مندوب توصيل جديد', style: TextStyle(color: AppConstants.gold)),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      focusNode: nameFocus,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(dialogContext).requestFocus(phoneFocus),
                      decoration: const InputDecoration(labelText: 'اسم المندوب'),
                      validator: Validators.requiredText,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: phoneController,
                      focusNode: phoneFocus,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(dialogContext).requestFocus(usernameFocus),
                      decoration: const InputDecoration(labelText: 'رقم الهاتف اليمني'),
                      validator: Validators.yemeniPhone,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: usernameController,
                      focusNode: usernameFocus,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(dialogContext).requestFocus(passwordFocus),
                      decoration: const InputDecoration(labelText: 'اسم المستخدم'),
                      validator: Validators.requiredText,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: passwordController,
                      focusNode: passwordFocus,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (formKey.currentState!.validate()) {
                          Navigator.pop(dialogContext, true);
                        }
                      },
                      decoration: const InputDecoration(labelText: 'كلمة مرور مؤقتة (10 أحرف على الأقل)'),
                      validator: (v) => (v == null || v.length < 10) ? '10 أحرف على الأقل' : null,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء', style: TextStyle(color: Colors.grey))),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppConstants.gold, foregroundColor: Colors.black),
                  onPressed: () => Navigator.pop(dialogContext, formKey.currentState!.validate()),
                  child: const Text('حفظ'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (saved && context.mounted) {
      try {
        await context.read<AppState>().addCourier(
              nameController.text,
              phoneController.text,
              usernameController.text,
              passwordController.text,
            );
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة المندوب بنجاح! 🛵')));
      } catch (error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
    nameController.dispose();
    phoneController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
    usernameFocus.dispose();
    passwordFocus.dispose();
  }
}

class AdminProductsSettingsTab extends StatefulWidget {
  const AdminProductsSettingsTab({super.key});

  @override
  State<AdminProductsSettingsTab> createState() => _AdminProductsSettingsTabState();
}

class _AdminProductsSettingsTabState extends State<AdminProductsSettingsTab> {
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  late final TextEditingController _feeController;

  // موجهات التركيز لمدخلات إعدادات العمل
  final FocusNode _startFocus = FocusNode();
  final FocusNode _endFocus = FocusNode();
  final FocusNode _feeFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _startController = TextEditingController(text: state.workStartHour.toString());
    _endController = TextEditingController(text: state.workEndHour.toString());
    _feeController = TextEditingController(text: state.deliveryFee.toString());
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _feeController.dispose();
    _startFocus.dispose();
    _endFocus.dispose();
    _feeFocus.dispose();
    super.dispose();
  }

  // دالة حفظ إعدادات العمل
  Future<void> _saveSettings() async {
    final start = int.tryParse(_startController.text);
    final end = int.tryParse(_endController.text);
    final fee = int.tryParse(_feeController.text);
    if (start == null || end == null || fee == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء إدخال أرقام صحيحة.')));
      return;
    }
    try {
      context.read<AppState>().updateBusinessSettings(startHour: start, endHour: end, deliveryFee: fee);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات بنجاح! ✅')));
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(), // إغلاق الكيبورد بسلاسة عند الضغط خارج الحقول
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          const Text('أوقات الدوام ورسوم التوصيل الأساسية', style: TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startController,
                  focusNode: _startFocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).requestFocus(_endFocus),
                  decoration: const InputDecoration(labelText: 'بداية الدوام (0-23)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _endController,
                  focusNode: _endFocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).requestFocus(_feeFocus),
                  decoration: const InputDecoration(labelText: 'نهاية الدوام (1-24)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _feeController,
                  focusNode: _feeFocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _saveSettings(),
                  decoration: const InputDecoration(labelText: 'رسوم التوصيل'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppConstants.gold, foregroundColor: Colors.black),
            onPressed: _saveSettings,
            child: const Text('حفظ إعدادات العمل', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 32),
          Row(
            children: [
              const Expanded(child: Text('إدارة المنتجات والصور', style: TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold, fontSize: 16))),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppConstants.gold, foregroundColor: Colors.black),
                onPressed: () => _editProduct(context), 
                icon: const Icon(Icons.add), 
                label: const Text('إضافة منتج'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...state.products.map((product) => Card(
                color: Theme.of(context).colorScheme.surface,
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: product.imageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(product.imageUrl, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.fastfood, color: AppConstants.gold)),
                        )
                      : const Icon(Icons.fastfood, color: AppConstants.gold),
                  title: Text(product.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text('${product.restaurantName} • ${product.price} ر.ي • ${product.available ? 'متوفر 🟢' : 'غير متوفر 🔴'}', style: const TextStyle(color: Colors.white70)),
                  onTap: () => _editProduct(context, product: product),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () => state.removeProduct(product.id),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Future<void> _editProduct(BuildContext context, {ProductModel? product}) async {
    final nameController = TextEditingController(text: product?.name ?? '');
    final storeController = TextEditingController(text: product?.restaurantName ?? '');
    final priceController = TextEditingController(text: product?.price.toString() ?? '');
    final imageUrlController = TextEditingController(text: product?.imageUrl ?? '');
    bool isAvailable = product?.available ?? true;
    String category = product?.category ?? ProductCategories.groceries;

    // موجهات التركيز للانتقال السلس بين الحقول
    final FocusNode nameFocus = FocusNode();
    final FocusNode storeFocus = FocusNode();
    final FocusNode priceFocus = FocusNode();
    final FocusNode imageFocus = FocusNode();

    final saved = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => GestureDetector(
              onTap: () => FocusScope.of(dialogContext).unfocus(),
              child: AlertDialog(
                backgroundColor: const Color(0xFF1E1E1E),
                title: Text(product == null ? 'إضافة منتج جديد' : 'تعديل المنتج', style: const TextStyle(color: AppConstants.gold)),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        focusNode: nameFocus,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(dialogContext).requestFocus(storeFocus),
                        decoration: const InputDecoration(labelText: 'اسم المنتج'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: storeController,
                        focusNode: storeFocus,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(dialogContext).requestFocus(priceFocus),
                        decoration: const InputDecoration(labelText: 'اسم المتجر / المطعم'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: priceController,
                        focusNode: priceFocus,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(dialogContext).requestFocus(imageFocus),
                        decoration: const InputDecoration(labelText: 'السعر (ر.ي)'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: imageUrlController,
                        focusNode: imageFocus,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (nameController.text.trim().isNotEmpty &&
                              storeController.text.trim().isNotEmpty &&
                              int.tryParse(priceController.text) != null &&
                              int.parse(priceController.text) >= 0) {
                            Navigator.pop(dialogContext, true);
                          }
                        },
                        decoration: const InputDecoration(labelText: 'رابط صورة المنتج (Image URL)'),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('المنتج متوفر حالياً', style: TextStyle(color: Colors.white70)),
                        value: isAvailable,
                        onChanged: (value) => setDialogState(() => isAvailable = value),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: category,
                        dropdownColor: const Color(0xFF1E1E1E),
                        items: ProductCategories.all
                            .where((item) => item != ProductCategories.custom)
                            .map((item) => DropdownMenuItem(value: item, child: Text(ProductCategories.label(item), style: const TextStyle(color: Colors.white))))
                            .toList(),
                        onChanged: (value) => setDialogState(() => category = value ?? category),
                        decoration: const InputDecoration(labelText: 'القسم'),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء', style: TextStyle(color: Colors.grey))),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppConstants.gold, foregroundColor: Colors.black),
                    onPressed: () {
                      if (nameController.text.trim().isEmpty ||
                          storeController.text.trim().isEmpty ||
                          int.tryParse(priceController.text) == null ||
                          int.parse(priceController.text) < 0) return;
                      Navigator.pop(dialogContext, true);
                    },
                    child: const Text('حفظ'),
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;

    if (saved && context.mounted) {
      final state = context.read<AppState>();
      state.upsertProduct(ProductModel(
        id: product?.id ?? 'prod-${DateTime.now().microsecondsSinceEpoch}',
        name: nameController.text.trim(),
        restaurantName: storeController.text.trim(),
        category: category,
        price: int.parse(priceController.text).toDouble(),
        imageUrl: imageUrlController.text.trim(),
        unit: product?.unit ?? 'حبة',
        available: isAvailable,
      ));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ المنتج بنجاح! ✅')));
    }

    nameController.dispose();
    storeController.dispose();
    priceController.dispose();
    imageUrlController.dispose();
    nameFocus.dispose();
    storeFocus.dispose();
    priceFocus.dispose();
    imageFocus.dispose();
  }
}

extension _AdminFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
