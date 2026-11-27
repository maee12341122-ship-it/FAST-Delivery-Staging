import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/fcm_push_service.dart';
import '../utils/constants.dart';
import '../utils/validators.dart';
import 'admin_dashboard.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
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

  Future<void> _login() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final appState = context.read<AppState>();
      final username = _usernameController.text.trim();
      final password = _passwordController.text.trim();

      final bool success =
          await appState.loginAdminFromSupabase(username, password);

      if (!mounted) return;

      if (!success || !appState.isAdminLoggedIn) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذر تسجيل الدخول: تأكد من بيانات وصلاحيات المشرف ❌',
            ),
          ),
        );
        return;
      }

      // مزامنة FCM token للمشرف بدون الاعتماد على OneSignal
      final authUserId = appState.supabase.auth.currentUser?.id;
      if (authUserId != null && authUserId.isNotEmpty) {
        try {
          final adminRow = await appState.supabase
              .from('admins')
              .select('id')
              .or('username.ilike.$username,username.ilike.${username.split('@').first}')
              .maybeSingle();
          await FcmPushService.requestPermissionAndSyncToken(
            role: 'admin',
            rowId: adminRow?['id'] ?? authUserId,
          );
        } catch (e) {
          debugPrint('تعذر مزامنة FCM token للمشرف: $e');
        }
      }

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const AdminDashboard(),
        ),
      );
    } catch (e) {
      debugPrint('❌ خطأ أثناء تسجيل دخول المشرف: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حدث خطأ أثناء الاتصال بالخادم، حاول مرة أخرى ⚠️'),
        ),
      );
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
              'دخول لوحة تحكم المشرف 🛡️',
              style: TextStyle(
                color: AppConstants.gold,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          body: Padding(
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
                          Icons.admin_panel_settings,
                          size: 60,
                          color: AppConstants.gold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'تسجيل دخول المشرف',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'أدخل صلاحيات المشرف للتحكم الكامل بالنظام وإدارة الطلبات',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),
                      TextFormField(
                        controller: _usernameController,
                        focusNode: _usernameFocus,
                        textInputAction: TextInputAction.next,
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
                        textInputAction: TextInputAction.done,
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
                          label: const Text(
                            'دخول لوحة التحكم الرئيسية 🚀',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
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
    );
  }
}
