import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../../utils/constants.dart';
import 'map_location_screen.dart'; // 👈 استدعاء شاشة الخريطة التفاعلية

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;

  // 🎯 تعريف موجهات التركيز (FocusNodes) للانتقال السلس عبر الكيبورد
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _addressFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    final profile = appState.userProfile;

    _nameController = TextEditingController(text: profile?['name'] ?? '');
    _phoneController = TextEditingController(text: profile?['phone'] ?? '');
    _addressController = TextEditingController(text: profile?['address'] ?? 'تعز - ديلوكس');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  // 🚀 دالة حفظ التعديلات الموحدة
  Future<void> _saveProfile() async {
    final appState = context.read<AppState>();
    
    // 1. حفظ تفاصيل الملف الشخصي
    await appState.saveUserProfileDetails(
      _nameController.text.trim(),
      _addressController.text.trim(),
    );
    
    // 2. تحديث الاسم ورقم الهاتف في الجلسة المحلية
    await appState.updateUser(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
    );

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ وتحديث بيانات الحساب بنجاح! ✅')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(), // إغلاق الكيبورد بسلاسة عند الضغط خارج الحقول
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            title: Text('تعديل الحساب الشخصي ⚙️', style: TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold, fontSize: 16)),
            backgroundColor: const Color(0xFF1E1E1E),
            iconTheme: IconThemeData(color: AppConstants.gold),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 👤 حقل الاسم الشخصي
                TextField(
                  controller: _nameController,
                  focusNode: _nameFocus,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) {
                    FocusScope.of(context).requestFocus(_phoneFocus);
                  },
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'الاسم الشخصي',
                    labelStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.person, color: AppConstants.gold),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                  ),
                ),
                const SizedBox(height: 15),

                // 📞 حقل رقم الهاتف
                TextField(
                  controller: _phoneController,
                  focusNode: _phoneFocus,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) {
                    FocusScope.of(context).requestFocus(_addressFocus);
                  },
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'رقم الهاتف',
                    labelStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.phone, color: AppConstants.gold),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                  ),
                ),
                const SizedBox(height: 15),

                // 🏠 حقل العنوان التفصيلي
                TextField(
                  controller: _addressController,
                  focusNode: _addressFocus,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _saveProfile(),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'العنوان (مثال: ديلوكس، شارع جمال...)',
                    labelStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.home, color: AppConstants.gold),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                  ),
                ),
                const SizedBox(height: 20),

                // 🗺️ قسم الخريطة التفاعلية لتحديد الموقع بدقة
                Text(
                  'تحديد الموقع الجغرافي على الخريطة 🗺️',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppConstants.gold),
                ),
                const SizedBox(height: 5),
                const Text(
                  'انقر على الخريطة أدناه لفتح خريطة جوجل وتحديد موقع منزلك أو نقطة التوصيل بدقة.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),

                // 👈 عنصر خريطة تفاعلي ينقل المستخدم إلى MapLocationScreen عند النقر
                GestureDetector(
                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MapLocationScreen(),
                      ),
                    );

                    if (result != null && result is Map) {
                      final address = result['address'] as String?;
                      final latLng = result['latLng'];

                      setState(() {
                        if (address != null && address.isNotEmpty) {
                          if (latLng != null) {
                            // 🎯 تنسيق الإحداثيات بشكل مرتب ومنظم تماماً
                            final lat = latLng.latitude;
                            final lng = latLng.longitude;
                            final formattedCoords = '(${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
                            
                            _addressController.text = '$address (الإحداثيات: $formattedCoords)';
                          } else {
                            _addressController.text = address;
                          }
                        }
                      });

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم تحديث العنوان والإحداثيات بنجاح! 📍')),
                        );
                      }
                    }
                  },
                  child: Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppConstants.gold, width: 1.5),
                      borderRadius: BorderRadius.circular(16),
                      color: const Color(0xFF1E1E1E),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.map, size: 50, color: AppConstants.gold),
                            const SizedBox(height: 8),
                            const Text(
                              'اضغط هنا لفتح خريطة جوجل التفاعلية 📍',
                              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        Positioned(
                          bottom: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppConstants.gold.withOpacity(0.5)),
                            ),
                            child: Text(
                              'تحديد الدبوس على موقعك في تعز',
                              style: TextStyle(fontSize: 11, color: AppConstants.gold, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                // 🚀 زر الحفظ ومزامنة البيانات في سوبابيس
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _saveProfile,
                    child: const Text(
                      'حفظ التعديلات 🚀',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
