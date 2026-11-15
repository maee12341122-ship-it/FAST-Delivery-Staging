import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import '../../providers/app_state.dart';
import '../../models/product_model.dart';

class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({Key? key}) : super(key: key);

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isUploadingImage = false;

  // 🗺️ خريطة شاملة لكافة الأقسام والمتاجر التابعة لها لتجنب أي نقص في القائمة المنسدلة
  final Map<String, List<String>> _categoryShopsMap = {
    'المطاعم': [
      'مدينتي', 'السعيد', 'الشميري', 'تاج مول', 'تاج شمسان', 'ماريوت',
      'الراسني', 'فود ستيشن', 'ابو خالد', 'بيرو كافي', 'وافل واي', 'دكه',
      'وضاح الدبعي', 'الحضرمي', 'عشي عشي', 'بيت المضغوط', 'زيزو', 'زيون',
      'افندي', 'متميزة في المطبخ'
    ],
    'حلويات ومعجنات': [
      'روزماري', 'كاندي', 'سويت سيتي', 'سيت هوم', 'ابو خالد', 'حلويات عامة'
    ],
    'البقالات': [
      'سوبرماركت المدينة', 'بقالة العائلة', 'مارت تعز', 'بقالة السعادة', 'متجر مواد غذائية عامة'
    ],
    'الخضار والفواكه': [
      'سوق الخضار المركزي', 'مكتبة الخضار الطازجة', 'مفروشات الخضار والفواكه'
    ],
    'الصيدلية الآمنة': [
      'صيدليه الوافي', 'صيدليه البريطانيه', 'صيدليه كريم',
      'صيدليه الشيخ', 'صيدليه التلال', 'صيدليه صدام'
    ],
    'هدايا واكسسوارات': [
      'شغف', 'فلاورز', 'دار التحف والهدايا', 'قصر التحف والهدايا'
    ],
  };

  final List<String> _mainCategories = [
    'المطاعم',
    'حلويات ومعجنات',
    'البقالات',
    'الخضار والفواكه',
    'الصيدلية الآمنة',
    'هدايا واكسسوارات'
  ];

  Future<String?> _uploadImageToSupabase(File imageFile, StateSetter setDialogState) async {
    try {
      setDialogState(() => _isUploadingImage = true);
      
      final fileName = 'product_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storagePath = 'products/$fileName';

      await Supabase.instance.client.storage
          .from('products')
          .upload(storagePath, imageFile);

      final String publicUrl = Supabase.instance.client.storage
          .from('products')
          .getPublicUrl(storagePath);

      setDialogState(() => _isUploadingImage = false);
      return publicUrl;
    } catch (e) {
      setDialogState(() => _isUploadingImage = false);
      debugPrint('❌ خطأ في رفع الصورة: $e');
      return null;
    }
  }

  void _showProductDialog(BuildContext context, AppState appState, {ProductModel? product}) {
    final isEditing = product != null;
    final nameController = TextEditingController(text: product?.name ?? '');
    final priceController = TextEditingController(text: product != null ? product.price.toString() : '');
    final imageController = TextEditingController(text: product?.imageUrl ?? '');
    final descriptionController = TextEditingController(text: product?.description ?? '');
    
    String selectedCategory = (product != null && _mainCategories.contains(product.category))
        ? product.category
        : 'المطاعم';

    String? selectedStore = product?.restaurantName;
    if (_categoryShopsMap.containsKey(selectedCategory)) {
      final stores = _categoryShopsMap[selectedCategory]!;
      if (!stores.contains(selectedStore)) {
        selectedStore = stores.first;
      }
    } else {
      selectedStore = product?.restaurantName ?? '';
    }

    bool isAvailable = product?.available ?? true;
    bool isVariablePrice = product?.isVariablePrice ?? false;
    String selectedUnit = product?.unit ?? 'كيلو';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final List<String>? availableStores = _categoryShopsMap[selectedCategory];

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                isEditing ? 'تعديل المنتج 🛠️' : 'إضافة منتج جديد ➕',
                style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'اسم المنتج *', labelStyle: TextStyle(color: Colors.grey)),
                    ),
                    const SizedBox(height: 8),

                    // اختيار القسم الرئيسي
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      dropdownColor: const Color(0xFF1E1E1E),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'القسم الرئيسي *', labelStyle: TextStyle(color: Colors.grey)),
                      items: _mainCategories.map((cat) {
                        return DropdownMenuItem(value: cat, child: Text(cat));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedCategory = val;
                            if (_categoryShopsMap.containsKey(val)) {
                              selectedStore = _categoryShopsMap[val]!.first;
                            } else {
                              selectedStore = '';
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),

                    // القائمة المنسدلة لأسماء المحلات والصيدليات تلقائياً بناءً على القسم
                    if (availableStores != null && availableStores.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        value: availableStores.contains(selectedStore) ? selectedStore : availableStores.first,
                        dropdownColor: const Color(0xFF1E1E1E),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'اختر اسم المتجر/المكان *',
                          labelStyle: const TextStyle(color: Colors.amber),
                          border: const OutlineInputBorder(),
                        ),
                        items: availableStores.map((store) {
                          return DropdownMenuItem(value: store, child: Text(store));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedStore = val;
                            });
                          }
                        },
                      ),
                    ] else ...[
                      TextField(
                        controller: TextEditingController(text: selectedStore),
                        style: const TextStyle(color: Colors.white),
                        onChanged: (val) => selectedStore = val,
                        decoration: const InputDecoration(labelText: 'اسم المتجر أو الجهة (اختياري)', labelStyle: TextStyle(color: Colors.grey)),
                      ),
                    ],
                    const SizedBox(height: 8),

                    TextField(
                      controller: priceController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: isVariablePrice ? 'السعر التقريبي لكل وحدة (ر.ي) *' : 'السعر الثابت (ر.ي) *',
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
                            decoration: const InputDecoration(labelText: 'رابط الصورة (Image URL)', labelStyle: TextStyle(color: Colors.grey)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _isUploadingImage
                            ? const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2)),
                              )
                            : IconButton(
                                onPressed: () async {
                                  final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                                  if (image != null) {
                                    final uploadedUrl = await _uploadImageToSupabase(File(image.path), setDialogState);
                                    if (uploadedUrl != null) {
                                      setDialogState(() {
                                        imageController.text = uploadedUrl;
                                      });
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('تم رفع الصورة بنجاح إلى السحاب ☁️')),
                                        );
                                      }
                                    } else {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('تعذر رفع الصورة ❌')),
                                        );
                                      }
                                    }
                                  }
                                },
                                icon: const Icon(Icons.add_photo_alternate, color: Colors.amber, size: 28),
                                tooltip: 'اختيار ورفع صورة من المعرض',
                              ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    SwitchListTile(
                      title: const Text('متوفر حالياً؟', style: TextStyle(color: Colors.white, fontSize: 13)),
                      value: isAvailable,
                      activeColor: Colors.amber,
                      onChanged: (val) => setDialogState(() => isAvailable = val),
                    ),
                    SwitchListTile(
                      title: const Text('سعر متغير (بالوزن/العدد)؟', style: TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                      value: isVariablePrice,
                      activeColor: Colors.amber,
                      onChanged: (val) => setDialogState(() => isVariablePrice = val),
                    ),
                    if (isVariablePrice) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedUnit,
                        dropdownColor: const Color(0xFF1E1E1E),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'وحدة القياس الإجبارية *', labelStyle: TextStyle(color: Colors.amber)),
                        items: ['كيلو', 'جرام', 'حبة', 'ربطة', 'لتر', 'باكت'].map((u) {
                          return DropdownMenuItem(value: u, child: Text(u));
                        }).toList(),
                        onChanged: (val) => setDialogState(() => selectedUnit = val!),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('⚠️ يرجى إدخال اسم المنتج بشكل إجباري!')),
                      );
                      return;
                    }

                    final double parsedPrice = double.tryParse(priceController.text.trim()) ?? 0.0;
                    if (parsedPrice <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('⚠️ يجب إدخال سعر صحيح أكبر من الصفر بشكل إجباري!')),
                      );
                      return;
                    }

                    final newProduct = ProductModel(
                      id: isEditing ? product.id : DateTime.now().millisecondsSinceEpoch.toString(),
                      name: nameController.text.trim(),
                      restaurantName: selectedStore ?? '',
                      price: parsedPrice,
                      category: selectedCategory,
                      available: isAvailable,
                      imageUrl: imageController.text.trim(),
                      description: descriptionController.text.trim(),
                      unit: isVariablePrice ? selectedUnit : 'حبة',
                      isVariablePrice: isVariablePrice,
                    );

                    try {
                      await appState.upsertProduct(newProduct);
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم حفظ المنتج مع الوصف بنجاح ✅')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('خطأ في الحفظ: $e')),
                      );
                    }
                  },
                  child: const Text('حفظ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context, AppState appState, String productId, String productName) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('تأكيد الحذف 🗑️', style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
              child: const Text('نعم، حذف', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final products = appState.products;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('إدارة المنتجات والأصناف 🍔', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: Colors.amber),
        ),
        body: products.isEmpty
            ? const Center(child: Text('لا توجد منتجات مسجلة حالياً', style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final ProductModel product = products[index];
                  return Card(
                    color: const Color(0xFF1E1E1E),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.amber.withOpacity(0.2)),
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
                                errorBuilder: (_, __, ___) => const Icon(Icons.fastfood, color: Colors.amber),
                              )
                            : const Icon(Icons.fastfood, color: Colors.amber),
                      ),
                      title: Text(product.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        '${product.restaurantName} | ${product.price} ر.ي\nوصف: ${product.description.isNotEmpty ? product.description : "بدون وصف"}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blueAccent, size: 20),
                            onPressed: () => _showProductDialog(context, appState, product: product),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                            onPressed: () => _showDeleteConfirmationDialog(context, appState, product.id, product.name),
                          ),
                        ],
                      ),
                    ),
                  );
                },
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
