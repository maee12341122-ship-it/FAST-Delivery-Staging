import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/product_model.dart';

class AdminRestaurantsScreen extends StatefulWidget {
  const AdminRestaurantsScreen({Key? key}) : super(key: key);

  @override
  State<AdminRestaurantsScreen> createState() => _AdminRestaurantsScreenState();
}

class _AdminRestaurantsScreenState extends State<AdminRestaurantsScreen> {
  final _restaurantNameController = TextEditingController();

  @override
  void dispose() {
    _restaurantNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final themeBg = appState.isDarkMode ? const Color(0xFF121212) : const Color(0xFFF0F2F5);
    final cardBg = appState.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = appState.isDarkMode ? Colors.white : Colors.black87;

    // تجميع المطاعم وحساب مبيعات كل مطعم من جدول الطلبات
    final List<ProductModel> allProducts = (appState.products as List).map((e) => e as ProductModel).toList();
    final Set<String> restaurantsList = allProducts
        .where((p) => p.category == 'المطاعم' && p.restaurantName.isNotEmpty)
        .map((p) => p.restaurantName)
        .toSet();

    // حساب الإحصائيات العامة
    final Map<String, int> restaurantOrdersCount = {};
    final Map<String, double> restaurantTotalSales = {};

    for (var order in appState.orders) {
      if (order['status'] == 'delivered') {
        final itemsDesc = order['items_desc'] ?? order['items_description'] ?? '';
        final double price = double.tryParse(order['products_total']?.toString() ?? '0') ?? 0.0;

        for (var restName in restaurantsList) {
          if (itemsDesc.toString().contains(restName)) {
            restaurantOrdersCount[restName] = (restaurantOrdersCount[restName] ?? 0) + 1;
            restaurantTotalSales[restName] = (restaurantTotalSales[restName] ?? 0.0) + price;
          }
        }
      }
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: themeBg,
        appBar: AppBar(
          backgroundColor: cardBg,
          title: const Text('إدارة المطاعم والمبيعات 🍽️', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: Colors.amber),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // بطاقة ملخص مبيعات المطاعم
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('إجمالي المطاعم المسجلة', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('${restaurantsList.length} مطعم', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('قائمة المطاعم وتقارير مبيعاتها', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 10),
            restaurantsList.isEmpty
                ? const Center(
                    padding: EdgeInsets.all(30),
                    child: Text('لا توجد مطاعم قائمة حالياً', style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: restaurantsList.length,
                    itemBuilder: (context, index) {
                      final restName = restaurantsList.elementAt(index);
                      final int orderCount = restaurantOrdersCount[restName] ?? 0;
                      final double sales = restaurantTotalSales[restName] ?? 0.0;
                      final int totalProductsCount = allProducts.where((p) => p.restaurantName == restName).length;

                      return Card(
                        color: cardBg,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: ExpansionTile(
                          iconColor: Colors.amber,
                          leading: const CircleAvatar(
                            backgroundColor: Colors.amber,
                            child: Icon(Icons.store, color: Colors.black),
                          ),
                          title: Text(restName, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                          subtitle: Text('عدد الوجبات: $totalProductsCount | إجمالي الطلبات المكتملة: $orderCount', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Divider(color: Colors.white12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('إجمالي المبيعات المحققة:', style: TextStyle(color: Colors.grey)),
                                      Text('$sales ر.ي', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 15)),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  const Text('الوجبات التابعة لهذا المطعم:', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 6),
                                  ...allProducts.where((p) => p.restaurantName == restName).map(
                                        (p) => Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('• ${p.name}', style: TextStyle(color: textColor, fontSize: 13)),
                                              Text('${p.price} ر.ي', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                            ],
                                          ),
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
