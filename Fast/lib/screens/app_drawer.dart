import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../utils/constants.dart';
import 'delivery_login_screen.dart';
import 'customer/edit_profile_screen.dart';

class AppDrawer extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  const AppDrawer({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.user;

    return Drawer(
      backgroundColor: const Color(0xFF121212),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
            ),
            accountName: Text(
              user?.name ?? 'زائر FAST تعز',
              style: TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            accountEmail: Text(
              user?.phone ?? 'لم يتم تسجيل رقم هاتف',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            // 💡 التصحيح هنا: استخدام currentAccountPicture بدلاً من accountPicture
            currentAccountPicture: const CircleAvatar(
              backgroundColor: AppConstants.gold,
              child: Icon(Icons.person, color: Colors.black, size: 36),
            ),
          ),
          
          _item(context, Icons.person_outline, 'حسابي', () => onNavigate(3)),
          _item(context, Icons.edit_location_alt, 'تعديل الحساب والموقع', () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const EditProfileScreen()),
            );
          }),
          _item(context, Icons.receipt_long, 'طلباتي', () => onNavigate(2)),
          
          const Divider(color: Colors.white12, height: 20),

          _item(context, Icons.location_city, 'تغيير المدينة (تعز)', () {
            Navigator.pop(context);
            _showMessage(context, 'الخدمة الحالية متاحة في مدينة تعز فقط.');
          }),
          _item(context, Icons.phone, 'تواصل معنا', () {
            Navigator.pop(context);
            _showMessage(context, 'بيانات التواصل الرسمية غير مضافة بعد.');
          }),
          _item(context, Icons.privacy_tip_outlined, 'سياسة الخصوصية', () {
            Navigator.pop(context);
            _showTextDialog(context, 'سياسة الخصوصية',
                'في نسخة المرحلة الأولى تُحفظ بيانات التجربة محلياً على الجهاز أو سحابياً عبر سوبابيس.');
          }),
          _item(context, Icons.share, 'مشاركة التطبيق', () async {
            await Clipboard.setData(const ClipboardData(text: 'تطبيق FAST - أسرع خدمة توصيل في تعز 🚀'));
            if (context.mounted) {
              Navigator.pop(context);
              _showMessage(context, 'تم نسخ رابط ورسالة التطبيق بنجاح! 🚀');
            }
          }),
          _item(context, Icons.info_outline, 'نبذة عن التطبيق', () {
            Navigator.pop(context);
            _showTextDialog(context, 'عن تطبيق FAST',
                'تطبيق FAST تطبيق توصيل رائد في تعز يجمع المطاعم والبقالات والصيدليات والطلبات الخاصة في واجهة واحدة متكاملة.');
          }),
          
          const Divider(color: Colors.white12, height: 20),

          _item(context, Icons.delivery_dining, 'تسجيل دخول المندوبين', () {
            Navigator.pop(context);
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeliveryLoginScreen()));
          }),
          _item(context, Icons.brightness_6, 'مظهر التطبيق', () => _showThemeDialog(context, state)),
          
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'الإصدار: 2.2.0\nFAST • تعز، اليمن',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppConstants.gold),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      dense: true,
    );
  }

  void _showThemeDialog(BuildContext context, AppState state) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('اختر مظهر التطبيق', style: TextStyle(color: AppConstants.gold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _themeOption(dialogContext, state, ThemeMode.light, 'الوضع الفاتح'),
            _themeOption(dialogContext, state, ThemeMode.dark, 'الوضع الداكن'),
            _themeOption(dialogContext, state, ThemeMode.system, 'مطابق للنظام'),
          ],
        ),
      ),
    );
  }

  Widget _themeOption(BuildContext context, AppState state, ThemeMode mode, String label) {
    return RadioListTile<ThemeMode>(
      value: mode,
      groupValue: state.themeMode,
      title: Text(label, style: const TextStyle(color: Colors.white)),
      activeColor: AppConstants.gold,
      onChanged: (value) {
        if (value != null) state.setThemeMode(value);
        Navigator.pop(context);
      },
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showTextDialog(BuildContext context, String title, String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(title, style: TextStyle(color: AppConstants.gold)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext), 
            child: Text('إغلاق', style: TextStyle(color: AppConstants.gold)),
          ),
        ],
      ),
    );
  }
}
