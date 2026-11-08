import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart'; // 👈 لاستخدام زر فتح الخرائط بسلاسة
import 'package:onesignal_flutter/onesignal_flutter.dart'; // 👈 استيراد مكتبة OneSignal لتحديث الـ Player ID
import 'package:supabase_flutter/supabase_flutter.dart'; // 👈 استيراد سوبابيس لحفظ المعرّف
import '../providers/app_state.dart';
import 'package:fast/screens/chat_screen.dart';

class CourierScreen extends StatefulWidget {
  const CourierScreen({Key? key}) : super(key: key);

  @override
  State<CourierScreen> createState() => _CourierScreenState();
}

class _CourierScreenState extends State<CourierScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 🗺️ دالة لفتح خرائط جوجل باستخدام العنوان النصي أو رابط البحث
  Future<void> _openMap(String address) async {
    final query = Uri.encodeComponent(address.isNotEmpty ? address : 'Taiz, Yemen');
    final googleMapsUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    
    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح الخريطة حالياً')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final courier = appState.currentCourier;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          elevation: 2,
          title: Text(
            courier == null ? 'تسجيل دخول الكابتن' : 'لوحة المندوب: ${courier['name']}', 
            style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          actions: [
            if (courier != null)
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.redAccent),
                tooltip: 'تسجيل الخروج',
                onPressed: () => appState.logoutCourier(),
              ),
          ],
        ),
        body: courier == null
            ? Padding(
                padding: const EdgeInsets.all(20.0),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.1),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.amber.withOpacity(0.3)),
                          ),
                          child: const Icon(Icons.two_wheeler, size: 60, color: Colors.amber),
                        ),
                        const SizedBox(height: 24),
                        const Text('بوابة تسجيل دخول الكابتن', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('أدخل بيانات الاعتماد الخاصة بك للوصول للطلبات', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        const SizedBox(height: 30),
                        TextField(
                          controller: _usernameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'اسم المستخدم',
                            labelStyle: TextStyle(color: Colors.grey),
                            filled: true,
                            fillColor: Color(0xFF1E1E1E),
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person_outline, color: Colors.amber),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'كلمة السر',
                            labelStyle: TextStyle(color: Colors.grey),
                            filled: true,
                            fillColor: Color(0xFF1E1E1E),
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock_outline, color: Colors.amber),
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber, 
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            bool success = await appState.loginCourier(_usernameController.text.trim(), _passwordController.text.trim());
                            if (success) {
                              // 👈 [تحديث OneSignal Player ID للمندوب تلقائياً عند تسجيل الدخول الناجح]
                              try {
                                String? playerId = OneSignal.User.pushSubscription.id;
                                if (playerId != null && playerId.isNotEmpty && appState.currentCourier != null) {
                                  String courierId = appState.currentCourier!['id']?.toString() ?? appState.currentCourier!['delivery_man_id']?.toString() ?? '';
                                  if (courierId.isNotEmpty) {
                                    await Supabase.instance.client
                                        .from('couriers')
                                        .update({'onesignal_player_id': playerId})
                                        .eq('id', courierId);
                                    debugPrint('✅ تم تحديث OneSignal Player ID للمندوب بنجاح: $playerId');
                                  }
                                }
                              } catch (e) {
                                debugPrint('⚠️ خطأ في تحديث Player ID للمندوب: $e');
                              }
                            } else {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('فشل الدخول: إما بيانات غير صحيحة أو أن الحساب مفتوح في جلسة أخرى حالياً!')),
                                );
                              }
                            }
                          },
                          child: const Text('دخول لوحة الطلبات 🚀', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : _buildCourierOrdersList(appState, courier),
      ),
    );
  }

  Widget _buildCourierOrdersList(AppState appState, Map<String, dynamic> courier) {
    // 🟢 فلترة ذكية لا تتأثر بحالة الأحرف (Capital/Small) أو المسافات الزائدة
    final String courierName = (courier['name'] ?? '').toString().trim().toLowerCase();
    final String courierId = (courier['id'] ?? '').toString().trim();

    final myOrders = appState.orders.where((o) {
      final assigned = (o['assigned_courier'] ?? '').toString().trim().toLowerCase();
      return assigned == courierName || assigned == courierId || assigned.contains(courierName);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E), 
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Colors.amber,
                      radius: 18,
                      child: Icon(Icons.delivery_dining, color: Colors.black, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text('الكابتن: ${courier['name']}', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('طلبات اليوم: ${myOrders.length}', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Expanded(
            child: myOrders.isEmpty
                ? const Center(child: Text('لا توجد طلبات مسندة لك حالياً 📦', style: TextStyle(color: Colors.grey, fontSize: 15)))
                : ListView.builder(
                    itemCount: myOrders.length,
                    itemBuilder: (context, index) {
                      final order = myOrders[index];
                      final orderId = order['id'].toString();
                      final String customerAddress = order['address'] ?? '';
                      final String orderStatus = order['status'] ?? '';

                      return Card(
                        color: const Color(0xFF1E1E1E),
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.amber.withOpacity(0.2)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('طلب #$orderId', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                                  IconButton(
                                    style: IconButton.styleFrom(backgroundColor: Colors.blueGrey[800]),
                                    icon: const Icon(Icons.chat, color: Colors.amber, size: 20),
                                    tooltip: 'مراسلة المشرف',
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ChatScreen(
                                            orderId: orderId,
                                            userRole: 'courier',
                                            targetChat: 'admin_courier',
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const Divider(color: Colors.white12, height: 16),
                              Row(
                                children: [
                                  const Icon(Icons.location_on, size: 16, color: Colors.redAccent),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text('العنوان: $customerAddress', style: const TextStyle(color: Colors.white70, fontSize: 13))),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                height: 36,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.amber),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.map, color: Colors.amber, size: 16),
                                  label: const Text('فتح الموقع في خرائط جوجل 🗺️', style: TextStyle(color: Colors.amber, fontSize: 12)),
                                  onPressed: () => _openMap(customerAddress),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.shopping_bag, size: 16, color: Colors.amberAccent),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text('المنتجات: ${order['items_description'] ?? order['items_desc'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 13))),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text('💰 الإجمالي المطلوب: ${order['total_price'] ?? order['total_amount'] ?? 0} ر.ي', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text('📌 الحالة: ${appState.getArabicStatus(orderStatus)}', style: const TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                              const Divider(color: Colors.white12, height: 20),

                              if (orderStatus == 'waitingCourierApproval' || orderStatus == 'approvedByCustomer') ...[
                                const Text('هل تقبل توصيل هذا الطلب؟', style: TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green, 
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        icon: const Icon(Icons.check, size: 18),
                                        onPressed: () {
                                          appState.courierRespondToOrder(orderId, true);
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('قَبِلت الطلب بنجاح 🟢')));
                                        },
                                        label: const Text('قبول الطلب', style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red, 
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        icon: const Icon(Icons.close, size: 18),
                                        onPressed: () {
                                          appState.courierRespondToOrder(orderId, false);
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفض الطلب وإعادته للإدارة 🔴')));
                                        },
                                        label: const Text('رفض الطلب', style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                  ],
                                ),
                              ]
                              else if (orderStatus == 'acceptedByCourier' || orderStatus == 'onTheWay') ...[
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent, 
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(double.infinity, 44),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.navigation),
                                  onPressed: () {
                                    appState.courierUpdateArrival(orderId);
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال إشعار الوصول للعميل والمشرف! 📍')));
                                  },
                                  label: const Text('هل وصلت إلى العميل؟ (نعم، وصلت)', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ]
                              else if (orderStatus == 'arrivedToCustomer' || orderStatus == 'arrived') ...[
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green, 
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(double.infinity, 44),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.task_alt),
                                  onPressed: () {
                                    appState.markOrderDelivered(orderId);
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تأكيد تسليم الطلب بنجاح! ✅')));
                                  },
                                  label: const Text('تم التسليم ✅', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ]
                              else ...[
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('ملاحظة: ${order['admin_message'] ?? ''}', style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ],
      ),
    );
  }
}
