import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_state.dart';
import '../models/cart_item_model.dart';
import '../models/product_model.dart';
import '../widgets/fast_app_logo.dart';
import 'admin_screen.dart';
import 'auth/phone_auth_screen.dart';
import 'courier_screen.dart';
import 'package:fast/screens/chat_screen.dart';
import 'customer/edit_profile_screen.dart';
import 'customer/favorites_screen.dart';
import 'customer/addresses_screen.dart';
import 'customer/map_location_screen.dart';

class OrderTrackingScreen extends StatelessWidget {
  final String orderId;

  const OrderTrackingScreen({Key? key, required this.orderId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    final order = appState.orders.firstWhere(
      (o) => o['id'].toString() == orderId.toString(),
      orElse: () => {},
    );

    if (order.isEmpty) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text('تتبع الطلب', style: TextStyle(color: Colors.amber)),
            iconTheme: const IconThemeData(color: Colors.amber),
          ),
          body: const Center(
            child: Text('عذراً، لم يتم العثور على تفاصيل هذا الطلب ❌', style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
    }

    final String rawStatus = order['status'] ?? 'waitingForPricing';
    final String arabicStatus = appState.getArabicStatus(rawStatus);
    final String assignedCourier = order['assigned_courier'] ?? 'قريباً يتم التعيين...';
    final double productsTotal = double.tryParse(order['products_total']?.toString() ?? '0') ?? 0.0;
    final double deliveryFee = double.tryParse(order['delivery_fee']?.toString() ?? '0') ?? 0.0;
    final double grandTotal = productsTotal + deliveryFee;

    int currentStep = 0;
    if (rawStatus == 'waitingForPricing') currentStep = 0;
    else if (rawStatus == 'pricingSentToCustomer' || rawStatus == 'waitingCourierApproval') currentStep = 1;
    else if (rawStatus == 'acceptedByCourier' || rawStatus == 'onTheWay') currentStep = 2;
    else if (rawStatus == 'arrivedToCustomer' || rawStatus == 'arrived') currentStep = 3;
    else if (rawStatus == 'delivered') currentStep = 4;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text('تتبع الطلب #$orderId 📦', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: Colors.amber),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.withOpacity(0.4), width: 1.5),
                ),
                child: Column(
                  children: [
                    const Text('حالة الطلب الحالية', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 6),
                    Text(
                      arabicStatus,
                      style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: (currentStep + 1) / 5,
                      backgroundColor: Colors.grey[800],
                      color: Colors.amber,
                      minHeight: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('المندوب المسؤول 🛵', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(assignedCourier, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    if (assignedCourier != 'قريباً يتم التعيين...' && assignedCourier != 'لم يتم التعيين')
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey[800],
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.chat, color: Colors.amber, size: 18),
                        label: const Text('مراسلة المندوب'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                orderId: orderId,
                                userRole: 'customer',
                                targetChat: 'admin_courier',
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('تفاصيل الفاتورة 🧾', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('المنتجات: ${order['items_description'] ?? order['items_desc'] ?? 'غير متوفرة'}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const Divider(color: Colors.white12, height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('سعر المنتجات:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        Text('$productsTotal ر.ي', style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('رسوم التوصيل:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        Text('$deliveryFee ر.ي', style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('الإجمالي الكلي:', style: TextStyle(color: Colors.amber, fontSize: 15, fontWeight: FontWeight.bold)),
                        Text('$grandTotal ر.ي', style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  String selectedCategory = 'الكل';
  String? selectedRestaurantName;
  final TextEditingController _searchController = TextEditingController();

  final TextEditingController _customItemNameController = TextEditingController();
  final TextEditingController _customItemPriceController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressDescriptionController = TextEditingController();
  final _paymentAccountController = TextEditingController();
  String _selectedPaymentMethod = 'cash';

  final Set<String> _shownPricingDialogs = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      appState.fetchStoreSettings();
      appState.fetchProductsFromSupabase();

      if (appState.userProfile != null) {
        _nameController.text = appState.userProfile?['name'] ?? '';
        _phoneController.text = appState.userProfile?['phone'] ?? '';
        _addressDescriptionController.text = appState.userProfile?['address'] ?? '';
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customItemNameController.dispose();
    _customItemPriceController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressDescriptionController.dispose();
    _paymentAccountController.dispose();
    super.dispose();
  }

  Future<void> _launchWhatsApp() async {
    final Uri url = Uri.parse('https://wa.me/967775145534?text=مرحباً، أود الاستفسار عن خدمة التوصيل');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchPhoneCall() async {
    final Uri url = Uri.parse('tel:775145534');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void _showContactUsDialog(BuildContext context, Color cardBg, Color textColor) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.headset_mic, color: Colors.amber),
              SizedBox(width: 10),
              Text('خدمة العملاء والتواصل 📞', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('تواصل معنا عبر خدمة العملاء لأي استفسار أو مساعدة:', style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _launchWhatsApp,
                icon: const Icon(Icons.chat, color: Colors.white),
                label: const Text('خدمة العملاء واتساب (775145534) 💬', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey[800],
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _launchPhoneCall,
                icon: const Icon(Icons.phone, color: Colors.amber),
                label: const Text('اتصل بخدمة العملاء (775145534) 📞', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
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

  void showExitConfirmationDialog(BuildContext context, Color cardBg, Color textColor) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.amber.withOpacity(0.3)),
          ),
          title: const Row(
            children: [
              Icon(Icons.exit_to_app, color: Colors.amber),
              SizedBox(width: 10),
              Text('تأكيد الخروج', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'هل أنت متأكد أنك تريد الخروج من تطبيق FAST؟',
            style: TextStyle(color: textColor, fontSize: 14),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              onPressed: () {
                Navigator.pop(context);
                SystemNavigator.pop();
              },
              child: const Text('نعم', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  void _showHowToUseDialog(BuildContext context, Color cardBg, Color textColor) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.amber.withOpacity(0.4)),
          ),
          title: const Row(
            children: [
              Icon(Icons.help_center, color: Colors.amber, size: 28),
              SizedBox(width: 10),
              Text('كيفية استخدام تطبيق FAST 🌟', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildInstructionStep(
                  '1️⃣ تصفح المنتجات أو اطلب خدمة خاصة',
                  'اختر قسمك المفضل (مطاعم، بقالات، خضار وفواكه...) أو اطلب خدمة خاصة من تبويب "طلبات أخرى".',
                  textColor,
                ),
                const Divider(color: Colors.white12, height: 16),
                _buildInstructionStep(
                  '2️⃣ تحديد الموقع وإرسال الطلب',
                  'أضف منتجاتك للسلة، حدد عنوانك بدقة أو عبر خريطة الـ GPS، ثم اضغط على "تأكيد وإرسال الطلب".',
                  textColor,
                ),
                const Divider(color: Colors.white12, height: 16),
                _buildInstructionStep(
                  '3️⃣ مراجعة التسعيرة من الإدارة',
                  'ستقوم الإدارة بتحديد رسوم التوصيل وإرسالها لك. ستظهر لك نافذة فورية للموافقة على السعر أو رفضه.',
                  textColor,
                ),
                const Divider(color: Colors.white12, height: 16),
                _buildInstructionStep(
                  '4️⃣ تعيين المندوب والتوصيل الفوري',
                  'بعد موافقتك، سيتم تعيين مندوب لتوصيل طلبك. يمكنك تتبعه خطوة بخطوة ومراسلته عبر الشات حتى يصل باب منزلك ✅',
                  textColor,
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('فهمت، شكراً 🚀', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionStep(String title, String desc, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        Text(desc, style: TextStyle(color: textColor.withOpacity(0.8), fontSize: 12, height: 1.4)),
      ],
    );
  }

  void _showEnterPriceDialog(BuildContext context, AppState appState, ProductModel product) {
    final TextEditingController priceController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: appState.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.amber.withOpacity(0.4)),
          ),
          title: Row(
            children: [
              const Icon(Icons.monetization_on, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تحديد السعر لـ ${product.name}',
                  style: TextStyle(
                    color: appState.isDarkMode ? Colors.white : Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'الرجاء إدخال السعر المطلوب (ر.ي) بشكل إلزامي للمتابعة:',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  style: TextStyle(color: appState.isDarkMode ? Colors.white : Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'السعر الإلزامي (ر.ي)*',
                    labelStyle: const TextStyle(color: Colors.amber),
                    hintText: 'اكتب السعر هنا...',
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                    filled: true,
                    fillColor: appState.isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'إدخال السعر إلزامي لإتمام الطلب!';
                    }
                    final double? parsedPrice = double.tryParse(value.trim());
                    if (parsedPrice == null || parsedPrice <= 0) {
                      return 'الرجاء إدخال سعر صحيح أكبر من الصفر!';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  final double enteredPrice = double.parse(priceController.text.trim());

                  appState.addToCart(CartItemModel(
                    id: '${product.id}-${DateTime.now().millisecondsSinceEpoch}',
                    name: '${product.name} (بسعر محدد)',
                    price: enteredPrice,
                    quantity: 1,
                    restaurantId: product.restaurantName.isNotEmpty ? product.restaurantName : 'قسم الخضار والفواكه',
                    imageUrl: product.imageUrl,
                  ));

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تمت إضافة ${product.name} بسعر $enteredPrice ر.ي إلى السلة بنجاح ✅')),
                  );
                }
              },
              child: const Text('إضافة للسلة', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showCheckoutDialog(BuildContext context, AppState appState, Color cardBg, Color textColor) {
    if (appState.userProfile != null) {
      _nameController.text = appState.userProfile?['name'] ?? '';
      _phoneController.text = appState.userProfile?['phone'] ?? '';
      _addressDescriptionController.text = appState.userProfile?['address'] ?? '';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('بيانات التوصيل وطريقة الدفع 💳', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        labelText: 'الاسم الكامل',
                        labelStyle: const TextStyle(color: Colors.grey),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: appState.isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'يرجى إدخال الاسم' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        labelText: 'رقم الهاتف',
                        labelStyle: const TextStyle(color: Colors.grey),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: appState.isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
                      ),
                      validator: (v) => v == null || v.length < 9 ? 'يرجى إدخال رقم صحيح' : null,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.amber,
                          side: const BorderSide(color: Colors.amber),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const MapLocationScreen()),
                          );
                          if (result != null && result is Map) {
                            setDialogState(() {
                              _addressDescriptionController.text = result['address'] ?? '';
                            });
                          }
                        },
                        icon: const Icon(Icons.map, color: Colors.amber),
                        label: const Text('تحديد الموقع عبر الخريطة والـ GPS 🗺️', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _addressDescriptionController,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        labelText: 'العنوان التفصيلي (تعز)*',
                        labelStyle: const TextStyle(color: Colors.grey),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: appState.isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'يرجى إدخال العنوان أو تحديده من الخريطة' : null,
                    ),
                    const SizedBox(height: 16),
                    const Text('اختر طريقة الدفع:', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedPaymentMethod,
                      dropdownColor: cardBg,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: appState.isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
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
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    final itemsDescription = appState.cartItems
                        .map((item) => '${item.name} (x${item.quantity})')
                        .join(', ');

                    try {
                      await appState.createOrder(
                        customerName: _nameController.text.trim(),
                        phone: _phoneController.text.trim(),
                        address: _addressDescriptionController.text.trim(),
                        itemsDesc: itemsDescription.isNotEmpty ? itemsDescription : 'طلب عام من السلة',
                        productsTotal: appState.totalAmount,
                        paymentMethod: _selectedPaymentMethod,
                        paymentAccount: 'نقدي',
                      );
                      if (!context.mounted) return;
                      Navigator.pop(ctx);
                      setState(() => _currentIndex = 2);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تم استلام الطلب. رمز المتابعة: ${appState.lastOrderTrackingCode ?? '—'}')),
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
      ),
    );
  }

  void _showRatingDialog(BuildContext context, AppState appState, String orderId, String courierName, Color cardBg, Color textColor) {
    int rating = 5;
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.star, color: Colors.amber),
                SizedBox(width: 10),
                Text('تقييم المندوب والطلب', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('كيف وجدت سرعة الخدمة وتعامُل المندوب معك؟', style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 30,
                      ),
                      onPressed: () {
                        setState(() {
                          rating = index + 1;
                        });
                      },
                    );
                  }),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: commentController,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    labelText: 'ملاحظاتك أو شكر للمندوب (اختياري)',
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: appState.isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  await appState.submitCourierRating(
                    orderId: orderId,
                    courierName: courierName.isNotEmpty ? courierName : 'المندوب',
                    rating: rating.toDouble(),
                    reviewText: commentController.text.trim(),
                  );
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('شكراً لك! تم إرسال تقييمك للمندوب بنجاح ⭐')),
                  );
                },
                child: const Text('إرسال التقييم', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRestaurantRatingDialog(BuildContext context, AppState appState, String orderId, String restaurantName, Color cardBg, Color textColor) {
    int rating = 5;
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.restaurant, color: Colors.amber),
                const SizedBox(width: 10),
                Expanded(child: Text('تقييم مطعم: $restaurantName 🍽️', style: const TextStyle(color: Colors.amber, fontSize: 15, fontWeight: FontWeight.bold))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('كيف وجدت جودة وطعم الطعام من المطعم؟', style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 30,
                      ),
                      onPressed: () {
                        setState(() {
                          rating = index + 1;
                        });
                      },
                    );
                  }),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: commentController,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    labelText: 'ملاحظاتك عن الطعام والمطعم (اختياري)',
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: appState.isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  await appState.submitRestaurantRating(
                    orderId: orderId,
                    rating: rating.toDouble(),
                    reviewText: commentController.text.trim(),
                  );
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('شكراً لك! تم إرسال تقييم المطعم بنجاح وإشعار المشرف ⭐')),
                  );
                },
                child: const Text('إرسال تقييم المطعم', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _checkAndShowPricingDialog(BuildContext context, AppState appState, Color cardBg, Color textColor) {
    if (appState.userProfile == null || appState.isAdminLoggedIn || appState.currentCourier != null) return;

    final customerOrders = appState.customerOrders;
    for (var order in customerOrders) {
      final orderId = order['id']?.toString() ?? '';
      final status = order['status']?.toString() ?? '';

      if (status == 'pricingSentToCustomer' && !_shownPricingDialogs.contains(orderId)) {
        _shownPricingDialogs.add(orderId);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: cardBg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Row(
                  children: [
                    Icon(Icons.notifications_active, color: Colors.amber),
                    SizedBox(width: 10),
                    Text('تسعيرة جديدة من المشرف', style: TextStyle(color: Colors.amber, fontSize: 16)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('طلب #$orderId', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('• رسوم التوصيل: (${order['delivery_fee']} ر.ي)', style: TextStyle(color: textColor, fontSize: 14)),
                    Text('• الإجمالي الكلي: ${order['total_price']} ر.ي', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 12),
                    Text('هل توافق على رسوم التوصيل وتأكيد الطلب ليرسل للمندوب؟', style: TextStyle(color: textColor, fontSize: 13)),
                  ],
                ),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      appState.customerConfirmOrder(order['id']);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم تأكيد الطلب وإرساله للمندوب بنجاح! ✅')),
                      );
                    },
                    child: const Text('موافقة وتأكيد الطلب', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                    onPressed: () {
                      appState.customerCancelOrder(order['id']);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم رفض الطلب وإلغاؤه ❌')),
                      );
                    },
                    child: const Text('رفض وإلغاء', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    final themeBg = appState.isDarkMode ? const Color(0xFF121212) : const Color(0xFFF0F2F5);
    final cardBg = appState.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = appState.isDarkMode ? Colors.white : Colors.black87;

    _checkAndShowPricingDialog(context, appState, cardBg, textColor);

    final List<Widget> pages = [
      _buildShopTab(appState, cardBg, textColor),
      _buildCartTab(appState, cardBg, textColor),
      _buildOrdersTab(appState, cardBg, textColor),
      _buildProfileTab(appState, cardBg, textColor),
    ];

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        showExitConfirmationDialog(context, cardBg, textColor);
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: themeBg,
          appBar: AppBar(
            backgroundColor: cardBg,
            elevation: 2,
            title: Row(
              children: [
                const SizedBox(
                  width: 35,
                  height: 35,
                  child: FittedBox(
                    child: FastAppLogo(),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'FAST – تعز',
                  style: TextStyle(color: Colors.amber[700], fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.two_wheeler, color: Colors.amber),
                tooltip: 'لوحة المندوب',
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const CourierScreen()));
                },
              ),
              IconButton(
                icon: const Icon(Icons.admin_panel_settings, color: Colors.amber),
                tooltip: 'لوحة المشرف',
                onPressed: () {
                  if (appState.isAdminLoggedIn) {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminScreen()));
                  } else {
                    final passwordController = TextEditingController();
                    final usernameController = TextEditingController();

                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: cardBg,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: Text('تسجيل دخول المشرف الآمن', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold)),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: usernameController,
                              style: TextStyle(color: textColor, fontSize: 14),
                              decoration: const InputDecoration(
                                labelText: 'اسم المستخدم',
                                labelStyle: TextStyle(color: Colors.grey),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: passwordController,
                              obscureText: true,
                              style: TextStyle(color: textColor, fontSize: 14),
                              decoration: const InputDecoration(
                                labelText: 'كلمة المرور',
                                labelStyle: TextStyle(color: Colors.grey),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () async {
                              String username = usernameController.text.trim();
                              String password = passwordController.text.trim();

                              bool loginSuccess = await appState.loginAdminFromSupabase(username, password);

                              if (!context.mounted) return;
                              Navigator.pop(context);

                              if (loginSuccess) {
                                if (!context.mounted) return;
                                Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminScreen()));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('مرحباً بك، تم تسجيل دخول المشرف بنجاح! 🚀')),
                                );
                              } else {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('اسم المستخدم أو كلمة المرور غير صحيحة! ❌')),
                                );
                              }
                            },
                            child: const Text('دخول', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          body: Stack(
            children: [
              IndexedStack(
                index: _currentIndex,
                children: pages,
              ),
              if (_currentIndex == 0 && appState.cartItems.isNotEmpty)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _currentIndex = 1);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.green[700],
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Row(
                            children: appState.cartItems.take(3).map((item) {
                              return Container(
                                width: 32,
                                height: 32,
                                margin: const EdgeInsets.only(left: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: ClipOval(
                                  child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                                      ? Image.network(
                                          item.imageUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.shopping_bag, size: 16, color: Colors.green),
                                        )
                                      : const Icon(Icons.shopping_bag, size: 16, color: Colors.green),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${appState.totalCartItemsCount} عناصر في السلة',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Text(
                                '${appState.totalAmount} ر.ي',
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                          const Spacer(),
                          const Text(
                            'عرض السلة 🛒',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              if (index == 1 && appState.userProfile == null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PhoneAuthScreen(
                      onLoginSuccess: () {
                        Navigator.pop(context);
                        setState(() => _currentIndex = 1);
                      },
                    ),
                  ),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('يجب تسجيل الدخول برقم الهاتف للوصول إلى السلة 🛒')),
                );
                return;
              }
              setState(() => _currentIndex = index);
            },
            backgroundColor: cardBg,
            selectedItemColor: Colors.amber,
            unselectedItemColor: Colors.grey,
            type: BottomNavigationBarType.fixed,
            items: [
              const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'الرئيسية'),
              BottomNavigationBarItem(
                icon: Stack(
                  children: [
                    const Icon(Icons.shopping_cart),
                    if (appState.totalCartItemsCount > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                            '${appState.totalCartItemsCount}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                label: 'السلة',
              ),
              const BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'طلباتي'),
              const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'حسابي'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShopTab(AppState appState, Color cardBg, Color textColor) {
    if (selectedCategory == 'طلبات أخرى') {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            _buildInteractiveCategoriesBar(appState, textColor, cardBg),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.withOpacity(0.4), width: 1),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.edit_note, color: Colors.amber, size: 24),
                      SizedBox(width: 8),
                      Text('طلب خاص أو خدمة أخرى', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('(مثل: غاز، قات، طلبات خاصة من السوق...)', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _customItemNameController,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      labelText: 'اكتب تفاصيل أو اسم الطلب',
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: appState.isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _customItemPriceController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      labelText: 'السعر التقديري (ر.ي)',
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: appState.isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appState.isStoreOpen ? Colors.amber : Colors.grey,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: appState.isStoreOpen
                        ? () {
                      if (_customItemNameController.text.isNotEmpty && _customItemPriceController.text.isNotEmpty) {
                        final price = double.tryParse(_customItemPriceController.text) ?? 1000.0;
                        appState.addCustomOrderToCart(
                          customName: _customItemNameController.text,
                          estimatedPrice: price,
                        );
                        _customItemNameController.clear();
                        _customItemPriceController.clear();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تمت إضافة الطلب الخاص إلى السلة بنجاح! 🚀')),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('الرجاء إدخال اسم الطلب والسعر التقديري')),
                        );
                      }
                    }
                        : () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('عذراً، التطبيق مغلق حالياً. لا يمكن إضافة طلبات 🛑')),
                      );
                    },
                    child: Text(
                      appState.isStoreOpen ? 'إضافة الطلب الخاص للسلة وتجميعه 🛒' : 'التطبيق مغلق حالياً 🛑',
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final searchQuery = _searchController.text.trim().toLowerCase();

    List<String> uniqueRestaurants = [];
    List<ProductModel> filteredProducts = [];

    // 🟢 التعديل الجذري هنا لفصل المطاعم عن البقالات والمستودع بدقة
    if (selectedCategory == 'المطاعم') {
      if (selectedRestaurantName == null) {
        // جلب المطاعم التي تصنيفها 'المطاعم' حصراً
        uniqueRestaurants = (appState.products as List)
            .map((e) => e as ProductModel)
            .where((p) => p.category.trim() == 'المطاعم')
            .map((p) => p.restaurantName)
            .toSet()
            .toList();
      } else {
        // جلب وجبات المطعم المختار فقط ضمن تصنيف المطاعم
        filteredProducts = (appState.products as List).map((e) => e as ProductModel).where((p) {
          final matchesCategory = p.category.trim() == 'المطاعم';
          final matchesRestaurant = p.restaurantName.trim() == selectedRestaurantName!.trim();
          final matchesSearch = searchQuery.isEmpty || p.name.toLowerCase().contains(searchQuery);
          return matchesCategory && matchesRestaurant && matchesSearch;
        }).toList();
      }
    } else {
      // باقي الأقسام (البقالات، الخضار، إلخ) أو 'الكل'
      filteredProducts = (appState.products as List).map((e) => e as ProductModel).where((p) {
        final matchesCategory = selectedCategory == 'الكل' || p.category.trim() == selectedCategory.trim();
        final matchesSearch = searchQuery.isEmpty ||
            p.name.toLowerCase().contains(searchQuery) ||
            p.restaurantName.toLowerCase().contains(searchQuery);
        return matchesCategory && matchesSearch;
      }).toList();
    }

    return RefreshIndicator(
      color: Colors.amber,
      backgroundColor: cardBg,
      onRefresh: () async {
        await appState.fetchStoreSettings();
        await appState.fetchProductsFromSupabase();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            color: cardBg,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  appState.isStoreOpen ? Icons.check_circle : Icons.access_time_filled,
                  color: appState.isStoreOpen ? Colors.greenAccent : Colors.amber,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  appState.isStoreOpen
                      ? '🟢  مفتوح الآن (الدوام من ${appState.startHour}:00 ص إلى ${appState.endHour}:00 م)'
                      : '🔴 التطبيق مغلق حالياً (يبدأ الدوام الساعة ${appState.startHour}:00 صباحاً)',
                  style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: textColor),
              decoration: InputDecoration(
                hintText: selectedCategory == 'المطاعم' && selectedRestaurantName != null
                    ? 'ابحث داخل وجبات $selectedRestaurantName...'
                    : 'ابحث عن طعام، بقالة، خضار، أو دواء...',
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.amber),
                filled: true,
                fillColor: cardBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))),
              ),
              onChanged: (val) => setState(() {}),
            ),
          ),
          _buildInteractiveCategoriesBar(appState, textColor, cardBg),
          const SizedBox(height: 15),

          if (selectedCategory == 'المطاعم' && selectedRestaurantName == null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
              child: Text('اختر مطعماً لعرض وجباته وقائمته الخاصة 🍽️', style: TextStyle(color: Colors.amber[800], fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            uniqueRestaurants.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(40.0),
                    child: Center(child: Text('لا توجد مطاعم متاحة حالياً 🍽️', style: TextStyle(color: Colors.grey))),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: uniqueRestaurants.length,
                    itemBuilder: (context, index) {
                      final restaurantName = uniqueRestaurants[index];
                      return Card(
                        color: cardBg,
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.amber,
                            child: Icon(Icons.restaurant, color: Colors.black),
                          ),
                          title: Text(restaurantName, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                          subtitle: const Text('اضغط لعرض الوجبات الخاصة بهذا المطعم فقط 📋', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          trailing: const Icon(Icons.arrow_forward_ios, color: Colors.amber, size: 16),
                          onTap: () {
                            setState(() {
                              selectedRestaurantName = restaurantName;
                            });
                          },
                        ),
                      );
                    },
                  ),
          ] else ...[
            if (selectedCategory == 'المطاعم' && selectedRestaurantName != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('وجبات مطعم: $selectedRestaurantName 🍔', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          selectedRestaurantName = null;
                        });
                      },
                      icon: const Icon(Icons.arrow_back, size: 16, color: Colors.amber),
                      label: const Text('تغيير المطعم', style: TextStyle(color: Colors.amber)),
                    ),
                  ],
                ),
              ),
            ],
            filteredProducts.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(50.0),
                    child: Center(child: Text('لا توجد منتجات مطابقة 🔍', style: TextStyle(color: Colors.grey, fontSize: 15))),
                  )
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.70,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: filteredProducts.length,
                    itemBuilder: (context, index) {
                      final ProductModel product = filteredProducts[index];
                      if (!product.available) return const SizedBox.shrink();

                      final bool isVariable = product.category == 'الخضار والفواكه';
                      int qtyInCart = appState.getProductQuantityInCart(product.id);

                      return Container(
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.withOpacity(0.2)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                children: [
                                  Container(
                                    height: 85,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: appState.isDarkMode ? const Color(0xFF2A2A2A) : Colors.grey[200],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: product.imageUrl.isNotEmpty
                                          ? Image.network(
                                              product.imageUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_not_supported, color: Colors.grey),
                                            )
                                          : const Icon(Icons.fastfood, color: Colors.amber, size: 35),
                                    ),
                                  ),
                                  Positioned(
                                    top: 6,
                                    left: 6,
                                    child: Consumer<AppState>(
                                      builder: (context, state, child) {
                                        final bool isFav = state.isProductFavorite(product.id);
                                        return InkWell(
                                          onTap: () {
                                            state.toggleFavorite(product.id);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(isFav ? 'تمت الإزالة من المفضلة 💔' : 'تمت الإضافة للمفضلة ❤️'),
                                                duration: const Duration(seconds: 1),
                                              ),
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Colors.black54,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              isFav ? Icons.favorite : Icons.favorite_border,
                                              color: Colors.redAccent,
                                              size: 18,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                product.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                isVariable ? 'حدد السعر' : (product.restaurantName.isNotEmpty ? product.restaurantName : 'مستودع عام'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.grey, fontSize: 11),
                              ),
                              const Spacer(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      isVariable ? 'إدخال يدوي' : '${product.price} ر.ي',
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  isVariable
                                      ? SizedBox(
                                          height: 30,
                                          child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.amber,
                                              padding: const EdgeInsets.symmetric(horizontal: 6),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                            onPressed: appState.isStoreOpen
                                                ? () => _showEnterPriceDialog(context, appState, product)
                                                : null,
                                            child: const Text('أدخل السعر', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                        )
                                      : (qtyInCart == 0
                                          ? SizedBox(
                                              height: 30,
                                              child: ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.amber,
                                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                ),
                                                onPressed: appState.isStoreOpen
                                                    ? () {
                                                        appState.addToCart(CartItemModel(
                                                          id: product.id,
                                                          name: product.name,
                                                          price: product.price,
                                                          quantity: 1,
                                                          restaurantId: product.restaurantName,
                                                          imageUrl: product.imageUrl,
                                                        ));
                                                      }
                                                    : null,
                                                child: const Text('ADD', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                                              ),
                                            )
                                          : Container(
                                              height: 30,
                                              decoration: BoxDecoration(
                                                color: Colors.amber,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  InkWell(
                                                    onTap: () => appState.updateQuantity(product.id, -1),
                                                    child: const Padding(
                                                      padding: EdgeInsets.symmetric(horizontal: 5),
                                                      child: Icon(Icons.remove, size: 14, color: Colors.black),
                                                    ),
                                                  ),
                                                  Text(
                                                    '$qtyInCart',
                                                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                                                  ),
                                                  InkWell(
                                                    onTap: () => appState.updateQuantity(product.id, 1),
                                                    child: const Padding(
                                                      padding: EdgeInsets.symmetric(horizontal: 5),
                                                      child: Icon(Icons.add, size: 14, color: Colors.black),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ],
      ),
    );
  }

  Widget _buildInteractiveCategoriesBar(AppState appState, Color textColor, Color cardBg) {
    final categories = ['الكل', 'المطاعم', 'البقالات', 'الخضار والفواكه', 'الصيدلية الآمنة', 'هدايا واكسسوارات', 'طلبات أخرى'];
    
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: categories.map((cat) {
          final isSelected = selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: ChoiceChip(
              label: Text(cat, style: TextStyle(color: isSelected ? Colors.black : textColor, fontWeight: FontWeight.bold, fontSize: 13)),
              selected: isSelected,
              selectedColor: Colors.amber,
              backgroundColor: cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: isSelected ? Colors.amber : Colors.grey.withOpacity(0.3)),
              ),
              onSelected: (val) {
                setState(() {
                  selectedCategory = cat;
                  selectedRestaurantName = null;
                  _searchController.clear();
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCartTab(AppState appState, Color cardBg, Color textColor) {
    if (appState.userProfile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 70, color: Colors.amber),
              const SizedBox(height: 15),
              Text('يجب تسجيل الدخول للوصول إلى السلة ومتابعة طلباتك', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  minimumSize: const Size(220, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PhoneAuthScreen(
                        onLoginSuccess: () => Navigator.pop(context),
                      ),
                    ),
                  );
                },
                child: const Text('تسجيل الدخول برقم الهاتف 📱', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('سلة المشتريات والطلبات المجمعة', style: TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Expanded(
            child: appState.cartItems.isEmpty
                ? const Center(child: Text('السلة فارغة حالياً 🛒', style: TextStyle(color: Colors.grey, fontSize: 15)))
                : ListView.builder(
              itemCount: appState.cartItems.length,
              itemBuilder: (context, index) {
                final CartItemModel item = appState.cartItems[index];
                return Card(
                  color: cardBg,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    title: Text(item.name, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                    subtitle: Text('السعر: ${item.price} ر.ي | الكمية: ${item.quantity} | الإجمالي: ${item.price * item.quantity} ر.ي', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => appState.removeFromCart(item.id),
                    ),
                  ),
                );
              },
            ),
          ),
          if (appState.cartItems.isNotEmpty) ...[
            const Divider(color: Colors.grey, height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('إجمالي السلة المجمعة:', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                Text('${appState.totalAmount} ر.ي', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 15),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                _showCheckoutDialog(context, appState, cardBg, textColor);
              },
              child: Text('الانتقال لتأكيد الطلب المجمع (${appState.totalAmount} ر.ي) 🚀', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ],
      ),
    );
  }

  String _getArabicStatus(String status) {
    switch (status) {
      case 'waitingForPricing':
        return '⏳ بانتظار تحديد السعر من الإدارة';
      case 'pricingSentToCustomer':
        return '🔔 تم إرسال التسعيرة - بانتظار موافقتك';
      case 'waitingCourierApproval':
        return '🛵 بانتظار قبول المندوب للطلب';
      case 'onTheWay':
        return '🟢 المندوب في الطريق إليك';
      case 'arrived':
        return '📍 وصل المندوب إلى موقعك';
      case 'delivered':
        return '✅ تم تسليم الطلب بنجاح';
      case 'cancelledByCustomer':
        return '❌ تم إلغاء الطلب';
      default:
        return status;
    }
  }

  Widget _buildOrdersTab(AppState appState, Color cardBg, Color textColor) {
    final customerOrders = appState.customerOrders;

    if (customerOrders.isEmpty) {
      return const Center(
        child: Text('لا توجد طلبات سابقة خاصة بك 📦', style: TextStyle(color: Colors.grey, fontSize: 15)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: customerOrders.length,
      itemBuilder: (context, index) {
        final order = customerOrders[index];
        final status = order['status'] ?? '';
        final arabicStatus = _getArabicStatus(status);
        final String assignedCourierName = order['assigned_courier'] ?? 'المندوب';
        final String itemsDesc = (order['items_description'] ?? order['items_desc'] ?? '').toString();

        bool isRestaurantOrder = itemsDesc.contains('وجبة') || itemsDesc.contains('مطعم') || order['is_restaurant'] == true;
        String detectedRestaurantName = order['restaurant_name'] ?? 'المطعم';

        int currentStep = 0;
        if (status == 'waitingForPricing') currentStep = 1;
        else if (status == 'pricingSentToCustomer') currentStep = 2;
        else if (status == 'waitingCourierApproval' || status == 'onTheWay') currentStep = 3;
        else if (status == 'arrived' || status == 'delivered') currentStep = 4;

        return Card(
          color: cardBg,
          margin: const EdgeInsets.symmetric(vertical: 8),
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.amber.withOpacity(0.3)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => OrderTrackingScreen(orderId: order['id'].toString()),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('طلب #${order['id']}', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                      Row(
                        children: [
                          IconButton(
                            style: IconButton.styleFrom(backgroundColor: Colors.black12),
                            icon: const Icon(Icons.share, color: Colors.amber, size: 18),
                            tooltip: 'مشاركة الفاتورة',
                            onPressed: () {
                              final invoiceText = '⚡ فاتورة تطبيق FAST - تعز\n'
                                  'رقم الطلب: #${order['id']}\n'
                                  'المنتجات: ${order['items_desc'] ?? order['items_description']}\n'
                                  'العنوان: ${order['address']}\n'
                                  'رسوم التوصيل: ${order['delivery_fee']} ر.ي\n'
                                  'الإجمالي: ${order['total_price'] ?? order['total_amount']} ر.ي\n'
                                  'الحالة: $arabicStatus';
                              Share.share(invoiceText);
                            },
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            style: IconButton.styleFrom(backgroundColor: Colors.blueGrey.withOpacity(0.2)),
                            icon: const Icon(Icons.chat, color: Colors.amber, size: 18),
                            tooltip: 'مراسلة الإدارة ودعم الطلب',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChatScreen(
                                    orderId: order['id'].toString(),
                                    userRole: 'customer',
                                    targetChat: 'admin_customer',
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildStepIndicator(1, 'الطلب', currentStep >= 1),
                      _buildStepLine(currentStep >= 2),
                      _buildStepIndicator(2, 'التسعير', currentStep >= 2),
                      _buildStepLine(currentStep >= 3),
                      _buildStepIndicator(3, 'المندوب', currentStep >= 3),
                      _buildStepLine(currentStep >= 4),
                      _buildStepIndicator(4, 'التوصيل', currentStep >= 4),
                    ],
                  ),
                  const Divider(color: Colors.grey, height: 20),
                  Text('الحالة: $arabicStatus', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  Text('العنوان: ${order['address']}', style: TextStyle(color: textColor, fontSize: 13)),
                  Text('المنتجات: ${order['items_desc'] ?? order['items_description']}', style: TextStyle(color: textColor, fontSize: 13)),
                  Text('سعر المنتجات: ${order['products_total']} ر.ي', style: TextStyle(color: textColor, fontSize: 13)),
                  Text('رسوم التوصيل: ${order['delivery_fee']} ر.ي', style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold)),
                  const Divider(color: Colors.grey, height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('الإجمالي الكلي:', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold)),
                      Text('${order['total_price'] ?? order['total_amount']} ر.ي', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  if (status == 'delivered' || status == 'arrived') ...[
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.withOpacity(0.15),
                        foregroundColor: Colors.amber,
                        minimumSize: const Size(double.infinity, 42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.amber.withOpacity(0.5)),
                        ),
                      ),
                      onPressed: () {
                        _showRatingDialog(context, appState, order['id'].toString(), assignedCourierName, cardBg, textColor);
                      },
                      icon: const Icon(Icons.star, size: 18),
                      label: const Text('قيم المندوب وخدمة التوصيل ⭐', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    if (isRestaurantOrder) ...[
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.withOpacity(0.15),
                          foregroundColor: Colors.amber,
                          minimumSize: const Size(double.infinity, 42),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.amber.withOpacity(0.5)),
                          ),
                        ),
                        onPressed: () {
                          _showRestaurantRatingDialog(context, appState, order['id'].toString(), detectedRestaurantName, cardBg, textColor);
                        },
                        icon: const Icon(Icons.restaurant_menu, size: 18),
                        label: Text('قيم مطعم ($detectedRestaurantName) وجودة الطعام 🍽️', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStepIndicator(int stepNumber, String title, bool isCompleted) {
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted ? Colors.amber : Colors.grey[400],
          ),
          child: Center(
            child: Text(
              '$stepNumber',
              style: TextStyle(color: isCompleted ? Colors.black : Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(title, style: TextStyle(color: isCompleted ? Colors.amber[800] : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildStepLine(bool isActive) {
    return Expanded(
      child: Container(
        height: 2,
        color: isActive ? Colors.amber : Colors.grey[300],
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      ),
    );
  }

  Widget _buildProfileTab(AppState appState, Color cardBg, Color textColor) {
    final profile = appState.userProfile;

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Center(
          child: Text('حسابي الشخصي', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 20),
        profile == null
            ? Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              const Icon(Icons.person, size: 60, color: Colors.amber),
              const SizedBox(height: 10),
              Text('أنت لست مسجل دخول!', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 5),
              const Text('سجل دخولك برقم هاتفك للاستمتاع بتجربة التوصيل الأسرع في تعز.', style: TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: 18),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PhoneAuthScreen()),
                  );
                },
                child: const Text('تسجيل الدخول برقم الهاتف 📱', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ],
          ),
        )
            : Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Colors.amber,
                radius: 24,
                child: Icon(Icons.person, color: Colors.black, size: 28),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile['name'] ?? 'عميل FAST', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('📞 ${profile['phone']} | 📍 تعز', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    if (profile['address'] != null && profile['address'].toString().isNotEmpty)
                      Text('🏠 العنوان: ${profile['address']}', style: const TextStyle(color: Colors.amber, fontSize: 12)),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => appState.logoutUser(),
                child: const Text('خروج', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        _buildProfileItem(Icons.edit, 'تعديل البيانات الشخصية', cardBg, textColor, () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const EditProfileScreen()),
          );
        }),

        _buildProfileItem(Icons.location_on, 'إدارة عناويني المحفوظة 📍', cardBg, textColor, () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddressesScreen()),
          );
        }),

        _buildProfileItem(Icons.favorite, 'المنتجات المفضلة ❤️', cardBg, textColor, () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const FavoritesScreen()),
          );
        }),

        _buildProfileItem(Icons.headset_mic, 'خدمة العملاء وتواصل معنا 📞', cardBg, textColor, () {
          _showContactUsDialog(context, cardBg, textColor);
        }),

        _buildProfileItem(Icons.help_center_outlined, 'كيفية استخدام التطبيق 📖', cardBg, textColor, () {
          _showHowToUseDialog(context, cardBg, textColor);
        }),

        _buildProfileItem(Icons.dark_mode, 'مظهر التطبيق (${appState.isDarkMode ? "الوضع الداكن" : "الوضع الفاتح"})', cardBg, textColor, () {
          appState.toggleTheme();
        }),
        _buildProfileItem(Icons.location_city, 'المدينة (تعز - اليمن - حصرياً)', cardBg, textColor, () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تطبيق FAST مخصص لخدمة مدينة تعز بكل سرعة 🌟')),
          );
        }),
        _buildProfileItem(Icons.share, 'مشاركة التطبيق مع الأصدقاء', cardBg, textColor, () {
          appState.shareApp();
        }),

        const SizedBox(height: 25),
        Center(
          child: Column(
            children: [
              Text(
                'الإصدار: 2.0.63',
                style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'تم التطوير بواسطة Eng. Maeen Almurish',
                style: TextStyle(color: Colors.amber[700], fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),
      ],
    );
  }

  Widget _buildProfileItem(IconData icon, String title, Color cardBg, Color textColor, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.amber),
        title: Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
