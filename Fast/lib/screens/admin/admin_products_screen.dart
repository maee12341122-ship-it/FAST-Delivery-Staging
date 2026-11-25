import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/app_state.dart';
import '../../models/product_model.dart';

class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();

  bool _isUploadingImage = false;
  bool _isUploadingLogo = false;

  String _filterCategory = 'الكل';
  String _filterStore = 'الكل';
  String _filterSubCategory = 'الكل';

  static const String _customStoreOption = '__CUSTOM_STORE__';

  final Map<String, List<String>> _categoryShopsMap = {
    'المطاعم': [
      'مدينتي',
      'السعيد',
      'الشميري',
      'تاج مول',
      'تاج شمسان',
      'ماريوت',
      'الراسني',
      'فود ستيشن',
      'ابو خالد',
      'بيرو كافي',
      'وافل واي',
      'دكه',
      'وضاح الدبعي',
      'الحضرمي',
      'عشي عشي',
      'بيت المضغوط',
      'زيزو',
      'زيون',
      'افندي',
      'متميزة في المطبخ',
    ],
    'حلويات ومعجنات': [
      'روزماري',
      'كاندي',
      'سويت سيتي',
      'سيت هوم',
      'ابو خالد',
      'حلويات عامة',
    ],
    'البقالات': [
      'سوبرماركت المدينة',
      'بقالة العائلة',
      'مارت تعز',
      'بقالة السعادة',
      'متجر مواد غذائية عامة',
    ],
    'مشاريع منزلية': [
      'عنباتي',
      'TWISTA',
    ],
    'الخضار والفواكه': [
      'سوق الخضار المركزي',
      'مكتبة الخضار الطازجة',
      'مفروشات الخضار والفواكه',
    ],
    'الصيدلية الآمنة': [
      'صيدليه الوافي',
      'صيدليه البريطانيه',
      'صيدليه كريم',
      'صيدليه الشيخ',
      'صيدليه التلال',
      'صيدليه صدام',
    ],
    'هدايا واكسسوارات': [
      'شغف',
      'فلاورز',
      'دار التحف والهدايا',
      'قصر التحف والهدايا',
    ],
  };

  final List<String> _mainCategories = [
    'المطاعم',
    'حلويات ومعجنات',
    'البقالات',
    'مشاريع منزلية',
    'الخضار والفواكه',
    'الصيدلية الآمنة',
    'هدايا واكسسوارات',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> _suggestedSubCategories(
      AppState appState, String category, String storeName) {
    final existingForStore =
        appState.getSubCategoriesForStore(storeName, category: category);
    final lowerStore = storeName.trim().toLowerCase();
    final List<String> defaults = [];

    if (lowerStore.contains('وافل')) {
      defaults.addAll([
        'الوافل',
        'الكريب الحالي',
        'الوجبات والكريب المالح',
        'الطواجن والتشيز والكوكيز',
        'الصحون العائلي',
        'المكرونة',
        'الشاورما',
        'الخبز',
        'الإضافات والمشروبات الغازية',
      ]);
    } else if (category == 'المطاعم') {
      defaults.addAll([
        'المشويات واللحوم',
        'الوجبات والرز والمقبلات',
        'الفطائر والبيتزا والمخبوزات',
        'الفتة والشعبيات والفطور',
        'السلطات والسحاوق',
        'الحلويات',
        'العصائر والمشروبات',
      ]);
    }

    final result = <String>[];
    for (final item in [...existingForStore, ...defaults]) {
      if (!result.any((e) => e.toLowerCase() == item.toLowerCase())) {
        result.add(item);
      }
    }
    return result;
  }

  bool _isStoreActive(dynamic rawActive) {
    if (rawActive == null) return true;
    if (rawActive is bool) return rawActive;
    final val = rawActive.toString().trim().toLowerCase();
    return val != 'false' && val != '0' && val != 'inactive';
  }

  List<String> _getStoresForCategory(AppState appState, String category) {
    final targetCat = category.trim().toLowerCase();

    final fromDb = appState.restaurantsList
        .where((r) {
          final rCat = (r['category'] ?? '').toString().trim().toLowerCase();
          return _isStoreActive(r['is_active']) && rCat == targetCat;
        })
        .map((r) => (r['name'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toList();

    final fallback = _categoryShopsMap[category] ?? const <String>[];
    final combined = <String>[];

    for (final name in [...fromDb, ...fallback]) {
      if (!combined.any((e) => e.toLowerCase() == name.toLowerCase())) {
        combined.add(name);
      }
    }
    return combined;
  }

  List<String> _getFilterStores(AppState appState) {
    final result = <String>[];
    void addUnique(String raw) {
      final clean = raw.trim();
      if (clean.isEmpty) return;
      if (!result.any((e) => e.toLowerCase() == clean.toLowerCase())) {
        result.add(clean);
      }
    }

    if (_filterCategory == 'الكل') {
      for (final p in appState.products) {
        addUnique(p.restaurantName);
      }
      for (final r in appState.restaurantsList) {
        if (_isStoreActive(r['is_active'])) {
          addUnique((r['name'] ?? '').toString());
        }
      }
      for (final list in _categoryShopsMap.values) {
        for (final s in list) {
          addUnique(s);
        }
      }
    } else {
      for (final s in _getStoresForCategory(appState, _filterCategory)) {
        addUnique(s);
      }
      for (final p in appState.products) {
        if (p.category.trim().toLowerCase() ==
            _filterCategory.trim().toLowerCase()) {
          addUnique(p.restaurantName);
        }
      }
    }

    return result;
  }

  List<String> _getFilterSubCategories(AppState appState) {
    final result = <String>[];
    void addUnique(String raw) {
      final clean = raw.trim();
      if (clean.isEmpty) return;
      if (!result.any((e) => e.toLowerCase() == clean.toLowerCase())) {
        result.add(clean);
      }
    }

    if (_filterStore != 'الكل') {
      for (final sub in appState.getSubCategoriesForStore(
        _filterStore,
        category: _filterCategory == 'الكل' ? null : _filterCategory,
      )) {
        addUnique(sub);
      }
    }

    for (final p in appState.products) {
      final matchesCat = _filterCategory == 'الكل' ||
          p.category.trim().toLowerCase() ==
              _filterCategory.trim().toLowerCase();
      final matchesStore = _filterStore == 'الكل' ||
          p.restaurantName.trim().toLowerCase() ==
              _filterStore.trim().toLowerCase();
      if (matchesCat && matchesStore) {
        addUnique(p.subCategory);
      }
    }

    return result;
  }

  List<ProductModel> _filterProducts(List<ProductModel> products) {
    final query = _searchController.text.trim().toLowerCase();

    return products.where((p) {
      final matchesCategory = _filterCategory == 'الكل' ||
          p.category.trim().toLowerCase() ==
              _filterCategory.trim().toLowerCase();

      final matchesStore = _filterStore == 'الكل' ||
          p.restaurantName.trim().toLowerCase() ==
              _filterStore.trim().toLowerCase();

      final matchesSubCat = _filterSubCategory == 'الكل' ||
          p.subCategory.trim().toLowerCase() ==
              _filterSubCategory.trim().toLowerCase();

      final matchesSearch = query.isEmpty ||
          p.name.toLowerCase().contains(query) ||
          p.restaurantName.toLowerCase().contains(query) ||
          p.subCategory.toLowerCase().contains(query) ||
          p.description.toLowerCase().contains(query) ||
          p.category.toLowerCase().contains(query);

      return matchesCategory &&
          matchesStore &&
          matchesSubCat &&
          matchesSearch;
    }).toList();
  }

  void _resetFilters() {
    setState(() {
      _filterCategory = 'الكل';
      _filterStore = 'الكل';
      _filterSubCategory = 'الكل';
      _searchController.clear();
    });
  }

  String _findExistingStoreLogo(
      AppState appState, String category, String storeName) {
    final cleanName = storeName.trim().toLowerCase();
    if (cleanName.isEmpty) return '';

    for (final r in appState.restaurantsList) {
      final rName = (r['name'] ?? '').toString().trim().toLowerCase();
      if (rName == cleanName) {
        final logo = (r['logo_url'] ?? r['image_url'] ?? '').toString().trim();
        if (logo.isNotEmpty) return logo;
      }
    }
    return '';
  }

  Future<String?> _uploadImageToSupabase(
    File imageFile,
    StateSetter setDialogState, {
    required bool isLogo,
  }) async {
    try {
      setDialogState(() {
        if (isLogo) {
          _isUploadingLogo = true;
        } else {
          _isUploadingImage = true;
        }
      });

      final prefix = isLogo ? 'store_logo' : 'product';
      final folder = isLogo ? 'logos' : 'products';
      final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storagePath = '$folder/$fileName';

      await Supabase.instance.client.storage
          .from('products')
          .upload(storagePath, imageFile);

      final String publicUrl = Supabase.instance.client.storage
          .from('products')
          .getPublicUrl(storagePath);

      setDialogState(() {
        if (isLogo) {
          _isUploadingLogo = false;
        } else {
          _isUploadingImage = false;
        }
      });
      return publicUrl;
    } catch (e) {
      setDialogState(() {
        if (isLogo) {
          _isUploadingLogo = false;
        } else {
          _isUploadingImage = false;
        }
      });
      debugPrint('❌ خطأ في رفع الصورة: $e');
      return null;
    }
  }

  Future<void> _saveStoreLogoToDatabase(
    AppState appState, {
    required String storeName,
    required String category,
    required String logoUrl,
  }) async {
    final cleanName = storeName.trim();
    final cleanLogo = logoUrl.trim();
    if (cleanName.isEmpty || cleanLogo.isEmpty) return;

    if (category.trim() == 'مشاريع منزلية') {
      try {
        final existingProject = await Supabase.instance.client
            .from('home_projects')
            .select('id')
            .ilike('name', cleanName)
            .maybeSingle();

        if (existingProject != null && existingProject['id'] != null) {
          await Supabase.instance.client.from('home_projects').update({
            'logo_url': cleanLogo,
            'image_url': cleanLogo,
            'is_active': true,
          }).eq('id', existingProject['id']);
        } else {
          await Supabase.instance.client.from('home_projects').insert({
            'name': cleanName,
            'image_url': cleanLogo,
            'logo_url': cleanLogo,
            'is_active': true,
          });
        }
      } catch (e) {
        debugPrint('ℹ️ تنبيه عند حفظ اللوجو في جدول المشاريع المنزلية: $e');
      }
    }

    final existingStore = await Supabase.instance.client
        .from('restaurants')
        .select('id')
        .ilike('name', cleanName)
        .maybeSingle();

    if (existingStore != null && existingStore['id'] != null) {
      await Supabase.instance.client.from('restaurants').update({
        'image_url': cleanLogo,
        'category': category.trim(),
        'is_active': true,
      }).eq('id', existingStore['id']);
    } else {
      await Supabase.instance.client.from('restaurants').insert({
        'name': cleanName,
        'category': category.trim(),
        'image_url': cleanLogo,
        'is_active': true,
      });
    }

    await appState.fetchRestaurantsAndCategories();
  }

  Future<void> _showProductDialog(
      BuildContext context, AppState appState,
      {ProductModel? product}) async {
    final isEditing = product != null;
    final nameController = TextEditingController(text: product?.name ?? '');
    final priceController = TextEditingController(
        text: product != null ? product.price.toString() : '');
    final imageController = TextEditingController(text: product?.imageUrl ?? '');
    final descriptionController =
        TextEditingController(text: product?.description ?? '');
    final subCategoryController =
        TextEditingController(text: product?.subCategory ?? '');

    String selectedCategory =
        (product != null && _mainCategories.contains(product.category))
            ? product.category
            : (_filterCategory != 'الكل' &&
                    _mainCategories.contains(_filterCategory)
                ? _filterCategory
                : 'المطاعم');

    var storesForCategory = _getStoresForCategory(appState, selectedCategory);
    final initialStore = (product?.restaurantName ??
            (_filterStore != 'الكل' ? _filterStore : ''))
        .trim();

    bool useCustomStore = initialStore.isNotEmpty &&
        !storesForCategory
            .any((s) => s.toLowerCase() == initialStore.toLowerCase());

    String selectedStore = useCustomStore
        ? _customStoreOption
        : (storesForCategory.firstWhere(
            (s) => s.toLowerCase() == initialStore.toLowerCase(),
            orElse: () =>
                storesForCategory.isNotEmpty ? storesForCategory.first : '',
          ));

    final customStoreController =
        TextEditingController(text: useCustomStore ? initialStore : '');

    final initialStoreName = useCustomStore ? initialStore : selectedStore;
    final storeLogoController = TextEditingController(
      text: _findExistingStoreLogo(appState, selectedCategory, initialStoreName),
    );

    bool isAvailable = product?.available ?? true;
    bool isVariablePrice = product?.isVariablePrice ?? false;
    String selectedUnit = product?.unit ?? 'كيلو';

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          storesForCategory = _getStoresForCategory(appState, selectedCategory);
          final activeStoreName = useCustomStore
              ? customStoreController.text.trim()
              : (selectedStore == _customStoreOption
                  ? customStoreController.text.trim()
                  : selectedStore);
          final suggestions = _suggestedSubCategories(
              appState, selectedCategory, activeStoreName);

          final dropdownItems = <DropdownMenuItem<String>>[
            ...storesForCategory.map(
              (store) => DropdownMenuItem<String>(
                value: store,
                child: Text(store),
              ),
            ),
            const DropdownMenuItem<String>(
              value: _customStoreOption,
              child: Text(
                '➕ إضافة اسم متجر / مشروع جديد...',
                style: TextStyle(color: Colors.amber),
              ),
            ),
          ];

          final validDropdownValue =
              dropdownItems.any((item) => item.value == selectedStore)
                  ? selectedStore
                  : (storesForCategory.isNotEmpty
                      ? storesForCategory.first
                      : _customStoreOption);

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text(
                isEditing ? 'تعديل المنتج 🛠️' : 'إضافة منتج جديد ➕',
                style: const TextStyle(
                    color: Colors.amber, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'اسم المنتج *',
                        labelStyle: TextStyle(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      dropdownColor: const Color(0xFF1E1E1E),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'القسم الرئيسي *',
                        labelStyle: TextStyle(color: Colors.grey),
                      ),
                      items: _mainCategories.map((cat) {
                        return DropdownMenuItem(value: cat, child: Text(cat));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedCategory = val;
                            final updatedStores =
                                _getStoresForCategory(appState, val);
                            if (updatedStores.isNotEmpty) {
                              selectedStore = updatedStores.first;
                              useCustomStore = false;
                              storeLogoController.text = _findExistingStoreLogo(
                                  appState, val, selectedStore);
                            } else {
                              selectedStore = _customStoreOption;
                              useCustomStore = true;
                              storeLogoController.text = '';
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: validDropdownValue,
                      dropdownColor: const Color(0xFF1E1E1E),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'اسم المتجر / البقالة / المشروع *',
                        labelStyle: TextStyle(color: Colors.amber),
                        border: OutlineInputBorder(),
                      ),
                      items: dropdownItems,
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedStore = val;
                            useCustomStore = val == _customStoreOption;
                            if (!useCustomStore) {
                              storeLogoController.text = _findExistingStoreLogo(
                                  appState, selectedCategory, val);
                            }
                          });
                        }
                      },
                    ),
                    if (useCustomStore) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: customStoreController,
                        style: const TextStyle(color: Colors.white),
                        onChanged: (_) => setDialogState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'اكتب اسم المتجر أو المشروع المنزلي *',
                          labelStyle: TextStyle(color: Colors.amberAccent),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: subCategoryController,
                      style: const TextStyle(color: Colors.white),
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText:
                            'القسم الداخلي للمتجر / المطعم (مثال: الوافل، الكريب، المشويات)',
                        labelStyle:
                            TextStyle(color: Colors.amberAccent, fontSize: 12),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (suggestions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      const Text('أقسام سريعة لهذا النشاط/المتجر:',
                          style: TextStyle(color: Colors.grey, fontSize: 11)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: suggestions.map((sec) {
                          final selected =
                              subCategoryController.text.trim() == sec;
                          return ChoiceChip(
                            label:
                                Text(sec, style: const TextStyle(fontSize: 11)),
                            selected: selected,
                            selectedColor: Colors.amber,
                            backgroundColor: const Color(0xFF121212),
                            labelStyle: TextStyle(
                              color: selected ? Colors.black : Colors.white70,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            onSelected: (_) {
                              setDialogState(() {
                                subCategoryController.text = sec;
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: storeLogoController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'لوجو المتجر / المشروع (URL)',
                              labelStyle: TextStyle(color: Colors.amberAccent),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _isUploadingLogo
                            ? const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      color: Colors.amber, strokeWidth: 2),
                                ),
                              )
                            : IconButton(
                                onPressed: () async {
                                  final XFile? logoFile = await _picker
                                      .pickImage(source: ImageSource.gallery);
                                  if (logoFile != null) {
                                    final uploadedLogoUrl =
                                        await _uploadImageToSupabase(
                                      File(logoFile.path),
                                      setDialogState,
                                      isLogo: true,
                                    );
                                    if (uploadedLogoUrl != null) {
                                      setDialogState(() {
                                        storeLogoController.text =
                                            uploadedLogoUrl;
                                      });
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'تم رفع لوجو الجهة بنجاح ✅')),
                                        );
                                      }
                                    } else if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text('تعذر رفع اللوجو ❌')),
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.storefront,
                                    color: Colors.amber, size: 28),
                                tooltip: 'اختيار ورفع لوجو المتجر أو المشروع',
                              ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: priceController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: isVariablePrice
                            ? 'السعر التقريبي لكل وحدة (ر.ي) *'
                            : 'السعر الثابت (ر.ي) *',
                        labelStyle: const TextStyle(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'وصف المنتج أو تفاصيله (اختياري)',
                        labelStyle: TextStyle(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: imageController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'رابط صورة المنتج (Image URL)',
                              labelStyle: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _isUploadingImage
                            ? const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      color: Colors.amber, strokeWidth: 2),
                                ),
                              )
                            : IconButton(
                                onPressed: () async {
                                  final XFile? image = await _picker.pickImage(
                                      source: ImageSource.gallery);
                                  if (image != null) {
                                    final uploadedUrl =
                                        await _uploadImageToSupabase(
                                      File(image.path),
                                      setDialogState,
                                      isLogo: false,
                                    );
                                    if (uploadedUrl != null) {
                                      setDialogState(() {
                                        imageController.text = uploadedUrl;
                                      });
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'تم رفع الصورة بنجاح إلى السحاب ☁️')),
                                        );
                                      }
                                    } else if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text('تعذر رفع الصورة ❌')),
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.add_photo_alternate,
                                    color: Colors.amber, size: 28),
                                tooltip: 'اختيار ورفع صورة المنتج من المعرض',
                              ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('متوفر حالياً؟',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                      value: isAvailable,
                      activeColor: Colors.amber,
                      onChanged: (val) =>
                          setDialogState(() => isAvailable = val),
                    ),
                    SwitchListTile(
                      title: const Text('سعر متغير (بالوزن/العدد)؟',
                          style: TextStyle(
                              color: Colors.amberAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                      value: isVariablePrice,
                      activeColor: Colors.amber,
                      onChanged: (val) =>
                          setDialogState(() => isVariablePrice = val),
                    ),
                    if (isVariablePrice) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedUnit,
                        dropdownColor: const Color(0xFF1E1E1E),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'وحدة القياس الإجبارية *',
                          labelStyle: TextStyle(color: Colors.amber),
                        ),
                        items: ['كيلو', 'جرام', 'حبة', 'ربطة', 'لتر', 'باكت']
                            .map((u) {
                          return DropdownMenuItem(value: u, child: Text(u));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedUnit = val);
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child:
                      const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                '⚠️ يرجى إدخال اسم المنتج بشكل إجباري!')),
                      );
                      return;
                    }

                    final double parsedPrice =
                        double.tryParse(priceController.text.trim()) ?? 0.0;
                    if (parsedPrice <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                '⚠️ يجب إدخال سعر صحيح أكبر من الصفر بشكل إجباري!')),
                      );
                      return;
                    }

                    final String finalStoreName = useCustomStore
                        ? customStoreController.text.trim()
                        : (validDropdownValue == _customStoreOption
                            ? customStoreController.text.trim()
                            : validDropdownValue);

                    if (finalStoreName.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                '⚠️ يرجى اختيار أو كتابة اسم المتجر/المشروع!')),
                      );
                      return;
                    }

                    final newProduct = ProductModel(
                      id: isEditing
                          ? product.id
                          : DateTime.now().millisecondsSinceEpoch.toString(),
                      name: nameController.text.trim(),
                      restaurantName: finalStoreName,
                      price: parsedPrice,
                      category: selectedCategory,
                      subCategory: subCategoryController.text.trim(),
                      available: isAvailable,
                      imageUrl: imageController.text.trim(),
                      description: descriptionController.text.trim(),
                      unit: isVariablePrice ? selectedUnit : 'حبة',
                      isVariablePrice: isVariablePrice,
                    );

                    try {
                      if (storeLogoController.text.trim().isNotEmpty) {
                        await _saveStoreLogoToDatabase(
                          appState,
                          storeName: finalStoreName,
                          category: selectedCategory,
                          logoUrl: storeLogoController.text.trim(),
                        );
                      }
                      await appState.upsertProduct(newProduct);
                      if (!context.mounted) return;
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('تم حفظ المنتج واللوجو بنجاح ✅')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('خطأ في الحفظ: $e')),
                      );
                    }
                  },
                  child: const Text('حفظ',
                      style: TextStyle(
                          color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        },
      ),
    );

    nameController.dispose();
    priceController.dispose();
    imageController.dispose();
    descriptionController.dispose();
    subCategoryController.dispose();
    customStoreController.dispose();
    storeLogoController.dispose();
  }

  void _showDeleteConfirmationDialog(BuildContext context, AppState appState,
      String productId, String productName) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('تأكيد الحذف 🗑️',
                  style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'هل أنت متأكد من رغبتك في حذف المنتج ($productName) نهائياً؟',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.pop(context);
                await appState.removeProduct(productId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حذف المنتج بنجاح 🗑️')),
                  );
                }
              },
              child: const Text('نعم، حذف',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChipStrip({
    required String label,
    required List<String> items,
    required String selectedValue,
    required ValueChanged<String> onSelected,
  }) {
    final chips = ['الكل', ...items];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4, top: 6),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: chips.length,
            itemBuilder: (context, index) {
              final item = chips[index];
              final isSelected = selectedValue == item;
              return Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(
                  label: Text(
                    item,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isSelected ? Colors.black : Colors.white70,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: Colors.amber,
                  backgroundColor: const Color(0xFF121212),
                  side: BorderSide(
                    color: isSelected
                        ? Colors.amber
                        : Colors.white.withOpacity(0.15),
                  ),
                  onSelected: (_) => onSelected(item),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final allProducts = appState.products;
    final availableStores = _getFilterStores(appState);
    final validStoreFilter =
        _filterStore == 'الكل' || availableStores.contains(_filterStore)
            ? _filterStore
            : 'الكل';

    final availableSubCategories = _getFilterSubCategories(appState);
    final validSubCatFilter = _filterSubCategory == 'الكل' ||
            availableSubCategories.contains(_filterSubCategory)
        ? _filterSubCategory
        : 'الكل';

    final filteredProducts = _filterProducts(allProducts);
    final hasActiveFilter = _filterCategory != 'الكل' ||
        validStoreFilter != 'الكل' ||
        validSubCatFilter != 'الكل' ||
        _searchController.text.trim().isNotEmpty;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('إدارة المنتجات والأصناف 🍔',
              style:
                  TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: Colors.amber),
          actions: [
            if (hasActiveFilter)
              TextButton.icon(
                onPressed: _resetFilters,
                icon: const Icon(Icons.filter_alt_off,
                    color: Colors.amber, size: 18),
                label: const Text('إعادة ضبط',
                    style: TextStyle(color: Colors.amber, fontSize: 12)),
              ),
          ],
        ),
        body: Column(
          children: [
            Container(
              color: const Color(0xFF1E1E1E),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText:
                          'ابحث باسم المنتج، المتجر، القسم الداخلي، أو الوصف...',
                      hintStyle:
                          const TextStyle(color: Colors.grey, fontSize: 12),
                      prefixIcon: const Icon(Icons.search, color: Colors.amber),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear,
                                  color: Colors.grey, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF121212),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: Colors.amber.withOpacity(0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: Colors.amber.withOpacity(0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.amber),
                      ),
                    ),
                  ),
                  _buildFilterChipStrip(
                    label: '1. القسم الرئيسي:',
                    items: _mainCategories,
                    selectedValue: _filterCategory,
                    onSelected: (val) {
                      setState(() {
                        _filterCategory = val;
                        _filterStore = 'الكل';
                        _filterSubCategory = 'الكل';
                      });
                    },
                  ),
                  _buildFilterChipStrip(
                    label: '2. المتجر / المشروع:',
                    items: availableStores,
                    selectedValue: validStoreFilter,
                    onSelected: (val) {
                      setState(() {
                        _filterStore = val;
                        _filterSubCategory = 'الكل';
                      });
                    },
                  ),
                  if (availableSubCategories.isNotEmpty)
                    _buildFilterChipStrip(
                      label: '3. القسم الداخلي / الصنف:',
                      items: availableSubCategories,
                      selectedValue: validSubCatFilter,
                      onSelected: (val) {
                        setState(() {
                          _filterSubCategory = val;
                        });
                      },
                    ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'عدد المنتجات: ${filteredProducts.length} من ${allProducts.length}',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold),
                      ),
                      if (validStoreFilter != 'الكل')
                        Text(
                          'المتجر: $validStoreFilter',
                          style: const TextStyle(
                              color: Colors.amberAccent, fontSize: 11),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: filteredProducts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'لا توجد منتجات مطابقة للتصفية أو البحث',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                          if (hasActiveFilter) ...[
                            const SizedBox(height: 10),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.amber,
                                  side: const BorderSide(color: Colors.amber)),
                              onPressed: _resetFilters,
                              child: const Text('عرض جميع المنتجات'),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final ProductModel product = filteredProducts[index];
                        final subLabel = product.subCategory.trim().isNotEmpty
                            ? ' | قسم: ${product.subCategory.trim()}'
                            : '';
                        return Card(
                          color: const Color(0xFF1E1E1E),
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: Colors.amber.withOpacity(0.2)),
                          ),
                          child: ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: product.imageUrl.isNotEmpty
                                  ? Image.network(
                                      product.imageUrl,
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(
                                          Icons.fastfood,
                                          color: Colors.amber),
                                    )
                                  : const Icon(Icons.fastfood,
                                      color: Colors.amber),
                            ),
                            title: Text(product.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              '${product.restaurantName}$subLabel | ${product.price} ر.ي\nوصف: ${product.description.isNotEmpty ? product.description : "بدون وصف"}',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      color: Colors.blueAccent, size: 20),
                                  onPressed: () => _showProductDialog(
                                      context, appState,
                                      product: product),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.redAccent, size: 20),
                                  onPressed: () =>
                                      _showDeleteConfirmationDialog(
                                          context,
                                          appState,
                                          product.id,
                                          product.name),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.amber,
          onPressed: () => _showProductDialog(context, appState),
          child: const Icon(Icons.add, color: Colors.black),
        ),
      ),
    );
  }
}
