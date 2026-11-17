import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';

class CustomDeliveryScreen extends StatefulWidget {
  final String? token;

  const CustomDeliveryScreen({Key? key, this.token}) : super(key: key);

  @override
  State<CustomDeliveryScreen> createState() => _CustomDeliveryScreenState();
}

class _CustomDeliveryScreenState extends State<CustomDeliveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  final _estimatedPriceController = TextEditingController();
  final _notesController = TextEditingController();
  
  bool _isLoading = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    _addressController.dispose();
    _estimatedPriceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submitOrder(AppState appState) async {
    if (!_formKey.currentState!.validate()) return;

    if (appState.userProfile == null || appState.userProfile!['phone'] == null || (appState.userProfile!['phone'] as String).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء تسجيل الدخول برقم الهاتف أولاً ⚠️')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final customerName = appState.userProfile!['name'] ?? 'عميل';
      final phone = appState.userProfile!['phone'] ?? '';
      final address = _addressController.text.trim();
      final itemsDesc = _descriptionController.text.trim() + (_notesController.text.isNotEmpty ? ' - ملاحظات: ${_notesController.text.trim()}' : '');
      final estimatedPrice = double.tryParse(_estimatedPriceController.text.trim()) ?? 1000.0;

      await appState.createOrder(
        customerName: customerName,
        phone: phone,
        address: address,
        itemsDesc: itemsDesc,
        productsTotal: estimatedPrice,
        paymentMethod: 'cash',
        paymentAccount: 'cash_on_delivery',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال طلب "وصل لي" بنجاح، بانتظار تسعير الإدارة 🚀')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل إرسال الطلب: $e ❌')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('خدمة "وصل لي" الخاصة 🛵', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: Colors.amber),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.withOpacity(0.3)),
                  ),
                  child: const Text(
                    'اكتب تفاصيل ما تريد إحضاره أو توصيله (مثل: غاز، قات، طلبات من الصيدلية، أو شحنة خاصة)، وسيقوم المشرف بتحديد رسوم التوصيل وإرسالها لك للموافقة.',
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'تفاصيل الغرض أو الطلب المطلوب',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF1E1E1E),
                    prefixIcon: Icon(Icons.shopping_bag_outlined, color: Colors.amber),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty ? 'الرجاء إدخال تفاصيل الطلب' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _addressController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'عنوان التوصيل بالتفصيل (الشارع، المعلم، المنزل)',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF1E1E1E),
                    prefixIcon: Icon(Icons.location_on_outlined, color: Colors.amber),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty ? 'الرجاء إدخال عنوان التوصيل' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _estimatedPriceController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'قيمة أو سعر الغرض التقديري (ر.ي)',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF1E1E1E),
                    prefixIcon: Icon(Icons.attach_money, color: Colors.amber),
                  ),
                  validator: (value) {
                    if (value == null || double.tryParse(value) == null || double.parse(value) <= 0) {
                      return 'أدخل قيمة تقديرية صحيحة';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات إضافية (اختياري)',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF1E1E1E),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : () => _submitOrder(appState),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                        )
                      : const Text(
                          'إرسال طلب "وصل لي" 🚀',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
