import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state.dart';
import '../models/product_model.dart';

class AdminRestaurantsScreen extends StatefulWidget {
  const AdminRestaurantsScreen({Key? key}) : super(key: key);

  @override
  State<AdminRestaurantsScreen> createState() => _AdminRestaurantsScreenState();
}

class _AdminRestaurantsScreenState extends State<AdminRestaurantsScreen> {
  List _restaurants = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRestaurants();
  }

  Future _fetchRestaurants() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client.from('restaurants').select();
      setState(() {
        _restaurants = response is List ? response : [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _showEditRestaurantDialog(Map? restaurant) {
    final nameController = TextEditingController(text: restaurant?['name'] ?? '');
    final logoController = TextEditingController(text: restaurant?['logo_url'] ?? '');
    final ratingController = TextEditingController(text: restaurant?['rating']?.toString() ?? '5.0');

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(restaurant == null ? 'إضافة مطعم جديد 🍽️' : 'تعديل بيانات المطعم ✏️', style: const TextStyle(color: Colors.amber)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'اسم المطعم', labelStyle: TextStyle(color: Colors.grey)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: logoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'رابط الشعار (Logo URL)', labelStyle: TextStyle(color: Colors.grey)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ratingController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'التقييم الافتراضي أو اليدوي', labelStyle: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  final data = {
                    'name': nameController.text.trim(),
                    'logo_url': logoController.text.trim(),
                    'rating': double.tryParse(ratingController.text.trim()) ?? 5.0,
                  };

                  if (restaurant == null) {
                    await Supabase.instance.client.from('restaurants').insert(data);
                  } else {
                    await Supabase.instance.client.from('restaurants').update(data).eq('id', restaurant['id']);
                  }

                  if (!context.mounted) return;
                  Navigator.pop(context);
                  _fetchRestaurants();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ بيانات المطعم بنجاح ✅')));
                }
              },
              child: const Text('حفظ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final themeBg = appState.isDarkMode ? const Color(0xFF121212) : const Color(0xFFF0F2F5);
    final cardBg = appState.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = appState.isDarkMode ? Colors.white : Colors.black87;

    final allProducts = appState.products;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: themeBg,
        appBar: AppBar(
          backgroundColor: cardBg,
          title: const Text('إدارة المطاعم والشعارات والتقييمات العادلة 🍽️', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
          iconTheme: const IconThemeData(color: Colors.amber),
          actions: [
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.amber),
              tooltip: 'إضافة مطعم',
              onPressed: () => _showEditRestaurantDialog(null),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.amber))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
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
                        const Text('إجمالي المطاعم المسجلة ونظام التقييم', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('${_restaurants.length} مطعم نشط', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('قائمة المطاعم والشعارات والتقييم العادل', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _restaurants.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(30),
                          child: Center(
                            child: Text('لا توجد مطاعم مسجلة، اضغط على زر الإضافة أعلى الصفحة ➕', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _restaurants.length,
                          itemBuilder: (context, index) {
                            final rest = _restaurants[index] as Map;
                            final restName = rest['name'] ?? '';
                            final logoUrl = rest['logo_url'] ?? '';
                            final rating = rest['rating'] ?? 5.0;
                            final totalProductsCount = allProducts.where((p) => p.restaurantName == restName).length;

                            return Card(
                              color: cardBg,
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              child: ExpansionTile(
                                iconColor: Colors.amber,
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: logoUrl.isNotEmpty
                                      ? Image.network(logoUrl, width: 45, height: 45, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.store, color: Colors.amber))
                                      : Container(
                                          width: 45,
                                          height: 45,
                                          color: Colors.amber.withOpacity(0.2),
                                          child: const Icon(Icons.store, color: Colors.amber),
                                        ),
                                ),
                                title: Text(restName, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                                subtitle: Row(
                                  children: [
                                    const Icon(Icons.star, color: Colors.amber, size: 14),
                                    const SizedBox(width: 4),
                                    Text('$rating (تقييم عادل)', style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                                    const Text(' | ', style: TextStyle(color: Colors.grey)),
                                    Text('الوجبات: $totalProductsCount', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blueAccent),
                                  onPressed: () => _showEditRestaurantDialog(rest),
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Divider(color: Colors.white12),
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
