import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
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

  void _showProductDialog(BuildContext context, AppState appState, {ProductModel? product}) {
    final isEditing = product != null;
    final nameController = TextEditingController(text: product?.name ?? '');
    final restaurantController = TextEditingController(text: product?.restaurantName ?? '');
    final priceController = TextEditingController(text: product != null ? product.price.toString() : '');
    final imageController = TextEditingController(text: product?.imageUrl ?? '');
    String selectedCategory = product?.category ?? 'المطاعم';
    bool isAvailable = product?.available ?? true;
    bool isVariablePrice = product?.isVariablePrice ?? false;
    String selectedUnit = product?.unit ?? 'كيلو';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
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
                  TextField(
                    controller: restaurantController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'اسم المطعم أو المتجر', labelStyle: TextStyle(color: Colors.grey)),
                  ),
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
                  const SizedBox(height: 12),
                  
                  // 🖼️ قسم اختيار الصورة من المعرض
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
                      IconButton(
                        onPressed: () async {
                          final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                          if (image != null) {
                            setDialogState(() {
                              // مؤقتاً نضع مسار الصورة المحلي أو يمكن رفعه لـ Supabase Storage
                              imageController.text = image.path;
                            });
                          }
                        },
                        icon: const Icon(Icons.add_photo_alternate, color: Colors.amber, size: 28),
                        tooltip: 'اختيار صورة من المعرض',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    dropdownColor: const Color(0xFF1E1E1E),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'القسم', labelStyle: TextStyle(color: Colors.grey)),
                    items: ['المطاعم', 'البقالات', 'الخضار والفواكه', 'الصيدلية الآمنة', 'هدايا واكسسوارات'].map((cat) {
                      return DropdownMenuItem(value: cat, child: Text(cat));
                    }).toList(),
                    onChanged: (val) => setDialogState(() => selectedCategory = val!),
                  ),
                  const SizedBox(height: 8),
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
                    restaurantName: restaurantController.text.trim(),
                    price: parsedPrice,
                    category: selectedCategory,
                    available: isAvailable,
                    imageUrl: imageController.text.trim(),
                    unit: isVariablePrice ? selectedUnit : 'حبة',
                    isVariablePrice: isVariablePrice,
                  );

                  try {
                    await appState.upsertProduct(newProduct);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم حفظ المنتج وتحديث الصورة بنجاح ✅')),
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
                            ? (product.imageUrl.startsWith('http')
                                ? Image.network(product.imageUrl, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.fastfood, color: Colors.amber))
                                : Image.file(File(product.imageUrl), width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.fastfood, color: Colors.amber)))
                            : const Icon(Icons.fastfood, color: Colors.amber),
                      ),
                      title: Text(product.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        '${product.restaurantName} | ${product.price} ر.ي ${product.isVariablePrice ? "(بـ ${product.unit})" : ""}\nالحالة: ${product.available ? "متوفر ✅" : "غير متوفر ❌"}',
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
                            onPressed: () async {
                              await appState.removeProduct(product.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم حذف المنتج بنجاح 🗑️')),
                              );
                            },
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
