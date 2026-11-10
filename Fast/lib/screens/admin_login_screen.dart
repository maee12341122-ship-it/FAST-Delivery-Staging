import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/notification_service.dart'; // 👈 استدعاء خدمة الإشعارات
import '../utils/constants.dart';
import '../utils/validators.dart';
// استبدل المسار أدناه بشاشة لوحة تحكم المشرف لديك إن كانت مختلفة
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

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    
    final appState = context.read<AppState>();
    
    // استدعاء دالة تسجيل دخول المشرف من الـ AppState
    bool success = await appState.loginAdmin(
      _usernameController.text.trim(), 
      _passwordController.text.trim()
    );

    if (!success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اسم المستخدم أو كلمة المرور غير صحيحة للمشرف ❌')),
      );
      return;
    }

    // جلب معرف المشرف بعد نجاح تسجيل الدخول
    final adminId = appState.currentAdminId ?? 'admin_main';

    // 🚀 حفظ معرف OneSignal Player ID الخاص بجهاز المشرف في جدول admins في Supabase
    await NotificationService.saveUserPlayerId(adminId, 'admins');

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const AdminDashboard(),
      ),
    );
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
          title: const Text(
            'دخول لوحة تحكم المشرف 🛡️', 
            style: TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold, fontSize: 16)
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
                        color: AppConstants.gold.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppConstants.gold.withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.admin_panel_settings, size: 60, color: AppConstants.gold),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'تسجيل دخول المشرف', 
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'أدخل صلاحيات المشرف للتحكم الكامل بالنظام وإدارة الطلبات', 
                      style: TextStyle(color: Colors.grey, fontSize: 13), 
                      textAlign: TextAlign.center
                    ),
                    const SizedBox(height: 30),
                    
                    // حقل اسم المستخدم (بدون تلميح افتراضي)
                    TextFormField(
                      controller: _usernameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'اسم المستخدم',
                        labelStyle: TextStyle(color: Colors.grey),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Color(0xFF1E1E1E),
                        prefixIcon: Icon(Icons.person, color: AppConstants.gold),
                      ),
                      validator: Validators.requiredText,
                    ),
                    const SizedBox(height: 16),

                    // حقل كلمة المرور
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'كلمة المرور',
                        labelStyle: TextStyle(color: Colors.grey),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Color(0xFF1E1E1E),
                        prefixIcon: Icon(Icons.lock, color: AppConstants.gold),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _login,
                        icon: const Icon(Icons.login, color: Colors.black),
                        label: const Text('دخول لوحة التحكم الرئيسية 🚀', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
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
