import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/constants.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({Key? key}) : super(key: key);

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  // 👈 متغيرات نظام الدفع الجديد والمحافظ الإلكترونية
  String _selectedPaymentMethod = 'cash';
  final TextEditingController _accountNumberController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // تعبئة البيانات تلقائياً إذا كان العميل مسجلاً مسبقاً لتسهيل العملية عليه
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      if (appState.userProfile != null) {
        _nameController.text = appState.userProfile?['name'] ?? '';
        _phoneController.text = appState.userProfile?['phone'] ?? '';
        _addressController.text = appState.userProfile?['address'] ?? '';
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _accountNumberController.dispose();
    super.dispose();
  }

  void _showCheckoutDialog(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder( // استخدام StatefulBuilder لتحديث حالة حقل رقم الحساب واختيار الدفع داخل النافذة المنبثقة
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('بيانات التوصيل وطريقة الدفع 💳', style: TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'الاسم الكامل',
                      labelStyle: TextStyle(color: Colors.grey),
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Color(0xFF121212),
                    ),
                    validator: (v) => v == null || v.isEmpty ? 'يرجى إدخال الاسم' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      labelStyle: TextStyle(color: Colors.grey),
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Color(0xFF121212),
                    ),
                    validator: (v) => v == null || v.length < 9 ? 'يرجى إدخال رقم صحيح' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'العنوان التفصيلي (تعز)',
                      labelStyle: TextStyle(color: Colors.grey),
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Color(0xFF121212),
                    ),
                    validator: (v) => v == null || v.isEmpty ? 'يرجى إدخال العنوان' : null,
                  ),
                  const SizedBox(height: 16),
                  
                  // 👈 قسم اختيار طريقة الدفع الجديدة (نقدي أو محافظ إلكترونية)
                  const Text('اختر طريقة الدفع:', style: TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedPaymentMethod,
                    dropdownColor: const Color(0xFF1E1E1E),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Color(0xFF121212),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('💵 الدفع نقداً عند الاستلام فقط')),
                    ],
                    onChanged: (val) {
                      setDialogState(() {
                        _selectedPaymentMethod = val!;
                      });
                    },
                  ),

                  // 👈 إذا اختار العميل محفظة إلكترونية، يظهر حقل إدخال رقم الحساب المحول منه
                  if (false && _selectedPaymentMethod != 'cash') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _accountNumberController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'رقم الحساب المحول منه (${_selectedPaymentMethod})',
                        labelStyle: const TextStyle(color: Colors.amberAccent),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Color(0xFF121212),
                      ),
                      validator: (v) => _selectedPaymentMethod != 'cash' && (v == null || v.isEmpty) ? 'يرجى إدخال رقم الحساب' : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (_formKey.currentState!.validate()) {
                  final itemsDescription = appState.cartItems
                      .map((item) => '${item.name} (${item.quantity})')
                      .join(', ');

                  try {
                    await appState.createOrder(
                      customerName: _nameController.text.trim(),
                      phone: _phoneController.text.trim(),
                      address: _addressController.text.trim(),
                      itemsDesc: itemsDescription.isNotEmpty ? itemsDescription : 'طلب عام من السلة',
                      productsTotal: appState.totalAmount,
                      paymentMethod: _selectedPaymentMethod,
                      paymentAccount: 'نقدي',
                    );
                    if (!context.mounted) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم استلام طلبك. رمز المتابعة: ${appState.lastOrderTrackingCode ?? '—'}')),
                    );
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إرسال الطلب: $e')));
                  }
                }
              },
              child: const Text('تأكيد وإرسال', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
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
          title: const Text('سلة المشتريات 🛒', style: TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold)),
        ),
        body: appState.cartItems.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.shopping_cart_outlined, size: 70, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('السلة فارغة حالياً', style: TextStyle(color: Colors.grey, fontSize: 16)),
                  ],
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: appState.cartItems.length,
                      itemBuilder: (ctx, i) {
                        final item = appState.cartItems[i];
                        return Card(
                          color: const Color(0xFF1E1E1E),
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: ListTile(
                            title: Text(item.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            subtitle: Text('${item.price} ر.ي', style: const TextStyle(color: AppConstants.gold)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                                  onPressed: () => appState.updateQuantity(item.id, -1),
                                ),
                                Text('${item.quantity}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent),
                                  onPressed: () => appState.updateQuantity(item.id, 1),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('إجمالي القطع:', style: TextStyle(color: Colors.white70)),
                            Text('${appState.totalCartItemsCount} قطعة', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('الإجمالي المالي:', style: TextStyle(color: Colors.white70)),
                            Text('${appState.totalAmount} ر.ي', style: const TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: appState.isStoreOpen ? AppConstants.gold : Colors.grey[800],
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: appState.isStoreOpen
                                ? () => _showCheckoutDialog(context, appState)
                                : null,
                            child: Text(
                              appState.isStoreOpen ? 'إتمام الطلب 🚀' : 'المتجر مغلق حالياً',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
      ),
    );
  }
}
