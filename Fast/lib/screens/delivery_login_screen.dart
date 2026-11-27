import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/fcm_push_service.dart';
import '../utils/constants.dart';
import '../utils/validators.dart';
import 'delivery_dashboard.dart';

class DeliveryLoginScreen extends StatefulWidget {
  const DeliveryLoginScreen({super.key});

  @override
  State<DeliveryLoginScreen> createState() => _DeliveryLoginScreenState();
}

class _DeliveryLoginScreenState extends State<DeliveryLoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = true}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? const Color(0xFF2B1618) : const Color(0xFF16291C),
      ),
    );
  }

  Future<void> _login() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    try {
      final appState = context.read<AppState>();
      final bool success = await appState.loginCourier(username, password);

      if (!success || appState.currentCourier == null) {
        _showMessage('اسم المستخدم أو كلمة المرور غير صحيحة للمندوب ❌');
        return;
      }

      final courier = Map<String, dynamic>.from(appState.currentCourier!);
      final rawId = courier['id']?.toString().trim() ?? '';
      final authId = courier['auth_user_id']?.toString().trim() ??
          appState.supabase.auth.currentUser?.id.trim() ??
          '';

      final courierId = rawId.isNotEmpty ? rawId : authId;
      final courierNameRaw = courier['name']?.toString().trim() ?? '';
      final courierName = courierNameRaw.isNotEmpty ? courierNameRaw : 'مندوب';

      if (courierId.isEmpty) {
        _showMessage('تعذر تحديد معرف حساب المندوب ❌');
        return;
      }

      final targetIdForPush = rawId.isNotEmpty ? rawId : courierId;
      try {
        await FcmPushService.requestPermissionAndSyncToken(
          role: 'courier',
          rowId: targetIdForPush,
        );
      } catch (e) {
        debugPrint('تعذر مزامنة FCM token للمندوب: $e');
      }

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DeliveryDashboard(
            courierId: courierId,
            courierName: courierName,
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('خطأ أثناء تسجيل دخول المندوب: $e\n$stackTrace');
      _showMessage('حدث خطأ أثناء الاتصال بالخادم، حاول مرة أخرى ❌');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E1E1E),
            elevation: 2,
            title: const Text(
              'دخول حساب المندوب 🛵',
              style: TextStyle(
                color: AppConstants.gold,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppConstants.gold.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppConstants.gold.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Icon(
                            Icons.delivery_dining,
                            size: 60,
                            color: AppConstants.gold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'تسجيل دخول المندوب',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'أدخل بيانات الاعتماد الخاصة بحسابك المسجل من الإدارة',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 30),
                        TextFormField(
                          controller: _usernameController,
                          focusNode: _usernameFocus,
                          keyboardType: TextInputAction.next == TextInputAction.next
                              ? TextInputType.text
                              : TextInputType.text,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.username],
                          onSubmitted: (_) {
                            FocusScope.of(context).requestFocus(_passwordFocus);
                          },
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'اسم المستخدم',
                            labelStyle: TextStyle(color: Colors.grey),
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Color(0xFF1E1E1E),
                            prefixIcon:
                                Icon(Icons.person, color: AppConstants.gold),
                          ),
                          validator: Validators.requiredText,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          obscureText: _obscurePassword,
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _login(),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'كلمة المرور',
                            labelStyle: const TextStyle(color: Colors.grey),
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: const Color(0xFF1E1E1E),
                            prefixIcon:
                                const Icon(Icons.lock, color: AppConstants.gold),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.grey,
                              ),
                              onPressed: () {
                                setState(
                                    () => _obscurePassword = !_obscurePassword);
                              },
                            ),
                          ),
                          validator: Validators.requiredText,
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppConstants.gold,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _isLoading ? null : _login,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.black,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.login, color: Colors.black),
                            label: Text(
                              _isLoading
                                  ? 'جاري تسجيل الدخول...'
                                  : 'دخول لوحة المندوب 🚀',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Text(
                            'تنبيه: يمكنك إضافة حسابات المناديب وتعديل كلمات مرورهم مباشرة من لوحة تحكم المشرف.',
                            style: TextStyle(
                              color: Colors.lightBlueAccent,
                              fontSize: 11,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
