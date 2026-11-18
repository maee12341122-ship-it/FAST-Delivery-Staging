import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import 'map_location_screen.dart';

class CustomDeliveryScreen extends StatefulWidget {
  final String? token;

  const CustomDeliveryScreen({Key? key, this.token}) : super(key: key);

  @override
  State<CustomDeliveryScreen> createState() => _CustomDeliveryScreenState();
}

class _CustomDeliveryScreenState extends State<CustomDeliveryScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // حقول الربط الثلاثي الجديدة (من أين، إلى أين، وصف الغرض والملاحظات)
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropoffController = TextEditingController();
  final TextEditingController _itemDescriptionController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  
  bool _isLoading = false;

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    _itemDescriptionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // اختيار الموقع إما من الخريطة أو من العناوين المحفوظة
  Future<void> _pickLocationOptions(TextEditingController targetController) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'اختر مصدر العنوان 📍',
                style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                tileColor: const Color(0xFF121212),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.map, color: Colors.amber),
                title: const Text('تحديد من الخريطة التفاعلية 🗺️', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const MapLocationScreen()),
                  );
                  if (result != null && result is Map) {
                    setState(() {
                      targetController.text = result['address'] ?? 'موقع محدد من الخريطة';
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                tileColor: const Color(0xFF121212),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.bookmark, color: Colors.amber),
                title: const Text('من العناوين المحفوظة 🏠', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                onTap: () {
                  Navigator.pop(context);
                  _showSavedAddressesDialog(targetController);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  // نافذة اختيار العنوان من العناوين المحفوظة للمستخدم
  void _showSavedAddressesDialog(TextEditingController targetController) {
    final appState = Provider.of<AppState>(context, listen: false);

    if (appState.userAddresses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد عناوين محفوظة مسبقاً. يمكنك إضافتها من صفحة حسابي 🏠')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Row(
            children: [
              Icon(Icons.bookmark, color: Colors.amber),
              SizedBox(width: 8),
              Text('عناوينك المحفوظة 📍', style: TextStyle(color: Colors.amber, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 250,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: appState.userAddresses.length,
              itemBuilder: (context, index) {
                final addr = appState.userAddresses[index];
                return Card(
                  color: const Color(0xFF121212),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(addr.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text('${addr.area} - ${addr.details}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    trailing: const Icon(Icons.arrow_forward_ios, color: Colors.amber, size: 14),
                    onTap: () {
                      setState(() {
                        targetController.text = '${addr.title}: ${addr.area} - ${addr.details}';
                      });
                      Navigator.pop(context);
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
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
      
      final pickup = _pickupController.text.trim();
      final dropoff = _dropoffController.text.trim();
      final itemDesc = _itemDescriptionController.text.trim();
      final notes = _notesController.text.trim();

      // دمج تفاصيل النقل والمسار في وصف الطلب والعنوان لترسل للإدارة والمندوب بدقة
      final fullAddress = 'من: $pickup ➡️ إلى: $dropoff';
      final itemsDesc = '📦 [خدمة وصل لي الخاصة]\n'
          '📍 مكان الاستلام: $pickup\n'
          '🎯 مكان التوصيل: $dropoff\n'
          '🏷️ الغرض: $itemDesc' + (notes.isNotEmpty ? '\n💬 ملاحظات: $notes' : '');

      // 💡 التعديل هنا: جعل سعر المنتجات 0.0 تماماً لأنها خدمة توصيل أغراض وليست شراء منتجات، بانتظار تسعير الإدارة لرسوم التوصيل
      await appState.createOrder(
        customerName: customerName,
        phone: phone,
        address: fullAddress,
        itemsDesc: itemsDesc,
        productsTotal: 0.0, 
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
                    'خدمة توصيل الأغراض من نقطة إلى نقطة (من أين وإلى أين). حدد موقع الاستلام، موقع التوصيل، ووصف الغرض، وسيقوم المشرف بتحديد رسوم التوصيل وإرسالها لك.',
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                ),
                const SizedBox(height: 20),

                // 1️⃣ حقل الاستلام (من أين)
                TextFormField(
                  controller: _pickupController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'من أين نستلم الغرض؟ (مكان الاستلام)*',
                    labelStyle: const TextStyle(color: Colors.grey),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    prefixIcon: const Icon(Icons.trip_origin, color: Colors.amber),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.location_searching, color: Colors.amber),
                      tooltip: 'اختر من الخريطة أو العناوين',
                      onPressed: () => _pickLocationOptions(_pickupController),
                    ),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty ? 'الرجاء إحديد مكان الاستلام' : null,
                ),
                const SizedBox(height: 14),

                // 2️⃣ حقل التوصيل (إلى أين)
                TextFormField(
                  controller: _dropoffController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'إلى أين نوصّل الغرض؟ (مكان التسليم)*',
                    labelStyle: const TextStyle(color: Colors.grey),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    prefixIcon: const Icon(Icons.location_on, color: Colors.redAccent),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.location_searching, color: Colors.amber),
                      tooltip: 'اختر من الخريطة أو العناوين',
                      onPressed: () => _pickLocationOptions(_dropoffController),
                    ),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty ? 'الرجاء تحديد مكان التوصيل' : null,
                ),
                const SizedBox(height: 14),

                // 3️⃣ وصف الغرض أو الشحنة
                TextFormField(
                  controller: _itemDescriptionController,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'ما هو أصل أو نوع الغرض المراد نقله؟*',
                    labelStyle: TextStyle(color: Colors.grey),
                    hintText: 'مثال: أوراق رسمية، صندوق هدايا، أدوية، طرد...',
                    hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF1E1E1E),
                    prefixIcon: Icon(Icons.inventory_2_outlined, color: Colors.amber),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty ? 'الرجاء كتابة وصف الغرض أو الشحنة' : null,
                ),
                const SizedBox(height: 14),

                // 4️⃣ ملاحظات إضافية
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات إضافية للمندوب (اختياري)',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF1E1E1E),
                    prefixIcon: Icon(Icons.note_alt_outlined, color: Colors.amber),
                  ),
                ),
                const SizedBox(height: 24),

                // زر الإرسال
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
