import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../utils/constants.dart';
import '../utils/validators.dart';

class CustomOrderWidget extends StatefulWidget {
  const CustomOrderWidget({super.key});

  @override
  State<CustomOrderWidget> createState() => _CustomOrderWidgetState();
}

class _CustomOrderWidgetState extends State<CustomOrderWidget> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _add() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AppState>().addCustomItem(
          name: _nameController.text,
          price: int.parse(_priceController.text),
          quantity: int.parse(_quantityController.text),
          notes: _notesController.text,
        );
    _nameController.clear();
    _priceController.clear();
    _quantityController.text = '1';
    _notesController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('أُضيف الطلب الخاص إلى السلة بنجاح! 🛒')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.edit_note, color: AppConstants.gold, size: 24),
                SizedBox(width: 8),
                Text('طلبات خاصة وخدمات أخرى', style: TextStyle(color: AppConstants.gold, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'اكتب الغرض المطلوب وسعره التقديري. سيحتاج السعر إلى مراجعة الإدارة قبل اعتماده نهائياً.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'اسم المنتج أو الطلب المطلوب',
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFF1E1E1E),
                prefixIcon: Icon(Icons.shopping_bag_outlined, color: AppConstants.gold),
              ),
              validator: (value) => Validators.requiredText(value),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'السعر التقديري (ر.ي)',
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFF1E1E1E),
                prefixIcon: Icon(Icons.attach_money, color: AppConstants.gold),
              ),
              validator: (value) {
                if (value == null || int.tryParse(value) == null || int.parse(value) < 0) return 'أدخل سعراً صحيحاً';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'الكمية',
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFF1E1E1E),
                prefixIcon: Icon(Icons.format_list_numbered, color: AppConstants.gold),
              ),
              validator: (value) {
                if (value == null || int.tryParse(value) == null || int.parse(value) < 1) return 'أدخل كمية صحيحة';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'الوصف أو الملاحظات التفصيلية (اختياري)',
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFF1E1E1E),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppConstants.gold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _add,
              icon: const Icon(Icons.add_shopping_cart, color: Colors.black),
              label: const Text('إضافة الطلب إلى السلة 🚀', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
