import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/app_state.dart';
import '../models/cart_item_model.dart';
import '../models/product_model.dart';
import '../widgets/fast_app_logo.dart';
import '../widgets/empty_state_widget.dart';
import 'order_time_helper.dart';
import 'auth/phone_auth_screen.dart';
import 'chat_screen.dart';
import 'customer/edit_profile_screen.dart';
import 'customer/favorites_screen.dart';
import 'customer/addresses_screen.dart';
import 'customer/map_location_screen.dart';
import 'notifications_screen.dart';
import 'order_tracking_screen.dart';
import 'customer/custom_delivery_screen.dart';
import 'admin_screen.dart';
import 'courier_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
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
  String _selectedPaymentMethod = 'cash';
  bool _isSubmittingCheckout = false;

  final Set<String> _shownPricingDialogs = {};

  late AnimationController _popupAnimController;
  late Animation<double> _popupScaleAnimation;
  int _previousUnreadCount = 0;
  bool _showPopupBadge = false;
  String _latestNotificationText = 'إشعار جديد!';

  Color _accent(AppState appState) =>
      appState.isDarkMode ? Colors.amber : const Color(0xFF0D47A1);

  String _formatPrice(double value) {
    if (value % 1 == 0) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }

  String _formatHourLabel(int hour) {
    final normalized = ((hour % 24) + 24) % 24;
    if (normalized == 0 || normalized == 24) return '12:00 ص';
    if (normalized == 12) return '12:00 م';
    if (normalized < 12) return '$normalized:00 ص';
    return '${normalized - 12}:00 م';
  }

  String formatLocationAddress(String? rawAddress) {
    if (rawAddress == null || rawAddress.isEmpty) return 'تعز - مركز المدينة';
    if (rawAddress.contains('(') && rawAddress.contains(',')) {
      if (rawAddress.contains('13.57') || rawAddress.contains('44.00')) {
        return 'منطقة دي لوكس، تعز';
      } else if (rawAddress.contains('13.58')) {
        return 'شارع التحرير، تعز';
      } else {
        return 'منطقة معتمدة، تعز';
      }
    }
    return rawAddress;
  }

  void _handleNotificationTap(
      BuildContext context, Map<String, dynamic> notification) {
    final String? orderId = notification['order_id']?.toString() ??
        notification['related_id']?.toString() ??
        notification['additionalData']?['order_id']?.toString() ??
        _extractOrderIdFromText(
            '${notification['title'] ?? ''} ${notification['message'] ?? ''}');

    if (orderId != null && orderId.isNotEmpty) {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              OrderTrackingScreen(orderIdParam: orderId),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const NotificationsScreen(),
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
      if (!mounted) return;
      final appState = Provider.of<AppState>(context, listen: false);
      unawaited(appState.fetchStoreSettings());
      unawaited(appState.fetchProductsFromSupabase());

      if (appState.userProfile != null) {
        _nameController.text = appState.userProfile?['name'] ?? '';
        _phoneController.text = appState.userProfile?['phone'] ?? '';
        _addressDescriptionController.text =
            appState.userProfile?['address'] ?? '';
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
    super.dispose();
  }

  void _checkAndShowPrivacyPolicyDialog(BuildContext context, AppState appState) {
    final bool hasAcceptedPrivacy = appState.hasAcceptedPrivacyPolicy;
    final accent = _accent(appState);

    if (!hasAcceptedPrivacy) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor:
                appState.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: accent.withOpacity(0.5), width: 1.5),
            ),
            title: Row(
              children: [
                Icon(Icons.shield_outlined, color: accent, size: 26),
                const SizedBox(width: 8),
                Text(
                  'شروط وسياسة تطبيق FAST',
                  style: TextStyle(
                      color: accent, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 380,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: appState.isDarkMode
                      ? const Color(0xFF121212)
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withOpacity(0.3)),
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    const Text(
                      'مرحباً بك في تطبيق FAST لتوصيل الطلبات\nلضمان تقديم أفضل خدمة سريعة وآمنة، يرجى قراءة التعليمات والسياسات التالية بعناية:',
                      style: TextStyle(
                          color: Colors.grey, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 8),
                    _buildPrivacyPoint(
                      '1. مراجعة وتأكيد تفاصيل الطلب:',
                      'يرجى قراءة تفاصيل (الطلب والعنوان) بعناية والتأكيد عليهما؛ حيث نعتذر عن قبول أي تغيير بعد اعتماد الطلب، ويتحمل العميل مسؤولية ذلك.',
                      accent,
                      appState.isDarkMode,
                    ),
                    const SizedBox(height: 12),
                    _buildPrivacyPoint(
                      '2. سياسة الحسابات والإيداع المالي:',
                      'لو الحساب إيداع، الإيداع يتم بعد استلام الطلب مباشرة مع إرسال البيان.',
                      accent,
                      appState.isDarkMode,
                    ),
                    const SizedBox(height: 12),
                    _buildPrivacyPoint(
                      '3. التواصل والاتصال بالمندوب:',
                      'لا تغلق تلفونك حتى تتم عملية التوصيل.',
                      accent,
                      appState.isDarkMode,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor:
                        appState.isDarkMode ? Colors.black : Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    appState.setPrivacyPolicyAccepted(true);
                    Navigator.pop(context);
                  },
                  child: const Text('أقر وأوافق، متابعة للتطبيق',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildPrivacyPoint(
      String title, String desc, Color accent, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: accent, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 3),
        Text(desc,
            style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 12,
                height: 1.4)),
      ],
    );
  }

  Future<void> _launchWhatsApp(
      {String message = 'مرحباً، أود الاستفسار عن خدمة التوصيل'}) async {
    final appState = Provider.of<AppState>(context, listen: false);
    await appState.openFastWhatsApp(message: message);
  }

  Future<void> _launchPhoneCall() async {
    final Uri url = Uri.parse('tel:776857316');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _launchWhatsAppForAd() async {
    await _launchWhatsApp(
        message: 'مرحباً، أريد الاستفسار عن حجز مساحة إعلانية في تطبيق FAST.');
  }

  Widget _buildStoreHoursStatusBar(
      AppState appState, Color cardBg, Color textColor) {
    final bool isOpen = appState.isStoreOpen;
    final String hoursText =
        '${_formatHourLabel(appState.startHour)} - ${_formatHourLabel(appState.endHour)}';
    final Color statusColor = isOpen ? Colors.green : Colors.redAccent;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.access_time_filled, color: statusColor, size: 18),
              const SizedBox(width: 8),
              Text(
                isOpen ? 'مفتوح الآن' : 'مغلق حالياً',
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          Text(
            'ساعات العمل: $hoursText',
            style: TextStyle(
              color: textColor.withOpacity(0.8),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicPromoBanners(AppState appState) {
    return FutureBuilder<List<dynamic>>(
      future: Supabase.instance.client
          .from('promo_banners')
          .select()
          .eq('is_active', true)
          .order('id', ascending: false),
      builder: (context, snapshot) {
        if (!snapshot.hasData || (snapshot.data ?? []).isEmpty) {
          return const SizedBox.shrink();
        }
        final banners = snapshot.data!;

        return SizedBox(
          height: 98,
          child: PageView.builder(
            controller: PageController(viewportFraction: 0.92),
            itemCount: banners.length,
            itemBuilder: (context, index) {
              final banner = banners[index];
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: appState.isDarkMode
                        ? [
                            Colors.amber.shade800,
                            Colors.amber.shade600,
                            Colors.orangeAccent
                          ]
                        : [
                            const Color(0xFF0D47A1),
                            const Color(0xFF1565C0),
                            const Color(0xFF1E88E5)
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
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
                            style: TextStyle(
                              color: appState.isDarkMode
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            banner['subtitle'] ?? '',
                            style: TextStyle(
                              color: appState.isDarkMode
                                  ? Colors.black87
                                  : Colors.white70,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.local_offer,
                        color:
                            appState.isDarkMode ? Colors.black87 : Colors.white,
                        size: 28),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAdBannerWidget(
      AppState appState, Color cardBg, Color textColor) {
    final accent = _accent(appState);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.35), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.campaign_rounded, color: accent, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مساحتك الإعلانية هنا',
                  style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'أعلن معنا واوصل لآلاف العملاء في تعز!',
                  style: TextStyle(
                      color: textColor.withOpacity(0.75), fontSize: 11),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: appState.isDarkMode ? Colors.black : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => _launchWhatsAppForAd(),
            child: const Text('احجز',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomDeliveryBanner(
      BuildContext context, AppState appState, String token) {
    final accent = _accent(appState);
    final isDark = appState.isDarkMode;
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                CustomDeliveryScreen(token: token),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF332700), const Color(0xFF1E1E1E)]
                : [const Color(0xFFE3F2FD), Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent, width: 1.2),
        ),
        child: Row(
          children: [
            Icon(Icons.delivery_dining, color: accent, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'وصل لي (توصيل خاص مرن)',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'من أين، إلى أين، وبأفضل الأسعار',
                    style: TextStyle(
                      color: isDark ? Colors.grey : Colors.black54,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: accent, size: 15),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesHorizontalList(
      AppState appState, Color textColor, Color cardBg) {
    final accent = _accent(appState);
    final categoriesList = [
      {
        'title': 'الكل',
        'image': 'https://images.unsplash.com/photo-1513104890138-7c749659a591',
        'category': 'الكل'
      },
      {
        'title': 'المطاعم',
        'image': 'https://images.unsplash.com/photo-1555396273-367ea4eb4db5',
        'category': 'المطاعم'
      },
      {
        'title': 'البقالات',
        'image': 'https://images.unsplash.com/photo-1542838132-92c53300491e',
        'category': 'البقالات'
      },
      {
        'title': 'الحلويات',
        'image': 'https://images.unsplash.com/photo-1551024709-8f23befc6f87',
        'category': 'حلويات ومعجنات'
      },
      {
        'title': 'خضروات',
        'image': 'https://images.unsplash.com/photo-1610348725531-843dff563e2c',
        'category': 'الخضار والفواكه'
      },
      {
        'title': 'الصيدلية',
        'image': 'https://images.unsplash.com/photo-1584308666744-24d5c474f2ae',
        'category': 'الصيدلية الآمنة'
      },
      {
        'title': 'هدايا',
        'image': 'https://images.unsplash.com/photo-1513519245088-0e12902e5a38',
        'category': 'هدايا واكسسوارات'
      },
      {
        'title': 'أخرى',
        'image': 'https://images.unsplash.com/photo-1526367460882-16d124185750',
        'category': 'طلبات أخرى'
      },
    ];

    return Container(
      height: 86,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        itemCount: categoriesList.length,
        itemBuilder: (context, index) {
          final catItem = categoriesList[index];
          final catName = catItem['category'] as String;
          final isSelected = selectedCategory == catName;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                selectedCategory = catName;
                selectedRestaurantName = null;
                _searchController.clear();
              });
            },
            child: Container(
              width: 74,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? accent.withOpacity(0.18) : cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? accent : Colors.grey.withOpacity(0.25),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: catItem['image'] as String,
                      width: 38,
                      height: 38,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    catItem['title'] as String,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? accent : textColor,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _handleProductTapOrAdd(
      BuildContext context, AppState appState, ProductModel product) async {
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تمت إضافة ${product.name} للسلة بنجاح'),
              duration: const Duration(milliseconds: 800)),
        );
      }
    } else {
      if (!context.mounted) return;
      _showProductModifiersDialog(context, appState, product);
    }
  }

  void _showProductModifiersDialog(
      BuildContext context, AppState appState, ProductModel product) {
    final Set<String> selectedModifiers = {};
    double additionalTotalPrice = 0.0;
    final accent = _accent(appState);

    showDialog(
      context: context,
      builder: (context) => GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: StatefulBuilder(
          builder: (context, setDialogState) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor:
                  appState.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: accent.withOpacity(0.4)),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      style: TextStyle(
                        color:
                            appState.isDarkMode ? Colors.white : Colors.black87,
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
                            child: CachedNetworkImage(
                              imageUrl: product.imageUrl,
                              height: 100,
                              width: 100,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Center(
                                  child: CircularProgressIndicator(
                                      color: accent)),
                              errorWidget: (context, url, error) =>
                                  Icon(Icons.fastfood, size: 50, color: accent),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          product.description.isNotEmpty
                              ? product.description
                              : 'اختر الإضافات المناسبة:',
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 13),
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
                            final double modPrice = double.tryParse(
                                    mod['additional_price']?.toString() ??
                                        '0') ??
                                0.0;
                            final bool isSelected =
                                selectedModifiers.contains(modName);

                            return CheckboxListTile(
                              activeColor: accent,
                              checkColor: appState.isDarkMode
                                  ? Colors.black
                                  : Colors.white,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                modName,
                                style: TextStyle(
                                    color: appState.isDarkMode
                                        ? Colors.white70
                                        : Colors.black87,
                                    fontSize: 14),
                              ),
                              subtitle: modPrice > 0
                                  ? Text('+${_formatPrice(modPrice)} ر.ي',
                                      style: TextStyle(
                                          color: accent, fontSize: 12))
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
                          const Text('السعر الإجمالي:',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 13)),
                          Text(
                            '${_formatPrice(product.price + additionalTotalPrice)} ر.ي',
                            style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
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
                  child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor:
                        appState.isDarkMode ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    String finalProductName = product.name;
                    if (selectedModifiers.isNotEmpty) {
                      finalProductName +=
                          ' (الإضافات: ${selectedModifiers.join(', ')})';
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
                      SnackBar(
                          content: Text(
                              'تمت إضافة ${product.name} مع الإضافات للسلة بنجاح')),
                    );
                  },
                  child: const Text('أضف للسلة',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showContactUsDialog(
      BuildContext context, AppState appState, Color cardBg, Color textColor) {
    final accent = _accent(appState);
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: cardBg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.headset_mic, color: accent),
              const SizedBox(width: 10),
              Text('خدمة العملاء والتواصل',
                  style: TextStyle(
                      color: accent, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'تواصل معنا عبر خدمة العملاء لأي استفسار أو مساعدة:',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _launchWhatsApp(
                    message:
                        'مرحباً، أستفسر عن خدمات التوصيل في تطبيق FAST'),
                icon: const Icon(Icons.chat, color: Colors.white),
                label: const Text('خدمة العملاء واتساب (776857316)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey[800],
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _launchPhoneCall,
                icon: Icon(Icons.phone, color: accent),
                label: const Text('اتصل بخدمة العملاء (776857316)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
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

  void showExitConfirmationDialog(
      BuildContext context, AppState appState, Color cardBg, Color textColor) {
    final accent = _accent(appState);
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: accent.withOpacity(0.3)),
          ),
          title: Row(
            children: [
              Icon(Icons.exit_to_app, color: accent),
              const SizedBox(width: 10),
              Text('تأكيد الخروج',
                  style: TextStyle(
                      color: accent, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'هل أنت متأكد أنك تريد الخروج من تطبيق FAST؟',
            style: TextStyle(color: textColor, fontSize: 14),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: accent),
              onPressed: () {
                Navigator.pop(context);
                SystemNavigator.pop();
              },
              child: Text('نعم',
                  style: TextStyle(
                      color: appState.isDarkMode ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  void _showHowToUseDialog(
      BuildContext context, AppState appState, Color cardBg, Color textColor) {
    final accent = _accent(appState);
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: accent.withOpacity(0.4)),
          ),
          title: Row(
            children: [
              Icon(Icons.help_center, color: accent, size: 28),
              const SizedBox(width: 10),
              Text('كيفية استخدام تطبيق FAST',
                  style: TextStyle(
                      color: accent, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildInstructionStep(
                  '1. تصفح المنتجات أو اطلب خدمة "وصل لي"',
                  'اختر قسمك المفضل أو استخدم خدمة "وصل لي" لتحديد مكان الاستلام والتوصيل وتفاصيل شحنتك الخاصة.',
                  textColor,
                  accent,
                ),
                const Divider(color: Colors.white12, height: 16),
                _buildInstructionStep(
                  '2. تحديد الموقع وإرسال الطلب',
                  'أضف منتجاتك للسلة أو أرسل تفاصيل التوصيل الخاص، حدد عنوانك بدقة، ثم اضغط على "تأكيد وإرسال".',
                  textColor,
                  accent,
                ),
                const Divider(color: Colors.white12, height: 16),
                _buildInstructionStep(
                  '3. مراجعة التسعيرة من الإدارة',
                  'ستقوم الإدارة بتحديد رسوم التوصيل وإرسالها لك. ستظهر لك نافذة فورية للموافقة على السعر أو رفضه.',
                  textColor,
                  accent,
                ),
                const Divider(color: Colors.white12, height: 16),
                _buildInstructionStep(
                  '4. تعيين المندوب والتوصيل الفوري',
                  'بعد موافقتك، سيتم تعيين مندوب لتوصيل طلبك. يمكنك تتبعه خطوة بخطوة ومراسلته حتى يصل باب منزلك',
                  textColor,
                  accent,
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(context),
              child: Text('فهمت، شكراً',
                  style: TextStyle(
                      color: appState.isDarkMode ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionStep(
      String title, String desc, Color textColor, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: accent, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        Text(desc,
            style: TextStyle(
                color: textColor.withOpacity(0.8), fontSize: 12, height: 1.4)),
      ],
    );
  }

  bool _isCustomOrSpecialOrder(
      Map<dynamic, dynamic> order, String itemsText) {
    final trimmedItems = itemsText.trim();
    if (trimmedItems.startsWith('طلب خاص') ||
        trimmedItems.contains('[خدمة وصل لي الخاصة]') ||
        trimmedItems.contains('خدمة وصل لي') ||
        trimmedItems.contains('مكان الاستلام:')) {
      return true;
    }

    final orderType = (order['order_type'] ?? order['type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (orderType == 'custom' ||
        orderType == 'special' ||
        orderType == 'custom_delivery' ||
        orderType == 'wasalli') {
      return true;
    }

    return false;
  }

  Map<String, dynamic> _resolveRestaurantOrderInfo(
      AppState appState, Map<dynamic, dynamic> order) {
    final String itemsText =
        (order['items_desc'] ?? order['items_description'] ?? '').toString();

    if (_isCustomOrSpecialOrder(order, itemsText)) {
      return {
        'isRestaurant': false,
        'restaurantName': '',
      };
    }

    String rawRestaurantName = (order['restaurant_name'] ??
            order['restaurantName'] ??
            order['store_name'] ??
            '')
        .toString()
        .trim();

    if (rawRestaurantName == 'طلب خاص' ||
        rawRestaurantName.startsWith('طلب خاص')) {
      return {
        'isRestaurant': false,
        'restaurantName': '',
      };
    }

    if (rawRestaurantName.isEmpty || rawRestaurantName == 'المطعم') {
      for (final item in appState.cartItems) {
        if (item.restaurantId.trim().isNotEmpty &&
            itemsText.contains(item.name)) {
          rawRestaurantName = item.restaurantId.trim();
          break;
        }
      }
    }

    if (rawRestaurantName.isEmpty || rawRestaurantName == 'المطعم') {
      for (final product in appState.products) {
        if (product.category.trim() == 'المطاعم' &&
            product.name.isNotEmpty &&
            itemsText.contains(product.name)) {
          rawRestaurantName = product.restaurantName.trim();
          break;
        }
      }
    }

    bool belongsToRestaurantsCategory = false;

    if (rawRestaurantName.isNotEmpty) {
      final matchedStore = appState.restaurantsList.firstWhere(
        (r) =>
            (r['name'] ?? '').toString().trim().toLowerCase() ==
            rawRestaurantName.toLowerCase(),
        orElse: () => <String, dynamic>{},
      );
      final storeCat = (matchedStore['category'] ?? '').toString().trim();
      if (storeCat == 'المطاعم') {
        belongsToRestaurantsCategory = true;
      }
    }

    if (!belongsToRestaurantsCategory && rawRestaurantName.isNotEmpty) {
      belongsToRestaurantsCategory = appState.products.any((p) =>
          p.category.trim() == 'المطاعم' &&
          p.restaurantName.trim().toLowerCase() ==
              rawRestaurantName.toLowerCase());
    }

    final bool isRestaurant =
        belongsToRestaurantsCategory || appState.isRestaurantOrder(order);

    final String resolvedName =
        rawRestaurantName.isNotEmpty ? rawRestaurantName : 'المطعم';

    return {
      'isRestaurant': isRestaurant,
      'restaurantName': resolvedName,
    };
  }

  Future<void> _showRatingDialog(
      BuildContext parentContext,
      AppState appState,
      String orderId,
      String courierName,
      Color cardBg,
      Color textColor) async {
    double rating = 5.0;
    bool isSubmitting = false;
    final TextEditingController commentController = TextEditingController();
    final accent = _accent(appState);

    await showDialog(
      context: parentContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: cardBg,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.star, color: accent),
                const SizedBox(width: 8),
                Text('تقييم المندوب ($courierName)',
                    style: TextStyle(
                        color: accent,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'كيف كانت تجربة التوصيل وسرعة الخدمة مع المندوب؟',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: accent,
                        size: 32,
                      ),
                      onPressed: isSubmitting
                          ? null
                          : () {
                              setDialogState(() {
                                rating = (index + 1).toDouble();
                              });
                            },
                    );
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: commentController,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    labelText: 'ملاحظات أو تعليق (اختياري)',
                    labelStyle: const TextStyle(color: Colors.grey),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: appState.isDarkMode
                        ? const Color(0xFF121212)
                        : Colors.grey[100],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: accent),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        setDialogState(() => isSubmitting = true);
                        try {
                          await appState.submitCourierRating(
                            orderId: orderId,
                            courierName: courierName,
                            rating: rating,
                            reviewText: commentController.text.trim(),
                          );
                          if (mounted) setState(() {});
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          if (parentContext.mounted) {
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'شكراً لك! تم إرسال تقييم المندوب بنجاح')),
                            );
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            setDialogState(() => isSubmitting = false);
                          }
                          if (parentContext.mounted) {
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              SnackBar(
                                content: Text(e
                                    .toString()
                                    .replaceAll('Exception: ', '')),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        }
                      },
                child: isSubmitting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: appState.isDarkMode
                              ? Colors.black
                              : Colors.white,
                        ),
                      )
                    : Text('إرسال التقييم',
                        style: TextStyle(
                            color: appState.isDarkMode
                                ? Colors.black
                                : Colors.white,
                            fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
    commentController.dispose();
  }

  Future<void> _showRestaurantRatingDialog(
      BuildContext parentContext,
      AppState appState,
      String orderId,
      String restaurantName,
      Color cardBg,
      Color textColor) async {
    double rating = 5.0;
    bool isSubmitting = false;
    final TextEditingController commentController = TextEditingController();
    final accent = _accent(appState);

    await showDialog(
      context: parentContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: cardBg,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.restaurant_menu, color: accent),
                const SizedBox(width: 8),
                Text('تقييم مطعم ($restaurantName)',
                    style: TextStyle(
                        color: accent,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('كيف كانت جودة الطعام والوجبات من هذا المطعم؟',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: accent,
                        size: 32,
                      ),
                      onPressed: isSubmitting
                          ? null
                          : () {
                              setDialogState(() {
                                rating = (index + 1).toDouble();
                              });
                            },
                    );
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: commentController,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    labelText: 'ملاحظات عن الطعام (اختياري)',
                    labelStyle: const TextStyle(color: Colors.grey),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: appState.isDarkMode
                        ? const Color(0xFF121212)
                        : Colors.grey[100],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: accent),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        setDialogState(() => isSubmitting = true);
                        try {
                          await appState.submitRestaurantRating(
                            orderId: orderId,
                            rating: rating,
                            reviewText: commentController.text.trim(),
                            restaurantName: restaurantName,
                          );
                          if (mounted) setState(() {});
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          if (parentContext.mounted) {
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'شكراً لك! تم إرسال تقييم المطعم بنجاح')),
                            );
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            setDialogState(() => isSubmitting = false);
                          }
                          if (parentContext.mounted) {
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              SnackBar(
                                content: Text(e
                                    .toString()
                                    .replaceAll('Exception: ', '')),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        }
                      },
                child: isSubmitting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: appState.isDarkMode
                              ? Colors.black
                              : Colors.white,
                        ),
                      )
                    : Text('إرسال التقييم',
                        style: TextStyle(
                            color: appState.isDarkMode
                                ? Colors.black
                                : Colors.white,
                            fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
    commentController.dispose();
  }

  void _showEnterPriceDialog(
      BuildContext context, AppState appState, ProductModel product) {
    final TextEditingController priceController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final accent = _accent(appState);

    showDialog(
      context: context,
      builder: (context) => GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor:
                appState.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: accent.withOpacity(0.4)),
            ),
            title: Row(
              children: [
                Icon(Icons.monetization_on, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تحديد السعر لـ ${product.name}',
                    style: TextStyle(
                      color:
                          appState.isDarkMode ? Colors.white : Colors.black87,
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
                    validator: (val) {
                      final parsed = double.tryParse(val?.trim() ?? '');
                      if (parsed == null || parsed <= 0) {
                        return 'أدخل سعراً صحيحاً أكبر من صفر';
                      }
                      return null;
                    },
                    style: TextStyle(
                        color:
                            appState.isDarkMode ? Colors.white : Colors.black87,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      labelText: 'السعر الإلزامي (ر.ي)*',
                      labelStyle: TextStyle(color: accent),
                      hintText: 'اكتب السعر هنا...',
                      hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                      filled: true,
                      fillColor: appState.isDarkMode
                          ? const Color(0xFF121212)
                          : Colors.grey[100],
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    final double enteredPrice =
                        double.parse(priceController.text.trim());

                    appState.addToCart(CartItemModel(
                      id: '${product.id}-${DateTime.now().millisecondsSinceEpoch}',
                      name: '${product.name} (بسعر محدد)',
                      price: enteredPrice,
                      quantity: 1,
                      restaurantId: product.restaurantName.isNotEmpty
                          ? product.restaurantName
                          : 'قسم الخضار والفواكه',
                      imageUrl: product.imageUrl,
                    ));

                    Navigator.pop(context);
                    HapticFeedback.lightImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'تمت إضافة ${product.name} بسعر ${_formatPrice(enteredPrice)} ر.ي إلى السلة بنجاح')),
                    );
                  }
                },
                child: Text('إضافة للسلة',
                    style: TextStyle(
                        color: appState.isDarkMode ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCheckoutDialog(
      BuildContext context, AppState appState, Color cardBg, Color textColor) {
    if (_isSubmittingCheckout) return;

    if (appState.userProfile != null) {
      _nameController.text = appState.userProfile?['name'] ?? '';
      _phoneController.text = appState.userProfile?['phone'] ?? '';
      _addressDescriptionController.text =
          appState.userProfile?['address'] ?? '';
    }

    final TextEditingController couponController = TextEditingController();
    final accent = _accent(appState);
    bool isSubmittingOrder = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => GestureDetector(
        onTap: () => FocusScope.of(ctx).unfocus(),
        child: StatefulBuilder(
          builder: (context, setDialogState) => PopScope(
            canPop: !isSubmittingOrder,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: cardBg,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: Text('بيانات التوصيل وطريقة الدفع',
                    style:
                        TextStyle(color: accent, fontWeight: FontWeight.bold)),
                content: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _nameController,
                          enabled: !isSubmittingOrder,
                          style: TextStyle(color: textColor),
                          validator: (val) =>
                              (val == null || val.trim().isEmpty)
                                  ? 'الرجاء إدخال الاسم الكامل'
                                  : null,
                          decoration: InputDecoration(
                            labelText: 'الاسم الكامل*',
                            labelStyle: const TextStyle(color: Colors.grey),
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: appState.isDarkMode
                                ? const Color(0xFF121212)
                                : Colors.grey[100],
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phoneController,
                          enabled: !isSubmittingOrder,
                          keyboardType: TextInputType.phone,
                          style: TextStyle(color: textColor),
                          validator: (val) =>
                              (val == null || val.trim().isEmpty)
                                  ? 'الرجاء إدخال رقم الهاتف'
                                  : null,
                          decoration: InputDecoration(
                            labelText: 'رقم الهاتف*',
                            labelStyle: const TextStyle(color: Colors.grey),
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: appState.isDarkMode
                                ? const Color(0xFF121212)
                                : Colors.grey[100],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: accent,
                              side: BorderSide(color: accent),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: isSubmittingOrder
                                ? null
                                : () async {
                                    final result = await Navigator.push(
                                      context,
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation,
                                                secondaryAnimation) =>
                                            const MapLocationScreen(),
                                        transitionsBuilder: (context, animation,
                                            secondaryAnimation, child) {
                                          return FadeTransition(
                                              opacity: animation, child: child);
                                        },
                                      ),
                                    );
                                    if (result != null && result is Map) {
                                      setDialogState(() {
                                        _addressDescriptionController.text =
                                            result['address'] ?? '';
                                      });
                                    }
                                  },
                            icon: Icon(Icons.map, color: accent),
                            label: const Text(
                                'تحديد الموقع عبر الخريطة والـ GPS',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _addressDescriptionController,
                          enabled: !isSubmittingOrder,
                          style: TextStyle(color: textColor),
                          validator: (val) =>
                              (val == null || val.trim().isEmpty)
                                  ? 'الرجاء إدخال العنوان التفصيلي'
                                  : null,
                          decoration: InputDecoration(
                            labelText: 'العنوان التفصيلي (تعز)*',
                            labelStyle: const TextStyle(color: Colors.grey),
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: appState.isDarkMode
                                ? const Color(0xFF121212)
                                : Colors.grey[100],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: couponController,
                                enabled: !isSubmittingOrder,
                                style: TextStyle(color: textColor),
                                decoration: InputDecoration(
                                  labelText: 'كود الخصم (اختياري)',
                                  labelStyle:
                                      const TextStyle(color: Colors.grey),
                                  border: const OutlineInputBorder(),
                                  filled: true,
                                  fillColor: appState.isDarkMode
                                      ? const Color(0xFF121212)
                                      : Colors.grey[100],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: appState.isDarkMode
                                    ? Colors.black
                                    : Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: isSubmittingOrder
                                  ? null
                                  : () async {
                                      final String msg =
                                          await appState.applyCouponCode(
                                              couponController.text,
                                              appState.totalAmount);
                                      setDialogState(() {});
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                                SnackBar(content: Text(msg)));
                                      }
                                    },
                              child: const Text('تطبيق',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        if (appState.activeCouponCode != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                  'تم تطبيق الكوبون: ${appState.activeCouponCode} (خصم: ${_formatPrice(appState.couponDiscountAmount)} ر.ي)',
                                  style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                              TextButton(
                                onPressed: isSubmittingOrder
                                    ? null
                                    : () {
                                        appState.removeCoupon();
                                        setDialogState(() {});
                                      },
                                child: const Text('إزالة',
                                    style: TextStyle(
                                        color: Colors.redAccent, fontSize: 12)),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: accent.withOpacity(0.4)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('حساب الكريمي (حاسب):',
                                      style: TextStyle(
                                          color: accent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                  Text('2655872',
                                      style: TextStyle(
                                          color: textColor,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                              IconButton(
                                icon: Icon(Icons.copy, color: accent, size: 20),
                                tooltip: 'نسخ رقم الحساب',
                                onPressed: () {
                                  Clipboard.setData(
                                      const ClipboardData(text: '2655872'));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'تم نسخ رقم حاسب الكريمي (2655872) بنجاح')),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('اختر طريقة الدفع:',
                            style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _selectedPaymentMethod,
                          dropdownColor: cardBg,
                          style: TextStyle(color: textColor),
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: appState.isDarkMode
                                ? const Color(0xFF121212)
                                : Colors.grey[100],
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'cash',
                                child: Text('الدفع نقداً عند الاستلام فقط')),
                          ],
                          onChanged: isSubmittingOrder
                              ? null
                              : (val) {
                                  if (val != null) {
                                    setDialogState(() {
                                      _selectedPaymentMethod = val;
                                    });
                                  }
                                },
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed:
                        isSubmittingOrder ? null : () => Navigator.pop(ctx),
                    child:
                        const Text('إغلاق', style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor:
                          appState.isDarkMode ? Colors.black : Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: (isSubmittingOrder || _isSubmittingCheckout)
                        ? null
                        : () async {
                            if (!(_formKey.currentState?.validate() ?? false)) {
                              return;
                            }
                            _isSubmittingCheckout = true;
                            setDialogState(() => isSubmittingOrder = true);

                            final itemsDescription = appState.cartItems
                                .map((item) =>
                                    '${item.name} (x${item.quantity})')
                                .join(', ');

                            final double finalAmountToPay =
                                appState.totalAmount -
                                    appState.couponDiscountAmount;

                            try {
                              await appState.createOrder(
                                customerName: _nameController.text.trim(),
                                phone: _phoneController.text.trim(),
                                address:
                                    _addressDescriptionController.text.trim(),
                                itemsDesc: itemsDescription.isNotEmpty
                                    ? itemsDescription
                                    : 'طلب عام من السلة',
                                productsTotal: finalAmountToPay > 0
                                    ? finalAmountToPay
                                    : 0.0,
                                paymentMethod: _selectedPaymentMethod,
                                paymentAccount: 'نقدي',
                              );
                              if (!context.mounted) return;
                              if (Navigator.canPop(ctx)) {
                                Navigator.pop(ctx);
                              }
                              setState(() => _currentIndex = 2);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'تم إرسال الطلب بنجاح. رمز المتابعة: ${appState.lastOrderTrackingCode ?? '—'}')),
                              );
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'تعذر إرسال الطلب: ${e.toString().replaceAll('Exception: ', '')}')));
                              }
                            } finally {
                              _isSubmittingCheckout = false;
                              if (context.mounted) {
                                setDialogState(() => isSubmittingOrder = false);
                              }
                            }
                          },
                    child: Text(
                      isSubmittingOrder ? 'جاري الإرسال...' : 'تأكيد وإرسال',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _checkAndShowPricingDialog(
      BuildContext context, AppState appState, Color cardBg, Color textColor) {
    if (appState.userProfile == null ||
        appState.isAdminLoggedIn ||
        appState.currentCourier != null) return;

    final accent = _accent(appState);
    final customerOrders = appState.customerOrders;
    for (var order in customerOrders) {
      final orderId = order['id']?.toString() ?? '';
      final status = order['status']?.toString() ?? '';

      if ((status == 'pricingSentToCustomer' ||
              status == 'pricing_sent_to_customer') &&
          !_shownPricingDialogs.contains(orderId)) {
        _shownPricingDialogs.add(orderId);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: cardBg,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    Icon(Icons.notifications_active, color: accent),
                    const SizedBox(width: 10),
                    Text('تسعيرة جديدة من المشرف',
                        style: TextStyle(color: accent, fontSize: 16)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('طلب #$orderId',
                        style: TextStyle(
                            color: accent, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                        '• رسوم التوصيل: (${order['delivery_fee'] ?? 0} ر.ي)',
                        style: TextStyle(color: textColor, fontSize: 14)),
                    Text('• الإجمالي الكلي: ${order['total_price'] ?? 0} ر.ي',
                        style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 12),
                    Text(
                        'هل توافق على رسوم التوصيل وتأكيد الطلب ليرسل للمندوب؟',
                        style: TextStyle(color: textColor, fontSize: 13)),
                  ],
                ),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      await appState.customerConfirmOrder(order['id']);
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'تم تأكيد الطلب وإرساله للمندوب بنجاح!')),
                      );
                    },
                    child: const Text('موافقة وتأكيد الطلب',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.redAccent),
                    onPressed: () async {
                      await appState.customerCancelOrder(order['id']);
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('تم رفض الطلب وإلغاؤه')),
                      );
                    },
                    child: const Text('رفض وإلغاء',
                        style: TextStyle(fontWeight: FontWeight.bold)),
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
            'تم انقطاع الإنترنت',
            style: TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderWarningNotice(AppState appState) {
    final isDark = appState.isDarkMode;
    final bg = isDark ? Colors.amber : const Color(0xFF0D47A1);
    final fg = isDark ? Colors.black : Colors.white;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: bg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning_amber_rounded, color: fg, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'الرجاء عدم إغلاق الإنترنت أو الخروج من التطبيق أثناء الطلب',
              style: TextStyle(
                color: fg,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final accent = _accent(appState);

    if (appState.unreadNotificationsCount > _previousUnreadCount) {
      _latestNotificationText =
          appState.latestNotificationMessage ?? 'لديك إشعار جديد!';
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

    final themeBg = appState.isDarkMode
        ? const Color(0xFF121212)
        : const Color(0xFFF7F8FA);
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

          if (_currentIndex == 0 && selectedRestaurantName != null) {
            setState(() {
              selectedRestaurantName = null;
            });
          } else if (_currentIndex == 0 && selectedCategory != 'الكل') {
            setState(() {
              selectedCategory = 'الكل';
              selectedRestaurantName = null;
            });
          } else if (_currentIndex != 0) {
            setState(() {
              _currentIndex = 0;
            });
          } else {
            showExitConfirmationDialog(context, appState, cardBg, textColor);
          }
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
                    width: 36,
                    height: 36,
                    child: FittedBox(
                      child: FastAppLogo(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'FAST – تعز',
                    style: TextStyle(
                        color: accent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.favorite,
                      color: Colors.redAccent, size: 24),
                  tooltip: 'المفضلة',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            const FavoritesScreen(),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                          return FadeTransition(opacity: animation, child: child);
                        },
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: Icon(_isSearching ? Icons.close : Icons.search,
                      color: accent, size: 24),
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            margin: const EdgeInsets.only(left: 4),
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withOpacity(0.5),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.bolt,
                                    size: 14,
                                    color: appState.isDarkMode
                                        ? Colors.black
                                        : Colors.white),
                                const SizedBox(width: 4),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 150),
                                  child: Text(
                                    _latestNotificationText,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: appState.isDarkMode
                                          ? Colors.black
                                          : Colors.white,
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
                          icon: Icon(Icons.notifications_rounded,
                              color: accent, size: 26),
                          tooltip: 'الإشعارات والتنبيهات',
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            Navigator.push(
                              context,
                              PageRouteBuilder(
                                pageBuilder:
                                    (context, animation, secondaryAnimation) =>
                                        const NotificationsScreen(),
                                transitionsBuilder: (context, animation,
                                    secondaryAnimation, child) {
                                  return FadeTransition(
                                      opacity: animation, child: child);
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
              ],
            ),
            body: Column(
              children: [
                _buildNetworkStatusBar(appState),
                _buildOrderWarningNotice(appState),
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: appState.isDarkMode
                                        ? [
                                            Colors.amber.shade800,
                                            Colors.amber.shade600
                                          ]
                                        : [
                                            const Color(0xFF0D47A1),
                                            const Color(0xFF1976D2)
                                          ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: accent.withOpacity(0.4),
                                      blurRadius: 15,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: appState.isDarkMode
                                            ? Colors.black
                                            : Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.shopping_bag_outlined,
                                          color: accent, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${appState.totalCartItemsCount} منتجات بالسلة',
                                          style: TextStyle(
                                            color: appState.isDarkMode
                                                ? Colors.black
                                                : Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          '${_formatPrice(appState.totalAmount)} ر.ي',
                                          style: TextStyle(
                                            color: appState.isDarkMode
                                                ? Colors.black87
                                                : Colors.white70,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    Text(
                                      'إتمام الطلب',
                                      style: TextStyle(
                                        color: appState.isDarkMode
                                            ? Colors.black
                                            : Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.arrow_forward_ios,
                                        color: appState.isDarkMode
                                            ? Colors.black
                                            : Colors.white,
                                        size: 14),
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
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          PhoneAuthScreen(
                        onLoginSuccess: () {
                          Navigator.pop(context);
                          setState(() => _currentIndex = 1);
                        },
                      ),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'يجب تسجيل الدخول برقم الهاتف للوصول إلى السلة')),
                  );
                  return;
                }
                setState(() => _currentIndex = index);
              },
              backgroundColor: cardBg,
              selectedItemColor: accent,
              unselectedItemColor: Colors.grey,
              type: BottomNavigationBarType.fixed,
              items: [
                const BottomNavigationBarItem(
                    icon: Icon(Icons.home_filled), label: 'الرئيسية'),
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
                            decoration: const BoxDecoration(
                                color: Colors.red, shape: BoxShape.circle),
                            constraints: const BoxConstraints(
                                minWidth: 16, minHeight: 16),
                            child: Text(
                              '${appState.totalCartItemsCount}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                  label: 'السلة',
                ),
                const BottomNavigationBarItem(
                    icon: Icon(Icons.receipt_long), label: 'طلباتي'),
                const BottomNavigationBarItem(
                    icon: Icon(Icons.person), label: 'حسابي'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShopTab(AppState appState, Color cardBg, Color textColor) {
    final accent = _accent(appState);

    if (selectedCategory == 'طلبات أخرى') {
      return Padding(
        padding: const EdgeInsets.all(12.0),
        child: ListView(
          children: [
            _buildStoreHoursStatusBar(appState, cardBg, textColor),
            _buildCategoriesHorizontalList(appState, textColor, cardBg),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('طلب خاص أو خدمة أخرى',
                      style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _customItemNameController,
                    style: TextStyle(color: textColor),
                    decoration: const InputDecoration(
                        labelText: 'تفاصيل الطلب', isDense: true),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customItemPriceController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textColor),
                    decoration: const InputDecoration(
                        labelText: 'السعر التقديري (ر.ي)', isDense: true),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        minimumSize: const Size(double.infinity, 42)),
                    onPressed: () {
                      if (_customItemNameController.text.isNotEmpty &&
                          _customItemPriceController.text.isNotEmpty) {
                        final price =
                            double.tryParse(_customItemPriceController.text) ??
                                1000.0;
                        appState.addCustomOrderToCart(
                            customName: _customItemNameController.text,
                            estimatedPrice: price);
                        _customItemNameController.clear();
                        _customItemPriceController.clear();
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('تمت إضافة الطلب الخاص للسلة')));
                      }
                    },
                    child: Text('إضافة للسلة',
                        style: TextStyle(
                            color: appState.isDarkMode
                                ? Colors.black
                                : Colors.white,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final searchQuery = _searchController.text.trim().toLowerCase();
    List filteredProducts = [];

    final bool isCategoryWithShops = selectedCategory == 'المطاعم' ||
        selectedCategory == 'حلويات ومعجنات' ||
        selectedCategory == 'الصيدلية الآمنة' ||
        selectedCategory == 'البقالات';

    if (isCategoryWithShops && selectedRestaurantName != null) {
      filteredProducts = appState.products.where((p) {
        final matchesCategory = selectedCategory == 'الكل' ||
            p.category.trim().toLowerCase() ==
                selectedCategory.trim().toLowerCase();
        final matchesRestaurant =
            p.restaurantName.trim() == selectedRestaurantName!.trim();
        final matchesSearch =
            searchQuery.isEmpty || p.name.toLowerCase().contains(searchQuery);
        return matchesCategory && matchesRestaurant && matchesSearch;
      }).toList();
    } else if (!isCategoryWithShops || selectedCategory == 'الكل') {
      filteredProducts = appState.products.where((p) {
        final matchesCategory = selectedCategory == 'الكل' ||
            p.category.trim().toLowerCase() ==
                selectedCategory.trim().toLowerCase();
        final matchesSearch = searchQuery.isEmpty ||
            p.name.toLowerCase().contains(searchQuery) ||
            p.restaurantName.toLowerCase().contains(searchQuery);
        return matchesCategory && matchesSearch;
      }).toList();
    }

    return RefreshIndicator(
      color: accent,
      onRefresh: () async {
        await appState.fetchStoreSettings();
        await appState.fetchProductsFromSupabase();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        children: [
          _buildStoreHoursStatusBar(appState, cardBg, textColor),
          _buildDynamicPromoBanners(appState),
          _buildCustomDeliveryBanner(
              context, appState, appState.userProfile?['id'] ?? 'guest'),
          _buildAdBannerWidget(appState, cardBg, textColor),
          if (_isSearching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  hintText: 'ابحث عن منتج أو مطعم...',
                  prefixIcon: Icon(Icons.search, color: accent, size: 20),
                  filled: true,
                  fillColor: cardBg,
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
                onChanged: (val) => setState(() {}),
              ),
            ),
          _buildCategoriesHorizontalList(appState, textColor, cardBg),
          if (isCategoryWithShops && selectedRestaurantName == null) ...[
            Builder(
              builder: (context) {
                final Set<String> storesInThisCategory = appState.products
                    .where((p) =>
                        p.category.trim().toLowerCase() ==
                        selectedCategory.trim().toLowerCase())
                    .map<String>((p) => p.restaurantName)
                    .toSet();

                List<dynamic> categoryStores = appState.restaurantsList.where((r) {
                  return storesInThisCategory
                      .contains(r['name']?.toString().trim());
                }).toList();

                if (categoryStores.isEmpty) {
                  categoryStores = storesInThisCategory
                      .map((name) =>
                          {'name': name, 'logo_url': '', 'rating': 4.9})
                      .toList();
                }

                if (categoryStores.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(18.0),
                    child: Center(
                        child: Text('لا توجد متاجر متاحة حالياً',
                            style:
                                TextStyle(color: Colors.grey, fontSize: 12))),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: Text('اختر متجراً',
                          style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                    ),
                    SizedBox(
                      height: 98,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        itemCount: categoryStores.length,
                        itemBuilder: (context, index) {
                          final store = categoryStores[index];
                          final storeName = store['name']?.toString() ?? 'متجر';
                          final logoUrl = store['logo_url']?.toString() ?? '';

                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => selectedRestaurantName = storeName);
                            },
                            child: Container(
                              width: 112,
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: accent.withOpacity(0.35)),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: accent.withOpacity(0.2),
                                    backgroundImage: logoUrl.isNotEmpty
                                        ? CachedNetworkImageProvider(logoUrl)
                                        : null,
                                    child: logoUrl.isEmpty
                                        ? Icon(Icons.store,
                                            color: accent, size: 20)
                                        : null,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    storeName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: textColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11.5),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ] else ...[
            if (isCategoryWithShops && selectedRestaurantName != null) ...[
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('منتجات: $selectedRestaurantName',
                        style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    TextButton(
                      onPressed: () =>
                          setState(() => selectedRestaurantName = null),
                      child: Text('تغيير المتجر',
                          style: TextStyle(color: accent, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
            filteredProducts.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(
                        child: Text('لا توجد منتجات مطابقة',
                            style:
                                TextStyle(color: Colors.grey, fontSize: 13))),
                  )
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: filteredProducts.length,
                    itemBuilder: (context, index) {
                      final ProductModel product = filteredProducts[index];
                      if (!product.available) return const SizedBox.shrink();

                      final bool isVariable =
                          product.category == 'الخضار والفواكه';
                      final bool isFav = appState.isProductFavorite(product.id);
                      final int qtyInCart =
                          appState.getProductQuantityInCart(product.id);

                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: accent.withOpacity(0.35)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: product.imageUrl.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: product.imageUrl,
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) =>
                                                  Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                              color: accent,
                                                              strokeWidth: 2)),
                                              errorWidget: (context, url,
                                                      error) =>
                                                  Container(
                                                color: accent.withOpacity(0.1),
                                                child: Icon(Icons.fastfood,
                                                    color: accent, size: 32),
                                              ),
                                            )
                                          : Container(
                                              width: double.infinity,
                                              color: accent.withOpacity(0.15),
                                              child: Icon(Icons.fastfood,
                                                  color: accent, size: 32),
                                            ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 6,
                                    left: 6,
                                    child: GestureDetector(
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        appState.toggleFavorite(product.id);
                                        ScaffoldMessenger.of(context)
                                            .clearSnackBars();
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(!isFav
                                                ? 'تمت إضافة ${product.name} إلى المفضلة'
                                                : 'تمت إزالة ${product.name} من المفضلة'),
                                            duration: const Duration(
                                                milliseconds: 800),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.55),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isFav
                                              ? Icons.favorite
                                              : Icons.favorite_border,
                                          color: isFav
                                              ? Colors.redAccent
                                              : Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              product.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              product.restaurantName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 11),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isVariable
                                  ? 'يدوي'
                                  : '${_formatPrice(product.price)} ر.ي',
                              style: TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            isVariable
                                ? SizedBox(
                                    width: double.infinity,
                                    height: 34,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: accent,
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                      ),
                                      onPressed: () => _showEnterPriceDialog(
                                          context, appState, product),
                                      child: Text('حدد السعر',
                                          style: TextStyle(
                                              color: appState.isDarkMode
                                                  ? Colors.black
                                                  : Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  )
                                : (qtyInCart == 0
                                    ? SizedBox(
                                        width: double.infinity,
                                        height: 34,
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: accent,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                          ),
                                          onPressed: () =>
                                              _handleProductTapOrAdd(
                                                  context, appState, product),
                                          child: Text('إضافة',
                                              style: TextStyle(
                                                  color: appState.isDarkMode
                                                      ? Colors.black
                                                      : Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold)),
                                        ),
                                      )
                                    : Container(
                                        height: 34,
                                        decoration: BoxDecoration(
                                            color: accent,
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceAround,
                                          children: [
                                            InkWell(
                                                onTap: () =>
                                                    appState.updateQuantity(
                                                        product.id, -1),
                                                child: Icon(Icons.remove,
                                                    size: 16,
                                                    color: appState.isDarkMode
                                                        ? Colors.black
                                                        : Colors.white)),
                                            Text('$qtyInCart',
                                                style: TextStyle(
                                                    color: appState.isDarkMode
                                                        ? Colors.black
                                                        : Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13)),
                                            InkWell(
                                                onTap: () =>
                                                    appState.updateQuantity(
                                                        product.id, 1),
                                                child: Icon(Icons.add,
                                                    size: 16,
                                                    color: appState.isDarkMode
                                                        ? Colors.black
                                                        : Colors.white)),
                                          ],
                                        ),
                                      )),
                          ],
                        ),
                      );
                    },
                  ),
          ],
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildCartTab(AppState appState, Color cardBg, Color textColor) {
    final accent = _accent(appState);

    if (appState.userProfile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 70, color: accent),
              const SizedBox(height: 15),
              Text(
                  'يجب تسجيل الدخول للوصول إلى السلة ومتابعة طلباتك',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  minimumSize: const Size(220, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          PhoneAuthScreen(
                        onLoginSuccess: () => Navigator.pop(context),
                      ),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                    ),
                  );
                },
                child: Text('تسجيل الدخول برقم الهاتف',
                    style: TextStyle(
                        color: appState.isDarkMode ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
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
        subtitle:
            'لم تقم بإضافة أي وجبات أو منتجات إلى السلة بعد. تصفح الأقسام واطلب ما تحب',
        buttonText: 'تصفح الأقسام والوجبات',
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
          Text('سلة المشتريات والطلبات المجمعة',
              style: TextStyle(
                  color: accent, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: appState.cartItems.length,
              itemBuilder: (context, index) {
                final CartItemModel item = appState.cartItems[index];
                return Card(
                  color: cardBg,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.name,
                                  style: TextStyle(
                                      color: textColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                              const SizedBox(height: 4),
                              Text(
                                  'السعر: ${_formatPrice(item.price)} ر.ي | الإجمالي: ${_formatPrice(item.price * item.quantity)} ر.ي',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.remove_circle_outline,
                                  color: accent, size: 22),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                appState.updateQuantity(item.id, -1);
                              },
                            ),
                            Text('${item.quantity}',
                                style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            IconButton(
                              icon: Icon(Icons.add_circle_outline,
                                  color: accent, size: 22),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                appState.updateQuantity(item.id, 1);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent, size: 22),
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
              Text('إجمالي السلة المجمعة:',
                  style:
                      TextStyle(color: textColor, fontWeight: FontWeight.bold)),
              Text('${_formatPrice(appState.totalAmount)} ر.ي',
                  style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ],
          ),
          const SizedBox(height: 15),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isSubmittingCheckout
                ? null
                : () {
                    _showCheckoutDialog(context, appState, cardBg, textColor);
                  },
            child: Text(
                'الانتقال لتأكيد الطلب المجمع (${_formatPrice(appState.totalAmount)} ر.ي)',
                style: TextStyle(
                    color: appState.isDarkMode ? Colors.black : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          ),
        ],
      ),
    );
  }

  String _getArabicStatus(String status) {
    switch (status) {
      case 'waitingForPricing':
        return 'بانتظار تحديد السعر من الإدارة';
      case 'pricingSentToCustomer':
      case 'pricing_sent_to_customer':
        return 'تم إرسال التسعيرة - بانتظار موافقتك';
      case 'waitingCourierApproval':
      case 'approvedByCustomer':
        return 'بانتظار قبول المندوب للطلب';
      case 'acceptedByCourier':
        return 'تم قبول الطلب من المندوب';
      case 'onTheWay':
        return 'المندوب في الطريق إليك';
      case 'arrivedToCustomer':
      case 'arrived':
        return 'وصل المندوب إلى موقعك';
      case 'delivered':
        return 'تم تسليم الطلب بنجاح';
      case 'cancelled':
      case 'cancelledByCustomer':
        return 'تم إلغاء الطلب';
      default:
        return status;
    }
  }

  Widget _buildOrdersTab(AppState appState, Color cardBg, Color textColor) {
    final customerOrders = appState.customerOrders;
    final accent = _accent(appState);

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withOpacity(0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.account_balance_wallet, color: accent, size: 24),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('حساب حاسب الكريمي (للدفع الإلكتروني):',
                          style: TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('2655872',
                          style: TextStyle(
                              color: textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2)),
                    ],
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor:
                      appState.isDarkMode ? Colors.black : Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: '2655872'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'تم نسخ رقم حاسب الكريمي (2655872) بنجاح')),
                  );
                },
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('نسخ الحساب',
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        Expanded(
          child: customerOrders.isEmpty
              ? EmptyStateWidget(
                  icon: Icons.receipt_long_outlined,
                  title: 'لا توجد طلبات سابقة!',
                  subtitle:
                      'لم تقم بإنشاء أي طلبات معنا حتى الآن. ابدأ طلبك الأول الآن واستمتع بأسرع خدمة توصيل في تعز',
                  buttonText: 'اطلب الآن',
                  onButtonPressed: () {
                    setState(() => _currentIndex = 0);
                  },
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: customerOrders.length,
                  itemBuilder: (context, index) {
                    final order = customerOrders[index];
                    final status = order['status']?.toString() ?? '';
                    final arabicStatus = _getArabicStatus(status);
                    final String assignedCourierName =
                        order['assigned_courier'] ?? 'المندوب';

                    final restaurantInfo =
                        _resolveRestaurantOrderInfo(appState, order);
                    final bool isRestaurantOrder =
                        restaurantInfo['isRestaurant'] as bool;
                    final String detectedRestaurantName =
                        restaurantInfo['restaurantName'] as String;

                    final formattedAddress =
                        formatLocationAddress(order['address']);

                    final double deliveryFee = double.tryParse(
                            order['delivery_fee']?.toString() ?? '0') ??
                        0.0;

                    final double? explicitProductsPrice = double.tryParse(
                        (order['products_total'] ??
                                order['products_price'] ??
                                order['items_price'] ??
                                '')
                            .toString());

                    final double totalPriceField = double.tryParse(
                            order['total_price']?.toString() ?? '0') ??
                        0.0;

                    final double finalProductsPrice = explicitProductsPrice ??
                        ((deliveryFee > 0 && totalPriceField >= deliveryFee)
                            ? (totalPriceField - deliveryFee)
                            : totalPriceField);

                    final double dbTotalAmount = double.tryParse(
                            order['total_amount']?.toString() ??
                                order['total']?.toString() ??
                                '0') ??
                        0.0;

                    final double grandTotal = dbTotalAmount > 0
                        ? dbTotalAmount
                        : (finalProductsPrice + deliveryFee);

                    return Card(
                      color: cardBg,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: accent.withOpacity(0.3)),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder:
                                  (context, animation, secondaryAnimation) =>
                                      OrderTrackingScreen(orderMap: order),
                              transitionsBuilder: (context, animation,
                                  secondaryAnimation, child) {
                                return FadeTransition(
                                    opacity: animation, child: child);
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Text('طلب #${order['id']}',
                                          style: TextStyle(
                                              color: accent,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16)),
                                      const SizedBox(width: 8),
                                      Icon(Icons.touch_app,
                                          color: accent, size: 16),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        style: IconButton.styleFrom(
                                            backgroundColor: Colors.black12),
                                        icon: Icon(Icons.share,
                                            color: accent, size: 18),
                                        tooltip: 'مشاركة الفاتورة',
                                        onPressed: () {
                                          final invoiceText =
                                              'فاتورة تطبيق FAST - تعز\n'
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
                                        style: IconButton.styleFrom(
                                            backgroundColor: Colors.blueGrey
                                                .withOpacity(0.2)),
                                        icon: Icon(Icons.chat,
                                            color: accent, size: 18),
                                        tooltip: 'مراسلة الإدارة ودعم الطلب',
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            PageRouteBuilder(
                                              pageBuilder: (context, animation,
                                                      secondaryAnimation) =>
                                                  ChatScreen(
                                                orderId: order['id'].toString(),
                                                userRole: 'customer',
                                                targetChat: 'admin_customer',
                                              ),
                                              transitionsBuilder: (context,
                                                  animation,
                                                  secondaryAnimation,
                                                  child) {
                                                return FadeTransition(
                                                    opacity: animation,
                                                    child: child);
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
                              if (status == 'pricingSentToCustomer' ||
                                  status == 'pricing_sent_to_customer') ...[
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: accent.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: accent),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          'تم إرسال التسعيرة للطلب، يرجى الموافقة:',
                                          style: TextStyle(
                                              color: accent,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12)),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8)),
                                              ),
                                              onPressed: () async {
                                                await appState
                                                    .customerConfirmOrder(
                                                        order['id']);
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                      content: Text(
                                                          'تم تأكيد الطلب وإرساله للمندوب بنجاح!')),
                                                );
                                              },
                                              child: const Text('موافقة',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.redAccent,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8)),
                                              ),
                                              onPressed: () async {
                                                await appState
                                                    .customerCancelOrder(
                                                        order['id']);
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                      content: Text(
                                                          'تم رفض الطلب وإلغاؤه')),
                                                );
                                              },
                                              child: const Text('إلغاء الطلب',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              Text('الحالة: $arabicStatus',
                                  style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              const SizedBox(height: 6),
                              Text('العنوان: $formattedAddress',
                                  style: TextStyle(
                                      color: textColor, fontSize: 13)),
                              Text(
                                  'المنتجات: ${order['items_desc'] ?? order['items_description']}',
                                  style: TextStyle(
                                      color: textColor, fontSize: 13)),
                              const SizedBox(height: 4),
                              Text(
                                  'وقت الطلب: ${OrderTimeHelper.formatDateTime(order['created_at'])}',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: appState.isDarkMode
                                      ? Colors.black26
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        'سعر المنتجات: ${finalProductsPrice.toStringAsFixed(0)} ر.ي',
                                        style: TextStyle(
                                            color: textColor, fontSize: 13)),
                                    const SizedBox(height: 4),
                                    Text(
                                        'رسوم التوصيل: ${deliveryFee.toStringAsFixed(0)} ر.ي',
                                        style: TextStyle(
                                            color: accent,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold)),
                                    Divider(
                                        color: appState.isDarkMode
                                            ? Colors.white12
                                            : Colors.black12,
                                        height: 8),
                                    Text(
                                        'الإجمالي الكلي: ${grandTotal.toStringAsFixed(0)} ر.ي',
                                        style: TextStyle(
                                            color: appState.isDarkMode
                                                ? Colors.greenAccent
                                                : Colors.green.shade800,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14)),
                                  ],
                                ),
                              ),
                              if (status == 'delivered' ||
                                  status == 'arrived' ||
                                  status == 'arrivedToCustomer') ...[
                                const SizedBox(height: 14),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accent.withOpacity(0.15),
                                    foregroundColor: accent,
                                    minimumSize: const Size(double.infinity, 42),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                          color: accent.withOpacity(0.5)),
                                    ),
                                  ),
                                  onPressed: () {
                                    _showRatingDialog(
                                        context,
                                        appState,
                                        order['id'].toString(),
                                        assignedCourierName,
                                        cardBg,
                                        textColor);
                                  },
                                  icon: const Icon(Icons.star, size: 18),
                                  label: const Text(
                                      'قيم المندوب وخدمة التوصيل',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ),
                                if (isRestaurantOrder) ...[
                                  const SizedBox(height: 8),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: accent.withOpacity(0.15),
                                      foregroundColor: accent,
                                      minimumSize:
                                          const Size(double.infinity, 42),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(
                                            color: accent.withOpacity(0.5)),
                                      ),
                                    ),
                                    onPressed: () {
                                      _showRestaurantRatingDialog(
                                          context,
                                          appState,
                                          order['id'].toString(),
                                          detectedRestaurantName,
                                          cardBg,
                                          textColor);
                                    },
                                    icon: const Icon(Icons.restaurant_menu,
                                        size: 18),
                                    label: Text(
                                        'قيم مطعم ($detectedRestaurantName) وجودة الطعام',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProfileTab(AppState appState, Color cardBg, Color textColor) {
    final profile = appState.userProfile;
    final accent = _accent(appState);

    final bool isAdmin = appState.isAdminLoggedIn ||
        (profile != null && profile['is_admin'] == true);
    final bool isCourier = appState.currentCourier != null ||
        (profile != null && profile['is_courier'] == true);

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Center(
          child: Text('حسابي الشخصي',
              style: TextStyle(
                  color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 20),
        if (isAdmin) ...[
          _buildProfileItem(Icons.admin_panel_settings,
              'لوحة تحكم المشرف الإدارية', cardBg, textColor, accent, () {
            Navigator.push(context,
                MaterialPageRoute(builder: (context) => AdminScreen()));
          }),
          const SizedBox(height: 10),
        ],
        if (isCourier) ...[
          _buildProfileItem(
              Icons.delivery_dining,
              'لوحة طلبات المندوب وتوصيل الشحنات',
              cardBg,
              textColor,
              accent, () {
            Navigator.push(context,
                MaterialPageRoute(builder: (context) => CourierScreen()));
          }),
          const SizedBox(height: 10),
        ],
        profile == null
            ? Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.person, size: 60, color: accent),
                    const SizedBox(height: 10),
                    Text('أنت لست مسجل دخول!',
                        style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    const SizedBox(height: 5),
                    const Text(
                        'سجل دخولك برقم هاتفك للاستمتاع بتجربة التوصيل الأسرع في تعز.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    const PhoneAuthScreen(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              return FadeTransition(
                                  opacity: animation, child: child);
                            },
                          ),
                        );
                      },
                      child: Text('تسجيل الدخول برقم الهاتف',
                          style: TextStyle(
                              color: appState.isDarkMode
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                    ),
                  ],
                ),
              )
            : Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: accent,
                      radius: 24,
                      child: Icon(Icons.person,
                          color:
                              appState.isDarkMode ? Colors.black : Colors.white,
                          size: 28),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(profile['name'] ?? 'عميل FAST',
                              style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                          const SizedBox(height: 4),
                          Text('هاتف: ${profile['phone']} | تعز',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                          if (profile['address'] != null &&
                              profile['address'].toString().isNotEmpty)
                            InkWell(
                              onTap: () => _launchWhatsApp(
                                  message:
                                      'مرحباً، بخصوص عنواني المسجل في التطبيق: ${profile['address']}'),
                              child: Text(
                                'العنوان: ${formatLocationAddress(profile['address'])} (اضغط للتواصل)',
                                style: TextStyle(
                                    color: accent,
                                    fontSize: 12,
                                    decoration: TextDecoration.underline),
                              ),
                            ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => appState.logoutUser(),
                      child: const Text('خروج',
                          style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
        const SizedBox(height: 20),
        _buildProfileItem(
            Icons.edit, 'تعديل البيانات الشخصية', cardBg, textColor, accent,
            () {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  const EditProfileScreen(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          );
        }),
        _buildProfileItem(
            Icons.location_on, 'إدارة عناويني المحفوظة', cardBg, textColor, accent,
            () {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  const AddressesScreen(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          );
        }),
        _buildProfileItem(
            Icons.favorite, 'المنتجات المفضلة', cardBg, textColor, accent, () {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  const FavoritesScreen(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          );
        }),
        _buildProfileItem(Icons.headset_mic, 'خدمة العملاء وتواصل معنا',
            cardBg, textColor, accent, () {
          _showContactUsDialog(context, appState, cardBg, textColor);
        }),
        _buildProfileItem(Icons.help_center_outlined,
            'كيفية استخدام التطبيق', cardBg, textColor, accent, () {
          _showHowToUseDialog(context, appState, cardBg, textColor);
        }),
        _buildProfileItem(Icons.privacy_tip_outlined,
            'سياسة الخصوصية والاستخدام', cardBg, textColor, accent, () {
          appState.setPrivacyPolicyAccepted(false);
          _checkAndShowPrivacyPolicyDialog(context, appState);
        }),
        _buildProfileItem(
            Icons.dark_mode,
            'مظهر التطبيق (${appState.isDarkMode ? "الوضع الداكن" : "الوضع الفاتح"})',
            cardBg,
            textColor,
            accent, () {
          appState.toggleTheme();
        }),
        _buildProfileItem(Icons.location_city, 'المدينة (تعز - اليمن - حصرياً)',
            cardBg, textColor, accent, () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('تطبيق FAST مخصص لخدمة مدينة تعز بكل سرعة')),
          );
        }),
        _buildProfileItem(Icons.share, 'مشاركة التطبيق مع الأصدقاء', cardBg,
            textColor, accent, () {
          appState.shareApp();
        }),
        const SizedBox(height: 25),
        Center(
          child: Column(
            children: [
              Text(
                'الإصدار: 2.0.65',
                style: TextStyle(
                    color: textColor.withOpacity(0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'تم التطوير بواسطة Eng. Maeen Almurish',
                style: TextStyle(
                  color: appState.isDarkMode
                      ? Colors.amber.shade700
                      : const Color(0xFF0D47A1),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),
      ],
    );
  }

  Widget _buildProfileItem(IconData icon, String title, Color cardBg,
      Color textColor, Color accent, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: ListTile(
        leading: Icon(icon, color: accent),
        title: Text(title,
            style: TextStyle(
                color: textColor, fontWeight: FontWeight.bold, fontSize: 14)),
        trailing:
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
