import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import '../../providers/app_state.dart';
import '../customer/map_location_screen.dart';

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
  final TextEditingController _addressController =
      TextEditingController(text: 'تعز - ديلوكس / بجوار الشارع العام');

  // مراحل العملية: 0 = إدخال الرقم، 1 = إدخال OTP، 2 = إكمال البروفايل
  int _currentStep = 0;
  bool _isLoading = false;

  final SupabaseClient _supabase = Supabase.instance.client;
  String _formattedPhone = '';

  // 🗺️ دالة لفتح الخريطة التفاعلية
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
            _addressController.text =
                '$address (الإحداثيات: ${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)})';
          } else {
            _addressController.text = address;
          }
        }
      });
    }
  }

  // 1️⃣ إرسال كود OTP عبر دالة generate_and_store_otp في Supabase
  Future<void> _sendSupabaseOTP() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال رقم هاتف صحيح')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // تنسيق الرقم بالصيغة الدولية (اليمن +967)
      String formattedPhone = phone;
      if (!formattedPhone.startsWith('+')) {
        if (formattedPhone.startsWith('0')) {
          formattedPhone = '+967${formattedPhone.substring(1)}';
        } else {
          formattedPhone = '+967$formattedPhone';
        }
      }
      _formattedPhone = formattedPhone;

      // توليد وحفظ كود الـ OTP عبر دالة Supabase SQL
      final response = await _supabase.rpc(
        'generate_and_store_otp',
        params: {'target_phone': _formattedPhone},
      );

      final generatedCode = response.toString();

      setState(() {
        _currentStep = 1; // الانتقال لمرحلة أدخل رمز OTP
        _isLoading = false;
      });

      // تنبيه توضيحي بمحتوى الكود (يتم استبداله بإرسال الواتساب من السيرفر)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إرسال رمز التحقق بنجاح! 💬 (رمز التجربة: $generatedCode)'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('❌ خطأ في إنشاء رمز OTP: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل إرسال رمز التحقق: $e')),
      );
    }
  }

  // 2️⃣ التحقق من كود OTP والانتقال للبروفايل / Supabase
  Future<void> _verifyOTPAndProceed(AppState appState) async {
    final otpCode = _otpController.text.trim();
    if (otpCode.isEmpty || otpCode.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال رمز تحقق مكون من 6 أرقام')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // التأكد من صحة الرمز عبر دالة verify_otp_code في Supabase
      final bool isValid = await _supabase.rpc(
        'verify_otp_code',
        params: {
          'target_phone': _formattedPhone,
          'entered_code': otpCode,
        },
      );

      if (isValid) {
        // فحص السجل في قاعدة بيانات Supabase جدول customers
        final existingCustomer = await _supabase
            .from('customers')
            .select()
            .eq('phone_number', _formattedPhone)
            .maybeSingle();

        setState(() => _isLoading = false);

        if (existingCustomer != null) {
          // العميل موجود مسبقاً، نملأ البيانات للانتقال للمرحلة الأخيرة
          _nameController.text = existingCustomer['full_name'] ?? '';
          _addressController.text =
              existingCustomer['address'] ?? 'تعز - ديلوكس';
          setState(() {
            _currentStep = 2;
          });
        } else {
          // عميل جديد
          appState.continueWithoutPhoneVerification(_formattedPhone);
          setState(() {
            _currentStep = 2;
          });
        }
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('رمز التحقق غير صحيح أو انتهت صلاحيته (5 دقائق)')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('❌ خطأ في التحقق من OTP: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء التحقق: $e')),
      );
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
            'FAST – تسجيل دخول العميل',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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
                    child: Icon(
                      _currentStep == 1
                          ? Icons.mark_chat_read_outlined
                          : Icons.person_outline_rounded,
                      size: 50,
                      color: primaryGold,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ---------------- المرحلة الأولى: إدخال رقم الهاتف ----------------
                  if (_currentStep == 0) ...[
                    const Text(
                      'تسجيل الدخول برقم الهاتف',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'أدخل رقم هاتفك لتلقي رمز التحقق OTP عبر الواتساب',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 25),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'رقم الهاتف (مثال: 770000000)',
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
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isLoading ? null : _sendSupabaseOTP,
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.black)
                          : const Text('إرسال رمز التحقق (OTP) 💬',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15)),
                    ),
                  ]

                  // ---------------- المرحلة الثانية: إدخال رمز الـ OTP ----------------
                  else if (_currentStep == 1) ...[
                    const Text(
                      'أدخل رمز التحقق (OTP)',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'تم إرسال رمز التحقق إلى $_formattedPhone',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 25),
                    TextField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 20, letterSpacing: 8),
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: 'رمز التحقق (6 أرقام)',
                        labelStyle:
                            const TextStyle(color: Colors.grey, letterSpacing: 0),
                        prefixIcon:
                            const Icon(Icons.lock_clock_outlined, color: primaryGold),
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
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGold,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isLoading
                          ? null
                          : () => _verifyOTPAndProceed(appState),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.black)
                          : const Text('تأكيد الرمز والمتابعة 🔑',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15)),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _currentStep = 0),
                      child: const Text('تغيير رقم الهاتف',
                          style: TextStyle(color: primaryGold)),
                    ),
                  ]

                  // ---------------- المرحلة الثالثة: إكمال وتأكيد البيانات الشخصية والعنوان ----------------
                  else ...[
                    const Text(
                      'استكمال وتأكيد البيانات الشخصية',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
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
                        prefixIcon:
                            const Icon(Icons.location_on, color: primaryGold),
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
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: primaryGold),
                        minimumSize: const Size(double.infinity, 45),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.map, color: primaryGold),
                      label: const Text(
                        'تحديد موقعك عبر الخريطة التفاعلية 🗺️',
                        style: TextStyle(
                            color: primaryGold, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _openInteractiveMap,
                    ),
                    const SizedBox(height: 25),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGold,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        final name = _nameController.text.trim();
                        final address = _addressController.text.trim();

                        if (name.isNotEmpty && address.isNotEmpty) {
                          // حفظ بيانات العميل في جدول customers في Supabase
                          await _supabase.from('customers').upsert({
                            'phone_number': _formattedPhone,
                            'full_name': name,
                            'address': address,
                          }, onConflict: 'phone_number');

                          await appState.saveUserProfileDetails(
                            name,
                            address,
                          );

                          await appState.requestLocationAndNotificationPermissions();

                          // حفظ OneSignal Player ID مع العميل
                          try {
                            String? playerId =
                                OneSignal.User.pushSubscription.id;
                            if (playerId != null && playerId.isNotEmpty) {
                              await _supabase
                                  .from('customers')
                                  .update({'onesignal_player_id': playerId})
                                  .eq('phone_number', _formattedPhone);
                            }
                          } catch (e) {
                            debugPrint('خطأ في حفظ Player ID: $e');
                          }

                          if (widget.onLoginSuccess != null) {
                            widget.onLoginSuccess!();
                          } else {
                            Navigator.pop(context);
                          }

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'أهلاً بك! تم حفظ البيانات وتسجيل الدخول بنجاح 🎉')),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('الرجاء إدخال الاسم والعنوان كاملاً')),
                          );
                        }
                      },
                      child: const Text('حفظ والدخول للتطبيق 🚀',
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
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
