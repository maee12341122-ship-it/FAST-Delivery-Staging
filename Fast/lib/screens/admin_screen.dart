import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state.dart';
import 'package:fast/screens/chat_screen.dart';
import 'admin/admin_products_screen.dart';
import 'admin/admin_reports_screen.dart';
import 'admin_restaurants_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({Key? key}) : super(key: key);

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _selectedNavIndex = 0;

  final TextEditingController _courierNameController = TextEditingController();
  final TextEditingController _courierPhoneController = TextEditingController();
  final TextEditingController _courierUsernameController = TextEditingController();
  final TextEditingController _courierPasswordController = TextEditingController();

  final Map<String, TextEditingController> _feeControllers = {};

  @override
  void dispose() {
    _courierNameController.dispose();
    _courierPhoneController.dispose();
    _courierUsernameController.dispose();
    _courierPasswordController.dispose();
    for (var controller in _feeControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _getArabicStatus(String status) {
    switch (status) {
      case 'waitingForPricing': return '⏳ بانتظار التسعير';
      case 'pricingSentToCustomer': return '🔔 بانتظار موافقة العميل';
      case 'waitingCourierApproval': return '🛵 بانتظار قبول المندوب';
      case 'onTheWay': return '🟢 المندوب في الطريق';
      case 'arrived': return '📍 المندوب وصل لموقع العميل';
      case 'delivered': return '✅ تم التسليم';
      case 'cancelledByCustomer': return '❌ ملغى من العميل';
      default: return status;
    }
  }

  // 🌟 نافذة عرض تقييمات وملاحظات المطاعم للمشرف
  void _showRestaurantRatingsDialog(BuildContext context) async {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.star, color: Colors.amber),
              SizedBox(width: 8),
              Text('تقييمات وملاحظات المطاعم ⭐', style: TextStyle(color: Colors.amber, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: FutureBuilder(
              future: Supabase.instance.client
                  .from('restaurant_ratings')
                  .select()
                  .order('created_at', ascending: false),
              builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.amber));
                }
                if (snapshot.hasError) {
                  return Center(child: Text('خطأ في جلب التقييمات: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                }
                final List<dynamic> ratings = snapshot.data ?? [];
                if (ratings.isEmpty) {
                  return const Center(child: Text('لا توجد تقييمات مطاعم مسجلة حتى الآن 📭', style: TextStyle(color: Colors.grey)));
                }
                return ListView.builder(
                  itemCount: ratings.length,
                  itemBuilder: (context, index) {
                    final r = ratings[index] as Map<String, dynamic>;
                    return Card(
                      color: const Color(0xFF121212),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.amber.withOpacity(0.3)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('🍽️ ${r['restaurant_name'] ?? 'مطعم'}', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
                                Row(
                                  children: [
                                    const Icon(Icons.star, color: Colors.amber, size: 16),
                                    const SizedBox(width: 4),
                                    Text('${r['rating'] ?? 5.0}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('📦 رقم الطلب: #${r['order_id']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            Text('📞 هاتف العميل: ${r['customer_phone'] ?? 'غير معروف'}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            if (r['review_text'] != null && r['review_text'].toString().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('💬 الملاحظة: "${r['review_text']}"', style: const TextStyle(color: Colors.amberAccent, fontSize: 13)),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    final List<Widget> adminPages = [
      _buildOrdersManagement(appState),
      _buildProductsManagement(appState),
      _buildCouriersManagement(appState),
      _buildSettingsTab(appState),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          elevation: 2,
          title: const Text('لوحة تحكم المشرف - FAST', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              tooltip: 'تسجيل خروج المشرف',
              onPressed: () {
                appState.logoutAdmin();
                Navigator.pop(context);
              },
            ),
          ],
        ),
        body: adminPages[_selectedNavIndex],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedNavIndex,
          onTap: (index) => setState(() => _selectedNavIndex = index),
          backgroundColor: const Color(0xFF1E1E1E),
          selectedItemColor: Colors.amber,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'الطلبات'),
            BottomNavigationBarItem(icon: Icon(Icons.fastfood), label: 'المنتجات'),
            BottomNavigationBarItem(icon: Icon(Icons.delivery_dining), label: 'المناديب'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'الإعدادات'),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersManagement(AppState appState) {
    if (appState.orders.isEmpty) {
      return const Center(child: Text('لا توجد طلبات جديدة حالياً 📦', style: TextStyle(color: Colors.grey, fontSize: 15)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: appState.orders.length,
      itemBuilder: (context, index) {
        final order = appState.orders[index];
        final orderId = order['id'].toString();
        final rawStatus = order['status'] ?? '';
        final arabicStatus = _getArabicStatus(rawStatus);
        final assignedCourier = order['assigned_courier']?.toString() ?? 'لم يتم التعيين';

        final paymentMethod = order['payment_method'] ?? 'cash';
        final paymentAccount = order['payment_account'] ?? '';
        final paymentDisplay = (paymentMethod == 'cash' || paymentMethod == 'cash_on_delivery')
            ? '💵 نقداً عند الاستلام'
            : '💳 محفظة ($paymentMethod) - حساب: $paymentAccount';

        final bool isLocked = rawStatus != 'waitingForPricing' && rawStatus != 'pricingSentToCustomer';

        if (!_feeControllers.containsKey(orderId)) {
          _feeControllers[orderId] = TextEditingController(text: order['delivery_fee']?.toString() ?? '0');
        }

        return Card(
          color: const Color(0xFF1E1E1E),
          margin: const EdgeInsets.symmetric(vertical: 8),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isLocked ? Colors.green.withOpacity(0.4) : Colors.amber.withOpacity(0.3), width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('طلب #$orderId', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isLocked ? Colors.green.withOpacity(0.2) : Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isLocked ? Colors.green : Colors.amber.withOpacity(0.3)),
                      ),
                      child: Text(arabicStatus, style: TextStyle(color: isLocked ? Colors.greenAccent : Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 20),
                Text('👤 العميل: ${order['customer_name']} (${order['phone']})', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('📍 العنوان: ${order['address']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text('🛒 المنتجات: ${order['items_description']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text('💰 سعر المنتجات: ${order['products_total']} ر.ي', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                  child: Text('طريقة الدفع: $paymentDisplay', style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                Text('🛵 المندوب الحالي: $assignedCourier', style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey[800],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.chat, size: 16, color: Colors.amber),
                        label: const Text('شات العميل', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(orderId: orderId, userRole: 'admin', targetChat: 'admin_customer'),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo[900],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.delivery_dining, size: 16, color: Colors.amber),
                        label: const Text('شات المندوب', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(orderId: orderId, userRole: 'admin', targetChat: 'admin_courier'),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _feeControllers[orderId],
                        keyboardType: TextInputType.number,
                        enabled: !isLocked,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: isLocked ? 'رسوم التوصيل (مقفل 🔒)' : 'رسوم التوصيل (ر.ي)',
                          labelStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF121212),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        dropdownColor: const Color(0xFF1E1E1E),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: isLocked ? 'المندوب (مقفل 🔒)' : 'اختر المندوب',
                          labelStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF121212),
                          border: const OutlineInputBorder(),
                        ),
                        value: appState.couriers.any((c) => c['name'] == order['assigned_courier'])
                            ? order['assigned_courier']
                            : null,
                        items: appState.couriers.map<DropdownMenuItem<String>>((courier) {
                          return DropdownMenuItem<String>(
                            value: courier['name'].toString(),
                            child: Text(courier['name'].toString(), style: const TextStyle(color: Colors.white)),
                          );
                        }).toList(),
                        onChanged: isLocked ? null : (val) {
                          setState(() {
                            order['assigned_courier'] = val;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isLocked ? Colors.grey[800] : Colors.amber,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isLocked ? null : () async {
                    final fee = double.tryParse(_feeControllers[orderId]?.text ?? '0') ?? 0.0;
                    final courierName = order['assigned_courier'] ?? 'لم يتم التعيين';
                    if (courierName == 'لم يتم التعيين') {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء اختيار مندوب أولاً')));
                      return;
                    }
                    
                    appState.setOrderDeliveryFee(orderId, fee, courierName);

                    try {
                      final customerPhone = order['phone']?.toString() ?? '';
                      if (customerPhone.isNotEmpty) {
                        String? customerPlayerId = await appState.getPlayerIdForUser(customerPhone, 'customers');
                        if (customerPlayerId != null && customerPlayerId.isNotEmpty) {
                          await appState.sendAutoNotification(
                            targetPlayerId: customerPlayerId,
                            title: 'تم تحديث طلبك #$orderId 💰',
                            body: 'تم تحديد رسوم التوصيل ($fee ر.ي). يرجى تأكيد الطلب للمتابعة!',
                          );
                        }
                      }
                    } catch (e) {
                      debugPrint('⚠️ خطأ في إرسال الإشعار التلقائي للعميل: $e');
                    }

                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديد الرسوم وإرسال الإشعار للعميل بنجاح! ✅')));
                  },
                  child: Text(
                    isLocked ? 'الطلب مؤكد ومقفل 🔒' : 'إرسال التسعيرة وإسناد الطلب للمندوب 🚀',
                    style: TextStyle(color: isLocked ? Colors.grey : Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductsManagement(AppState appState) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.restaurant_menu, size: 75, color: Colors.amber),
          const SizedBox(height: 16),
          const Text(
            'إدارة وتعديل منتجات وأصناف المتجر 🍔',
            style: TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          const Text(
            'تحكم كامل بقائمة الطعام والسلع: تعديل الأسعار، تبديل حالة التوفر (متوفر/غير متوفر)، حذف أو إضافة منتجات جديدة بكل سهولة.',
            style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 35),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AdminProductsScreen()),
              );
            },
            icon: const Icon(Icons.edit_note, size: 22),
            label: const Text('فتح لوحة إدارة المنتجات والأصناف 🚀', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ],
      ),
    );
  }

  Widget _buildCouriersManagement(AppState appState) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          const Text('حسابات المناديب ومستحقات المشرف (20%)', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (appState.couriers.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: Text('لا يوجد مناديب مسجلين حالياً', style: TextStyle(color: Colors.grey))))
          else
            ...appState.couriers.map((courier) {
              final courierName = courier['name'].toString();
              final courierId = courier['id']?.toString() ?? courier['delivery_man_id']?.toString() ?? '';
              double totalDeliveryFees = 0.0;
              int completedOrdersCount = 0;
              for (var order in appState.orders) {
                if (order['assigned_courier'] == courierName && order['status'] == 'delivered') {
                  completedOrdersCount++;
                  totalDeliveryFees += double.tryParse(order['delivery_fee']?.toString() ?? '0') ?? 0.0;
                }
              }
              double adminCommission = totalDeliveryFees * 0.20;
              return Card(
                color: const Color(0xFF1E1E1E),
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.amber.withOpacity(0.3))),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('🛵 المندوب: $courierName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                                child: Text('العمولة: ${adminCommission.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.notifications_active, color: Colors.amberAccent, size: 20),
                                tooltip: 'ربط وتحديث OneSignal Player ID للمندوب',
                                onPressed: () async {
                                  try {
                                    String? playerId = OneSignal.User.pushSubscription.id;
                                    if (playerId != null && playerId.isNotEmpty && courierId.isNotEmpty) {
                                      await Supabase.instance.client
                                          .from('couriers')
                                          .update({'onesignal_player_id': playerId})
                                          .eq('id', courierId);
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
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white12),
                      Text('📞 الهاتف: ${courier['phone'] ?? 'غير محدد'}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      Text('📦 الطلبات المكتملة: $completedOrdersCount', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      Text('💰 إجمالي دخل التوصيل: ${totalDeliveryFees.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 6),
                      Text('📌 المبلغ الواجب تسليمه للإدارة (20%): ${adminCommission.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                ),
              );
            }).toList(),
          const SizedBox(height: 25),
          const Divider(color: Colors.amber),
          const SizedBox(height: 10),
          const Text('إضافة مندوب توصيل جديد', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          TextField(controller: _courierNameController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'اسم المندوب الكامل', labelStyle: TextStyle(color: Colors.grey), filled: true, fillColor: Color(0xFF1E1E1E), border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _courierPhoneController, keyboardType: TextInputType.phone, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'رقم الهاتف', labelStyle: TextStyle(color: Colors.grey), filled: true, fillColor: Color(0xFF1E1E1E), border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _courierUsernameController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'اسم المستخدم للدخول', labelStyle: TextStyle(color: Colors.grey), filled: true, fillColor: Color(0xFF1E1E1E), border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _courierPasswordController, obscureText: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'كلمة المرور', labelStyle: TextStyle(color: Colors.grey), filled: true, fillColor: Color(0xFF1E1E1E), border: OutlineInputBorder())),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, minimumSize: const Size(double.infinity, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              if (_courierNameController.text.isNotEmpty && _courierUsernameController.text.isNotEmpty) {
                await appState.addCourier(_courierNameController.text, _courierPhoneController.text, _courierUsernameController.text, _courierPasswordController.text);
                
                _courierNameController.clear();
                _courierPhoneController.clear();
                _courierUsernameController.clear();
                _courierPasswordController.clear();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة المندوب بنجاح! 🛵')));
              }
            },
            child: const Text('حفظ المندوب', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab(AppState appState) {
    final startController = TextEditingController(text: appState.startHour.toString());
    final endController = TextEditingController(text: appState.endHour.toString());

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          const Text('إعدادات أوقات الدوام الرسمي للمتجر', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          TextField(controller: startController, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'ساعة الفتح', labelStyle: TextStyle(color: Colors.grey), filled: true, fillColor: Color(0xFF1E1E1E), border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: endController, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'ساعة الإغلاق', labelStyle: TextStyle(color: Colors.grey), filled: true, fillColor: Color(0xFF1E1E1E), border: OutlineInputBorder())),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, minimumSize: const Size(double.infinity, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              final start = int.tryParse(startController.text) ?? 8;
              final end = int.tryParse(endController.text) ?? 24;
              appState.updateStoreSettings(start, end);

              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث أوقات الدوام وحفظها سحابياً بنجاح! ✅')));
            },
            child: const Text('حفظ وتحديث أوقات الدوام', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 30),
          const Divider(color: Colors.white24),
          const SizedBox(height: 15),
          const Text('تقارير وأرباح المتجر والتوصيل', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AdminReportsScreen()),
              );
            },
            icon: const Icon(Icons.analytics, size: 22),
            label: const Text('عرض تقارير الأرباح والمبيعات الشاملة 📈', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(height: 12),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey[800],
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AdminRestaurantsScreen()),
              );
            },
            icon: const Icon(Icons.storefront, size: 22, color: Colors.amber),
            label: const Text('إدارة المطاعم ومبيعاتها 🍽️', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(height: 12),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo[900],
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: BorderSide(color: Colors.amber.withOpacity(0.5)),
            ),
            onPressed: () => _showRestaurantRatingsDialog(context),
            icon: const Icon(Icons.star_rate, size: 22, color: Colors.amber),
            label: const Text('عرض تقييمات وملاحظات المطاعم ⭐', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
