import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/app_state.dart';
import '../../services/api_service.dart';
import '../../services/fcm_push_service.dart';
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
  static const Duration _authNetworkTimeout = Duration(seconds: 25);

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  final TextEditingController _loginUsernameController = TextEditingController();
  final TextEditingController _loginPasswordController = TextEditingController();

  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _otpFocus = FocusNode();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _addressFocus = FocusNode();

  int _currentStep = 0;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isSubmittingCredentials = false;

  final SupabaseClient _supabase = Supabase.instance.client;
  String _formattedPhone = '';
  String _cleanPhoneInput = '';
  String _detectedRole = 'customer_new';
  Map<String, dynamic>? _pendingUserRecord;

  int _secretTapCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_checkExistingAdminOrCourierSession());
  }

  String _normalizePhone(String rawPhone) {
    String clean = rawPhone.trim().replaceAll(' ', '');
    if (clean.startsWith('+967')) clean = clean.substring(4);
    if (clean.startsWith('0')) clean = clean.substring(1);
    if (clean.startsWith('967')) clean = clean.substring(3);
    return clean;
  }

  List<String> _buildLoginEmailCandidates(
    Map<String, dynamic>? record,
    String rawInput,
  ) {
    final List<String> candidates = [];

    void addEmail(String value) {
      final clean = value.trim().toLowerCase();
      if (clean.isEmpty) return;
      if (clean.contains('@')) {
        if (!candidates.contains(clean)) candidates.add(clean);
      } else {
        final withFast = '$clean@fast.com';
        if (!candidates.contains(withFast)) candidates.add(withFast);
      }
    }

    addEmail((record?['email'] ?? '').toString());
    addEmail((record?['username'] ?? '').toString());
    addEmail(rawInput);

    return candidates;
  }

  String _formatFriendlyError(Object error, String fallbackMessage) {
    if (error is TimeoutException) {
      return 'الشبكة بطيئة حالياً، حاول مرة أخرى أو تحقق من اتصالك بالإنترنت';
    }
    final rawErr =
        error.toString().replaceFirst(RegExp(r'^ApiException:\s*'), '').trim();
    if (rawErr.isEmpty) return fallbackMessage;
    return rawErr;
  }

  Future<bool> _tryLoginAdminWithCandidates(
    AppState appState,
    List<String> emailCandidates,
    String password,
  ) async {
    for (final email in emailCandidates) {
      try {
        final ok = await appState
            .loginAdminFromSupabase(email, password)
            .timeout(_authNetworkTimeout);
        if (ok || appState.isAdminLoggedIn) {
          appState.isAdminLoggedIn = true;
          return true;
        }
      } catch (e) {
        debugPrint('⚠️ محاولة دخول مشرف لـ $email: $e');
      }

      try {
        final sessionUser = _supabase.auth.currentUser;
        if (sessionUser != null && appState.isAdminLoggedIn) {
          return true;
        }
      } catch (_) {}
    }
    return appState.isAdminLoggedIn;
  }

  Future<bool> _tryLoginCourierWithCandidates(
    AppState appState,
    List<String> emailCandidates,
    String password,
  ) async {
    for (final email in emailCandidates) {
      try {
        final ok = await appState
            .loginCourier(email, password)
            .timeout(_authNetworkTimeout);
        if (ok || appState.currentCourier != null) {
          return true;
        }
      } catch (e) {
        debugPrint('⚠️ محاولة دخول مندوب لـ $email: $e');
      }
    }
    return appState.currentCourier != null;
  }

  Future<void> _syncAdminUserSession(
    AppState appState, {
    String? username,
    Map<String, dynamic>? adminRecord,
  }) async {
    Map<String, dynamic>? record = adminRecord ?? _pendingUserRecord;

    try {
      if (record == null && username != null && username.trim().isNotEmpty) {
        final cleanUser = username.trim().toLowerCase();
        final userPrefix =
            cleanUser.contains('@') ? cleanUser.split('@').first : cleanUser;
        final res = await _supabase
            .from('admins')
            .select('id, username, phone')
            .or('username.ilike.$cleanUser,username.ilike.$userPrefix')
            .maybeSingle()
            .timeout(const Duration(seconds: 10));
        if (res != null) {
          record = Map<String, dynamic>.from(res);
        }
      } else if (record == null && _cleanPhoneInput.isNotEmpty) {
        final res = await _supabase
            .from('admins')
            .select('id, username, phone')
            .or('phone.eq.$_cleanPhoneInput,phone.eq.$_formattedPhone')
            .maybeSingle()
            .timeout(const Duration(seconds: 10));
        if (res != null) {
          record = Map<String, dynamic>.from(res);
        }
      }
    } catch (e) {
      debugPrint('⚠️ تعذر جلب سجل المشرف الكامل: $e');
    }

    final String resolvedUsername = (record?['username'] ??
            username ??
            _loginUsernameController.text.trim())
        .toString()
        .trim();

    final String resolvedPhone = _normalizePhone(
      (record?['phone'] ??
              (_cleanPhoneInput.isNotEmpty ? _cleanPhoneInput : ''))
          .toString()
          .trim(),
    );

    final String resolvedName =
        (resolvedUsername.isNotEmpty ? resolvedUsername : 'مشرف النظام').trim();

    const String resolvedAddress = 'تعز';

    appState.setUser(
      name: resolvedName,
      phone: resolvedPhone,
      address: resolvedAddress,
    );

    if (appState.userProfile != null) {
      appState.userProfile!['is_admin'] = true;
      if (record?['id'] != null) {
        appState.userProfile!['id'] = record!['id'];
      }
      if (resolvedUsername.isNotEmpty) {
        appState.userProfile!['username'] = resolvedUsername;
      }
      appState.notifyListeners();
    }

    if (record?['id'] != null) {
      unawaited(
        FcmPushService.syncTokenForCurrentUser(
          role: 'admin',
          rowId: record!['id'],
        ),
      );
    }
  }

  Future<void> _checkExistingAdminOrCourierSession() async {
    try {
      final session = _supabase.auth.currentSession;
      if (session == null) return;

      final user = session.user;
      final email = (user.email ?? '').trim().toLowerCase();
      final candidateUsername =
          email.contains('@') ? email.split('@').first : email;

      final results = await Future.wait<dynamic>([
        if (candidateUsername.isNotEmpty)
          _supabase
              .from('admins')
              .select('id, username, phone')
              .or('username.ilike.$email,username.ilike.$candidateUsername')
              .maybeSingle()
              .timeout(const Duration(seconds: 10))
        else
          Future.value(null),
        _supabase
            .from('couriers')
            .select()
            .eq('auth_user_id', user.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 10)),
      ]);

      final adminRes = results[0];
      final courierRes = results[1];

      if (adminRes != null && mounted) {
        final appState = Provider.of<AppState>(context, listen: false);
        appState.isAdminLoggedIn = true;
        unawaited(_syncAdminUserSession(
          appState,
          username: candidateUsername,
          adminRecord: Map<String, dynamic>.from(adminRes),
        ));
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AdminScreen()),
        );
        return;
      }

      if (courierRes != null &&
          courierRes['status']?.toString() != 'disabled' &&
          mounted) {
        final appState = Provider.of<AppState>(context, listen: false);
        appState.currentCourier = Map<String, dynamic>.from(courierRes);
        if (courierRes['id'] != null) {
          unawaited(FcmPushService.syncTokenForCurrentUser(
            role: 'courier',
            rowId: courierRes['id'],
          ));
        }
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const CourierScreen()),
        );
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

  void _syncFcmTokenBackground(
    AppState appState, {
    required String role,
    dynamic rowId,
  }) {
    unawaited(() async {
      try {
        await appState
            .requestLocationAndNotificationPermissions()
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
      try {
        await FcmPushService.requestPermissionAndSyncToken(
          role: role,
          rowId: rowId,
        ).timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('خطأ في مزامنة FCM token: $e');
      }
    }());
  }

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

      final filterOr = 'phone.eq.$_cleanPhoneInput,phone.eq.$_formattedPhone';

      final lookupResults = await Future.wait<dynamic>([
        _supabase
            .from('admins')
            .select('id, username, phone')
            .or(filterOr)
            .maybeSingle(),
        _supabase
            .from('couriers')
            .select('id, username, name, phone, status')
            .or(filterOr)
            .maybeSingle(),
        _supabase.from('customers').select().or(filterOr).maybeSingle(),
      ]).timeout(_authNetworkTimeout);

      final adminRes = lookupResults[0];
      final courierRes = lookupResults[1];
      final existingCustomer = lookupResults[2];

      if (adminRes != null) {
        _detectedRole = 'admin';
        _pendingUserRecord = Map<String, dynamic>.from(adminRes);
        _loginUsernameController.text =
            (_pendingUserRecord?['username'] ?? '').toString().trim();
        if (mounted) {
          setState(() => _currentStep = 3);
        }
        return;
      }

      if (courierRes != null) {
        _detectedRole = 'courier';
        _pendingUserRecord = Map<String, dynamic>.from(courierRes);
        _loginUsernameController.text =
            (_pendingUserRecord?['username'] ?? '').toString().trim();
        if (mounted) {
          setState(() => _currentStep = 3);
        }
        return;
      }

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

      final internationalPhone = '967$_cleanPhoneInput';
      final otpRes = await ApiService.sendWhatsappOtp(
        phoneNumber: internationalPhone,
      ).timeout(_authNetworkTimeout);

      final msg = otpRes['message']?.toString().isNotEmpty == true
          ? otpRes['message'].toString()
          : 'تم إرسال رمز التحقق إلى $_formattedPhone 💬';

      if (mounted) {
        setState(() {
          _currentStep = 1;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في إرسال الرمز: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _formatFriendlyError(
                e,
                'تعذر إرسال رمز التحقق، يرجى المحاولة لاحقاً',
              ),
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
      final internationalPhone = '967$_cleanPhoneInput';
      final verifyRes = await ApiService.verifyWhatsappOtp(
        phoneNumber: internationalPhone,
        otpCode: otpCode,
      ).timeout(_authNetworkTimeout);

      final bool isValid = verifyRes['verified'] == true ||
          verifyRes['ok'] == true ||
          verifyRes['success'] == true;

      if (isValid) {
        Map<String, dynamic>? customerRow = _pendingUserRecord;
        if (customerRow == null) {
          final fetched = await _supabase
              .from('customers')
              .select()
              .or('phone.eq.$_cleanPhoneInput,phone.eq.$_formattedPhone')
              .maybeSingle()
              .timeout(_authNetworkTimeout);
          if (fetched != null) {
            customerRow = Map<String, dynamic>.from(fetched);
            _pendingUserRecord = customerRow;
            final savedName = (customerRow['name'] ?? '').toString().trim();
            final savedAddress =
                (customerRow['address'] ?? '').toString().trim();
            if (mounted) {
              _nameController.text = savedName;
              _addressController.text = savedAddress;
            }
            if (savedName.isNotEmpty && savedAddress.isNotEmpty) {
              _detectedRole = 'customer_existing';
            }
          }
        }

        if (_detectedRole == 'customer_existing' && customerRow != null) {
          final String customerName =
              (customerRow['name'] ?? '').toString().trim();
          final String customerPhone = _normalizePhone(
              (customerRow['phone'] ?? _cleanPhoneInput).toString().trim());
          final String customerAddress =
              (customerRow['address'] ?? '').toString().trim();

          appState.setUser(
            name: customerName,
            phone: customerPhone,
            address: customerAddress,
          );

          final syncId = customerRow['id'] ?? customerPhone;
          _syncFcmTokenBackground(appState, role: 'customer', rowId: syncId);

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
              _currentStep = 2;
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
          SnackBar(
            content: Text(
              _formatFriendlyError(
                e,
                'رمز التحقق غير صحيح أو انتهت صلاحيته ❌',
              ),
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

  Future<void> _verifyAdminOrCourierCredentials(AppState appState) async {
    if (_isSubmittingCredentials || _isLoading) return;

    final rawLogin = _loginUsernameController.text.trim();
    final password = _loginPasswordController.text.trim();

    if (rawLogin.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'الرجاء إدخال البريد الإلكتروني أو اسم المستخدم وكلمة المرور')),
      );
      return;
    }

    final emailCandidates =
        _buildLoginEmailCandidates(_pendingUserRecord, rawLogin);

    setState(() {
      _isLoading = true;
      _isSubmittingCredentials = true;
    });

    try {
      if (_detectedRole == 'admin') {
        final bool adminSuccess = await _tryLoginAdminWithCandidates(
          appState,
          emailCandidates,
          password,
        );
        if (adminSuccess) {
          unawaited(_syncAdminUserSession(appState, username: rawLogin));
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
      } else if (_detectedRole == 'courier') {
        final bool courierSuccess = await _tryLoginCourierWithCandidates(
          appState,
          emailCandidates,
          password,
        );
        if (courierSuccess) {
          final courierId =
              appState.currentCourier?['id'] ?? _pendingUserRecord?['id'];
          if (courierId != null) {
            unawaited(FcmPushService.syncTokenForCurrentUser(
              role: 'courier',
              rowId: courierId,
            ));
          }
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
      } else {
        final bool adminSuccess = await _tryLoginAdminWithCandidates(
          appState,
          emailCandidates,
          password,
        );
        if (adminSuccess) {
          unawaited(_syncAdminUserSession(appState, username: rawLogin));
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AdminScreen()),
          );
          return;
        }

        final bool courierSuccess = await _tryLoginCourierWithCandidates(
          appState,
          emailCandidates,
          password,
        );
        if (courierSuccess) {
          final courierId =
              appState.currentCourier?['id'] ?? _pendingUserRecord?['id'];
          if (courierId != null) {
            unawaited(FcmPushService.syncTokenForCurrentUser(
              role: 'courier',
              rowId: courierId,
            ));
          }
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const CourierScreen()),
          );
          return;
        }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _formatFriendlyError(
                  e, 'تعذر إتمام تسجيل الدخول، يرجى المحاولة لاحقاً'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSubmittingCredentials = false;
        });
      }
    }
  }

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
      final cleanPhone = _cleanPhoneInput.isNotEmpty
          ? _cleanPhoneInput
          : _normalizePhone(_formattedPhone);

      final savedRecord = await _supabase
          .from('customers')
          .upsert({
            'phone': cleanPhone,
            'name': name,
            'address': address,
          }, onConflict: 'phone')
          .select()
          .maybeSingle()
          .timeout(_authNetworkTimeout);

      final finalName = (savedRecord?['name'] ?? name).toString().trim();
      final finalPhone = _normalizePhone(
          (savedRecord?['phone'] ?? cleanPhone).toString().trim());
      final finalAddress =
          (savedRecord?['address'] ?? address).toString().trim();

      appState.setUser(
        name: finalName,
        phone: finalPhone,
        address: finalAddress,
      );

      final syncId = savedRecord?['id'] ?? finalPhone;
      _syncFcmTokenBackground(appState, role: 'customer', rowId: syncId);

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
          SnackBar(
            content: Text(
              _formatFriendlyError(
                e,
                'تعذر حفظ البيانات، يرجى المحاولة مرة أخرى',
              ),
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
                    ] else if (_currentStep == 1) ...[
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
                        maxLength: 6,
                        decoration: InputDecoration(
                          labelText: 'رمز التحقق (6 أرقام)',
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
                    ] else if (_currentStep == 3) ...[
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
                          labelText: 'البريد الإلكتروني أو اسم المستخدم',
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
                        obscureText: _obscurePassword,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'كلمة السر',
                          labelStyle: const TextStyle(color: Colors.grey),
                          prefixIcon:
                              const Icon(Icons.lock_outline, color: primaryGold),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.grey,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
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
                    ] else ...[
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
