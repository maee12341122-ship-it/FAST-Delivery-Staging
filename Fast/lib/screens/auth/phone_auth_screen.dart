import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/app_state.dart';
import '../../services/notification_service.dart';
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
  String _detectedRole =
      'customer_new'; // 'admin', 'courier', 'customer_existing', 'customer_new'
  Map<String, dynamic>? _pendingUserRecord;

  // عداد النقرات المخفية للوصول لإدارة النظام سراّ
  int _secretTapCount = 0;

  @override
  void initState() {
    super.initState();
    _checkExistingAdminOrCourierSession();
  }

  String _normalizePhone(String rawPhone) {
    String clean = rawPhone.trim().replaceAll(' ', '');
    if (clean.startsWith('+967')) clean = clean.substring(4);
    if (clean.startsWith('0')) clean = clean.substring(1);
    if (clean.startsWith('967')) clean = clean.substring(3);
    return clean;
  }

  // 🛡️ التحقق التلقائي إذا كان المشرف أو المندوب مسجل الدخول مسبقاً لتخطي تسجيل الدخول
  Future<void> _checkExistingAdminOrCourierSession() async {
    try {
      final session = _supabase.auth.currentSession;
      if (session != null) {
        final user = session.user;
        final appRole = user.appMetadata['role']?.toString();

        if (appRole == 'admin') {
          final email = (user.email ?? '').trim().toLowerCase();
          final candidateUsername =
              email.contains('@') ? email.split('@').first : email;
          if (candidateUsername.isNotEmpty) {
            final adminRes = await _supabase
                .from('admins')
                .select('id, username, phone')
                .eq('username', candidateUsername)
                .maybeSingle();

            if (adminRes != null && mounted) {
              Provider.of<AppState>(context, listen: false).isAdminLoggedIn =
                  true;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const AdminScreen()),
              );
              return;
            }
          }
        }

        // فحص هل هو مندوب عبر auth_user_id (uuid)
        final courierRes = await _supabase
            .from('couriers')
            .select()
            .eq('auth_user_id', user.id)
            .maybeSingle();

        if (courierRes != null && courierRes['status']?.toString() != 'disabled') {
          if (!mounted) return;
          Provider.of<AppState>(context, listen: false).currentCourier =
              Map<String, dynamic>.from(courierRes);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const CourierScreen()),
          );
          return;
        }
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في فحص الجلسة التلقائية: $e');
    }
  }

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
            _addressController.text =
                '$address - الإحداثيات: $formattedCoords';
          } else {
            _addressController.text =
                'الموقع المحدد - الإحداثيات: $formattedCoords';
          }
        } else if (address != null && address.isNotEmpty) {
          _addressController.text = address;
        }
      });
    }
  }

  Future<void> _syncOneSignalPlayerId(String customerIdOrPhone) async {
    try {
      await NotificationService.saveUserPlayerId(
        customerIdOrPhone,
        'customers',
      );
    } catch (e) {
      debugPrint('خطأ في حفظ Player ID: $e');
    }
  }

  // 1️⃣ طلب إرسال كود OTP عبر الخادم وفحص دور المستخدم وجلب بيانات العميل المسجل من قاعدة البيانات
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
      final clean = _normalizePhone(phone);
      _cleanPhoneInput = clean;
      _formattedPhone = '+967$clean';
      _pendingUserRecord = null;
      _otpController.clear();

      // 1. فحص هل الرقم يتبع للمشرفين (admins)
      final adminRes = await _supabase
          .from('admins')
          .select('id, username, phone')
          .or('phone.eq.$_cleanPhoneInput,phone.eq.$_formattedPhone')
          .maybeSingle();

      if (adminRes != null) {
        _detectedRole = 'admin';
        _pendingUserRecord = Map<String, dynamic>.from(adminRes);
        _loginUsernameController.text = adminRes['username']?.toString() ?? '';
        if (mounted) {
          setState(() => _currentStep = 3);
        }
        return;
      }

      // 2. فحص هل الرقم يتبع للمناديب (couriers)
      final courierRes = await _supabase
          .from('couriers')
          .select('id, username, name, phone, status')
          .or('phone.eq.$_cleanPhoneInput,phone.eq.$_formattedPhone')
          .maybeSingle();

      if (courierRes != null) {
        _detectedRole = 'courier';
        _pendingUserRecord = Map<String, dynamic>.from(courierRes);
        _loginUsernameController.text =
            courierRes['username']?.toString() ?? '';
        if (mounted) {
          setState(() => _currentStep = 3);
        }
        return;
      }

      // 3. فحص هل العميل موجود مسبقاً في جدول customers وجلب بياناته المسجلة
      final existingCustomer = await _supabase
          .from('customers')
          .select()
          .or('phone.eq.$_cleanPhoneInput,phone.eq.$_formattedPhone')
          .maybeSingle();

      if (existingCustomer != null) {
        _pendingUserRecord = Map<String, dynamic>.from(existingCustomer);
        final savedName = (existingCustomer['name'] ?? '').toString().trim();
        final savedAddress =
            (existingCustomer['address'] ?? '').toString().trim();

        if (mounted) {
          _nameController.text = savedName;
          _addressController.text = savedAddress;
        }

        if (savedName.isNotEmpty && savedAddress.isNotEmpty) {
          _detectedRole = 'customer_existing';
        } else {
          _detectedRole = 'customer_new';
        }
      } else {
        _detectedRole = 'customer_new';
      }

      // طلب توليد وإرسال OTP فعلياً عبر Backend
      final reqResult = await appState.requestOtpForPhone(_cleanPhoneInput);
      final msg = (reqResult is Map && reqResult['message'] != null)
          ? reqResult['message'].toString()
          : 'تم طلب إرسال رمز التحقق إلى $_formattedPhone 💬';

      if (mounted) {
        setState(() {
          _currentStep = 1;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في إرسال الرمز: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceAll('Exception: ', '').isNotEmpty
                  ? e.toString().replaceAll('Exception: ', '')
                  : 'تعذر إرسال رمز التحقق، يرجى المحاولة لاحقاً',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 2️⃣ التحقق من كود OTP عبر الخادم وتفعيل الجلسة للعميل أو الانتقال لاستكمال البروفايل
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
      final bool isValid =
          await appState.verifyOtpAndLogin(_cleanPhoneInput, otpCode);

      if (isValid) {
        if (_detectedRole == 'customer_existing' && _pendingUserRecord != null) {
          final dbPhone =
              (_pendingUserRecord!['phone'] ?? _cleanPhoneInput).toString();
          final latestRecord = await _supabase
              .from('customers')
              .select()
              .eq('phone', dbPhone)
              .maybeSingle();

          final customerRow = latestRecord ?? _pendingUserRecord!;
          final String customerName =
              (customerRow['name'] ?? '').toString().trim();
          final String customerPhone =
              (customerRow['phone'] ?? dbPhone).toString().trim();
          final String customerAddress =
              (customerRow['address'] ?? '').toString().trim();

          appState.setUser(
            name: customerName,
            phone: customerPhone,
            address: customerAddress,
          );

          await appState.requestLocationAndNotificationPermissions();
          final syncKey = customerRow['id']?.toString() ?? customerPhone;
          await _syncOneSignalPlayerId(syncKey);

          if (!mounted) return;
          if (widget.onLoginSuccess != null) {
            widget.onLoginSuccess!();
          } else {
            Navigator.pop(context);
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'أهلاً بك مجدداً يا $customerName! تم تسجيل الدخول بنجاح 🚀'),
            ),
          );
        } else {
          if (mounted) {
            setState(() {
              _currentStep = 2; // استكمال بيانات العميل الجديد أو الناقصة
            });
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('رمز التحقق غير صحيح أو انتهت صلاحيته ❌')),
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
    final username = _loginUsernameController.text.trim();
    final password = _loginPasswordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال اسم المستخدم وكلمة المرور')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_detectedRole == 'admin' || _detectedRole.isEmpty) {
        bool adminSuccess =
            await appState.loginAdminFromSupabase(username, password);
        if (adminSuccess) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AdminScreen()),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('مرحباً بك يا مشرف النظام 🛡️')),
          );
          return;
        }
      }

      bool courierSuccess = await appState.loginCourier(username, password);
      if (courierSuccess) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const CourierScreen()),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('مرحباً بك يا مندوب التوصيل 🛵')),
        );
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('بيانات الاعتماد غير صحيحة ❌'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في تسجيل الدخول: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 4️⃣ حفظ بيانات العميل النهائية في قاعدة البيانات وتحديث AppState
  Future<void> _saveCustomerProfile(AppState appState) async {
    final name = _nameController.text.trim();
    final address = _addressController.text.trim();

    if (name.isEmpty || address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال الاسم والعنوان كاملاً')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final cleanPhone =
          _cleanPhoneInput.isNotEmpty ? _cleanPhoneInput : _formattedPhone;

      final savedRecord = await _supabase
          .from('customers')
          .upsert({
            'phone': cleanPhone,
            'name': name,
            'address': address,
          }, onConflict: 'phone')
          .select()
          .maybeSingle();

      final finalName = (savedRecord?['name'] ?? name).toString().trim();
      final finalPhone = (savedRecord?['phone'] ?? cleanPhone).toString().trim();
      final finalAddress =
          (savedRecord?['address'] ?? address).toString().trim();

      appState.setUser(
        name: finalName,
        phone: finalPhone,
        address: finalAddress,
      );

      await appState.requestLocationAndNotificationPermissions();
      final syncKey = savedRecord?['id']?.toString() ?? finalPhone;
      await _syncOneSignalPlayerId(syncKey);

      if (!mounted) return;
      if (widget.onLoginSuccess != null) {
        widget.onLoginSuccess!();
      } else {
        Navigator.pop(context);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('أهلاً بك! تم حفظ البيانات وتسجيل الدخول بنجاح 🎉')),
      );
    } catch (e) {
      debugPrint('❌ خطأ في حفظ بيانات العميل: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تعذر حفظ البيانات، يرجى المحاولة مرة أخرى')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
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
                  border: Border.all(
                      color: primaryGold.withOpacity(0.3), width: 1),
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
                    // 🕵️‍♂️ النقرة المخفية السريعة (الضغط 5 مرات متتالية على الأيقونة يفتح شاشة الأدمن سراً)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _secretTapCount++;
                          if (_secretTapCount >= 5) {
                            _secretTapCount = 0;
                            _detectedRole = 'admin';
                            _currentStep = 3;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      '🔐 تم تفعيل وضع الدخول الإداري السري')),
                            );
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: primaryGold.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _currentStep == 1
                              ? Icons.mark_chat_read_outlined
                              : _currentStep == 3
                                  ? (_detectedRole == 'admin'
                                      ? Icons.admin_panel_settings
                                      : Icons.delivery_dining)
                                  : Icons.person_outline_rounded,
                          size: 50,
                          color: primaryGold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ---------------- المرحلة 0: إدخال رقم الهاتف ----------------
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
                          prefixIcon: const Icon(Icons.phone_android,
                              color: primaryGold),
                          filled: true,
                          fillColor: backgroundColor,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade800),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: primaryGold, width: 2),
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
                        onPressed:
                            _isLoading ? null : () => _sendSupabaseOTP(appState),
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.black, strokeWidth: 2),
                              )
                            : const Text('إرسال رمز التحقق عبر واتساب 💬',
                                style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                      ),
                    ]

                    // ---------------- المرحلة 1: إدخال رمز OTP ----------------
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
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 25),
                      TextField(
                        controller: _otpController,
                        focusNode: _otpFocus,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            letterSpacing: 8),
                        maxLength: 4,
                        decoration: InputDecoration(
                          labelText: 'رمز التحقق (4 أرقام)',
                          labelStyle: const TextStyle(
                              color: Colors.grey, letterSpacing: 0),
                          prefixIcon: const Icon(Icons.lock_clock_outlined,
                              color: primaryGold),
                          filled: true,
                          fillColor: backgroundColor,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade800),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: primaryGold, width: 2),
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
                                child: CircularProgressIndicator(
                                    color: Colors.black, strokeWidth: 2),
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

                    // ---------------- المرحلة 3: شاشة تسجيل دخول المشرف أو المندوب السرّية ----------------
                    else if (_currentStep == 3) ...[
                      Text(
                        _detectedRole == 'admin'
                            ? 'تسجيل دخول المشرف الآمن 🛡️'
                            : 'بوابة تسجيل دخول الكابتن 🛵',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
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
                          prefixIcon: const Icon(Icons.person_outline,
                              color: primaryGold),
                          filled: true,
                          fillColor: backgroundColor,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade800),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: primaryGold, width: 2),
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
                          prefixIcon:
                              const Icon(Icons.lock_outline, color: primaryGold),
                          filled: true,
                          fillColor: backgroundColor,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade800),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: primaryGold, width: 2),
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
                        onPressed: _isLoading
                            ? null
                            : () => _verifyAdminOrCourierCredentials(appState),
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.black, strokeWidth: 2),
                              )
                            : Text(
                                _detectedRole == 'admin'
                                    ? 'دخول لوحة التحكم 🚀'
                                    : 'دخول لوحة الطلبات 🚀',
                                style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _currentStep = 0),
                        child: const Text('العودة لتسجيل العملاء',
                            style: TextStyle(color: primaryGold)),
                      ),
                    ]

                    // ---------------- المرحلة 2: إكمال بروفايل العميل الجديد ----------------
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
                        keyboardType: TextInputType.name,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'الاسم الكامل',
                          labelStyle: const TextStyle(color: Colors.grey),
                          prefixIcon:
                              const Icon(Icons.person, color: primaryGold),
                          filled: true,
                          fillColor: backgroundColor,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade800),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: primaryGold, width: 2),
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
                          prefixIcon: const Icon(Icons.location_on,
                              color: primaryGold),
                          filled: true,
                          fillColor: backgroundColor,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade800),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: primaryGold, width: 2),
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
                        onPressed: _isLoading
                            ? null
                            : () => _saveCustomerProfile(appState),
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.black, strokeWidth: 2),
                              )
                            : const Text('حفظ والدخول للتطبيق 🚀',
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
