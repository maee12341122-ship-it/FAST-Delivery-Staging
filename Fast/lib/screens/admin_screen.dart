import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state.dart';
import 'order_time_helper.dart';
import 'order_tracking_screen.dart';
import 'chat_screen.dart';
import 'admin/admin_products_screen.dart';
import 'admin/admin_reports_screen.dart';
import 'home_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  int _selectedNavIndex = 0;
  late TabController _ordersTabController;

  final Map<String, TextEditingController> _feeControllers = {};
  final Map<String, String> _selectedCouriersForOrder = {};
  final Set<String> _pricingOrderIds = {};
  final Set<String> _settlingCourierKeys = {};
  String _ordersPeriodFilter = 'all'; // all, today, custom
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  // المشاريع المنزلية الافتراضية المعتمدة في النظام
  final List> _defaultHomeProjects = [
    {
      'id': 'proj_enabati',
      'name': 'عنباتي',
      'category': 'مشاريع منزلية',
      'description': 'مشروع عنباتي للمنتجات والحلويات المنزلية',
      'is_active': true,
    },
    {
      'id': 'proj_twista',
      'name': 'TWISTA',
      'category': 'مشاريع منزلية',
      'description': 'مشروع TWISTA للمأكولات والوجبات المنزلية المميزة',
      'is_active': true,
    },
  ];

  @override
  void initState() {
    super.initState();
    _ordersTabController = TabController(length: 3, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verifyAdminSecurity();
    });
  }

  Future<void> _verifyAdminSecurity() async {
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final session = Supabase.instance.client.auth.currentSession;

      if (session != null &&
          session.user.appMetadata['role']?.toString() == 'admin') {
        appState.isAdminLoggedIn = true;
        return;
      }

      final currentPhone = appState.userProfile?['phone']?.toString() ?? '';

      if (currentPhone.isEmpty && !appState.isAdminLoggedIn) {
        _kickOutUnauthorizedUser('جلسة غير صالحة، يرجى تسجيل الدخول مجدداً ⚠️');
        return;
      }

      if (appState.isAdminLoggedIn) return;

      var cleanPhone = currentPhone.replaceAll(' ', '');
      if (cleanPhone.startsWith('+967')) cleanPhone = cleanPhone.substring(4);
      if (cleanPhone.startsWith('0')) cleanPhone = cleanPhone.substring(1);
      if (cleanPhone.startsWith('967')) cleanPhone = cleanPhone.substring(3);
      final formattedPhone = '+967$cleanPhone';

      final adminRes = await Supabase.instance.client
          .from('admins')
          .select('id, username, phone')
          .or('phone.eq.$cleanPhone,phone.eq.$formattedPhone')
          .maybeSingle();

      if (adminRes == null) {
        _kickOutUnauthorizedUser(
            'عذراً، لا تمتلك صلاحيات مشرف للوصول إلى هذه اللوحة 🚫');
      } else {
        appState.isAdminLoggedIn = true;
      }
    } catch (e) {
      debugPrint('❌ خطأ في التحقق الأمني للأدمن: $e');
    }
  }

  void _kickOutUnauthorizedUser(String message) {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
      (route) => false,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _ordersTabController.dispose();
    for (final controller in _feeControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _getArabicStatus(String status) {
    switch (status) {
      case 'waitingForPricing':
        return '⏳ بانتظار التسعير';
      case 'pricingSentToCustomer':
        return '🔔 بانتظار موافقة العميل';
      case 'waitingCourierApproval':
        return '🛵 بانتظار قبول المندوب';
      case 'acceptedByCourier':
        return '🚀 وافق المندوب';
      case 'onTheWay':
        return '🟢 المندوب في الطريق';
      case 'arrived':
      case 'arrivedToCustomer':
        return '📍 وصل المندوب للموقع';
      case 'delivered':
        return '✅ تم التسليم';
      case 'cancelled':
      case 'cancelledByCustomer':
        return '❌ ملغى';
      default:
        return status;
    }
  }

  bool _isCourierBusy(AppState appState, Map courier) {
    final courierName = (courier['name'] ?? courier['full_name'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final courierId = courier['id']?.toString().trim() ?? '';

    return appState.orders.any((o) {
      if (o is! Map) return false;
      final assigned =
          (o['assigned_courier'] ?? '').toString().trim().toLowerCase();
      final nameField =
          (o['courier_name'] ?? '').toString().trim().toLowerCase();
      final matchesCourier = (courierName.isNotEmpty &&
              (assigned == courierName || nameField == courierName)) ||
          (courierId.isNotEmpty && assigned == courierId);
      if (!matchesCourier) return false;
      final status = o['status']?.toString().trim() ?? '';
      return status == 'onTheWay' ||
          status == 'arrivedToCustomer' ||
          status == 'arrived';
    });
  }

  void _openAdminChatPicker(BuildContext context, String orderId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          orderId: orderId,
          userRole: 'admin',
          targetChat: 'unified_order_chat',
        ),
      ),
    );
  }

  void _handleAdminNotificationTap(
      BuildContext context, Map<String, dynamic> notification) {
    final additionalData = notification['additionalData'];
    final String? orderId = notification['order_id']?.toString() ??
        notification['related_id']?.toString() ??
        (additionalData is Map ? additionalData['order_id']?.toString() : null);

    if (orderId != null && orderId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => OrderTrackingScreen(orderIdParam: orderId)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('هذا الإشعار غير مرتبط برقم طلب معين 📭')),
      );
    }
  }

  // ==================== إدارة المشاريع المنزلية (عنباتي و TWISTA) ====================

  Future<List>> _fetchHomeProjectsList(
      AppState appState) async {
    try {
      final response = await Supabase.instance.client
          .from('home_projects')
          .select()
          .order('id', ascending: true);

      final fetched = List>.from(response);

      // ضمان وجود "عنباتي" و "TWISTA" ضمن القائمة المعروضة
      final existingNames = fetched
          .map((e) => (e['name'] ?? '').toString().trim().toLowerCase())
          .toSet();

      for (final defProj in _defaultHomeProjects) {
        final defName = defProj['name'].toString().trim().toLowerCase();
        if (!existingNames.contains(defName)) {
          fetched.insert(0, Map<String, dynamic>.from(defProj));
        }
      }
      return fetched;
    } catch (e) {
      debugPrint('⚠️ تعذر جلب جدول home_projects، سيتم عرض القائمة الافتراضية: $e');
      return List>.from(_defaultHomeProjects);
    }
  }

  void _showAddOrEditHomeProjectDialog(
    BuildContext context,
    AppState appState,
    Map<String, dynamic>? project,
  ) {
    final nameController =
        TextEditingController(text: project?['name']?.toString() ?? '');
    final descController =
        TextEditingController(text: project?['description']?.toString() ?? '');
    final phoneController =
        TextEditingController(text: project?['phone']?.toString() ?? '');
    bool isActive = project?['is_active'] ?? true;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              project == null
                  ? 'إضافة مشروع منزلي جديد 🏠'
                  : 'تعديل المشروع المنزلي ✏️',
              style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // أزرار تعبئة سريعة للأسماء المعتمدة
                  if (project == null) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        children: [
                          ActionChip(
                            backgroundColor: Colors.amber.withOpacity(0.15),
                            label: const Text('عنباتي',
                                style: TextStyle(
                                    color: Colors.amber, fontSize: 12)),
                            onPressed: () {
                              nameController.text = 'عنباتي';
                              if (descController.text.isEmpty) {
                                descController.text =
                                    'مشروع عنباتي للمنتجات والحلويات المنزلية';
                              }
                            },
                          ),
                          ActionChip(
                            backgroundColor: Colors.amber.withOpacity(0.15),
                            label: const Text('TWISTA',
                                style: TextStyle(
                                    color: Colors.amber, fontSize: 12)),
                            onPressed: () {
                              nameController.text = 'TWISTA';
                              if (descController.text.isEmpty) {
                                descController.text =
                                    'مشروع TWISTA للمأكولات والوجبات المنزلية';
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'اسم المشروع (مثال: عنباتي / TWISTA)',
                      labelStyle: TextStyle(color: Colors.grey),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'وصف المشروع والمنتجات',
                      labelStyle: TextStyle(color: Colors.grey),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'رقم هاتف صاحب المشروع (اختياري)',
                      labelStyle: TextStyle(color: Colors.grey),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: Colors.amber,
                    title: const Text('المشروع نشط ومتاح للطلب',
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                    value: isActive,
                    onChanged: (val) => setDialogState(() => isActive = val),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                onPressed: () async {
                  final projName = nameController.text.trim();
                  if (projName.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('الرجاء إدخال اسم المشروع المنزلي ⚠️')),
                    );
                    return;
                  }

                  final payload = {
                    'name': projName,
                    'description': descController.text.trim(),
                    'phone': phoneController.text.trim(),
                    'category': 'مشاريع منزلية',
                    'is_active': isActive,
                  };

                  try {
                    final rawId = project?['id'];
                    if (rawId == null ||
                        rawId.toString().startsWith('proj_')) {
                      await Supabase.instance.client
                          .from('home_projects')
                          .insert(payload);
                    } else {
                      await Supabase.instance.client
                          .from('home_projects')
                          .update(payload)
                          .eq('id', rawId);
                    }

                    // مزامنة الحالة مع AppState إذا كانت الدالة متوفرة
                    try {
                      await (appState as dynamic).fetchHomeProjects();
                    } catch (_) {}

                    if (!context.mounted) return;
                    Navigator.pop(ctx);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text('تم حفظ المشروع المنزلي "$projName" بنجاح ✅'),
                        backgroundColor: Colors.green[700],
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('حدث خطأ أثناء الحفظ: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: const Text('حفظ المشروع',
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeProjectsManagement(AppState appState) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.home_work, color: Colors.amber, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'المشاريع المنزلية (عنباتي / TWISTA)',
                    style: TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('إضافة مشروع',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () =>
                    _showAddOrEditHomeProjectDialog(context, appState, null),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List>>(
            future: _fetchHomeProjectsList(appState),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Colors.amber));
              }

              final projects = snapshot.data ?? _defaultHomeProjects;
              if (projects.isEmpty) {
                return const Center(
                  child: Text('لا توجد مشاريع منزلية مضافة حالياً 🏠',
                      style: TextStyle(color: Colors.grey)),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: projects.length,
                itemBuilder: (context, index) {
                  final proj = projects[index];
                  final name = proj['name']?.toString() ?? 'مشروع منزلي';
                  final desc = proj['description']?.toString() ?? '';
                  final phone = proj['phone']?.toString() ?? '';
                  final isActive = proj['is_active'] != false;

                  return Card(
                    color: const Color(0xFF1E1E1E),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: isActive
                            ? Colors.amber.withOpacity(0.45)
                            : Colors.grey.withOpacity(0.25),
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: Colors.amber.withOpacity(0.2),
                        child: const Icon(Icons.storefront,
                            color: Colors.amber, size: 22),
                      ),
                      title: Row(
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? Colors.green.withOpacity(0.2)
                                  : Colors.red.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isActive ? 'نشط' : 'متوقف',
                              style: TextStyle(
                                color: isActive
                                    ? Colors.greenAccent
                                    : Colors.redAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (desc.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(desc,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                          ],
                          if (phone.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('📞 $phone',
                                style: const TextStyle(
                                    color: Colors.amberAccent, fontSize: 11)),
                          ],
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit,
                                color: Colors.blueAccent, size: 20),
                            tooltip: 'تعديل المشروع',
                            onPressed: () => _showAddOrEditHomeProjectDialog(
                                context, appState, proj),
                          ),
                          if (!proj['id'].toString().startsWith('proj_'))
                            IconButton(
                              icon: const Icon(Icons.delete,
                                  color: Colors.redAccent, size: 20),
                              tooltip: 'حذف المشروع',
                              onPressed: () async {
                                await Supabase.instance.client
                                    .from('home_projects')
                                    .delete()
                                    .eq('id', proj['id']);
                                setState(() {});
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'تم حذف مشروع "$name" بنجاح 🗑️')),
                                  );
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== إدارة البنرات الترويجية ====================

  void _showAddOrEditBannerDialog(
    BuildContext context,
    AppState appState,
    Map<String, dynamic>? banner,
  ) {
    final titleController =
        TextEditingController(text: banner?['title']?.toString() ?? '');
    final subtitleController =
        TextEditingController(text: banner?['subtitle']?.toString() ?? '');
    final codeController =
        TextEditingController(text: banner?['code']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(
            banner == null
                ? 'إضافة بنر ترويجي جديد 📢'
                : 'تعديل البنر الترويجي ✏️',
            style: const TextStyle(color: Colors.amber),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    labelText: 'عنوان البنر',
                    labelStyle: TextStyle(color: Colors.grey)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: subtitleController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    labelText: 'الوصف أو التفاصيل',
                    labelStyle: TextStyle(color: Colors.grey)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: codeController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    labelText: 'كود الخصم (اختياري)',
                    labelStyle: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              onPressed: () async {
                if (titleController.text.trim().isNotEmpty) {
                  if (banner == null) {
                    await Supabase.instance.client
                        .from('promo_banners')
                        .insert({
                      'title': titleController.text.trim(),
                      'subtitle': subtitleController.text.trim(),
                      'code': codeController.text.trim(),
                      'is_active': true,
                    });
                  } else {
                    await Supabase.instance.client
                        .from('promo_banners')
                        .update({
                      'title': titleController.text.trim(),
                      'subtitle': subtitleController.text.trim(),
                      'code': codeController.text.trim(),
                    }).eq('id', banner['id']);
                  }
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم حفظ البنر بنجاح ✅')));
                }
              },
              child: const Text('حفظ',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showBannersManagementDialog(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('إدارة البنرات الترويجية 📢',
                    style: TextStyle(
                        color: Colors.amber,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('إضافة بنر'),
                  onPressed: () {
                    Navigator.pop(context);
                    _showAddOrEditBannerDialog(context, appState, null);
                  },
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: FutureBuilder<List<dynamic>>(
                future: Supabase.instance.client
                    .from('promo_banners')
                    .select()
                    .order('id', ascending: false),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: Colors.amber));
                  }
                  final banners = snapshot.data ?? [];
                  if (banners.isEmpty) {
                    return const Center(
                        child: Text('لا توجد بنرات مضافة حالياً 📭',
                            style: TextStyle(color: Colors.grey)));
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: banners.length,
                    itemBuilder: (context, index) {
                      final banner = banners[index];
                      return Card(
                        color: const Color(0xFF121212),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: Colors.amber.withOpacity(0.3))),
                        child: ListTile(
                          title: Text(banner['title']?.toString() ?? '',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              '${banner['subtitle'] ?? ''}\nكود الخصم: ${banner['code'] ?? "لا يوجد"}',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit,
                                    color: Colors.blueAccent, size: 20),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showAddOrEditBannerDialog(
                                      context, appState, banner);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Colors.redAccent, size: 20),
                                onPressed: () async {
                                  await Supabase.instance.client
                                      .from('promo_banners')
                                      .delete()
                                      .eq('id', banner['id']);
                                  setDialogState(() {});
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('تم حذف البنر بنجاح 🗑️')));
                                  }
                                },
                              ),
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
      ),
    );
  }

  void _showRestaurantRatingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.star, color: Colors.amber),
                SizedBox(width: 8),
                Text('تقييمات وملاحظات المطاعم الشهرية ⭐',
                    style: TextStyle(color: Colors.amber, fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: FutureBuilder<List<dynamic>>(
                future: Supabase.instance.client
                    .from('ratings_and_reviews')
                    .select(
                        'id, order_id, customer_phone, target_id, rating, comment, created_at')
                    .eq('target_type', 'restaurant')
                    .order('created_at', ascending: false),
                builder: (BuildContext context,
                    AsyncSnapshot<List<dynamic>> snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: Colors.amber));
                  }
                  if (snapshot.hasError) {
                    return const Center(
                        child: Text('تعذر جلب تقييمات المطاعم حالياً',
                            style: TextStyle(color: Colors.grey)));
                  }

                  final List<dynamic> listData = snapshot.data ?? [];
                  if (listData.isEmpty) {
                    return const Center(
                        child: Text('لا توجد تقييمات مطاعم مسجلة حتى الآن 📭',
                            style: TextStyle(color: Colors.grey)));
                  }

                  return ListView.builder(
                    itemCount: listData.length,
                    itemBuilder: (BuildContext context, int index) {
                      final dynamic item = listData[index];
                      final Map<String, dynamic> r =
                          item is Map<String, dynamic> ? item : {};
                      final targetLabel =
                          (r['target_id'] ?? 'مطعم').toString().trim();
                      final commentText =
                          (r['comment'] ?? '').toString().trim();

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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '🍽️ $targetLabel',
                                    style: const TextStyle(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15),
                                  ),
                                  Row(
                                    children: [
                                      const Icon(Icons.star,
                                          color: Colors.amber, size: 18),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${r['rating'] ?? 0}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '💬 الملاحظة: ${commentText.isNotEmpty ? commentText : 'بدون تعليق'}',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
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
        );
      },
    );
  }

  Future<void> _settleCourierSafely({
    required BuildContext context,
    required AppState appState,
    required String courierName,
    required List unsettledOrders,
    required double totalCourierEarnings,
    required double adminCommission,
    required double netCourierEarnings,
  }) async {
    final orderIds = unsettledOrders
        .map((o) => o['id'])
        .where((id) => id != null)
        .toList();

    await appState.settleCourierEarnings(courierName);

    if (orderIds.isNotEmpty) {
      await Supabase.instance.client
          .from('orders')
          .update({'is_settled': true}).inFilter('id', orderIds);
      await appState.fetchOrders();
    }

    if (mounted) {
      setState(() {});
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'تم تصفير حساب المندوب $courierName بنجاح ✅ (صافي العمولة لك: ${adminCommission.toStringAsFixed(0)} ر.ي)'),
          backgroundColor: Colors.green[700],
        ),
      );
    }
  }

  Widget _buildCouriersManagement(AppState appState) {
    return FutureBuilder<List<dynamic>>(
      future: Supabase.instance.client.from('couriers').select(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.amber));
        }
        final couriers = snapshot.data ?? [];
        if (couriers.isEmpty) {
          return const Center(
              child: Text('لا يوجد مناديب مسجلين حالياً 🛵',
                  style: TextStyle(color: Colors.grey)));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: couriers.length,
          itemBuilder: (context, index) {
            final courier = couriers[index];
            final courierMap = courier is Map
                ? Map<String, dynamic>.from(courier)
                : <String, dynamic>{};
            final courierName = courierMap['name']?.toString().trim() ??
                courierMap['full_name']?.toString().trim() ??
                '';
            final courierKey =
                courierMap['id']?.toString() ?? '$courierName-$index';
            final isSettlingThis = _settlingCourierKeys.contains(courierKey);
            final isBusy = _isCourierBusy(appState, courierMap);

            final courierUnsettledOrders = appState.orders.where((o) {
              final assigned = o['assigned_courier']?.toString().trim() ?? '';
              final name = o['courier_name']?.toString().trim() ?? '';
              final isDelivered =
                  o['status']?.toString().trim() == 'delivered';
              final isSettled = o['is_settled'] == true;
              return (assigned == courierName || name == courierName) &&
                  isDelivered &&
                  !isSettled;
            }).toList();

            var totalCourierEarnings = 0.0;
            for (final order in courierUnsettledOrders) {
              totalCourierEarnings +=
                  double.tryParse(order['delivery_fee']?.toString() ?? '0') ??
                      0.0;
            }

            final adminCommission = totalCourierEarnings * 0.20;
            final netCourierEarnings = totalCourierEarnings - adminCommission;

            return Card(
              color: const Color(0xFF1E1E1E),
              margin: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.amber.withOpacity(0.4)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.two_wheeler,
                                color: Colors.amber, size: 24),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    courierName.isNotEmpty
                                        ? courierName
                                        : 'مندوب',
                                    style: const TextStyle(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isBusy
                                        ? Colors.orange.withOpacity(0.2)
                                        : Colors.green.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    isBusy ? 'مشغول بطلب' : 'متاح',
                                    style: TextStyle(
                                      color: isBusy
                                          ? Colors.orangeAccent
                                          : Colors.greenAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.green),
                              ),
                              child: Text(
                                  '📞 ${courierMap['phone'] ?? 'غير متوفر'}',
                                  style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: isSettlingThis
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.redAccent),
                                    )
                                  : const Icon(Icons.delete_sweep,
                                      color: Colors.redAccent, size: 24),
                              tooltip: 'تصفير الحساب والعمولات',
                              onPressed: isSettlingThis
                                  ? null
                                  : () {
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => Directionality(
                                          textDirection: TextDirection.rtl,
                                          child: AlertDialog(
                                            backgroundColor:
                                                const Color(0xFF1E1E1E),
                                            title: const Text(
                                                'تصفير حساب المندوب ⚠️',
                                                style: TextStyle(
                                                    color: Colors.amber,
                                                    fontSize: 16)),
                                            content: Text(
                                                'هل أنت متأكد من رغبتك في تصفير حساب العمولة والطلبات للمندوب "$courierName"؟\n\n• صافي لك (20%): ${adminCommission.toStringAsFixed(0)} ر.ي\n• صافي المندوب (80%): ${netCourierEarnings.toStringAsFixed(0)} ر.ي',
                                                style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 13)),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx),
                                                child: const Text('إلغاء',
                                                    style: TextStyle(
                                                        color: Colors.grey)),
                                              ),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.redAccent,
                                                    foregroundColor:
                                                        Colors.white),
                                                onPressed: () async {
                                                  Navigator.pop(ctx);
                                                  if (mounted) {
                                                    setState(() =>
                                                        _settlingCourierKeys
                                                            .add(courierKey));
                                                  }
                                                  try {
                                                    await _settleCourierSafely(
                                                      context: context,
                                                      appState: appState,
                                                      courierName: courierName,
                                                      unsettledOrders:
                                                          courierUnsettledOrders,
                                                      totalCourierEarnings:
                                                          totalCourierEarnings,
                                                      adminCommission:
                                                          adminCommission,
                                                      netCourierEarnings:
                                                          netCourierEarnings,
                                                    );
                                                  } catch (e) {
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        SnackBar(
                                                          content: Text(e
                                                              .toString()
                                                              .replaceAll(
                                                                  'Exception: ',
                                                                  '')),
                                                          backgroundColor:
                                                              Colors.orange,
                                                        ),
                                                      );
                                                    }
                                                  } finally {
                                                    if (mounted) {
                                                      setState(() =>
                                                          _settlingCourierKeys
                                                              .remove(
                                                                  courierKey));
                                                    }
                                                  }
                                                },
                                                child: const Text(
                                                    'نعم، تصفير الحساب'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatColumn(
                            'طلبات غير مسوية',
                            '${courierUnsettledOrders.length} طلب',
                            Colors.white70),
                        _buildStatColumn(
                            'إجمالي التوصيل',
                            '${totalCourierEarnings.toStringAsFixed(0)} ر.ي',
                            Colors.amber),
                        _buildStatColumn(
                            'صافي المندوب (80%)',
                            '${netCourierEarnings.toStringAsFixed(0)} ر.ي',
                            Colors.greenAccent),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: Colors.amber.withOpacity(0.35)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '💰 الصافي لك بعد خصم العمولة (20%):',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${adminCommission.toStringAsFixed(0)} ر.ي',
                            style: const TextStyle(
                                color: Colors.amber,
                                fontSize: 14,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatColumn(String title, String value, Color valueColor) {
    return Column(
      children: [
        Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: valueColor, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildSettingsTab(AppState appState) {
    final startHourController =
        TextEditingController(text: appState.startHour.toString());
    final endHourController =
        TextEditingController(text: appState.endHour.toString());

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          const Text('إعدادات ومواعيد عمل التطبيق ⏰',
              style: TextStyle(
                  color: Colors.amber,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('تحديد ساعات فتح وإغلاق التطبيق يومياً:',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: startHourController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                            labelText: 'ساعة الفتح (مثال: 8)',
                            labelStyle: TextStyle(color: Colors.grey),
                            border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: endHourController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                            labelText: 'ساعة الإغلاق (مثال: 23)',
                            labelStyle: TextStyle(color: Colors.grey),
                            border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      minimumSize: const Size(double.infinity, 44)),
                  onPressed: () async {
                    final newStart = int.tryParse(startHourController.text);
                    final newEnd = int.tryParse(endHourController.text);
                    if (newStart != null && newEnd != null) {
                      await appState.updateStoreHours(newStart, newEnd);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('تم تحديث أوقات العمل بنجاح ✅')));
                      }
                    }
                  },
                  child: const Text('حفظ وتحديث أوقات العمل 💾',
                      style: TextStyle(
                          color: Colors.black, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      OrderTimeHelper.isWithinStoreHours(
                              appState.startHour, appState.endHour)
                          ? Icons.check_circle
                          : Icons.schedule,
                      size: 16,
                      color: OrderTimeHelper.isWithinStoreHours(
                              appState.startHour, appState.endHour)
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        OrderTimeHelper.isWithinStoreHours(
                                appState.startHour, appState.endHour)
                            ? 'الحالة الآن: التطبيق مفتوح لاستقبال الطلبات'
                            : 'الحالة الآن: التطبيق خارج أوقات العمل',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            tileColor: const Color(0xFF1E1E1E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.home_work, color: Colors.amber),
            title: const Text('إضافة مشروع منزلي (عنباتي / TWISTA) 🏠',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.add_circle_outline,
                size: 20, color: Colors.amber),
            onTap: () =>
                _showAddOrEditHomeProjectDialog(context, appState, null),
          ),
          const SizedBox(height: 10),
          ListTile(
            tileColor: const Color(0xFF1E1E1E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.star, color: Colors.amber),
            title: const Text('عرض تقييمات المطاعم الشهرية ⭐',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.arrow_forward_ios,
                size: 16, color: Colors.grey),
            onTap: () => _showRestaurantRatingsDialog(context),
          ),
          const SizedBox(height: 10),
          ListTile(
            tileColor: const Color(0xFF1E1E1E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.campaign, color: Colors.amber),
            title: const Text('إدارة البنرات الترويجية 📢',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.arrow_forward_ios,
                size: 16, color: Colors.grey),
            onTap: () => _showBannersManagementDialog(context, appState),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkStatusBar(AppState appState) {
    if (appState.isConnectedToInternet) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.red[800],
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text(
            'تنبيه: انقطع الاتصال بالإنترنت! يرجى التحقق من الشبكة ⚠️',
            style: TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    final totalCompletedOrdersCount =
        appState.orders.where((o) => o['status'] == 'delivered').length;

    final adminPages = <Widget>[
      _buildOrdersManagementWithTabs(appState),
      _buildProductsManagement(appState),
      _buildHomeProjectsManagement(appState),
      _buildCouriersManagement(appState),
      const AdminReportsScreen(),
      _buildSettingsTab(appState),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          elevation: 2,
          title: const Text('لوحة تحكم المشرف FAST',
              style: TextStyle(
                  color: Colors.amber,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          actions: [
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_active,
                      color: Colors.amber, size: 24),
                  tooltip: 'سجل الإشعارات والطلبات الجديدة',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => Directionality(
                        textDirection: TextDirection.rtl,
                        child: AlertDialog(
                          backgroundColor: const Color(0xFF1E1E1E),
                          title: const Row(
                            children: [
                              Icon(Icons.notifications, color: Colors.amber),
                              SizedBox(width: 8),
                              Text('إشعارات النظام الفورية 🛎️',
                                  style: TextStyle(
                                      color: Colors.amber, fontSize: 16)),
                            ],
                          ),
                          content: SizedBox(
                            width: double.maxFinite,
                            height: 350,
                            child: appState.notifications.isEmpty
                                ? const Center(
                                    child: Text(
                                        'لا توجد إشعارات جديدة حالياً 📭',
                                        style: TextStyle(color: Colors.grey)))
                                : ListView.builder(
                                    itemCount: appState.notifications.length,
                                    itemBuilder: (_, idx) {
                                      final notif = appState.notifications[idx];
                                      return Card(
                                        color: const Color(0xFF121212),
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        child: ListTile(
                                          title: Text(
                                              notif['title']?.toString() ?? '',
                                              style: const TextStyle(
                                                  color: Colors.amber,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13)),
                                          subtitle: Text(
                                              notif['body']?.toString() ?? '',
                                              style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12)),
                                          trailing: const Icon(
                                              Icons.arrow_forward_ios,
                                              color: Colors.amber,
                                              size: 14),
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            _handleAdminNotificationTap(
                                                context, notif);
                                          },
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('إغلاق',
                                  style: TextStyle(color: Colors.grey)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                if (appState.orders
                    .where((o) => o['status'] == 'waitingForPricing')
                    .isNotEmpty)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                      constraints:
                          const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(
                        '${appState.orders.where((o) => o['status'] == 'waitingForPricing').length}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
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
        body: Column(
          children: [
            _buildNetworkStatusBar(appState),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.amber.withOpacity(0.4), width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.2),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.remove_red_eye,
                                color: Colors.amber, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('إجمالي الزوار',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text('${appState.totalVisitorsCount} زائر',
                                  style: const TextStyle(
                                      color: Colors.amber,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.green.withOpacity(0.4), width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.check_circle,
                                color: Colors.greenAccent, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('الطلبات المكتملة',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text('$totalCompletedOrdersCount طلب',
                                  style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: adminPages[_selectedNavIndex],
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedNavIndex,
          onTap: (index) => setState(() => _selectedNavIndex = index),
          backgroundColor: const Color(0xFF1E1E1E),
          selectedItemColor: Colors.amber,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 11,
          unselectedFontSize: 10,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.receipt_long), label: 'الطلبات'),
            BottomNavigationBarItem(
                icon: Icon(Icons.fastfood), label: 'المنتجات'),
            BottomNavigationBarItem(
                icon: Icon(Icons.home_work), label: 'المشاريع'),
            BottomNavigationBarItem(
                icon: Icon(Icons.delivery_dining), label: 'المناديب'),
            BottomNavigationBarItem(
                icon: Icon(Icons.bar_chart), label: 'التقارير'),
            BottomNavigationBarItem(
                icon: Icon(Icons.settings), label: 'الإعدادات'),
          ],
        ),
      ),
    );
  }

  List _filterOrdersByPeriod(List sourceOrders) {
    if (_ordersPeriodFilter == 'today') {
      return sourceOrders
          .where((o) => OrderTimeHelper.isToday(o['created_at']))
          .toList();
    }
    if (_ordersPeriodFilter == 'custom' &&
        (_customStartDate != null || _customEndDate != null)) {
      final start = _customStartDate != null
          ? DateTime(_customStartDate!.year, _customStartDate!.month,
              _customStartDate!.day, 0, 0, 0)
          : null;
      final end = _customEndDate != null
          ? DateTime(_customEndDate!.year, _customEndDate!.month,
              _customEndDate!.day, 23, 59, 59)
          : null;
      return sourceOrders
          .where((o) => OrderTimeHelper.isWithinRange(o['created_at'],
              start: start, end: end))
          .toList();
    }
    return sourceOrders;
  }

  Future<void> _pickOrdersDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(
        start: _customStartDate ?? now,
        end: _customEndDate ?? now,
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Colors.amber,
                onPrimary: Colors.black,
                surface: Color(0xFF1E1E1E),
                onSurface: Colors.white,
              ),
            ),
            child: child!,
          ),
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _ordersPeriodFilter = 'custom';
        _customStartDate = picked.start;
        _customEndDate = picked.end;
      });
    }
  }

  Widget _buildOrdersManagementWithTabs(AppState appState) {
    final periodFilteredOrders = _filterOrdersByPeriod(appState.orders);

    final activeOrders = periodFilteredOrders
        .where((o) =>
            o['status'] != 'delivered' &&
            o['status'] != 'cancelled' &&
            o['status'] != 'cancelledByCustomer')
        .toList();
    final completedOrders =
        periodFilteredOrders.where((o) => o['status'] == 'delivered').toList();
    final cancelledOrders = periodFilteredOrders
        .where((o) =>
            o['status'] == 'cancelled' || o['status'] == 'cancelledByCustomer')
        .toList();

    return Column(
      children: [
        Container(
          color: const Color(0xFF1E1E1E),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('الكل', style: TextStyle(fontSize: 12)),
                selected: _ordersPeriodFilter == 'all',
                selectedColor: Colors.amber,
                backgroundColor: const Color(0xFF121212),
                labelStyle: TextStyle(
                  color: _ordersPeriodFilter == 'all'
                      ? Colors.black
                      : Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
                onSelected: (_) => setState(() => _ordersPeriodFilter = 'all'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('اليوم', style: TextStyle(fontSize: 12)),
                selected: _ordersPeriodFilter == 'today',
                selectedColor: Colors.amber,
                backgroundColor: const Color(0xFF121212),
                labelStyle: TextStyle(
                  color: _ordersPeriodFilter == 'today'
                      ? Colors.black
                      : Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
                onSelected: (_) => setState(() => _ordersPeriodFilter = 'today'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: _ordersPeriodFilter == 'custom'
                            ? Colors.amber
                            : Colors.white24),
                    foregroundColor: _ordersPeriodFilter == 'custom'
                        ? Colors.amber
                        : Colors.white70,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  onPressed: _pickOrdersDateRange,
                  icon: const Icon(Icons.date_range, size: 16),
                  label: Text(
                    _ordersPeriodFilter == 'custom' &&
                            _customStartDate != null &&
                            _customEndDate != null
                        ? '${_customStartDate!.month}/${_customStartDate!.day} - ${_customEndDate!.month}/${_customEndDate!.day}'
                        : 'تحديد فترة',
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          color: const Color(0xFF1E1E1E),
          child: TabBar(
            controller: _ordersTabController,
            labelColor: Colors.amber,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.amber,
            tabs: [
              Tab(text: 'النشطة (${activeOrders.length})'),
              Tab(text: 'المكتملة (${completedOrders.length})'),
              Tab(text: 'الملغية (${cancelledOrders.length})'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _ordersTabController,
            children: [
              _buildOrdersList(
                  appState, activeOrders, 'لا توجد طلبات نشطة حالياً 📦'),
              _buildOrdersList(
                  appState, completedOrders, 'لا توجد طلبات مكتملة 📭'),
              _buildOrdersList(
                  appState, cancelledOrders, 'لا توجد طلبات ملغية 🚫'),
            ],
          ),
        ),
      ],
    );
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    return double.tryParse(value.toString().trim()) ?? 0.0;
  }

  Widget _buildOrdersList(
      AppState appState, List ordersList, String emptyMessage) {
    if (ordersList.isEmpty) {
      return Center(
          child: Text(emptyMessage,
              style: const TextStyle(color: Colors.grey, fontSize: 15)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: ordersList.length,
      itemBuilder: (context, index) {
        final order = ordersList[index];
        final orderId = order['id'].toString();
        final intOrderId = int.tryParse(orderId);
        final rawStatus = order['status']?.toString() ?? '';
        final arabicStatus = _getArabicStatus(rawStatus);

        final isWaitingPricing = rawStatus == 'waitingForPricing';
        final isPricingThisOrder = _pricingOrderIds.contains(orderId);

        final projectName = (order['home_project_name'] ??
                order['project_name'] ??
                order['store_name'] ??
                '')
            .toString()
            .trim();
        final isHomeProjectOrder = order['is_home_project'] == true ||
            projectName == 'عنباتي' ||
            projectName.toUpperCase() == 'TWISTA';

        final deliveryFeeAmount = _parseDouble(order['delivery_fee']);

        final explicitProductsPrice = _parseDouble(
          order['products_total'] ??
              order['items_price'] ??
              order['products_price'],
        );

        final rawTotalPrice = _parseDouble(
          order['total_price'] ?? order['total_amount'] ?? order['total'],
        );

        var finalProductsPrice = explicitProductsPrice;
        if (finalProductsPrice <= 0 && rawTotalPrice > 0) {
          finalProductsPrice = rawTotalPrice > deliveryFeeAmount &&
                  rawStatus != 'waitingForPricing'
              ? (rawTotalPrice - deliveryFeeAmount)
              : rawTotalPrice;
        }

        final grandTotal = rawTotalPrice > 0
            ? rawTotalPrice
            : (finalProductsPrice + deliveryFeeAmount);

        if (!_feeControllers.containsKey(orderId)) {
          _feeControllers[orderId] = TextEditingController(
              text: order['delivery_fee']?.toString() ?? '0');
        }

        return Card(
          color: const Color(0xFF1E1E1E),
          margin: const EdgeInsets.symmetric(vertical: 8),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
                color: isWaitingPricing
                    ? Colors.amber
                    : Colors.green.withOpacity(0.4),
                width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      OrderTrackingScreen(orderIdParam: orderId),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('طلب #$orderId',
                          style: const TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      Row(
                        children: [
                          IconButton(
                            style: IconButton.styleFrom(
                                backgroundColor: Colors.red.withOpacity(0.2)),
                            icon: const Icon(Icons.delete_forever,
                                color: Colors.redAccent, size: 20),
                            tooltip: 'حذف الطلب',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => Directionality(
                                  textDirection: TextDirection.rtl,
                                  child: AlertDialog(
                                    backgroundColor: const Color(0xFF1E1E1E),
                                    title: const Row(
                                      children: [
                                        Icon(Icons.warning_amber_rounded,
                                            color: Colors.redAccent),
                                        SizedBox(width: 8),
                                        Text('تأكيد الحذف 🗑️',
                                            style: TextStyle(
                                                color: Colors.amber,
                                                fontSize: 16)),
                                      ],
                                    ),
                                    content: Text(
                                        'هل تريد الحذف حقاً للطلب #$orderId؟\n(لن يمكنك التراجع عن هذا الإجراء بعد الحذف).',
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13)),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('إلغاء',
                                            style:
                                                TextStyle(color: Colors.grey)),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.redAccent,
                                            foregroundColor: Colors.white),
                                        onPressed: () async {
                                          Navigator.pop(ctx);
                                          try {
                                            if (intOrderId != null) {
                                              await Supabase.instance.client
                                                  .from('orders')
                                                  .delete()
                                                  .eq('id', intOrderId);
                                            }
                                            await appState.fetchOrders();
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(
                                                        'تم حذف الطلب #$orderId بنجاح ✅'),
                                                    backgroundColor:
                                                        Colors.green),
                                              );
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(
                                                        'فشل حذف الطلب: $e'),
                                                    backgroundColor: Colors.red),
                                              );
                                            }
                                          }
                                        },
                                        child: const Text('نعم، احذف الطلب'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            style: IconButton.styleFrom(
                                backgroundColor: Colors.amber.withOpacity(0.2)),
                            icon: const Icon(Icons.map,
                                color: Colors.amber, size: 20),
                            tooltip: 'تتبع الطلب',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      OrderTrackingScreen(orderIdParam: orderId),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            style: IconButton.styleFrom(
                                backgroundColor: Colors.blueGrey[800]),
                            icon: const Icon(Icons.chat,
                                color: Colors.amber, size: 20),
                            tooltip: 'محادثة العميل أو المندوب',
                            onPressed: () =>
                                _openAdminChatPicker(context, orderId),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isWaitingPricing
                                  ? Colors.amber.withOpacity(0.15)
                                  : Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: isWaitingPricing
                                      ? Colors.amber
                                      : Colors.green),
                            ),
                            child: Text(arabicStatus,
                                style: TextStyle(
                                    color: isWaitingPricing
                                        ? Colors.amber
                                        : Colors.greenAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (isHomeProjectOrder || projectName.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.amber.withOpacity(0.5)),
                      ),
                      child: Text(
                        '🏠 مشروع منزلي: ${projectName.isNotEmpty ? projectName : 'مشاريع منزلية'}',
                        style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  const Divider(color: Colors.white12, height: 16),
                  Text(
                      '👤 العميل: ${order['customer_name'] ?? 'غير معروف'} \n📞 ${order['phone'] ?? ''}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  const SizedBox(height: 6),
                  Text('📍 العنوان: ${order['address'] ?? ''}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 6),
                  Text(
                      '🛒 تفاصيل الطلب: ${order['items_description'] ?? order['items_desc'] ?? 'بدون وصف'}',
                      style: const TextStyle(
                          color: Colors.amberAccent, fontSize: 12)),
                  const SizedBox(height: 6),
                  Text(
                      '🕒 وقت الطلب: ${OrderTimeHelper.formatDateTime(order['created_at'])}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  const Divider(color: Colors.white12, height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '🛒 سعر المنتجات: ${finalProductsPrice.toStringAsFixed(0)} ر.ي',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                            '🏍️ رسوم التوصيل: ${deliveryFeeAmount.toStringAsFixed(0)} ر.ي',
                            style: const TextStyle(
                                color: Colors.amber,
                                fontSize: 13,
                                fontWeight: FontWeight.bold)),
                        const Divider(color: Colors.white12, height: 8),
                        Text(
                            '💰 الإجمالي الكلي: ${grandTotal.toStringAsFixed(0)} ر.ي',
                            style: const TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (isWaitingPricing) ...[
                    const Text('⚙️ تسعير الطلب وتعيين المندوب:',
                        style: TextStyle(
                            color: Colors.amber,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _feeControllers[orderId],
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'رسوم التوصيل (ر.ي)',
                              labelStyle:
                                  TextStyle(color: Colors.grey, fontSize: 12),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FutureBuilder<List<dynamic>>(
                            future: Supabase.instance.client
                                .from('couriers')
                                .select(),
                            builder: (context, courierSnapshot) {
                              final couriersList = courierSnapshot.data ?? [];
                              return DropdownButtonFormField<String>(
                                value: _selectedCouriersForOrder[orderId],
                                dropdownColor: const Color(0xFF1E1E1E),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                                decoration: const InputDecoration(
                                  labelText: 'اختر المندوب',
                                  labelStyle: TextStyle(
                                      color: Colors.grey, fontSize: 12),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: couriersList
                                    .map<DropdownMenuItem<String>>((courier) {
                                  final cMap = courier is Map
                                      ? Map<String, dynamic>.from(courier)
                                      : <String, dynamic>{};
                                  final name = cMap['name']?.toString() ??
                                      cMap['full_name']?.toString() ??
                                      'مندوب';
                                  final busy = _isCourierBusy(appState, cMap);
                                  return DropdownMenuItem<String>(
                                    value: name,
                                    child: Text(
                                      '$name (${busy ? 'مشغول' : 'متاح'})',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: busy
                                            ? Colors.orangeAccent
                                            : Colors.greenAccent,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _selectedCouriersForOrder[orderId] = val;
                                    });
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 38),
                      ),
                      onPressed: isPricingThisOrder
                          ? null
                          : () async {
                              final fee = double.tryParse(
                                  _feeControllers[orderId]?.text ?? '0');
                              final selectedCourier =
                                  _selectedCouriersForOrder[orderId];

                              if (fee == null || fee < 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'الرجاء إدخال رسوم توصيل صحيحة ⚠️')));
                                return;
                              }
                              if (selectedCourier == null ||
                                  selectedCourier.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'الرجاء اختيار المندوب لتوصيل الطلب 🛵')));
                                return;
                              }

                              setState(() => _pricingOrderIds.add(orderId));
                              try {
                                await appState.setOrderDeliveryFee(
                                    orderId, fee, selectedCourier);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'تم إرسال التسعير وتعيين المندوب بنجاح ✅')));
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              'تعذر إرسال التسعير: $e'),
                                          backgroundColor: Colors.red));
                                }
                              } finally {
                                if (mounted) {
                                  setState(
                                      () => _pricingOrderIds.remove(orderId));
                                }
                              }
                            },
                      child: isPricingThisOrder
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.black, strokeWidth: 2),
                            )
                          : const Text('إرسال التسعير وتعيين المندوب 🚀',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductsManagement(AppState appState) {
    return const AdminProductsScreen();
  }
}
