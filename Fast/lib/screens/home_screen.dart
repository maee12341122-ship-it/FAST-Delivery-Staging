import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state.dart';
import '../models/cart_item_model.dart';
import '../models/product_model.dart';
import '../widgets/fast_app_logo.dart';
import '../widgets/empty_state_widget.dart';
import 'admin_screen.dart';
import 'auth/phone_auth_screen.dart';
import 'courier_screen.dart';
import 'chat_screen.dart';
import 'customer/edit_profile_screen.dart';
import 'customer/favorites_screen.dart';
import 'customer/addresses_screen.dart';
import 'customer/map_location_screen.dart';
import 'notifications_screen.dart';
import 'order_tracking_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  String selectedCategory = 'الكل';
  String? selectedRestaurantName;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  final TextEditingController _customItemNameController = TextEditingController();
  final TextEditingController _customItemPriceController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressDescriptionController = TextEditingController();
  final _paymentAccountController = TextEditingController();
  String _selectedPaymentMethod = 'cash';

  final FocusNode _searchFocus = FocusNode();
  final FocusNode _customItemNameFocus = FocusNode();
  final FocusNode _customItemPriceFocus = FocusNode();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _addressFocus = FocusNode();

  final Set<String> _shownPricingDialogs = {};

  late AnimationController _popupAnimController;
  late Animation<double> _popupScaleAnimation;
  int _previousUnreadCount = 0;
  bool _showPopupBadge = false;
  String _latestNotificationText = 'إشعار جديد!';

  final List<String> _quickTags = ['برجر', 'حليب', 'دجاج', 'بطاطس', 'أرز', 'عصير'];

  String formatLocationAddress(String? rawAddress) {
    if (rawAddress == null || rawAddress.isEmpty) return 'تعز - مركز المدينة 📍';
    if (rawAddress.contains('(') && rawAddress.contains(',')) {
      if (rawAddress.contains('13.57') || rawAddress.contains('44.00')) {
        return 'منطقة دي لوكس، تعز 📍';
      } else if (rawAddress.contains('13.58')) {
        return 'شارع التحرير، تعز 📍';
      } else {
        return 'منطقة معتمدة، تعز 📍';
      }
    }
    return rawAddress;
  }

  void _handleNotificationTap(BuildContext context, Map<String, dynamic> notification) {
    final String? orderId = notification['order_id']?.toString() ??
        notification['related_id']?.toString() ??
        notification['additionalData']?['order_id']?.toString() ??
        _extractOrderIdFromText((notification['title'] ?? '') + ' ' + (notification['message'] ?? ''));

    if (orderId != null && orderId.isNotEmpty) {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => OrderTrackingScreen(orderIdParam: orderId),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const NotificationsScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  String? _extractOrderIdFromText(String text) {
    final RegExp regExp = RegExp(r'(?:طلب|#)\s*(\d+)');
    final match = regExp.firstMatch(text);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();

    _popupAnimController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _popupScaleAnimation = CurvedAnimation(
      parent: _popupAnimController,
      curve: Curves.elasticOut,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      appState.fetchStoreSettings();
      appState.fetchProductsFromSupabase();

      if (appState.userProfile != null) {
        _nameController.text = appState.userProfile?['name'] ?? '';
        _phoneController.text = appState.userProfile?['phone'] ?? '';
        _addressDescriptionController.text = appState.userProfile?['address'] ?? '';
      }
      _previousUnreadCount = appState.unreadNotificationsCount;

      _checkAndShowPrivacyPolicyDialog(context, appState);
    });
  }

  @override
  void dispose() {
    _popupAnimController.dispose();
    _searchController.dispose();
    _customItemNameController.dispose();
    _customItemPriceController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressDescriptionController.dispose();
    _paymentAccountController.dispose();
    _searchFocus.dispose();
    _customItemNameFocus.dispose();
    _customItemPriceFocus.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  void _checkAndShowPrivacyPolicyDialog(BuildContext context, AppState appState) {
    bool hasAcceptedPrivacy = appState.hasAcceptedPrivacyPolicy ?? false;

    if (!hasAcceptedPrivacy) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: appState.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.amber.withOpacity(0.5), width: 1.5),
            ),
            title: const Row(
              children: [
                Icon(Icons.shield_outlined, color: Colors.amber, size: 26),
                SizedBox(width: 8),
                Text(
                  'سياسة الخصوصية وشروط الاستخدام 🛡️',
                  style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'مرحباً بك في تطبيق FAST – تعز! نحن نحرص على حماية بياناتك وتقديم أسرع خدمة توصيل.',
                      style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    _buildPrivacyPoint('1️⃣ جمع واستخدام البيانات:', 'نقوم بجمع معلومات أساسية مثل (الاسم، رقم الهاتف، العنوان، وإحداثيات الموقع الجغرافي GPS) حصراً لتسهيل عملية توصيل الطلبات بدقة وسرعة عبر المناديب المعتمدين.'),
                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.withOpacity(0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🛑 تنبيهات هامة:',
                            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '• يرجى قراءة تفاصيل (الطلب والعنوان) بعناية والتأكيد عليهما؛ حيث نعتذر عن قبول أي تغيير بعد اعتماد الطلب، ويتحمل العميل مسؤولية ذلك. ✅',
                            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '• لو الحساب إيداع، الإيداع يتم بعد استلاستلام الطلب مباشرة مع ارسال البيان. 🪪',
                            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '• لا تغلق تلفونك حتى تتم عملية التوصيل. 🏍️',
                            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildPrivacyPoint('2️⃣ أمان وحماية البيانات:', 'جميع بيانات المعاملات والعملاء مشفرة وآمنة عبر قواعد بيانات سحابية متقدمة، ولا يتم مشاركتها مع أي طرف ثالث سوى فريق التوصيل والإدارة لإتمام الخدمة.'),
                    const SizedBox(height: 8),
                    _buildPrivacyPoint('3️⃣ الدعم والتواصل:', 'لأي استفسارات أو مساعدة حول سياسة الخصوصية أو الخدمة، يمكنك التواصل مع إدارة التطبيق في تعز، اليمن.'),
                    const SizedBox(height: 12),
                    const Text(
                      'باستخدامك للتطبيق، فإنك توافق على الشروط وسياسة الخصوصية الموضحة أعلاه.',
                      style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  SystemNavigator.pop();
                },
                child: const Text('رفض وخروج ❌', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  appState.setPrivacyPolicyAccepted(true);
                  Navigator.pop(context);
                },
                child: const Text('موافق واستمرار 🚀', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildPrivacyPoint(String title, String desc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 2),
        Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 12, height: 1.3)),
      ],
    );
  }

  Future<void> _launchWhatsApp() async {
    final Uri url = Uri.parse('https://wa.me/967776857316?text=مرحباً، أود الاستفسار عن خدمة التوصيل');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchPhoneCall() async {
    final Uri url = Uri.parse('tel:776857316');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _launchWhatsAppForAd() async {
    final Uri url = Uri.parse('https://wa.me/967776857316?text=مرحباً، أريد الاستفسار عن حجز مساحة إعلانية في تطبيق FAST.');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildDynamicPromoBanners() {
    return FutureBuilder<List<dynamic>>(
      future: Supabase.instance.client.from('promo_banners').select().eq('is_active', true).order('id', ascending: false),
      builder: (context, snapshot) {
        if (!snapshot.hasData || (snapshot.data ?? []).isEmpty) {
          return const SizedBox.shrink();
        }
        final banners = snapshot.data!;

        return SizedBox(
          height: 130,
          child: PageView.builder(
            controller: PageController(viewportFraction: 0.9),
            itemCount: banners.length,
            itemBuilder: (context, index) {
              final banner = banners[index];
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.amber[800]!, Colors.amber[600]!, Colors.orangeAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            banner['title'] ?? '',
                            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            banner['subtitle'] ?? '',
                            style: const TextStyle(color: Colors.black87, fontSize: 12),
                          ),
                          if (banner['code'] != null && banner['code'].toString().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'كود الخصم: ${banner['code']}',
                                style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(Icons.local_offer, color: Colors.black54, size: 45),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAdBannerWidget(Color cardBg, Color textColor) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.withOpacity(0.15), Colors.orangeAccent.withOpacity(0.05)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.campaign_rounded, color: Colors.amber, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'مساحتك الإعلانية هنا 📢',
                      style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('متاح', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'هل لديك مطعم أو متجر؟ أعلن معنا واوصل لآلاف العملاء في تعز يومياً!',
                  style: TextStyle(color: Colors.grey, fontSize: 11, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () {
              _launchWhatsAppForAd();
            },
            child: const Text('احجز إعلانك', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _handleProductTapOrAdd(BuildContext context, AppState appState, ProductModel product) async {
    await appState.fetchProductModifiers(product.id);

    if (appState.productModifiers.isEmpty) {
      appState.addToCart(CartItemModel(
        id: product.id,
        name: product.name,
        price: product.price,
        quantity: 1,
        restaurantId: product.restaurantName,
        imageUrl: product.imageUrl,
      ));
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تمت إضافة ${product.name} للسلة بنجاح ✅'), duration: const Duration(milliseconds: 800)),
      );
    } else {
      if (!context.mounted) return;
      _showProductModifiersDialog(context, appState, product);
    }
  }

  void _showProductModifiersDialog(BuildContext context, AppState appState, ProductModel product) {
    final Set<String> selectedModifiers = {};
    double additionalTotalPrice = 0.0;

    showDialog(
      context: context,
      builder: (context) => GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: StatefulBuilder(
          builder: (context, setDialogState) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: appState.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.amber.withOpacity(0.4)),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      style: TextStyle(
                        color: appState.isDarkMode ? Colors.white : Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (product.imageUrl.isNotEmpty)
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              product.imageUrl,
                              height: 100,
                              width: 100,
                              fit: BoxFit.cover,
                              errorBuilder: (c, e, s) => const Icon(Icons.fastfood, size: 50, color: Colors.amber),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          product.description.isNotEmpty ? product.description : 'اختر الإضافات المناسبة:',
                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const Divider(color: Colors.grey, height: 20),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: appState.productModifiers.length,
                          itemBuilder: (context, index) {
                            final mod = appState.productModifiers[index];
                            final modName = mod['option_name']?.toString() ?? '';
                            final double modPrice = double.tryParse(mod['additional_price']?.toString() ?? '0') ?? 0.0;
                            final bool isSelected = selectedModifiers.contains(modName);

                            return CheckboxListTile(
                              activeColor: Colors.amber,
                              checkColor: Colors.black,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                modName,
                                style: TextStyle(color: appState.isDarkMode ? Colors.white70 : Colors.black87, fontSize: 14),
                              ),
                              subtitle: modPrice > 0
                                  ? Text('+$modPrice ر.ي', style: const TextStyle(color: Colors.amber, fontSize: 12))
                                  : null,
                              value: isSelected,
                              onChanged: (bool? value) {
                                setDialogState(() {
                                  if (value == true) {
                                    selectedModifiers.add(modName);
                                    additionalTotalPrice += modPrice;
                                  } else {
                                    selectedModifiers.remove(modName);
                                    additionalTotalPrice -= modPrice;
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const Divider(color: Colors.grey, height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('السعر الإجمالي:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          Text(
                            '${product.price + additionalTotalPrice} ر.ي',
                            style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    String finalProductName = product.name;
                    if (selectedModifiers.isNotEmpty) {
                      finalProductName += ' (الإضافات: ${selectedModifiers.join(', ')})';
                    }

                    appState.addToCart(CartItemModel(
                      id: '${product.id}-${DateTime.now().millisecondsSinceEpoch}',
                      name: finalProductName,
                      price: product.price + additionalTotalPrice,
                      quantity: 1,
                      restaurantId: product.restaurantName,
                      imageUrl: product.imageUrl,
                    ));

                    Navigator.pop(context);
                    HapticFeedback.lightImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تمت إضافة ${product.name} مع الإضافات للسلة بنجاح ✅')),
                    );
                  },
                  child: const Text('أضف للسلة 🛒', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
                label: const Text('خدمة العملاء واتساب (776857316) 💬', style: TextStyle(fontWeight: FontWeight.bold)),
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
                label: const Text('اتصل بخدمة العملاء (776857316) 📞', style: TextStyle(fontWeight: FontWeight.bold)),
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
    final FocusNode priceFocus = FocusNode();

    showDialog(
      context: context,
      builder: (context) => GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Directionality(
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
                  TextField(
                    controller: priceController,
                    focusNode: priceFocus,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
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
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('تمت إضافة ${product.name} بسعر $enteredPrice ر.ي إلى السلة بنجاح ✅')),
                        );
                      }
                    },
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
                    HapticFeedback.lightImpact();
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
      ),
    );
  }

  void _showCheckoutDialog(BuildContext context, AppState appState, Color cardBg, Color textColor) {
    if (appState.userProfile != null) {
      _nameController.text = appState.userProfile?['name'] ?? '';
      _phoneController.text = appState.userProfile?['phone'] ?? '';
      _addressDescriptionController.text = appState.userProfile?['address'] ?? '';
    }

    final TextEditingController couponController = TextEditingController();
    final FocusNode couponFocus = FocusNode();

    showDialog(
      context: context,
      builder: (ctx) => GestureDetector(
        onTap: () => FocusScope.of(ctx).unfocus(),
        child: StatefulBuilder(
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
                      TextField(
                        controller: _nameController,
                        focusNode: _nameFocus,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(context).requestFocus(_phoneFocus),
                        style: TextStyle(color: textColor),
                        decoration: InputDecoration(
                          labelText: 'الاسم الكامل',
                          labelStyle: const TextStyle(color: Colors.grey),
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: appState.isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phoneController,
                        focusNode: _phoneFocus,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(context).requestFocus(_addressFocus),
                        style: TextStyle(color: textColor),
                        decoration: InputDecoration(
                          labelText: 'رقم الهاتف',
                          labelStyle: const TextStyle(color: Colors.grey),
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: appState.isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
                        ),
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
                              PageRouteBuilder(
                                pageBuilder: (context, animation, secondaryAnimation) => const MapLocationScreen(),
                                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                  return FadeTransition(opacity: animation, child: child);
                                },
                              ),
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

                      TextField(
                        controller: _addressDescriptionController,
                        focusNode: _addressFocus,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(context).requestFocus(couponFocus),
                        style: TextStyle(color: textColor),
                        decoration: InputDecoration(
                          labelText: 'العنوان التفصيلي (تعز)*',
                          labelStyle: const TextStyle(color: Colors.grey),
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: appState.isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
                        ),
                      ),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: couponController,
                              focusNode: couponFocus,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) async {
                                String msg = await appState.applyCouponCode(couponController.text, appState.totalAmount);
                                setDialogState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                              },
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                labelText: 'كود الخصم (اختياري)',
                                labelStyle: const TextStyle(color: Colors.grey),
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: appState.isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () async {
                              String msg = await appState.applyCouponCode(couponController.text, appState.totalAmount);
                              setDialogState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                            },
                            child: const Text('تطبيق', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      if (appState.activeCouponCode != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('تم تطبيق الكوبون: ${appState.activeCouponCode} (خصم: ${appState.couponDiscountAmount} ر.ي)', style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                            TextButton(
                              onPressed: () {
                                appState.removeCoupon();
                                setDialogState(() {});
                              },
                              child: const Text('إزالة', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                            ),
                          ],
                        ),
                      ],

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
                  child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
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

                      final double finalAmountToPay = appState.totalAmount - appState.couponDiscountAmount;

                      try {
                        await appState.createOrder(
                          customerName: _nameController.text.trim(),
                          phone: _phoneController.text.trim(),
                          address: _addressDescriptionController.text.trim(),
                          itemsDesc: itemsDescription.isNotEmpty ? itemsDescription : 'طلب عام من السلة',
                          productsTotal: finalAmountToPay > 0 ? finalAmountToPay : 0.0,
                          paymentMethod: _selectedPaymentMethod,
                          paymentAccount: 'نقدي',
                        );
                        if (!context.mounted) return;
                        Navigator.pop(ctx);
                        setState(() => _currentIndex = 2);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('تم استلاستلام الطلب. رمز المتابعة: ${appState.lastOrderTrackingCode ?? '—'}')),
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
      ),
    );
  }

  void _showRatingDialog(BuildContext context, AppState appState, String orderId, String courierName, Color cardBg, Color textColor) {
    int rating = 5;
    final commentController = TextEditingController();
    final FocusNode commentFocus = FocusNode();

    showDialog(
      context: context,
      builder: (context) => GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: StatefulBuilder(
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
                    focusNode: commentFocus,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) async {
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
      ),
    );
  }

  void _showRestaurantRatingDialog(BuildContext context, AppState appState, String orderId, String restaurantName, Color cardBg, Color textColor) {
    int rating = 5;
    final commentController = TextEditingController();
    final FocusNode commentFocus = FocusNode();

    showDialog(
      context: context,
      builder: (context) => GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: StatefulBuilder(
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
                    focusNode: commentFocus,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) async {
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

  Widget _buildNetworkStatusBar(AppState appState) {
    if (appState.isConnectedToInternet) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.red[800],
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text(
            'تنبيه: انقطع الاتصال بالإنترنت! يرجى التحقق من الشبكة ⚠️',
            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    if (appState.unreadNotificationsCount > _previousUnreadCount) {
      _latestNotificationText = appState.latestNotificationMessage ?? 'لديك إشعار جديد!';
      _popupAnimController.forward(from: 0.0);
      setState(() {
        _showPopupBadge = true;
      });
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) {
          _popupAnimController.reverse().then((_) {
            if (mounted) setState(() => _showPopupBadge = false);
          });
        }
      });
      _previousUnreadCount = appState.unreadNotificationsCount;
    } else if (appState.unreadNotificationsCount < _previousUnreadCount) {
      _previousUnreadCount = appState.unreadNotificationsCount;
    }

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

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
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
                  icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.amber, size: 24),
                  tooltip: 'البحث السريع',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _isSearching = !_isSearching;
                      if (!_isSearching) _searchController.clear();
                    });
                  },
                ),

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_showPopupBadge)
                      ScaleTransition(
                        scale: _popupScaleAnimation,
                        child: GestureDetector(
                          onTap: () {
                            _handleNotificationTap(context, {
                              'title': _latestNotificationText,
                              'message': _latestNotificationText,
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            margin: const EdgeInsets.only(left: 4),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.amber.withOpacity(0.5),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.bolt, size: 14, color: Colors.black),
                                const SizedBox(width: 4),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 150),
                                  child: Text(
                                    _latestNotificationText,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.notifications_rounded, color: Colors.amber, size: 26),
                          tooltip: 'الإشعارات والتنبيهات',
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            Navigator.push(
                              context,
                              PageRouteBuilder(
                                pageBuilder: (context, animation, secondaryAnimation) => const NotificationsScreen(),
                                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                  return FadeTransition(opacity: animation, child: child);
                                },
                              ),
                            );
                          },
                        ),
                        if (appState.unreadNotificationsCount > 0)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              child: Text(
                                '${appState.unreadNotificationsCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                IconButton(
                  icon: const Icon(Icons.two_wheeler, color: Colors.amber),
                  tooltip: 'لوحة المندوب',
                  onPressed: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) => const CourierScreen(),
                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                          return FadeTransition(opacity: animation, child: child);
                        },
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.admin_panel_settings, color: Colors.amber),
                  tooltip: 'لوحة المشرف',
                  onPressed: () {
                    if (appState.isAdminLoggedIn) {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (context, animation, secondaryAnimation) => const AdminScreen(),
                          transitionsBuilder: (context, animation, secondaryAnimation, child) {
                            return FadeTransition(opacity: animation, child: child);
                          },
                        ),
                      );
                    } else {
                      final passwordController = TextEditingController();
                      final usernameController = TextEditingController();
                      final FocusNode adminUserFocus = FocusNode();
                      final FocusNode adminPassFocus = FocusNode();

                      showDialog(
                        context: context,
                        builder: (context) => GestureDetector(
                          onTap: () => FocusScope.of(context).unfocus(),
                          child: AlertDialog(
                            backgroundColor: cardBg,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            title: Text('تسجيل دخول المشرف الآمن', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold)),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(
                                  controller: usernameController,
                                  focusNode: adminUserFocus,
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) => FocusScope.of(context).requestFocus(adminPassFocus),
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
                                  focusNode: adminPassFocus,
                                  obscureText: true,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) async {
                                    String username = usernameController.text.trim();
                                    String password = passwordController.text.trim();
                                    bool loginSuccess = await appState.loginAdminFromSupabase(username, password);
                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                    if (loginSuccess) {
                                      if (!context.mounted) return;
                                      Navigator.push(
                                        context,
                                        PageRouteBuilder(
                                          pageBuilder: (context, animation, secondaryAnimation) => const AdminScreen(),
                                          transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                            return FadeTransition(opacity: animation, child: child);
                                          },
                                        ),
                                      );
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
                                    Navigator.push(
                                      context,
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation, secondaryAnimation) => const AdminScreen(),
                                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                          return FadeTransition(opacity: animation, child: child);
                                        },
                                      ),
                                    );
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
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            body: Column(
              children: [
                _buildNetworkStatusBar(appState),
                Expanded(
                  child: Stack(
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
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutBack,
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                setState(() => _currentIndex = 1);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.amber[800]!, Colors.amber[600]!],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.amber.withOpacity(0.4),
                                      blurRadius: 15,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: const BoxDecoration(
                                        color: Colors.black,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.shopping_bag_outlined, color: Colors.amber, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${appState.totalCartItemsCount} منتجات بالسلة',
                                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        Text(
                                          '${appState.totalAmount} ر.ي',
                                          style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    const Text(
                                      'إتمام الطلب',
                                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.arrow_forward_ios, color: Colors.black, size: 14),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                HapticFeedback.selectionClick();
                if (index == 1 && appState.userProfile == null) {
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) => PhoneAuthScreen(
                        onLoginSuccess: () {
                          Navigator.pop(context);
                          setState(() => _currentIndex = 1);
                        },
                      ),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        return FadeTransition(opacity: animation, child: child);
                      },
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
                const BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'الرئيسية'),
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
                    focusNode: _customItemNameFocus,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).requestFocus(_customItemPriceFocus),
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
                    focusNode: _customItemPriceFocus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
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
                      }
                    },
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

    List uniqueRestaurants = [];
    List filteredProducts = [];

    if (selectedCategory == 'المطاعم') {
      if (selectedRestaurantName == null) {
        uniqueRestaurants = appState.products
            .where((p) => p.category.trim() == 'المطاعم')
            .map((p) => p.restaurantName)
            .toSet()
            .toList();
      } else {
        filteredProducts = appState.products.where((p) {
          final matchesCategory = p.category.trim() == 'المطاعم';
          final matchesRestaurant = p.restaurantName.trim() == selectedRestaurantName!.trim();
          final matchesSearch = searchQuery.isEmpty || p.name.toLowerCase().contains(searchQuery);
          return matchesCategory && matchesRestaurant && matchesSearch;
        }).toList();
      }
    } else {
      filteredProducts = appState.products.where((p) {
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
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
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

          _buildDynamicPromoBanners(),

          _buildAdBannerWidget(cardBg, textColor),

          if (_isSearching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      hintText: selectedCategory == 'المطاعم' && selectedRestaurantName != null
                          ? 'ابحث داخل وجبات $selectedRestaurantName...'
                          : 'ابحث عن طعام، بقالة، خضار، أو دواء...',
                      hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                      prefixIcon: const Icon(Icons.search, color: Colors.amber),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      ),
                      filled: true,
                      fillColor: cardBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))),
                    ),
                    onChanged: (val) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _quickTags.map((tag) {
                        return Padding(
                          padding: const EdgeInsets.only(left: 6.0),
                          child: ActionChip(
                            elevation: 0,
                            backgroundColor: cardBg,
                            side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                            label: Text('# $tag', style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              _searchController.text = tag;
                              setState(() {});
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

          _buildInteractiveCategoriesBar(appState, textColor, cardBg),
          const SizedBox(height: 10),

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
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.amber.withOpacity(0.2)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.restaurant_menu, color: Colors.black, size: 22),
                    ),
                    title: Text(restaurantName, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15)),
                    subtitle: const Text('اضغط لعرض الوجبات الخاصة بهذا المطعم فقط 📋', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    trailing: const Icon(Icons.arrow_forward_ios, color: Colors.amber, size: 16),
                    onTap: () {
                      HapticFeedback.selectionClick();
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
                childAspectRatio: 0.62,
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
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber.withOpacity(0.15)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
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
                                color: appState.isDarkMode ? const Color(0xFF252525) : Colors.grey[200],
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: product.imageUrl.isNotEmpty
                                    ? Image.network(
                                  product.imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_not_supported, color: Colors.grey),
                                )
                                    : const Icon(Icons.fastfood, color: Colors.amber, size: 30),
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
                                      HapticFeedback.lightImpact();
                                      state.toggleFavorite(product.id);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(isFav ? 'تمت الإزالة من المفضلة 💔' : 'تمت الإضافة للمفضلة ❤️'),
                                          duration: const Duration(seconds: 1),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isFav ? Icons.favorite : Icons.favorite_border,
                                        color: Colors.redAccent,
                                        size: 16,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          product.description.isNotEmpty ? product.description : (product.restaurantName.isNotEmpty ? product.restaurantName : 'مستودع عام'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.grey, fontSize: 10, height: 1.2),
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
                          ],
                        ),
                        const SizedBox(height: 6),
                        isVariable
                            ? SizedBox(
                          width: double.infinity,
                          height: 32,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: appState.isStoreOpen
                                ? () => _showEnterPriceDialog(context, appState, product)
                                : null,
                            child: const Text('أدخل السعر', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        )
                            : (qtyInCart == 0
                            ? SizedBox(
                          width: double.infinity,
                          height: 32,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: appState.isStoreOpen
                                ? () {
                              HapticFeedback.lightImpact();
                              _handleProductTapOrAdd(context, appState, product);
                            }
                                : null,
                            child: const Text('إضافة للسلة', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        )
                            : Container(
                          width: double.infinity,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              InkWell(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  appState.updateQuantity(product.id, -1);
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10),
                                  child: Icon(Icons.remove, size: 14, color: Colors.black),
                                ),
                              ),
                              Text(
                                '$qtyInCart',
                                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              InkWell(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  appState.updateQuantity(product.id, 1);
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10),
                                  child: Icon(Icons.add, size: 14, color: Colors.black),
                                ),
                              ),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 70),
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
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: isSelected ? Colors.amber : Colors.grey.withOpacity(0.3)),
              ),
              onSelected: (val) {
                HapticFeedback.selectionClick();
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
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) => PhoneAuthScreen(
                        onLoginSuccess: () => Navigator.pop(context),
                      ),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        return FadeTransition(opacity: animation, child: child);
                      },
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

    if (appState.cartItems.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.shopping_cart_outlined,
        title: 'سلة المشتريات فارغة!',
        subtitle: 'لم تقم بإضافة أي وجبات أو منتجات إلى السلة بعد. تصفح الأقسام واطلب ما تحب 🍔🛒',
        buttonText: 'تصفح الأقسام والوجبات 🚀',
        onButtonPressed: () {
          setState(() => _currentIndex = 0);
        },
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
            child: ListView.builder(
              itemCount: appState.cartItems.length,
              itemBuilder: (context, index) {
                final CartItemModel item = appState.cartItems[index];
                return Card(
                  color: cardBg,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.name, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text('السعر: ${item.price} ر.ي | الإجمالي: ${item.price * item.quantity} ر.ي', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.amber, size: 22),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                appState.updateQuantity(item.id, -1);
                              },
                            ),
                            Text('${item.quantity}', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: Colors.amber, size: 22),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                appState.updateQuantity(item.id, 1);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                              onPressed: () => appState.removeFromCart(item.id),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
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
      return EmptyStateWidget(
        icon: Icons.receipt_long_outlined,
        title: 'لا توجد طلبات سابقة!',
        subtitle: 'لم تقم بإنشاء أي طلبات معنا حتى الآن. ابدأ طلبك الأول الآن واستمتع بأسرع خدمة توصيل في تعز ⚡',
        buttonText: 'اطلب الآن 🛵',
        onButtonPressed: () {
          setState(() => _currentIndex = 0);
        },
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

        final formattedAddress = formatLocationAddress(order['address']);

        // 💰 المعادلة الموحدة والذكية لضمان صحة الأسعار وعدم ظهور الصفر مطلقاً
        final double productsPrice = double.tryParse(
            order['total_price']?.toString() ??
                order['items_price']?.toString() ??
                order['products_total']?.toString() ??
                order['products_price']?.toString() ?? '0'
        ) ?? 0.0;

        final double deliveryFee = double.tryParse(
            order['delivery_fee']?.toString() ?? '0'
        ) ?? 0.0;

        final double dbTotalAmount = double.tryParse(
            order['total_amount']?.toString() ??
                order['total']?.toString() ?? '0'
        ) ?? 0.0;

        final double finalProductsPrice = (productsPrice <= 0 && dbTotalAmount > deliveryFee)
            ? (dbTotalAmount - deliveryFee)
            : productsPrice;

        final double grandTotal = dbTotalAmount > 0
            ? dbTotalAmount
            : (finalProductsPrice + deliveryFee);

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
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => OrderTrackingScreen(orderIdParam: order['id'].toString()),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
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
                            style: IconButton.styleFrom(backgroundColor: Colors.amber.withOpacity(0.2)),
                            icon: const Icon(Icons.map, color: Colors.amber, size: 20),
                            tooltip: 'تتبع الطلب',
                            onPressed: () {
                              Navigator.push(
                                context,
                                PageRouteBuilder(
                                  pageBuilder: (context, animation, secondaryAnimation) => OrderTrackingScreen(orderIdParam: order['id'].toString()),
                                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                    return FadeTransition(opacity: animation, child: child);
                                  },
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            style: IconButton.styleFrom(backgroundColor: Colors.black12),
                            icon: const Icon(Icons.share, color: Colors.amber, size: 18),
                            tooltip: 'مشاركة الفاتورة',
                            onPressed: () {
                              final invoiceText = '⚡ فاتورة تطبيق FAST - تعز\n'
                                  'رقم الطلب: #${order['id']}\n'
                                  'المنتجات: ${order['items_desc'] ?? order['items_description']}\n'
                                  'العنوان: $formattedAddress\n'
                                  'سعر المنتجات: ${finalProductsPrice.toStringAsFixed(0)} ر.ي\n'
                                  'رسوم التوصيل: ${deliveryFee.toStringAsFixed(0)} ر.ي\n'
                                  'الإجمالي الكلي: ${grandTotal.toStringAsFixed(0)} ر.ي\n'
                                  'الحالة: $arabicStatus';
                              Share.share(invoiceText);
                            },
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            style: IconButton.styleFrom(backgroundColor: Colors.blueGrey.withOpacity(0.2)),
                            icon: const Icon(Icons.chat, color: Colors.amber, size: 18),
                            tooltip: 'مراسلة الإدارة ودعم الطلب',
                            onPressed: () {
                              Navigator.push(
                                context,
                                PageRouteBuilder(
                                  pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(
                                    orderId: order['id'].toString(),
                                    userRole: 'customer',
                                    targetChat: 'admin_customer',
                                  ),
                                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                    return FadeTransition(opacity: animation, child: child);
                                  },
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(color: Colors.grey, height: 20),

                  // 🚀 زر تتبع الطلب الواضح جداً بالنص العربي الصريح
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 1,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (context, animation, secondaryAnimation) => OrderTrackingScreen(orderIdParam: order['id'].toString()),
                          transitionsBuilder: (context, animation, secondaryAnimation, child) {
                            return FadeTransition(opacity: animation, child: child);
                          },
                        ),
                      );
                    },
                    icon: const Icon(Icons.map_rounded, color: Colors.black, size: 18),
                    label: const Text(
                      '🗺️ اضغط هنا لتتبع خط سير الطلب 🚀',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 🟢 زر الموافقة أو الإلغاء السريع يظهر حصراً عندما تكون الحالة pricingSentToCustomer
                  if (status == 'pricingSentToCustomer') ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('🔔 تم إرسال التسعيرة للطلب، يرجى الموافقة:', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () {
                                    appState.customerConfirmOrder(order['id']);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('تم تأكيد الطلب وإرساله للمندوب بنجاح! ✅')),
                                    );
                                  },
                                  child: const Text('موافقة ✅', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () {
                                    appState.customerCancelOrder(order['id']);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('تم رفض الطلب وإلغاؤه ❌')),
                                    );
                                  },
                                  child: const Text('إلغاء الطلب ❌', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  Text('الحالة: $arabicStatus', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  Text('العنوان: $formattedAddress', style: TextStyle(color: textColor, fontSize: 13)),
                  Text('المنتجات: ${order['items_desc'] ?? order['items_description']}', style: TextStyle(color: textColor, fontSize: 13)),
                  const SizedBox(height: 8),

                  // 📦 صندوق عرض الأسعار المفصول والمطابق تماماً للمندوب والمشرف
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🛒 سعر المنتجات: ${finalProductsPrice.toStringAsFixed(0)} ر.ي', style: TextStyle(color: textColor, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('🏍️ رسوم التوصيل: ${deliveryFee.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold)),
                        const Divider(color: Colors.white12, height: 8),
                        Text('💰 الإجمالي الكلي: ${grandTotal.toStringAsFixed(0)} ر.ي', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
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
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) => const PhoneAuthScreen(),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                    ),
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
                      Text('🏠 العنوان: ${formatLocationAddress(profile['address'])}', style: const TextStyle(color: Colors.amber, fontSize: 12)),
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
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => const EditProfileScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          );
        }),

        _buildProfileItem(Icons.location_on, 'إدارة عناويني المحفوظة 📍', cardBg, textColor, () {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => const AddressesScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          );
        }),

        _buildProfileItem(Icons.favorite, 'المنتجات المفضلة ❤️', cardBg, textColor, () {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => const FavoritesScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          );
        }),

        _buildProfileItem(Icons.headset_mic, 'خدمة العملاء وتواصل معنا 📞', cardBg, textColor, () {
          _showContactUsDialog(context, cardBg, textColor);
        }),

        _buildProfileItem(Icons.help_center_outlined, 'كيفية استخدام التطبيق 📖', cardBg, textColor, () {
          _showHowToUseDialog(context, cardBg, textColor);
        }),

        _buildProfileItem(Icons.privacy_tip_outlined, 'سياسة الخصوصية والاستخدام 🛡️', cardBg, textColor, () {
          appState.setPrivacyPolicyAccepted(false);
          _checkAndShowPrivacyPolicyDialog(context, appState);
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
                'الإصدار: 2.0.65',
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