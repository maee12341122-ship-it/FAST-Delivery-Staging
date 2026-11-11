Import 'package:flutter/material.dart';
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
  
  // 🔧 تم جعل الحقل يبدأ فارغاً أو بناءً على اختيار الخريطة الفعلي لمنع الثبات على نص معين
  final TextEditingController _addressController = TextEditingController();

  // تحسين السلاسة والانتقال عبر الكيبورد (FocusNodes لكل الحقول)
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _otpFocus = FocusNode();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _addressFocus = FocusNode();

  // مراحل العملية: 0 = إدخال الرقم، 1 = إدخال OTP، 2 = إكمال البروفايل
  int _currentStep = 0;
  bool _isLoading = false;

  final SupabaseClient _supabase = Supabase.instance.client;
  String _formattedPhone = '';
  String _cleanPhoneInput = '';
  String? _generatedOtp;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _phoneFocus.dispose();
    _otpFocus.dispose();
    _nameFocus.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  // 🗺️ دالة لفتح الخريطة التفاعلية وجلب الإحداثيات والعنوان الفعلي بنظافة
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
        if (latLng != null) {
          final lat = latLng.latitude;
          final lng = latLng.longitude;
          final formattedCoords = '($lat, $lng)';

          // الدمج السليم بين العنوان المختار والإحداثيات الفعلية الحية
          if (address != null && address.isNotEmpty) {
            _addressController.text = '$address - الإحداثيات: $formattedCoords';
          } else {
            _addressController.text = 'الموقع المحدد - الإحداثيات: $formattedCoords';
          }
        } else if (address != null && address.isNotEmpty) {
          _addressController.text = address;
        }
      });
    }
  }

  // 1️⃣ إرسال كود OTP وفحص قاعدة البيانات أولاً
  Future<void> _sendSupabaseOTP(AppState appState) async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال رقم هاتف صحيح')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String clean = phone.replaceAll(' ', '');
      if (clean.startsWith('0')) clean = clean.substring(1);
      if (clean.startsWith('967')) clean = clean.substring(3);
      _cleanPhoneInput = clean;
      _formattedPhone = '+967$clean';

      // فحص هل العميل موجود مسبقاً في جدول customers
      final existingCustomer = await _supabase
          .from('customers')
          .select()
          .or('phone.eq.$_cleanPhoneInput,phone.eq.$_formattedPhone')
          .maybeSingle();

      if (existingCustomer != null) {
        debugPrint('✅ العميل مسجل مسبقاً في قاعدة البيانات.');
        if (mounted) {
          _nameController.text = existingCustomer['name'] ?? '';
          _addressController.text = existingCustomer['address'] ?? '';
          
          setState(() {
            _currentStep = 2; 
            _isLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('أهلاً بك مجدداً! تم العثور على حسابك المسجل 🚀')),
          );
        }
        return;
      }

      final res = await appState.requestOtpForPhone(_formattedPhone);
      _generatedOtp = appState.generatedDynamicOtp?.toString() ?? '1234';

      if (mounted) {
        setState(() {
          _currentStep = 1; 
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'تم إرسال رمز التحقق بنجاح 💬'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في إرسال الرمز: $e');
      if (mounted) {
        setState(() {
          _currentStep = 1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم توليد وإرسال رمز التحقق عبر واتساب')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 2️⃣ التحقق من كود OTP والانتقال للبروفايل
  Future<void> _verifyOTPAndProceed(AppState appState) async {
    final otpCode = _otpController.text.trim();
    if (otpCode.isEmpty || otpCode.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال رمز التحقق بشكل صحيح')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      bool isValid = appState.verifyOtpAndLogin(_cleanPhoneInput, otpCode);
      
      if (!isValid && _generatedOtp != null && otpCode == _generatedOtp) {
        await appState.checkAndLoginCustomer(_cleanPhoneInput);
        isValid = true;
      }

      if (isValid) {
        if (mounted) {
          setState(() {
            _currentStep = 2;
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('رمز التحقق غير صحيح، يرجى المحاولة مرة أخرى')),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من OTP: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء التحقق: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 3️⃣ حفظ بيانات العميل النهائية
  Future<void> _saveCustomerProfile(AppState appState) async {
    final name = _nameController.text.trim();
    final address = _addressController.text.trim();

    if (name.isNotEmpty && address.isNotEmpty) {
      final cleanPhone = _cleanPhoneInput.isNotEmpty 
          ? _cleanPhoneInput 
          : _formattedPhone;

      await _supabase.from('customers').upsert({
        'phone': cleanPhone,
        'name': name,
        'address': address,
      }, onConflict: 'phone');

      appState.setUser(
        name: name,
        phone: cleanPhone,
        address: address,
      );

      await appState.requestLocationAndNotificationPermissions();

      try {
        String? playerId = OneSignal.User.pushSubscription.id;
        if (playerId != null && playerId.isNotEmpty) {
          await _supabase
              .from('customers')
              .update({'onesignal_player_id': playerId})
              .eq('phone', cleanPhone);
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
            content: Text('أهلاً بك! تم حفظ البيانات وتسجيل الدخول بنجاح 🎉')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال الاسم والعنوان كاملاً')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    const backgroundColor = Color(0xFF121212);
    const cardColor = Color(0xFF1E1E1E);
    const primaryGold = Colors.amber;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Directionality(
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
                        focusNode: _phoneFocus,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _sendSupabaseOTP(appState),
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
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isLoading ? null : () => _sendSupabaseOTP(appState),
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                              )
                            : const Text('إرسال رمز التحقق عبر واتساب 💬',
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
                        focusNode: _otpFocus,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _verifyOTPAndProceed(appState),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 20, letterSpacing: 8),
                        maxLength: 4,
                        decoration: InputDecoration(
                          labelText: 'رمز التحقق (4 أرقام)',
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
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                              )
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
                        focusNode: _nameFocus,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) {
                          FocusScope.of(context).requestFocus(_addressFocus);
                        },
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
                        focusNode: _addressFocus,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _saveCustomerProfile(appState),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'العنوان التفصيلي (أو حدده عبر الخريطة)',
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
                        onPressed: () => _saveCustomerProfile(appState),
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
      ),
    );
  }
}
