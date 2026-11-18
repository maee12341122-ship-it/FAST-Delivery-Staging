import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import '../../providers/app_state.dart';
import '../customer/map_location_screen.dart';
import '../admin_screen.dart';   
import '../courier_screen.dart'; 

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
  final TextEditingController _addressController = TextEditingController();
  
  // حقول شاشة تسجيل الدخول الخاصة بالأدمن والمندوب
  final TextEditingController _loginUsernameController = TextEditingController();
  final TextEditingController _loginPasswordController = TextEditingController();

  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _otpFocus = FocusNode();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _addressFocus = FocusNode();

  // المراحل: 0 = إدخال الرقم، 1 = إدخال OTP، 2 = إكمال بروفايل العميل، 3 = شاشة تسجيل الدخول الخاصة (أدمن أو مندوب)
  int _currentStep = 0;
  bool _isLoading = false;

  final SupabaseClient _supabase = Supabase.instance.client;
  String _formattedPhone = '';
  String _cleanPhoneInput = '';
  String _detectedRole = 'customer_new'; // 'admin', 'courier', 'customer_existing', 'customer_new'
  Map<String, dynamic>? _pendingUserRecord; 

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _loginUsernameController.dispose();
    _loginPasswordController.dispose();
    _phoneFocus.dispose();
    _otpFocus.dispose();
    _nameFocus.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

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

  // 1️⃣ إرسال كود OTP وتوليده وحفظه في جدول otp_codes في Supabase وفحص دور المستخدم
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

      // 1. فحص هل الرقم يتبع للمشرفين (admins)
      final adminRes = await _supabase
          .from('admins')
          .select()
          .or('phone.eq.$_cleanPhoneInput,phone.eq.$_formattedPhone')
          .maybeSingle();

      if (adminRes != null) {
        _detectedRole = 'admin';
        _pendingUserRecord = adminRes;
        _loginUsernameController.text = adminRes['username'] ?? adminRes['name'] ?? '';
      } else {
        // 2. فحص هل الرقم يتبع للمناديب (couriers)
        final courierRes = await _supabase
            .from('couriers')
            .select()
            .or('phone.eq.$_cleanPhoneInput,phone.eq.$_formattedPhone')
            .maybeSingle();

        if (courierRes != null) {
          _detectedRole = 'courier';
          _pendingUserRecord = courierRes;
          _loginUsernameController.text = courierRes['username'] ?? courierRes['name'] ?? '';
        } else {
          // 3. فحص هل العميل موجود مسبقاً
          final existingCustomer = await _supabase
              .from('customers')
              .select()
              .or('phone.eq.$_cleanPhoneInput,phone.eq.$_formattedPhone')
              .maybeSingle();

          if (existingCustomer != null) {
            _detectedRole = 'customer_existing';
            if (mounted) {
              _nameController.text = existingCustomer['name'] ?? '';
              _addressController.text = existingCustomer['address'] ?? '';
            }
          } else {
            _detectedRole = 'customer_new';
          }
        }
      }

      // استدعاء دالة توليد وإرسال الرمز الحقيقية من الـ AppState
      await appState.requestOtpForPhone(_formattedPhone);

      if (mounted) {
        setState(() {
          _currentStep = 1; 
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم توليد وإرسال رمز التحقق بنجاح 💬'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في إرسال الرمز: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر إرسال رمز التحقق، يرجى المحاولة لاحقاً')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 2️⃣ التحقق من كود OTP من جدول otp_codes والانتقال للشاشة التالية
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
      // التحقق عبر دالة الـ AppState المرتبطة بقاعدة البيانات
      bool isValid = await appState.verifyOtpAndLogin(_cleanPhoneInput, otpCode);

      if (isValid) {
        if (mounted) {
          if (_detectedRole == 'admin' || _detectedRole == 'courier') {
            setState(() {
              _currentStep = 3; // الانتقال لشاشة تسجيل الدخول الخاصة (مشرف أو مندوب)
            });
          } else {
            if (_detectedRole == 'customer_existing') {
              // إذا كان عميلاً مسجلاً مسبقاً، نسجل دخوله مباشرة ونتخطى صفحة البروفايل
              if (widget.onLoginSuccess != null) {
                widget.onLoginSuccess!();
              } else {
                Navigator.pop(context);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('أهلاً بك مجدداً! تم تسجيل الدخول بنجاح 🚀')),
              );
              return;
            }
            setState(() {
              _currentStep = 2; // استكمال بيانات العميل الجديد
            });
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('رمز التحقق غير صحيح أو انتهت صلاحيته ❌')),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من OTP: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدث خطأ أثناء التحقق من الرمز')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 3️⃣ التحقق من اسم المستخدم وكلمة المرور الخاصة بالأدمن أو المندوب
  Future<void> _verifyAdminOrCourierCredentials(AppState appState) async {
    final enteredPassword = _loginPasswordController.text.trim();
    if (enteredPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال كلمة المرور')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_pendingUserRecord != null) {
        final storedPassword = _pendingUserRecord!['password_hash']?.toString() ?? 
                               _pendingUserRecord!['password']?.toString() ?? '';

        if (storedPassword == enteredPassword) {
          if (!mounted) return;

          if (_detectedRole == 'admin') {
            appState.isAdminLoggedIn = true;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const AdminScreen()),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('مرحباً بك يا مشرف النظام 🛡️')),
            );
          } else if (_detectedRole == 'courier') {
            appState.currentCourier = _pendingUserRecord;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const CourierScreen()),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('مرحباً بك يا مندوب التوصيل 🛵')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('كلمة المرور غير صحيحة ❌'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في التحقق: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 4️⃣ حفظ بيانات العميل النهائية
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
        const SnackBar(content: Text('أهلاً بك! تم حفظ البيانات وتسجيل الدخول بنجاح 🎉')),
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
              'FAST – تسجيل الدخول والتحقق',
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
                      child: Icon(
                        _currentStep == 1
                            ? Icons.mark_chat_read_outlined
                            : _currentStep == 3
                                ? (_detectedRole == 'admin' ? Icons.admin_panel_settings : Icons.delivery_dining)
                                : Icons.person_outline_rounded,
                        size: 50,
                        color: primaryGold,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ---------------- المرحلة 0: إدخال رقم الهاتف ----------------
                    if (_currentStep == 0) ...[
                      const Text(
                        'تسجيل الدخول برقم الهاتف',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'أدخل رقم هاتفك لتلقي رمز التحقق عبر الواتساب',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 25),
                      TextField(
                        controller: _phoneController,
                        focusNode: _phoneFocus,
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
                        onPressed: _isLoading ? null : () => _sendSupabaseOTP(appState),
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                              )
                            : const Text('إرسال رمز التحقق عبر واتساب 💬',
                                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ]

                    // ---------------- المرحلة 1: إدخال رمز OTP ----------------
                    else if (_currentStep == 1) ...[
                      const Text(
                        'أدخل رمز التحقق (OTP)',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
                        style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 8),
                        maxLength: 4,
                        decoration: InputDecoration(
                          labelText: 'رمز التحقق (4 أرقام)',
                          labelStyle: const TextStyle(color: Colors.grey, letterSpacing: 0),
                          prefixIcon: const Icon(Icons.lock_clock_outlined, color: primaryGold),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isLoading ? null : () => _verifyOTPAndProceed(appState),
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                              )
                            : const Text('تأكيد الرمز والمتابعة 🔑',
                                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _currentStep = 0),
                        child: const Text('تغيير رقم الهاتف', style: TextStyle(color: primaryGold)),
                      ),
                    ]

                    // ---------------- المرحلة 3: شاشة تسجيل دخول المشرف أو المندوب ----------------
                    else if (_currentStep == 3) ...[
                      Text(
                        _detectedRole == 'admin' ? 'تسجيل دخول المشرف الآمن 🛡️' : 'بوابة تسجيل دخول الكابتن 🛵',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'أدخل بيانات الاعتماد الخاصة بك للوصول للطلبات',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 25),
                      TextField(
                        controller: _loginUsernameController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'اسم المستخدم أو البريد الإلكتروني',
                          labelStyle: const TextStyle(color: Colors.grey),
                          prefixIcon: const Icon(Icons.person_outline, color: primaryGold),
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
                      const SizedBox(height: 14),
                      TextField(
                        controller: _loginPasswordController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'كلمة السر',
                          labelStyle: const TextStyle(color: Colors.grey),
                          prefixIcon: const Icon(Icons.lock_outline, color: primaryGold),
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
                        onPressed: _isLoading ? null : () => _verifyAdminOrCourierCredentials(appState),
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                              )
                            : Text(
                                _detectedRole == 'admin' ? 'دخول لوحة التحكم 🚀' : 'دخول لوحة الطلبات 🚀',
                                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                      ),
                    ]

                    // ---------------- المرحلة 2: إكمال بروفايل العميل الجديد ----------------
                    else ...[
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
                        focusNode: _nameFocus,
                        keyboardType: TextInputType.name,
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
                        keyboardType: TextInputType.text,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'العنوان التفصيلي (أو حدده عبر الخريطة)',
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
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: primaryGold),
                          minimumSize: const Size(double.infinity, 45),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.map, color: primaryGold),
                        label: const Text(
                          'تحديد موقعك عبر الخريطة التفاعلية 🗺️',
                          style: TextStyle(color: primaryGold, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _openInteractiveMap,
                      ),
                      const SizedBox(height: 25),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGold,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _saveCustomerProfile(appState),
                        child: const Text('حفظ والدخول للتطبيق 🚀',
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
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
