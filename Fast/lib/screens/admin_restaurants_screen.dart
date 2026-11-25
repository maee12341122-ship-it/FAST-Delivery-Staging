import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../state/app_state.dart';

class AdminRestaurantsScreen extends StatefulWidget {
  const AdminRestaurantsScreen({super.key});

  @override
  State<AdminRestaurantsScreen> createState() => _AdminRestaurantsScreenState();
}

class _AdminRestaurantsScreenState extends State<AdminRestaurantsScreen> {
  List<Map<String, dynamic>> _restaurants = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_fetchRestaurants());
  }

  String _normalizeCategory(String raw) {
    final clean = raw.trim();
    if (clean == 'المشاريع المنزلية' || clean == 'home_projects') {
      return 'مشاريع منزلية';
    }
    return clean.isEmpty ? 'المطاعم' : clean;
  }

  Future<void> _fetchRestaurants() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response =
          await Supabase.instance.client.from('restaurants').select();
      final list = List<Map<String, dynamic>>.from(response).map((row) {
        final rawCat = (row['category'] ?? row['type'] ?? '').toString().trim();
        return {
          ...row,
          'name': (row['name'] ?? row['title'] ?? '').toString().trim(),
          'category': _normalizeCategory(rawCat),
          'logo_url': (row['logo_url'] ?? row['image_url'] ?? '').toString().trim(),
          'is_active': row['is_active'] ?? true,
        };
      }).toList();

      if (!mounted) return;
      setState(() {
        _restaurants = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'تعذر جلب قائمة المطاعم: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleRestaurantActive(
    AppState appState,
    Map<String, dynamic> restaurant,
    bool nextActive,
  ) async {
    final id = restaurant['id'];
    if (id == null) return;
    try {
      await Supabase.instance.client
          .from('restaurants')
          .update({'is_active': nextActive}).eq('id', id);
      await _fetchRestaurants();
      unawaited(appState.fetchRestaurantsAndCategories());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextActive ? 'تم تفعيل المطعم بنجاح ✅' : 'تم إيقاف المطعم مؤقتاً',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديث حالة المطعم: $e')),
      );
    }
  }

  void _showEditRestaurantDialog(
    AppState appState,
    Map<String, dynamic>? restaurant,
  ) {
    final nameController =
        TextEditingController(text: (restaurant?['name'] ?? '').toString());
    final logoController = TextEditingController(
      text: (restaurant?['logo_url'] ?? restaurant?['image_url'] ?? '').toString(),
    );

    final availableCategories = <String>{
      'المطاعم',
      'مشاريع منزلية',
      'سوبرماركت',
      'صيدليات',
      ...appState.categoriesList
          .map((c) => _normalizeCategory((c['name'] ?? '').toString()))
          .where((c) => c.isNotEmpty && c != 'الكل'),
    }.toList();

    String selectedCategory = _normalizeCategory(
      (restaurant?['category'] ?? restaurant?['type'] ?? 'المطاعم').toString(),
    );
    if (!availableCategories.contains(selectedCategory)) {
      availableCategories.insert(0, selectedCategory);
    }

    bool isActive = restaurant?['is_active'] ?? true;

    final ratingInfo = appState.getRestaurantRatingInfo(
      restaurantId: restaurant?['id']?.toString(),
      restaurantName: restaurant?['name']?.toString(),
    );
    final double fairAvg =
        double.tryParse(ratingInfo?['avg']?.toString() ?? '0.0') ?? 0.0;
    final int fairTotal =
        int.tryParse(ratingInfo?['total']?.toString() ?? '0') ?? 0;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: Text(
              restaurant == null
                  ? 'إضافة مطعم / متجر جديد 🍽️'
                  : 'تعديل بيانات المطعم / المتجر ✏️',
              style: const TextStyle(color: Colors.amber, fontSize: 16),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'اسم المطعم أو المتجر',
                      labelStyle: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    dropdownColor: const Color(0xFF262626),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'القسم',
                      labelStyle: TextStyle(color: Colors.grey),
                    ),
                    items: availableCategories
                        .map(
                          (cat) => DropdownMenuItem<String>(
                            value: cat,
                            child: Text(cat),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedCategory = val);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: logoController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'رابط الشعار (Logo URL)',
                      labelStyle: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_rounded,
                            color: Colors.amber, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            fairTotal > 0
                                ? 'التقييم العادل من العملاء: ${fairAvg.toStringAsFixed(1)} ($fairTotal تقييم)'
                                : 'التقييم العادل: لا توجد تقييمات بعد (جديد)',
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: Colors.amber,
                    title: const Text(
                      'نشط ومتاح للعملاء',
                      style: TextStyle(color: Colors.white, fontSize: 13.5),
                    ),
                    value: isActive,
                    onChanged: (val) => setDialogState(() => isActive = val),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child:
                    const Text('إغلاق', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                onPressed: () async {
                  final cleanName = nameController.text.trim();
                  if (cleanName.isEmpty) return;

                  final cleanLogo = logoController.text.trim();
                  final payload = <String, dynamic>{
                    'name': cleanName,
                    'category': selectedCategory,
                    'logo_url': cleanLogo,
                    'image_url': cleanLogo,
                    'is_active': isActive,
                  };

                  try {
                    if (restaurant == null) {
                      await Supabase.instance.client
                          .from('restaurants')
                          .insert(payload);
                    } else {
                      await Supabase.instance.client
                          .from('restaurants')
                          .update(payload)
                          .eq('id', restaurant['id']);
                    }

                    if (!mounted) return;
                    Navigator.pop(dialogContext);
                    await _fetchRestaurants();
                    unawaited(appState.fetchRestaurantsAndCategories());
                    unawaited(appState.fetchRestaurantAverages());

                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم حفظ بيانات المطعم بنجاح ✅'),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تعذر حفظ البيانات: $e')),
                    );
                  }
                },
                child: const Text(
                  'حفظ',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isDark = appState.isDarkMode;
    final themeBg =
        isDark ? const Color(0xFF121212) : const Color(0xFFF0F2F5);
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    final allProducts = appState.products;
    final activeCount =
        _restaurants.where((r) => (r['is_active'] ?? true) == true).length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: themeBg,
        appBar: AppBar(
          backgroundColor: cardBg,
          title: const Text(
            'إدارة المطاعم والشعارات والتقييمات العادلة 🍽️',
            style: TextStyle(
              color: Colors.amber,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          iconTheme: const IconThemeData(color: Colors.amber),
          actions: [
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.amber),
              tooltip: 'إضافة مطعم',
              onPressed: () => _showEditRestaurantDialog(appState, null),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.amber),
              )
            : RefreshIndicator(
                color: Colors.amber,
                onRefresh: () async {
                  await Future.wait([
                    _fetchRestaurants(),
                    appState.fetchRestaurantAverages(),
                    appState.fetchProductsFromSupabase(),
                  ]);
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 12.5),
                        ),
                      ),
                    ],
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'إجمالي المطاعم المسجلة ونظام التقييم العادل',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$activeCount مطعم نشط من أصل ${_restaurants.length}',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'قائمة المطاعم والشعارات والتقييم العادل',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _restaurants.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(30),
                            child: Center(
                              child: Text(
                                'لا توجد مطاعم مسجلة، اضغط على زر الإضافة أعلى الصفحة ➕',
                                style: TextStyle(color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _restaurants.length,
                            itemBuilder: (context, index) {
                              final rest = _restaurants[index];
                              final restId = rest['id']?.toString();
                              final restName =
                                  (rest['name'] ?? '').toString().trim();
                              final restCat = _normalizeCategory(
                                  (rest['category'] ?? '').toString());
                              final logoUrl =
                                  (rest['logo_url'] ?? '').toString().trim();
                              final isActive = rest['is_active'] ?? true;

                              final ratingInfo = appState.getRestaurantRatingInfo(
                                restaurantId: restId,
                                restaurantName: restName,
                              );
                              final double avg = double.tryParse(
                                      ratingInfo?['avg']?.toString() ?? '0.0') ??
                                  0.0;
                              final int totalRatings = int.tryParse(
                                      ratingInfo?['total']?.toString() ??
                                          '0') ??
                                  0;

                              final ratingLabel = totalRatings > 0 && avg > 0
                                  ? '${avg.toStringAsFixed(1)} ($totalRatings تقييم عادل)'
                                  : 'جديد (تقييم عادل)';

                              final storeProducts = allProducts
                                  .where((p) =>
                                      p.restaurantName.trim().toLowerCase() ==
                                      restName.toLowerCase())
                                  .toList();

                              return Card(
                                color: cardBg,
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: ExpansionTile(
                                  iconColor: Colors.amber,
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: logoUrl.isNotEmpty
                                        ? Image.network(
                                            logoUrl,
                                            width: 45,
                                            height: 45,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                Container(
                                              width: 45,
                                              height: 45,
                                              color: Colors.amber
                                                  .withValues(alpha: 0.2),
                                              child: const Icon(Icons.store,
                                                  color: Colors.amber),
                                            ),
                                          )
                                        : Container(
                                            width: 45,
                                            height: 45,
                                            color: Colors.amber
                                                .withValues(alpha: 0.2),
                                            child: const Icon(Icons.store,
                                                color: Colors.amber),
                                          ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          restName,
                                          style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (!isActive)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.redAccent
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'متوقف',
                                            style: TextStyle(
                                              color: Colors.redAccent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          const Icon(Icons.star,
                                              color: Colors.amber, size: 14),
                                          const SizedBox(width: 4),
                                          Text(
                                            ratingLabel,
                                            style: const TextStyle(
                                              color: Colors.amber,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const Text(' | ',
                                              style:
                                                  TextStyle(color: Colors.grey)),
                                          Text(
                                            'الوجبات: ${storeProducts.length}',
                                            style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        'القسم: $restCat',
                                        style: const TextStyle(
                                            color: Colors.grey, fontSize: 11.5),
                                      ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Switch(
                                        value: isActive,
                                        activeColor: Colors.amber,
                                        onChanged: (val) =>
                                            _toggleRestaurantActive(
                                                appState, rest, val),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit,
                                            color: Colors.blueAccent),
                                        onPressed: () =>
                                            _showEditRestaurantDialog(
                                                appState, rest),
                                      ),
                                    ],
                                  ),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Divider(color: Colors.white12),
                                          const Text(
                                            'الوجبات التابعة لهذا المطعم:',
                                            style: TextStyle(
                                              color: Colors.amber,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          if (storeProducts.isEmpty)
                                            const Text(
                                              'لا توجد وجبات مضافة بعد.',
                                              style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12.5),
                                            )
                                          else
                                            ...storeProducts.map(
                                              (p) => Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 2.0),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(
                                                      '• ${p.name}',
                                                      style: TextStyle(
                                                          color: textColor,
                                                          fontSize: 13),
                                                    ),
                                                    Text(
                                                      '${p.price} ر.ي',
                                                      style: const TextStyle(
                                                          color: Colors.grey,
                                                          fontSize: 12),
                                                    ),
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
      ),
    );
  }
}
