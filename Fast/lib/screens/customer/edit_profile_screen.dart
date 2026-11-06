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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          title: Text('تعديل الحساب الشخصي ⚙️', style: TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E1E1E),
          iconTheme: IconThemeData(color: AppConstants.gold),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // حقل الاسم الشخصي
              TextField(
                controller: _nameController,
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

              // حقل رقم الهاتف
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
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

              // حقل العنوان التفصيلي
              TextField(
                controller: _addressController,
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

              // قسم الخريطة التفاعلية لتحديد الموقع بدقة
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
                  // الانتقال إلى شاشة خريطة جوجل واستقبال خريطة البيانات (العنوان + الإحداثيات) عند العودة
                  final result = await Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const MapLocationScreen(),
  ),
);

                  if (result != null) {
                    final address = result['address'] as String?;
                    final latLng = result['latLng'];

                    setState(() {
                      if (address != null && address.isNotEmpty) {
                        // دمج العنوان النصي مع الإحداثيات إن وجدت
                        if (latLng != null) {
                          _addressController.text = '$address (الإحداثيات: ${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)})';
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

              // زر الحفظ بتصميم جذاب
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.gold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    // حفظ البيانات في الـ AppState وقاعدة البيانات سوبابيس
                    await context.read<AppState>().saveUserProfileDetails(
                      _nameController.text.trim(),
                      _addressController.text.trim(),
                    );
                    
                    // تحديث الهاتف أيضاً إذا تم تغييره
                    await context.read<AppState>().updateUser(
                      name: _nameController.text.trim(),
                      phone: _phoneController.text.trim(),
                    );

                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم حفظ وتحديث بيانات الحساب بنجاح! ✅')),
                      );
                    }
                  },
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
    );
  }
}
