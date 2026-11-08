import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';

class AdminReportsScreen extends StatelessWidget {
  const AdminReportsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final orders = appState.orders;

    // حساب الإحصائيات والأرقام القياسية
    int totalOrdersCount = orders.length;
    int deliveredOrdersCount = orders.where((o) => o['status'] == 'delivered').length;
    int cancelledOrdersCount = orders.where((o) => o['status']?.toString().contains('cancelled') ?? false).length;

    double totalProductsSales = 0.0;
    double totalDeliveryFees = 0.0;

    for (var o in orders) {
      if (o['status'] == 'delivered') {
        totalProductsSales += double.tryParse(o['products_total']?.toString() ?? '0') ?? 0.0;
        totalDeliveryFees += double.tryParse(o['delivery_fee']?.toString() ?? '0') ?? 0.0;
      }
    }

    double adminCommission = totalDeliveryFees * 0.20; // نسبة الإدارة 20% من التوصيل

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('تقارير الأرباح والمبيعات 📈', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          iconTheme: const Icon(Icons.amber),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'مؤشرات الأداء العامة (الطلبات المكتملة)',
                style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              
              // شبكة البطاقات الإحصائية
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics,
                childAspectRatio: 1.5,
                children: [
                  _buildStatCard('إجمالي المبيعات', '${totalProductsSales.toStringAsFixed(0)} ر.ي', Icons.shopping_cart, Colors.blueAccent),
                  _buildStatCard('أرباح التوصيل', '${totalDeliveryFees.toStringAsFixed(0)} ر.ي', Icons.delivery_dining, Colors.orangeAccent),
                  _buildStatCard('عمولة الإدارة (20%)', '${adminCommission.toStringAsFixed(0)} ر.ي', Icons.account_balance_wallet, Colors.greenAccent),
                  _buildStatCard('الطلبات المكتملة', '$deliveredOrdersCount / $totalOrdersCount', Icons.check_circle, Colors.amber),
                ],
              ),
              
              const SizedBox(height: 25),
              const Divider(color: Colors.white24),
              const SizedBox(height: 15),

              const Text(
                'تفاصيل حالات الطلبات',
                style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    _buildRowDetail('إجمالي الطلبات الواردة:', '$totalOrdersCount طلب'),
                    const Divider(color: Colors.white12),
                    _buildRowDetail('الطلبات الناجحة والمكتملة:', '$deliveredOrdersCount طلب ✅', color: Colors.greenAccent),
                    const Divider(color: Colors.white12),
                    _buildRowDetail('الطلبات الملغاة:', '$cancelledOrdersCount طلب ❌', color: Colors.redAccent),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRowDetail(String label, String val, {Color color = Colors.white}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(val, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
