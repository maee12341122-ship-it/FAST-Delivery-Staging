import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/address_model.dart';
import '../providers/app_state.dart';
import '../utils/constants.dart';
import '../utils/validators.dart';
import 'location_picker_screen.dart';
import 'main_shell.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _otpController;

  bool _isOtpSent = false;
  bool _isLoading = false;

  String _selectedArea = 'شارع جمال';
  LatLng? _selectedPoint;
  final List<String> _areas = const [
    'شارع جمال',
    'الروضة',
    'المسبح',
    'عصيفرة',
    'الحوبان',
    'بير باشا'
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    _otpController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final savedUser = context.read<AppState>().user;
      if (savedUser != null && mounted) {
        setState(() {
          _nameController.text = savedUser.name;
          _phoneController.text = savedUser.phone;
          _addressController.text = savedUser.defaultAddress?.details ?? '';
          _selectedArea = savedUser.defaultAddress?.area ?? _selectedArea;

          final lat = savedUser.defaultAddress?.latitude;
          final lng = savedUser.defaultAddress?.longitude;
          if (lat != null && lng != null) {
            _selectedPoint = LatLng(lat, lng);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _chooseLocation() async {
    final point = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initialPoint: _selectedPoint),
      ),
    );
    if (point != null && mounted) {
      setState(() => _selectedPoint = point);
    }
  }

  Future<void> _sendOtpViaWhatsApp(String phone, String otpCode) async {
    final message = Uri.encodeComponent(
        '🌟 تطبيق FAST - تعز 🌟\n\n'
            'أهلاً بك يا بطل!\n'
            'رمز التحقق الخاص بك هو: *$otpCode*\n\n'
            'لا تشارك هذا الرمز مع أي شخص حفاظاً على أمان حسابك. 🚀'
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح تطبيق الواتساب')),
        );
      }
    }
  }

  Future<void> _requestAndSendOtp() async {
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);
    final appState = context.read<AppState>();
    final phone = _phoneController.text.trim();

    appState.requestOtpForPhone(phone);

    if (appState.generatedDynamicOtp != null) {
      await _sendOtpViaWhatsApp(phone, appState.generatedDynamicOtp!);
    }

    setState(() {
      _isLoading = false;
      _isOtpSent = true;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم فتح رسالة FAST في واتساب. أرسلها بنفسك؛ لا يوجد تحقق آلي من الرقم.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _verifyAndSubmit() {
    final appState = context.read<AppState>();
    final phone = _phoneController.text.trim();
    final isValid = appState.continueWithoutPhoneVerification(phone);
    if (!isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رقم الهاتف غير صالح.')),
      );
      return;
    }

    final double finalLat = _selectedPoint?.latitude ?? 13.58874;
    final double finalLng = _selectedPoint?.longitude ?? 44.01809;

    final address = AddressModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: 'العنوان الرئيسي',
      area: _selectedArea,
      details: _addressController.text.trim().isNotEmpty
          ? _addressController.text.trim()
          : 'شارع جمال',
      latitude: finalLat,
      longitude: finalLng,
    );

    try {
      appState.setUser(
        name: _nameController.text.trim(),
        phone: phone,
        address: address,
      );

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShell()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('Error during submit: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء حفظ البيانات: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          elevation: 2,
          title: const Text('تسجيل بيانات العميل والتحقق', style: TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold, fontSize: 16)),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.verified_user_outlined, color: AppConstants.gold, size: 24),
                    SizedBox(width: 8),
                    Text('مرحباً بك في تطبيق FAST', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'أدخل بياناتك ورقم هاتفك ليصلك رمز التوثيق عبر الواتساب فوراً',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 24),

                TextFormField(
                  controller: _nameController,
                  enabled: !_isOtpSent,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'الاسم الكامل',
                    labelStyle: TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.person, color: AppConstants.gold),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF1E1E1E),
                  ),
                  validator: (value) {
                    final required = Validators.requiredText(value, message: 'يرجى إدخال الاسم');
                    if (required != null) return required;
                    if (value!.trim().length < 2) return 'الاسم قصير جداً';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _phoneController,
                  enabled: !_isOtpSent,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف اليمني (واتساب)',
                    labelStyle: TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.phone, color: AppConstants.gold),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF1E1E1E),
                  ),
                  validator: Validators.yemeniPhone,
                ),
                const SizedBox(height: 14),

                DropdownButtonFormField<String>(
                  value: _selectedArea,
                  dropdownColor: const Color(0xFF1E1E1E),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'المنطقة في تعز',
                    labelStyle: TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.location_city, color: AppConstants.gold),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF1E1E1E),
                  ),
                  items: _areas
                      .map((area) => DropdownMenuItem(value: area, child: Text(area, style: const TextStyle(color: Colors.white))))
                      .toList(),
                  onChanged: _isOtpSent ? null : (value) {
                    if (value != null) {
                      setState(() => _selectedArea = value);
                    }
                  },
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _addressController,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'عنوان البيت / المحل التفصيلي',
                    labelStyle: TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.home, color: AppConstants.gold),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF1E1E1E),
                    alignLabelWithHint: true,
                  ),
                  validator: (value) =>
                      Validators.requiredText(value, message: 'يرجى كتابة العنوان التفصيلي'),
                ),
                const SizedBox(height: 16),

                OutlinedButton.icon(
                  onPressed: _chooseLocation,
                  icon: const Icon(Icons.map_outlined, color: AppConstants.gold),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppConstants.gold,
                    side: BorderSide(color: AppConstants.gold.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  label: Text(
                    _selectedPoint == null
                        ? 'تحديد الموقع على الخريطة (اختياري) 🗺️'
                        : 'تم اختيار موقع على الخريطة ✓',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (_selectedPoint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'الإحداثيات: ${_selectedPoint!.latitude.toStringAsFixed(5)}, ${_selectedPoint!.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 24),

                if (!_isOtpSent) ...[
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppConstants.gold,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isLoading ? null : _requestAndSendOtp,
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.black)
                          : const Text(
                              'إرسال رمز التحقق عبر الواتساب 📩',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green.withOpacity(0.5)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'تم فتح محادثة FAST في واتساب برسالة جاهزة. أرسلها بنفسك، ثم يمكنك المتابعة كضيف. لا يتم توثيق ملكية الرقم بهذه الخطوة.',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green, 
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _verifyAndSubmit,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text(
                        'متابعة كضيف إلى التطبيق 🚀',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => setState(() => _isOtpSent = false),
                    child: const Text('تغيير رقم الهاتف أو إعادة الإرسال', style: TextStyle(color: AppConstants.gold)),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'ملاحظة: خدمة إرسال الرمز مجانية وتعمل بالربط المباشر مع الواتساب لضمان الوصول السريع.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 11, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
