import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'main_shell.dart'; // 👈 التوجيه إلى الحاوية الرئيسية الشاملة

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          elevation: 2,
          title: const Text('شروط الاستخدام - FAST 📜', style: TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.gavel, color: AppConstants.gold, size: 28),
                  SizedBox(width: 10),
                  Text(
                    'أهلاً بك في تطبيق FAST',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppConstants.gold.withOpacity(0.3)),
                ),
                child: const Text(
                  'يرجى قراءة والموافقة على الشروط والأحكام للبدء في استخدام خدمات التوصيل السريع والمتاجر بكل سهولة ويسر في مدينة تعز. جميع الحقوق محفوظة لتطبيق FAST 🌟',
                  style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const MainShell()), // 👈 الانتقال إلى MainShell بدلاً من HomeScreen
                    );
                  },
                  child: const Text(
                    'موافق والمتابعة 🚀',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
