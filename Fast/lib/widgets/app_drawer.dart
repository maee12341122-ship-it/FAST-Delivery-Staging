import 'package:flutter/material.dart';
import '../screens/home_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Colors.amber[700],
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.local_shipping, size: 50, color: Colors.white),
                SizedBox(height: 10),
                Text(
                  'تعز إكسبرس – Taiz Express',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'منصة التوصيل المتكاملة',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('الرئيسية (العميل)'),
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const HomeScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.admin_panel_settings),
            title: const Text('لوحة تحكم المشرف (Admin)'),
            onTap: () {
              // يمكنك هنا ربط شاشة المشرف الخاصة بك
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('جاري الانتقال إلى لوحة تحكم المشرف...')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delivery_dining),
            title: const Text('واجهة المندوب (Delivery)'),
            onTap: () {
              // يمكنك هنا ربط شاشة المندوب الخاصة بك
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('جاري الانتقال إلى واجهة المندوب...')),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('عن التطبيق'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'تعز إكسبرس',
                applicationVersion: '1.0.0',
                applicationLegalese: 'جميع الحقوق محفوظة - تعز 2026',
              );
            },
          ),
        ],
      ),
    );
  }
}