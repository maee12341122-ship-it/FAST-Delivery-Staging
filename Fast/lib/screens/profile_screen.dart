import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/address_model.dart';
import '../providers/app_state.dart';
import '../utils/constants.dart';
import '../utils/validators.dart';
import 'location_picker_screen.dart';
import 'register_screen.dart';

class ProfileScreen extends StatelessWidget {
  final VoidCallback? onOpenDrawer;
  const ProfileScreen({super.key, this.onOpenDrawer});

  Future<void> _sendOtpViaWhatsApp(BuildContext context, String phone, String otpCode) async {
    final message = Uri.encodeComponent(
        '🌟 تطبيق FAST - تعز 🌟\n\n'
            'أهلاً بك يا بطل!\n'
            'رمز التحقق الخاص بك هو: *$otpCode*\n\n'
            'لا تشارك هذا الرمز مع أي شخص حفاظاً على أمان حسابك. شكراً لاستخدامك FAST! 🚀'
    );

    String formattedPhone = phone.trim();
    if (formattedPhone.startsWith('0')) {
      formattedPhone = '967${formattedPhone.substring(1)}';
    } else if (!formattedPhone.startsWith('967')) {
      formattedPhone = '967$formattedPhone';
    }

    final whatsappUrl = Uri.parse('https://wa.me/$formattedPhone?text=$message');

    if (await canLaunchUrl(whatsappUrl)) {
      await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح تطبيق الواتساب ❌')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.user;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          elevation: 2,
          leading: onOpenDrawer == null ? null : IconButton(icon: const Icon(Icons.menu, color: AppConstants.gold), onPressed: onOpenDrawer),
          title: const Text('حسابي الشخصي 👤', style: TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        body: user == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.account_circle_outlined, size: 70, color: AppConstants.gold),
                      const SizedBox(height: 16),
                      const Text('لم تقم بتسجيل بيانات حسابك بعد', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('سجل بياناتك للبدء في استخدام خدمات التوصيل السريع في تعز', style: TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppConstants.gold,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          await state.openFastWhatsApp(message: 'مرحباً، أريد التسجيل في تطبيق FAST.');
                          if (context.mounted) {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen()));
                          }
                        },
                        icon: const Icon(Icons.person_add),
                        label: const Text('تسجيل بيانات العميل 🚀', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: const Color(0xFF1E1E1E),
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: AppConstants.gold.withOpacity(0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          const CircleAvatar(
                            radius: 36, 
                            backgroundColor: AppConstants.gold, 
                            child: Icon(Icons.person, color: Colors.black, size: 40),
                          ),
                          const SizedBox(height: 12),
                          Text(user.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(height: 4),
                          Text(user.phone, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppConstants.gold,
                                    side: BorderSide(color: AppConstants.gold.withOpacity(0.5)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () => _editProfile(context, user.name, user.phone),
                                  icon: const Icon(Icons.edit, size: 16),
                                  label: const Text('تعديل البيانات'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.greenAccent,
                                    side: BorderSide(color: Colors.greenAccent.withOpacity(0.5)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () async {
                                    await state.openFastWhatsApp(message: 'مرحباً، أريد تعديل بيانات حسابي. رقم الهاتف: ${user.phone}');
                                  },
                                  icon: const Icon(Icons.message, size: 16),
                                  label: const Text('التواصل مع FAST عبر واتساب'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('العناوين المحفوظة 📍', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppConstants.gold)),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: AppConstants.gold),
                        onPressed: () => _addAddress(context), 
                        icon: const Icon(Icons.add), 
                        label: const Text('إضافة عنوان', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  if (user.addresses.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: Text('لا توجد عناوين محفوظة حالياً 📍', style: TextStyle(color: Colors.grey))),
                    ),
                  ...user.addresses.map((address) => Card(
                    color: const Color(0xFF1E1E1E),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppConstants.gold.withOpacity(0.2)),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.location_on, color: AppConstants.gold),
                      title: Text(address.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text('${address.area}\n${address.details}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      isThreeLine: true,
                      trailing: user.defaultAddress?.id == address.id
                          ? const Chip(
                              backgroundColor: Colors.green,
                              label: Text('الافتراضي', style: TextStyle(color: Colors.white, fontSize: 11)),
                            )
                          : TextButton(
                              onPressed: () => context.read<AppState>().setDefaultAddress(address.id), 
                              child: const Text('تعيين كافتراضي', style: TextStyle(color: AppConstants.gold)),
                            ),
                    ),
                  )),
                  const SizedBox(height: 30),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => Directionality(
                          textDirection: TextDirection.rtl,
                          child: AlertDialog(
                            backgroundColor: const Color(0xFF1E1E1E),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            title: const Text('تسجيل الخروج', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            content: const Text('سيتم حذف بيانات العميل من هذا الجهاز فقط، وتبقى الطلبات المحلية محفوظة.', style: TextStyle(color: Colors.white70)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء', style: TextStyle(color: Colors.grey))),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                                onPressed: () => Navigator.pop(dialogContext, true), 
                                child: const Text('خروج', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ) ?? false;
                      if (confirm && context.mounted) {
                        context.read<AppState>().clearUser();
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const RegisterScreen()),
                          (route) => false,
                        );
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('تسجيل الخروج من هذا الجهاز', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'الحساب في هذه النسخة محفوظ محلياً ومزامن بسلاسة مع سوبابيس.',
                    style: TextStyle(color: Colors.grey, fontSize: 11), 
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _editProfile(BuildContext context, String oldName, String oldPhone) async {
    final nameController = TextEditingController(text: oldName);
    final phoneController = TextEditingController(text: oldPhone);
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('تعديل بيانات العميل', style: TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold)),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController, 
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'الاسم',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF121212),
                  ), 
                  validator: Validators.requiredText,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: phoneController, 
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF121212),
                  ), 
                  validator: Validators.yemeniPhone,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppConstants.gold, foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(dialogContext, formKey.currentState!.validate()), 
              child: const Text('حفظ', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    ) ?? false;
    if (saved && context.mounted) {
      context.read<AppState>().updateUser(name: nameController.text, phone: phoneController.text);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث البيانات بنجاح! ✅')));
    }
    nameController.dispose();
    phoneController.dispose();
  }

  Future<void> _addAddress(BuildContext context) async {
    final areaController = TextEditingController(text: 'شارع جمال / ديلوكس');
    final detailsController = TextEditingController();
    LatLng? point;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('إضافة عنوان جديد', style: TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: areaController, 
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'المنطقة (تعز)',
                  labelStyle: TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Color(0xFF121212),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: detailsController, 
                maxLines: 2, 
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'العنوان التفصيلي (بجوار...)',
                  labelStyle: TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Color(0xFF121212),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppConstants.gold,
                  side: BorderSide(color: AppConstants.gold.withOpacity(0.5)),
                  minimumSize: const Size(double.infinity, 42),
                ),
                onPressed: () async {
                  final selected = await Navigator.of(context).push<LatLng>(
                    MaterialPageRoute(builder: (_) => LocationPickerScreen(initialPoint: point)),
                  );
                  if (selected != null) point = selected;
                },
                icon: const Icon(Icons.map, size: 18),
                label: const Text('تحديد الموقع على الخريطة 🗺️', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppConstants.gold, foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(dialogContext, detailsController.text.trim().isNotEmpty),
              child: const Text('حفظ العنوان', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    ) ?? false;
    if (saved && context.mounted) {
      context.read<AppState>().addOrUpdateAddress(AddressModel(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: 'عنوان ${DateTime.now().hour}:${DateTime.now().minute}',
        area: areaController.text.trim(),
        details: detailsController.text.trim(),
        latitude: point?.latitude,
        longitude: point?.longitude,
      ));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة العنوان بنجاح! 📍')));
    }
    areaController.dispose();
    detailsController.dispose();
  }
}
