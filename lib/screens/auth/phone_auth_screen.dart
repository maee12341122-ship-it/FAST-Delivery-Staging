import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // 👈 استيراد سوبابيس لتحديث الـ Player ID
import 'package:onesignal_flutter/onesignal_flutter.dart'; // 👈 استيراد مكتبة OneSignal
import '../../providers/app_state.dart';
import '../../services/notification_service.dart'; 
import '../customer/map_location_screen.dart';
// 👈 استدعاء شاشة الخريطة التفاعلية

class PhoneAuthScreen extends StatefulWidget {
  final VoidCallback? onLoginSuccess;

  const PhoneAuthScreen({Key? key, this.onLoginSuccess}) : super(key: key);

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController(text: 'تعز - ديلوكس / بجوار الشارع العام');

  bool _isOtpSent = false;
  bool _isProfileStep = false;
  bool _isLoading = false;

  // 🗺️ دالة لفتح الخريطة التفاعلية واستقبال البيانات المرتجعة منها
  Future<void> _openInteractiveMap() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MapLocationScreen(),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      final address = result['address'] as String?;
      final latLng = result['latLng'];

      setState(() {
        if (address != null && address.isNotEmpty) {
          if (latLng != null) {
            _addressController.text = '$address (الإحداثيات: ${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)})';
          } else {
            _addressController.text = address;
          }
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديد موقعك ونقل الإحداثيات بنجاح! 📍')),
        );
      }
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    const backgroundColor = Color(0xFF121212);
    const cardColor = Color(0xFF1E1E1E);
    const primaryGold = Colors.amber;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: cardColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: primaryGold),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'تعز إكسبرس - بوابة المصادقة',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primaryGold.withOpacity(0.3), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: primaryGold.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.flash_on,
                      size: 50,
                      color: primaryGold,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ---------------- المرحلة الأولى: إدخال رقم الهاتف ----------------
                  if (!_isOtpSent && !_isProfileStep) ...[
                    const Text(
                      'تسجيل الدخول / حساب جديد',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'أدخل رقم هاتفك للتحقق أو استرجاع بياناتك المسجلة مسبقاً',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 25),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'رقم الهاتف',
                        labelStyle: const TextStyle(color: Colors.grey),
                        prefixIcon: const Icon(Icons.phone_android, color: primaryGold),
                        filled: true,
                        fillColor: backgroundColor,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade800),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: primaryGold, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGold,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isLoading
                          ? null
                          : () async {
                              final phone = _phoneController.text.trim();
                              if (phone.isEmpty || phone.length < 9) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('الرجاء إدخال رقم هاتف صحيح')),
                                );
                                return;
                              }
                              setState(() => _isLoading = true);

                              bool exists = await appState.checkAndLoginCustomer(phone);

                              if (exists && appState.userProfile != null) {
                                setState(() {
                                  _isLoading = false;
                                  _nameController.text = appState.userProfile!['name'] ?? '';
                                  _addressController.text = appState.userProfile!['address'] ?? 'تعز - ديلوكس';
                                  _isProfileStep = true;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('تم العثور على حسابك السابق واسترجاع بياناتك بنجاح! ✅')),
                                );
                              } else {
                                appState.requestOtpForPhone(phone);

                                setState(() {
                                  _isLoading = false;
                                  _isOtpSent = true;
                                });

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('تم فتح واتساب برسالة جاهزة. أرسلها بنفسك، ويمكنك المتابعة كضيف دون توثيق الرقم.')),
                                );
                              }
                            },
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.black)
                          : const Text('فتح واتساب والمتابعة', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ]

                  // ---------------- المرحلة الثانية: إدخال رمز الـ OTP ----------------
                  else if (_isOtpSent && !_isProfileStep) ...[
                    const Text(
                      'المتابعة كضيف',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'تم فتح واتساب برسالة جاهزة إلى FAST. هذه الخطوة تواصل يدوي وليست تحققاً آلياً من ملكية الرقم.',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 25),
                    const SizedBox(height: 25),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGold,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        final accepted = appState.continueWithoutPhoneVerification(_phoneController.text.trim());
                        if (accepted) {
                          setState(() => _isProfileStep = true);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تحقق من رقم الهاتف ثم حاول مجدداً.')),
                          );
                        }
                      },
                      child: const Text('متابعة كضيف (الرقم غير موثّق)', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _isOtpSent = false;
                        _otpController.clear();
                      }),
                      child: const Text('تغيير رقم الهاتف', style: TextStyle(color: Colors.grey)),
                    ),
                  ]

                  // ---------------- المرحلة الثالثة: إدخال البيانات والعنوان ----------------
                  else if (_isProfileStep) ...[
                    const Text(
                      'استكمال وتأكيد البيانات الشخصية',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'أدخل اسمك وعنوانك التفصيلي بدقة في تعز',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'الاسم الكامل',
                        labelStyle: const TextStyle(color: Colors.grey),
                        prefixIcon: const Icon(Icons.person, color: primaryGold),
                        filled: true,
                        fillColor: backgroundColor,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade800),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: primaryGold, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addressController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'العنوان التفصيلي (مثال: ديلوكس، شارع جمال)',
                        labelStyle: const TextStyle(color: Colors.grey),
                        prefixIcon: const Icon(Icons.location_on, color: primaryGold),
                        filled: true,
                        fillColor: backgroundColor,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade800),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: primaryGold, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),

                    // 🗺️ زر يفتح خريطة جوجل التفاعلية المباشرة بدلاً من المتصفح الخارجي
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: primaryGold),
                        minimumSize: const Size(double.infinity, 45),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.map, color: primaryGold),
                      label: const Text('تحديد موقعك عبر الخريطة التفاعلية 🗺️', style: TextStyle(color: primaryGold, fontWeight: FontWeight.bold)),
                      onPressed: _openInteractiveMap,
                    ),

                    const SizedBox(height: 25),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGold,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        if (_nameController.text.trim().isNotEmpty && _addressController.text.trim().isNotEmpty) {
                          // 1. حفظ بيانات الملف الشخصي
                          await appState.saveUserProfileDetails(
                            _nameController.text.trim(),
                            _addressController.text.trim(),
                          );
                          
                          // 2. طلب أذونات الموقع والإشعارات
                          await appState.requestLocationAndNotificationPermissions();

                          // 3. حفظ الـ OneSignal Player ID في جدول العملاء بسوبابيس فوراً
                          try {
                            String? playerId = OneSignal.User.pushSubscription.id;
                            if (playerId != null && playerId.isNotEmpty && appState.currentUserId != null) {
                              await Supabase.instance.client
                                  .from('customers')
                                  .update({'onesignal_player_id': playerId})
                                  .eq('phone', appState.currentUserId!);
                              debugPrint('✅ تم حفظ وتحديث OneSignal Player ID بنجاح: $playerId');
                            }
                          } catch (e) {
                            debugPrint('❌ خطأ أثناء حفظ Player ID في تسجيل الدخول: $e');
                          }

                          // 4. حفظ Player ID عبر NotificationService أيضاً للتأكد
                          if (appState.currentUserId != null) {
                            await NotificationService.saveUserPlayerId(
                              appState.currentUserId!, 
                              'customers', 
                            );
                          }

                          if (widget.onLoginSuccess != null) {
                            widget.onLoginSuccess!();
                          } else {
                            Navigator.pop(context);
                          }
                          
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('أهلاً بك! تم حفظ البيانات وتسجيل الدخول بنجاح 🎉')),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('الرجاء إدخال الاسم والعنوان كاملاً')),
                          );
                        }
                      },
                      child: const Text('حفظ والدخول للتطبيق 🚀', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
