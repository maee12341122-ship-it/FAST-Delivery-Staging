import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/constants.dart';
import 'admin_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);

    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل دخول المشرف')),
      body: Padding(
        padding: const EdgeInsets.all(22),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.admin_panel_settings_outlined, size: 76, color: AppConstants.gold),
                const SizedBox(height: 18),
                const Text(
                  'لوحة تحكم المشرف - FAST',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 25),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستخدم',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppConstants.gold),
                    onPressed: _isLoading
                        ? null
                        : () async {
                            String username = _usernameController.text.trim();
                            String password = _passwordController.text.trim();

                            if (username.isEmpty || password.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('الرجاء إدخال اسم المستخدم وكلمة المرور ⚠️')),
                              );
                              return;
                            }

                            setState(() => _isLoading = true);

                            // الاتصال بقاعدة البيانات والتحقق عبر AppState
                            bool loginSuccess = await appState.loginAdminFromSupabase(username, password);

                            setState(() => _isLoading = false);

                            if (!mounted) return;

                            if (loginSuccess) {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(builder: (_) => const AdminScreen()),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('مرحباً بك، تم تسجيل الدخول بنجاح! 🚀')),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('اسم المستخدم أو كلمة المرور غير صحيحة! ❌')),
                              );
                            }
                          },
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.black)
                        : const Text('تسجيل الدخول', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
