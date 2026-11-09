import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/notification_service.dart'; // 👈 استدعاء خدمة الإشعارات الخاصة بك
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

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    
    final appState = context.read<AppState>();
    bool success = await appState.loginCourier(
      _usernameController.text.trim(), 
      _passwordController.text.trim()
    );

    if (!success || appState.currentCourier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اسم المستخدم أو كلمة المرور غير صحيحة للمندوب ❌')),
      );
      return;
    }

    final courier = appState.currentCourier!;
    final courierId = courier['id']?.toString() ?? courier['delivery_man_id']?.toString() ?? 'D-001';
    final courierName = courier['name']?.toString() ?? 'مندوب';

    // 🚀 حفظ معرف OneSignal Player ID الخاص بجهاز المندوب في جدول couriers في Supabase
    await NotificationService.saveUserPlayerId(courierId, 'couriers');

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DeliveryDashboard(
          courierId: courierId,
          courierName: courierName,
        ),
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
          title: const Text('دخول حساب المندوب 🛵', style: TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold, fontSize: 16)),
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
                      child: const Icon(Icons.delivery_dining, size: 60, color: AppConstants.gold),
                    ),
                    const SizedBox(height: 24),
                    const Text('تسجيل دخول المندوب', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('أدخل بيانات الاعتماد الخاصة بحسابك المسجل من الإدارة', style: TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
                    const SizedBox(height: 30),
                    
                    // حقل اسم المستخدم للمندوب
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

                    // حقل كلمة المرور للمندوب
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
                        label: const Text('دخول لوحة المندوب 🚀', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: const Text(
                        'تنبيه: يمكنك إضافة حسابات المناديب وتعديل كلمات مرورهم مباشرة من لوحة تحكم المشرف.',
                        style: TextStyle(color: Colors.lightBlueAccent, fontSize: 11, height: 1.5),
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
    );
  }
}
