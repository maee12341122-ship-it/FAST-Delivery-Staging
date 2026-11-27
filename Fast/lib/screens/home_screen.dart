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
import '../services/fcm_push_service.dart';
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
  String selectedStoreSubCategory = 'الكل';

  final Map<String, double> _restaurantAvgRatings = {};
  final Map<String, int> _restaurantRatingCounts = {};
  final Map<String, double> _productAvgRatings = {};
  final Map<String, int> _productRatingCounts = {};
  bool _isLoadingRatings = false;
  bool _isInitialFetching = true;

  // تخزين Future البانرات و PageController لتجنب إعادة البناء المستمرة
  late Future<List<dynamic>> _promoBannersFuture;
  late final PageController _promoPageController;

  // مؤقت Debounce لتنعيم البحث ومنع التقطيع أثناء الكتابة
  Timer? _searchDebounce;
  String _debouncedSearchQuery = '';

  final ScrollController _shopScrollController = ScrollController();
  final ScrollController _otherOrdersScrollController = ScrollController();
  bool _showScrollToTop = false;
  bool _isPrivacyDialogOpen = false;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearching = false;
  String _searchScope = 'all';

  final TextEditingController _customItemNameController = TextEditingController();
  final TextEditingController _customItemPriceController = TextEditingController();
  final TextEditingController _customItemNotesController = TextEditingController();

  final TextEditingController _giftPharmaOrderNameController =
      TextEditingController();
  final TextEditingController _giftPharmaOrderPriceController =
      TextEditingController();
  final TextEditingController _giftPharmaOrderDetailsController =
      TextEditingController();

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

  static const String _supportPhoneDisplay = '775145534';
  static const String _supportPhoneIntl = '967775145534';

  Color _accent(AppState appState) =>
      appState.isDarkMode ? Colors.amber : const Color(0xFF0D47A1);

  void _showCleanSnackBar(BuildContext context, String message,
      {Duration duration = const Duration(seconds: 2),
      Color? backgroundColor}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

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

  bool _isPharmacyCategory(String? categoryName) {
    final c = (categoryName ?? '').trim().toLowerCase();
    return c == 'الصيدلية الآمنة' || c == 'الصيدلية' || c == 'الصيدليات';
  }

  bool _isGiftCategory(String? categoryName) {
    final c = (categoryName ?? '').trim().toLowerCase();
    return c == 'هدايا واكسسوارات' || c == 'هدايا' || c == 'الهدايا';
  }

  bool _isGiftOrPharmacyCategory(String? categoryName) {
    return _isPharmacyCategory(categoryName) || _isGiftCategory(categoryName);
  }

  Future<List<dynamic>> _fetchActivePromoBanners() async {
    try {
      final res = await Supabase.instance.client
          .from('promo_banners')
          .select()
          .eq('is_active', true)
          .order('id', ascending: false);
      return res;
    } catch (e) {
      debugPrint('⚠️ تعذر جلب البانرات الإعلانية: $e');
      return const [];
    }
  }

  Future<void> _fetchCustomerRatingsSummaries() async {
    if (_isLoadingRatings) return;
    _isLoadingRatings = true;
    try {
      final rows = await Supabase.instance.client
          .from('ratings_and_reviews')
          .select('target_type, target_id, rating');
      final Map<String, List<double>> restaurantScores = {};
      final Map<String, List<double>> productScores = {};
      for (final row in rows) {
        if (row is! Map) continue;
        final type = (row['target_type'] ?? '').toString().trim().toLowerCase();
        final targetId = (row['target_id'] ?? '').toString().trim();
        final ratingVal = double.tryParse(row['rating']?.toString() ?? '');
        if (targetId.isEmpty || ratingVal == null || ratingVal <= 0) continue;
        if (type == 'restaurant' || type == 'restaurants' || type == 'store') {
          restaurantScores
              .putIfAbsent(targetId.toLowerCase(), () => [])
              .add(ratingVal);
        } else if (type == 'product' || type == 'products' || type == 'item') {
          productScores
              .putIfAbsent(targetId.toLowerCase(), () => [])
              .add(ratingVal);
        }
      }
      final Map<String, double> rAvg = {};
      final Map<String, int> rCnt = {};
      restaurantScores.forEach((key, list) {
        if (list.isNotEmpty) {
          final sum = list.fold<double>(0, (a, b) => a + b);
          rAvg[key] = sum / list.length;
          rCnt[key] = list.length;
        }
      });
      final Map<String, double> pAvg = {};
      final Map<String, int> pCnt = {};
      productScores.forEach((key, list) {
        if (list.isNotEmpty) {
          final sum = list.fold<double>(0, (a, b) => a + b);
          pAvg[key] = sum / list.length;
          pCnt[key] = list.length;
        }
      });
      if (!mounted) return;
      setState(() {
        _restaurantAvgRatings
          ..clear()
          ..addAll(rAvg);
        _restaurantRatingCounts
          ..clear()
          ..addAll(rCnt);
        _productAvgRatings
          ..clear()
          ..addAll(pAvg);
        _productRatingCounts
          ..clear()
          ..addAll(pCnt);
      });
    } catch (e) {
      debugPrint('⚠️ تعذر جلب ملخص تقييمات العميل: $e');
    } finally {
      _isLoadingRatings = false;
    }
  }

  void _onSearchTextChanged(String val) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 240), () {
      if (!mounted) return;
      setState(() {
        _debouncedSearchQuery = val.trim().toLowerCase();
      });
    });
    // تحديث فوري فقط لإظهار/إخفاء زر المسح X
    setState(() {});
  }

  void _clearSearchState() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _debouncedSearchQuery = '';
  }

  String _searchHintText() {
    switch (_searchScope) {
      case 'products':
        return 'ابحث في أسماء المنتجات والوجبات...';
      case 'stores':
        return 'ابحث عن متجر، مطعم، أو مشروع منزلي...';
      case 'subCategories':
        return 'ابحث عن قسم داخلي (مثل: الوافل، الكريب)...';
      default:
        return 'ابحث عن منتج، متجر، أو قسم داخلي...';
    }
  }

  bool _matchesProductSearch(ProductModel product, String query) {
    if (query.isEmpty) return true;
    switch (_searchScope) {
      case 'products':
        return product.name.toLowerCase().contains(query);
      case 'stores':
        return product.restaurantName.toLowerCase().contains(query);
      case 'subCategories':
        return product.subCategory.toLowerCase().contains(query);
      default:
        return product.name.toLowerCase().contains(query) ||
            product.restaurantName.toLowerCase().contains(query) ||
            product.subCategory.toLowerCase().contains(query) ||
            product.category.toLowerCase().contains(query);
    }
  }

  List<Map<String, String>> _findMatchingStores(
      AppState appState, String query) {
    if (query.isEmpty) return const [];
    final Map<String, Map<String, String>> uniqueStores = {};
    for (final r in appState.restaurantsList) {
      final name = (r['name'] ?? '').toString().trim();
      final cat = (r['category'] ?? r['type'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      if (name.toLowerCase().contains(query) ||
          cat.toLowerCase().contains(query)) {
        uniqueStores.putIfAbsent(
          name.toLowerCase(),
          () => {'name': name, 'category': cat.isNotEmpty ? cat : 'المطاعم'},
        );
      }
    }
    for (final hp in appState.homeProjectsList) {
      final name = (hp['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      if (name.toLowerCase().contains(query)) {
        uniqueStores.putIfAbsent(
          name.toLowerCase(),
          () => {'name': name, 'category': 'مشاريع منزلية'},
        );
      }
    }
    for (final p in appState.products) {
      final name = p.restaurantName.trim();
      if (name.isEmpty) continue;
      if (name.toLowerCase().contains(query)) {
        uniqueStores.putIfAbsent(
          name.toLowerCase(),
          () => {
            'name': name,
            'category': p.category.trim().isNotEmpty
                ? p.category.trim()
                : 'المطاعم',
          },
        );
      }
    }
    for (final giftStore in [
      'شغف',
      'فلاورز',
      'دار التحف والهدايا',
      'قصر التحف والهدايا'
    ]) {
      if (giftStore.toLowerCase().contains(query)) {
        uniqueStores.putIfAbsent(
          giftStore.toLowerCase(),
          () => {'name': giftStore, 'category': 'هدايا واكسسوارات'},
        );
      }
    }
    return uniqueStores.values.take(6).toList();
  }

  String _resolveStoreCategory(AppState appState, String storeName) {
    final lower = storeName.trim().toLowerCase();
    for (final r in appState.restaurantsList) {
      if ((r['name'] ?? '').toString().trim().toLowerCase() == lower) {
        final cat = (r['category'] ?? r['type'] ?? '').toString().trim();
        if (cat.isNotEmpty) return cat;
      }
    }
    for (final hp in appState.homeProjectsList) {
      if ((hp['name'] ?? '').toString().trim().toLowerCase() == lower) {
        return 'مشاريع منزلية';
      }
    }
    for (final p in appState.products) {
      if (p.restaurantName.trim().toLowerCase() == lower &&
          p.category.trim().isNotEmpty) {
        return p.category.trim();
      }
    }
    if (['شغف', 'فلاورز', 'دار التحف والهدايا', 'قصر التحف والهدايا']
        .any((s) => s.toLowerCase() == lower)) {
      return 'هدايا واكسسوارات';
    }
    return 'المطاعم';
  }

  double? _resolveStoreRating(AppState appState, String storeName,
      {Map<String, dynamic>? storeMap}) {
    final lower = storeName.trim().toLowerCase();
    if (_restaurantAvgRatings.containsKey(lower)) {
      return _restaurantAvgRatings[lower];
    }
    final fromState = appState.getRestaurantRatingInfo(
      restaurantId: storeMap?['id']?.toString(),
      restaurantName: storeName,
    );
    if (fromState != null && fromState['avg'] != null) {
      final parsed = double.tryParse(fromState['avg'].toString());
      if (parsed != null && parsed > 0) return parsed;
    }
    final direct = storeMap?['rating'] ??
        storeMap?['avg_rating'] ??
        storeMap?['average_rating'];
    if (direct != null) {
      final parsed = double.tryParse(direct.toString());
      if (parsed != null && parsed > 0) return parsed;
    }
    for (final r in appState.restaurantsList) {
      if ((r['name'] ?? '').toString().trim().toLowerCase() == lower) {
        final rVal = r['rating'] ?? r['avg_rating'] ?? r['average_rating'];
        if (rVal != null) {
          final parsed = double.tryParse(rVal.toString());
          if (parsed != null && parsed > 0) return parsed;
        }
      }
    }
    return null;
  }

  Widget _buildBreadcrumbBar(
      AppState appState, Color cardBg, Color textColor) {
    if (selectedCategory == 'الكل' && selectedRestaurantName == null) {
      return const SizedBox.shrink();
    }
    final accent = _accent(appState);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (selectedRestaurantName != null) {
                  selectedRestaurantName = null;
                  selectedStoreSubCategory = 'الكل';
                } else {
                  selectedCategory = 'الكل';
                  selectedStoreSubCategory = 'الكل';
                }
              });
              scrollHomeToTop(animated: true);
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_ios_new_rounded,
                      size: 13, color: accent),
                  const SizedBox(width: 4),
                  Text(
                    'رجوع',
                    style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 14, color: Colors.grey.withOpacity(0.3)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  InkWell(
                    onTap: () => _resetToHomeView(
                        clearSearch: false, animateScroll: true),
                    child: Text(
                      'الرئيسية',
                      style: TextStyle(
                          color: textColor.withOpacity(0.7), fontSize: 11.5),
                    ),
                  ),
                  if (selectedCategory != 'الكل') ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.chevron_left_rounded,
                          size: 15, color: Colors.grey.withOpacity(0.7)),
                    ),
                    InkWell(
                      onTap: selectedRestaurantName != null
                          ? () {
                              setState(() {
                                selectedRestaurantName = null;
                                selectedStoreSubCategory = 'الكل';
                              });
                            }
                          : null,
                      child: Text(
                        selectedCategory,
                        style: TextStyle(
                          color: selectedRestaurantName == null
                              ? accent
                              : textColor.withOpacity(0.8),
                          fontWeight: selectedRestaurantName == null
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                  if (selectedRestaurantName != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.chevron_left_rounded,
                          size: 15, color: Colors.grey.withOpacity(0.7)),
                    ),
                    Text(
                      selectedRestaurantName!,
                      style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntegratedSearchBar(
      AppState appState, Color cardBg, Color textColor) {
    final accent = _accent(appState);
    final query = _debouncedSearchQuery;
    final matchingStores = _findMatchingStores(appState, query);
    final searchScopes = [
      {'key': 'all', 'label': 'الكل', 'icon': Icons.all_inclusive},
      {'key': 'products', 'label': 'المنتجات', 'icon': Icons.fastfood},
      {'key': 'stores', 'label': 'المتاجر', 'icon': Icons.storefront},
      {
        'key': 'subCategories',
        'label': 'الأقسام الداخلية',
        'icon': Icons.category
      },
    ];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      padding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: _isSearching || _searchController.text.isNotEmpty ? 10 : 6,
      ),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (_isSearching || _searchController.text.isNotEmpty)
              ? accent.withOpacity(0.55)
              : Colors.grey.withOpacity(0.22),
          width: (_isSearching || _searchController.text.isNotEmpty) ? 1.3 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  style: TextStyle(color: textColor, fontSize: 13),
                  onTap: () {
                    if (!_isSearching) {
                      setState(() => _isSearching = true);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: _searchHintText(),
                    hintStyle:
                        const TextStyle(color: Colors.grey, fontSize: 12),
                    prefixIcon:
                        Icon(Icons.search_rounded, color: accent, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close_rounded,
                                color: accent, size: 19),
                            onPressed: () {
                              setState(() {
                                _clearSearchState();
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: appState.isDarkMode
                        ? const Color(0xFF121212)
                        : Colors.grey[100],
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: _onSearchTextChanged,
                ),
              ),
              if (_isSearching || _searchController.text.isNotEmpty) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'طي خيارات البحث',
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _isSearching = false;
                      _clearSearchState();
                      _searchScope = 'all';
                    });
                  },
                  icon: const Icon(Icons.keyboard_arrow_up_rounded,
                      color: Colors.grey),
                ),
              ],
            ],
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: (_isSearching || _searchController.text.isNotEmpty)
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                SizedBox(
                  height: 32,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: searchScopes.length,
                    itemBuilder: (context, index) {
                      final item = searchScopes[index];
                      final key = item['key'] as String;
                      final label = item['label'] as String;
                      final icon = item['icon'] as IconData;
                      final isSelected = _searchScope == key;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _searchScope = key);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? accent
                                  : (appState.isDarkMode
                                      ? const Color(0xFF121212)
                                      : Colors.grey[100]),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? accent
                                    : Colors.grey.withOpacity(0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  icon,
                                  size: 14,
                                  color: isSelected
                                      ? (appState.isDarkMode
                                          ? Colors.black
                                          : Colors.white)
                                      : accent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isSelected
                                        ? (appState.isDarkMode
                                            ? Colors.black
                                            : Colors.white)
                                        : textColor,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (matchingStores.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'متاجر مطابقة:',
                    style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: matchingStores.map((st) {
                      final sName = st['name'] ?? '';
                      final sCat = st['category'] ??
                          _resolveStoreCategory(appState, sName);
                      return ActionChip(
                        avatar: Icon(Icons.storefront, size: 15, color: accent),
                        label: Text(sName, style: const TextStyle(fontSize: 11)),
                        backgroundColor: appState.isDarkMode
                            ? const Color(0xFF121212)
                            : Colors.grey[100],
                        side: BorderSide(color: accent.withOpacity(0.35)),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            selectedCategory = sCat;
                            selectedRestaurantName = sName;
                            selectedStoreSubCategory = 'الكل';
                            _clearSearchState();
                            _isSearching = false;
                          });
                          scrollHomeToTop(animated: true);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _extractNotificationPayload(
      Map<String, dynamic> notification) {
    final Map<String, dynamic> payload = {};
    final nested = notification['data'] ??
        notification['additionalData'] ??
        notification['payload'];
    if (nested is Map) {
      nested.forEach((k, v) {
        payload[k.toString()] = v;
      });
    }
    for (final key in [
      'type',
      'screen',
      'route',
      'target',
      'order_id',
      'orderId',
      'related_id',
      'chat_id',
      'chatId',
      'room_id',
      'roomId',
      'user_role',
      'userRole',
      'target_chat',
      'targetChat',
      'sender_id',
      'senderId',
      'other_user_id',
      'otherUserId',
      'title',
      'message',
      'body',
    ]) {
      if (notification[key] != null && !payload.containsKey(key)) {
        payload[key] = notification[key];
      }
    }
    return payload;
  }

  void _handleNotificationTap(
      BuildContext context, Map<String, dynamic> notification) {
    final payload = _extractNotificationPayload(notification);
    final String notifType = (payload['type'] ??
            payload['screen'] ??
            payload['route'] ??
            payload['target'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    final String? chatId = (payload['chat_id'] ??
            payload['chatId'] ??
            payload['room_id'] ??
            payload['roomId'])
        ?.toString()
        .trim();
    final String? orderId = (payload['order_id'] ??
            payload['orderId'] ??
            payload['related_id'] ??
            _extractOrderIdFromText(
                '${payload['title'] ?? ''} ${payload['message'] ?? ''} ${payload['body'] ?? ''}'))
        ?.toString()
        .trim();
    final bool isChatNotification = notifType.contains('chat') ||
        notifType.contains('message') ||
        (chatId != null && chatId.isNotEmpty);
    if (isChatNotification &&
        ((orderId != null && orderId.isNotEmpty) ||
            (chatId != null && chatId.isNotEmpty))) {
      final String userRole =
          (payload['user_role'] ?? payload['userRole'] ?? 'customer')
              .toString()
              .trim();
      final String targetChat = (payload['target_chat'] ??
              payload['targetChat'] ??
              'admin_customer')
          .toString()
          .trim();
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(
            orderId: (orderId != null && orderId.isNotEmpty) ? orderId : chatId!,
            userRole: userRole.isNotEmpty ? userRole : 'customer',
            targetChat: targetChat.isNotEmpty ? targetChat : 'admin_customer',
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
      return;
    }
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

  void scrollHomeToTop({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final controller in [
        _shopScrollController,
        _otherOrdersScrollController,
      ]) {
        if (controller.hasClients && controller.offset > 0) {
          if (animated) {
            controller.animateTo(
              0.0,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            );
          } else {
            controller.jumpTo(0.0);
          }
        }
      }
    });
  }

  void _resetToHomeView({bool clearSearch = true, bool animateScroll = true}) {
    FocusScope.of(context).unfocus();
    setState(() {
      _currentIndex = 0;
      selectedCategory = 'الكل';
      selectedRestaurantName = null;
      selectedStoreSubCategory = 'الكل';
      if (clearSearch) {
        _clearSearchState();
        _searchScope = 'all';
        _isSearching = false;
      }
    });
    scrollHomeToTop(animated: animateScroll);
  }

  void _onShopScroll() {
    if (!_shopScrollController.hasClients) return;
    final shouldShow = _shopScrollController.offset > 360;
    if (shouldShow != _showScrollToTop && mounted) {
      setState(() => _showScrollToTop = shouldShow);
    }
  }

  Future<void> _initializeInitialData(AppState appState) async {
    try {
      await Future.wait([
        appState.fetchStoreSettings(),
        appState.fetchRestaurantsAndCategories(),
        appState.fetchProductsFromSupabase(),
        _fetchCustomerRatingsSummaries(),
      ]);
    } catch (e) {
      debugPrint('⚠️ خطأ أثناء التحميل الأولي: $e');
    } finally {
      if (mounted) {
        setState(() => _isInitialFetching = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _promoPageController = PageController(viewportFraction: 0.92);
    _promoBannersFuture = _fetchActivePromoBanners();
    _shopScrollController.addListener(_onShopScroll);

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
      unawaited(_initializeInitialData(appState));
      unawaited(FcmPushService.initialize());
      unawaited(appState.syncFcmTokenForCurrentUsers());

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
    _searchDebounce?.cancel();
    _promoPageController.dispose();
    _shopScrollController.removeListener(_onShopScroll);
    _shopScrollController.dispose();
    _otherOrdersScrollController.dispose();
    _popupAnimController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _customItemNameController.dispose();
    _customItemPriceController.dispose();
    _customItemNotesController.dispose();
    _giftPharmaOrderNameController.dispose();
    _giftPharmaOrderPriceController.dispose();
    _giftPharmaOrderDetailsController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressDescriptionController.dispose();
    super.dispose();
  }

  void _checkAndShowPrivacyPolicyDialog(BuildContext context, AppState appState) {
    final bool hasAcceptedPrivacy = appState.hasAcceptedPrivacyPolicy;
    final accent = _accent(appState);
    if (!hasAcceptedPrivacy && !_isPrivacyDialogOpen) {
      _isPrivacyDialogOpen = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => Directionality(
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
                Expanded(
                  child: Text(
                    'شروط وسياسة تطبيق FAST',
                    style: TextStyle(
                        color: accent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 360,
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
                    _isPrivacyDialogOpen = false;
                    Navigator.pop(dialogCtx);
                    unawaited(() async {
                      String? role;
                      dynamic rowId;
                      if (appState.isAdminLoggedIn) {
                        role = 'admin';
                        rowId = appState.userProfile?['id'];
                      } else if (appState.currentCourier != null) {
                        role = 'courier';
                        rowId = appState.currentCourier?['id'];
                      } else if (appState.userProfile != null) {
                        role = 'customer';
                        rowId = appState.userProfile?['id'];
                      }
                      await FcmPushService.requestPermissionAndSyncToken(
                        role: role,
                        rowId: rowId,
                      );
                      await appState.syncFcmTokenForCurrentUsers();
                    }());
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
    final uri = Uri.parse(
        'https://wa.me/$_supportPhoneIntl?text=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      final appState = Provider.of<AppState>(context, listen: false);
      await appState.openFastWhatsApp(message: message);
    }
  }

  Future<void> _launchPhoneCall() async {
    final Uri url = Uri.parse('tel:$_supportPhoneDisplay');
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
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
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
      future: _promoBannersFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || (snapshot.data ?? []).isEmpty) {
          return const SizedBox.shrink();
        }
        final banners = snapshot.data!;
        return SizedBox(
          height: 98,
          child: PageView.builder(
            controller: _promoPageController,
            physics: const BouncingScrollPhysics(),
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
                  borderRadius: BorderRadius.circular(14),
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

  Widget _buildWasalliAndOtherOrdersRow(
      BuildContext context, AppState appState, String token) {
    final accent = _accent(appState);
    final isDark = appState.isDarkMode;
    final isOtherSelected = selectedCategory == 'طلبات أخرى';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  HapticFeedback.selectionClick();
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
                child: Ink(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
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
                      Icon(Icons.delivery_dining, color: accent, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'خدمة وصل لي',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'توصيل خاص مرن',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDark ? Colors.grey : Colors.black54,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, color: accent, size: 13),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    selectedCategory =
                        isOtherSelected ? 'الكل' : 'طلبات أخرى';
                    selectedRestaurantName = null;
                    selectedStoreSubCategory = 'الكل';
                    _clearSearchState();
                  });
                  scrollHomeToTop(animated: true);
                },
                child: Ink(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isOtherSelected
                          ? [accent.withOpacity(0.28), accent.withOpacity(0.12)]
                          : (isDark
                              ? [
                                  const Color(0xFF262626),
                                  const Color(0xFF1E1E1E)
                                ]
                              : [const Color(0xFFF3F6FA), Colors.white]),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: accent.withOpacity(isOtherSelected ? 1.0 : 0.7),
                      width: isOtherSelected ? 1.6 : 1.1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.playlist_add_check_circle_rounded,
                          color: accent, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'طلبات أخرى',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'طلب خاص أو خدمة',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDark ? Colors.grey : Colors.black54,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isOtherSelected
                            ? Icons.keyboard_arrow_up
                            : Icons.arrow_forward_ios,
                        color: accent,
                        size: 13,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// شريط الأقسام الأفقي المدمج والمتوسط الحجم
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
        'title': 'مشاريع منزلية',
        'image': 'https://images.unsplash.com/photo-1556910103-1c02745aae4d',
        'category': 'مشاريع منزلية'
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
        'title': 'هدايا واكسسوارات',
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
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: cardBg.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'الأقسام',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'اسحب للتصفح ◀',
                  style: TextStyle(
                    color: textColor.withOpacity(0.5),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 78,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
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
                      selectedStoreSubCategory = 'الكل';
                      _clearSearchState();
                    });
                    scrollHomeToTop(animated: true);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 82,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? accent.withOpacity(0.18) : cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            isSelected ? accent : Colors.grey.withOpacity(0.25),
                        width: isSelected ? 1.6 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: catItem['image'] as String,
                            width: 34,
                            height: 34,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => Icon(
                              Icons.category_rounded,
                              color: accent,
                              size: 24,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          catItem['title'] as String,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected ? accent : textColor,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.w600,
                            fontSize: 11,
                          ),
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
    );
  }

  /// هيكل تحميل أنيق (Skeleton Loading) يظهر أثناء الجلب الأولي بدلاً من الفراغ
  Widget _buildLoadingGridSkeleton(Color cardBg, Color accent) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withOpacity(0.15)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: accent.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 10,
                width: 80,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 8,
                width: 55,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// نموذج الطلب داخل متاجر الهدايا والإكسسوارات أو الصيدلية
  Widget _buildGiftOrPharmacyOrderForm(
      BuildContext context, AppState appState, Color cardBg, Color textColor) {
    final accent = _accent(appState);
    final isPharmacy = _isPharmacyCategory(selectedCategory);
    final sectionLabel =
        isPharmacy ? 'قسم الصيدلية' : 'قسم الهدايا والإكسسوارات';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.45), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPharmacy ? Icons.local_pharmacy : Icons.card_giftcard,
                color: accent,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selectedRestaurantName != null
                      ? 'طلب من متجر: $selectedRestaurantName'
                      : 'إدخال طلب — $sectionLabel',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5,
                  ),
                ),
              ),
              if (selectedRestaurantName != null)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      selectedRestaurantName = null;
                    });
                  },
                  icon: Icon(Icons.swap_horiz, size: 16, color: accent),
                  label: Text('تغيير المتجر',
                      style: TextStyle(color: accent, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            selectedRestaurantName != null
                ? 'أدخل الطلب، السعر، والتوضيح لطلبك من ($selectedRestaurantName):'
                : 'أدخل الطلب، السعر، والتوضيح ليتم إضافته إلى السلة.',
            style: TextStyle(color: textColor.withOpacity(0.75), fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _giftPharmaOrderNameController,
            style: TextStyle(color: textColor),
            decoration: InputDecoration(
              labelText: '1. الطلب*',
              hintText: isPharmacy
                  ? 'مثال: دواء خافض حرارة / فيتامينات'
                  : 'مثال: باقة ورد / هدية تخرج / إكسسوار',
              prefixIcon: Icon(Icons.shopping_bag_outlined, color: accent),
              filled: true,
              fillColor: appState.isDarkMode
                  ? const Color(0xFF121212)
                  : Colors.grey[100],
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _giftPharmaOrderPriceController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: textColor),
            decoration: InputDecoration(
              labelText: '2. السعر (ر.ي)*',
              hintText: 'أدخل السعر بالريال اليمني',
              prefixIcon: Icon(Icons.payments_outlined, color: accent),
              filled: true,
              fillColor: appState.isDarkMode
                  ? const Color(0xFF121212)
                  : Colors.grey[100],
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _giftPharmaOrderDetailsController,
            style: TextStyle(color: textColor),
            maxLines: 3,
            decoration: InputDecoration(
              labelText: '3. التوضيح*',
              hintText: isPharmacy
                  ? 'اكتب الجرعة أو التركيز أو أي ملاحظات للصيدلي...'
                  : 'اكتب التوضيح الكامل للطلب (اللون، العبارة على البطاقة، التغليف، التفاصيل)...',
              prefixIcon: Icon(Icons.description_outlined, color: accent),
              filled: true,
              fillColor: appState.isDarkMode
                  ? const Color(0xFF121212)
                  : Colors.grey[100],
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor:
                    appState.isDarkMode ? Colors.black : Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                final orderName = _giftPharmaOrderNameController.text.trim();
                final priceText = _giftPharmaOrderPriceController.text.trim();
                final orderDetails =
                    _giftPharmaOrderDetailsController.text.trim();
                final parsedPrice = double.tryParse(priceText);
                if (orderName.isEmpty) {
                  _showCleanSnackBar(context, 'الرجاء إدخال الطلب');
                  return;
                }
                if (parsedPrice == null || parsedPrice <= 0) {
                  _showCleanSnackBar(
                      context, 'الرجاء إدخال سعر صحيح أكبر من صفر');
                  return;
                }
                if (orderDetails.isEmpty) {
                  _showCleanSnackBar(
                      context, 'الرجاء إدخال التوضيح وتفاصيل الطلب');
                  return;
                }
                final storePrefix = selectedRestaurantName != null
                    ? '[$selectedRestaurantName - $sectionLabel] '
                    : '[$sectionLabel] ';
                final combinedCustomName =
                    '$storePrefix$orderName — التوضيح: $orderDetails';
                appState.addCustomOrderToCart(
                  customName: combinedCustomName,
                  estimatedPrice: parsedPrice,
                );
                _giftPharmaOrderNameController.clear();
                _giftPharmaOrderPriceController.clear();
                _giftPharmaOrderDetailsController.clear();
                FocusScope.of(context).unfocus();
                HapticFeedback.lightImpact();
                _showCleanSnackBar(
                  context,
                  selectedRestaurantName != null
                      ? 'تمت إضافة طلبك من ($selectedRestaurantName) إلى السلة بنجاح'
                      : 'تمت إضافة الطلب إلى السلة بنجاح',
                );
              },
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text(
                'إضافة الطلب للسلة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
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
        _showCleanSnackBar(
          context,
          'تمت إضافة ${product.name} للسلة بنجاح',
          duration: const Duration(milliseconds: 900),
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
                    _showCleanSnackBar(context,
                        'تمت إضافة ${product.name} مع الإضافات للسلة بنجاح');
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
                label: const Text(
                    'خدمة العملاء واتساب ($_supportPhoneDisplay)',
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
                label: const Text(
                    'اتصل بخدمة العملاء ($_supportPhoneDisplay)',
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
                            _showCleanSnackBar(parentContext,
                                'شكراً لك! تم إرسال تقييم المندوب بنجاح');
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            setDialogState(() => isSubmitting = false);
                          }
                          if (parentContext.mounted) {
                            _showCleanSnackBar(
                              parentContext,
                              e.toString().replaceAll('Exception: ', ''),
                              backgroundColor: Colors.redAccent,
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
                          unawaited(_fetchCustomerRatingsSummaries());
                          if (mounted) setState(() {});
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          if (parentContext.mounted) {
                            _showCleanSnackBar(parentContext,
                                'شكراً لك! تم إرسال تقييم المطعم بنجاح');
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            setDialogState(() => isSubmitting = false);
                          }
                          if (parentContext.mounted) {
                            _showCleanSnackBar(
                              parentContext,
                              e.toString().replaceAll('Exception: ', ''),
                              backgroundColor: Colors.redAccent,
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
                    _showCleanSnackBar(context,
                        'تمت إضافة ${product.name} بسعر ${_formatPrice(enteredPrice)} ر.ي إلى السلة بنجاح');
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
    final GlobalKey<FormState> sheetFormKey = GlobalKey<FormState>();
    final accent = _accent(appState);
    bool isSubmittingOrder = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GestureDetector(
        onTap: () => FocusScope.of(ctx).unfocus(),
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final double subtotal = appState.totalAmount;
            final double discount = appState.couponDiscountAmount;
            final double finalTotal =
                (subtotal - discount) > 0 ? (subtotal - discount) : 0.0;

            return PopScope(
              canPop: !isSubmittingOrder,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.90,
                    ),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      border: Border(
                        top: BorderSide(
                            color: accent.withOpacity(0.5), width: 1.5),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.45),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.local_shipping_outlined,
                                      color: accent),
                                  const SizedBox(width: 8),
                                  Text(
                                    'بيانات التوصيل وطريقة الدفع',
                                    style: TextStyle(
                                      color: accent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                onPressed: isSubmittingOrder
                                    ? null
                                    : () => Navigator.pop(ctx),
                                icon:
                                    const Icon(Icons.close, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Form(
                              key: sheetFormKey,
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
                                      labelStyle:
                                          const TextStyle(color: Colors.grey),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
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
                                      labelStyle:
                                          const TextStyle(color: Colors.grey),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
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
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                      ),
                                      onPressed: isSubmittingOrder
                                          ? null
                                          : () async {
                                              final result =
                                                  await Navigator.push(
                                                context,
                                                PageRouteBuilder(
                                                  pageBuilder: (context,
                                                          animation,
                                                          secondaryAnimation) =>
                                                      const MapLocationScreen(),
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
                                              if (result != null &&
                                                  result is Map) {
                                                setDialogState(() {
                                                  _addressDescriptionController
                                                          .text =
                                                      result['address'] ?? '';
                                                });
                                              }
                                            },
                                      icon: Icon(Icons.map, color: accent),
                                      label: const Text(
                                          'تحديد الموقع عبر الخريطة والـ GPS',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
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
                                      labelStyle:
                                          const TextStyle(color: Colors.grey),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
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
                                            labelStyle: const TextStyle(
                                                color: Colors.grey),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
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
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                        ),
                                        onPressed: isSubmittingOrder
                                            ? null
                                            : () async {
                                                final String msg = await appState
                                                    .applyCouponCode(
                                                        couponController.text,
                                                        appState.totalAmount);
                                                setDialogState(() {});
                                                if (context.mounted) {
                                                  _showCleanSnackBar(
                                                      context, msg);
                                                }
                                              },
                                        child: const Text('تطبيق',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                  if (appState.activeCouponCode != null) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                            'تم تطبيق الكوبون: ${appState.activeCouponCode} (خصم: ${_formatPrice(discount)} ر.ي)',
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
                                                  color: Colors.redAccent,
                                                  fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  // ملخص الفاتورة السريع قبل التأكيد
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: appState.isDarkMode
                                          ? const Color(0xFF121212)
                                          : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: Colors.grey.withOpacity(0.25)),
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text('مجموع المنتجات:',
                                                style: TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 12.5)),
                                            Text('${_formatPrice(subtotal)} ر.ي',
                                                style: TextStyle(
                                                    color: textColor,
                                                    fontSize: 12.5,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ],
                                        ),
                                        if (discount > 0) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text('الخصم:',
                                                  style: TextStyle(
                                                      color: Colors.green,
                                                      fontSize: 12.5)),
                                              Text(
                                                  '- ${_formatPrice(discount)} ر.ي',
                                                  style: const TextStyle(
                                                      color: Colors.green,
                                                      fontSize: 12.5,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ],
                                          ),
                                        ],
                                        const Divider(height: 12),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text('صافي المنتجات:',
                                                style: TextStyle(
                                                    color: textColor,
                                                    fontSize: 13.5,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            Text(
                                                '${_formatPrice(finalTotal)} ر.ي',
                                                style: TextStyle(
                                                    color: accent,
                                                    fontSize: 14.5,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: accent.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: accent.withOpacity(0.4)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text('حساب الكريمي (حاسب):',
                                                style: TextStyle(
                                                    color: accent,
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            Text('2655872',
                                                style: TextStyle(
                                                    color: textColor,
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ],
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.copy,
                                              color: accent, size: 20),
                                          tooltip: 'نسخ رقم الحساب',
                                          onPressed: () {
                                            Clipboard.setData(
                                                const ClipboardData(
                                                    text: '2655872'));
                                            _showCleanSnackBar(context,
                                                'تم نسخ رقم حاسب الكريمي (2655872) بنجاح');
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
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor: appState.isDarkMode
                                          ? const Color(0xFF121212)
                                          : Colors.grey[100],
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'cash',
                                          child: Text(
                                              'الدفع نقداً عند الاستلام فقط')),
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
                                  const SizedBox(height: 18),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.grey,
                                            minimumSize: const Size(0, 48),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          onPressed: isSubmittingOrder
                                              ? null
                                              : () => Navigator.pop(ctx),
                                          child: const Text('إغلاق'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        flex: 2,
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: accent,
                                            foregroundColor: appState.isDarkMode
                                                ? Colors.black
                                                : Colors.white,
                                            minimumSize: const Size(0, 48),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12)),
                                          ),
                                          onPressed: (isSubmittingOrder ||
                                                  _isSubmittingCheckout)
                                              ? null
                                              : () async {
                                                  if (!(sheetFormKey
                                                          .currentState
                                                          ?.validate() ??
                                                      false)) {
                                                    return;
                                                  }
                                                  _isSubmittingCheckout = true;
                                                  setDialogState(() =>
                                                      isSubmittingOrder = true);
                                                  final itemsDescription =
                                                      appState.cartItems
                                                          .map((item) =>
                                                              '${item.name} (x${item.quantity})')
                                                          .join(', ');
                                                  final double
                                                      finalAmountToPay =
                                                      appState.totalAmount -
                                                          appState
                                                              .couponDiscountAmount;
                                                  try {
                                                    await appState.createOrder(
                                                      customerName:
                                                          _nameController.text
                                                              .trim(),
                                                      phone: _phoneController
                                                          .text
                                                          .trim(),
                                                      address:
                                                          _addressDescriptionController
                                                              .text
                                                              .trim(),
                                                      itemsDesc:
                                                          itemsDescription
                                                                  .isNotEmpty
                                                              ? itemsDescription
                                                              : 'طلب عام من السلة',
                                                      productsTotal:
                                                          finalAmountToPay > 0
                                                              ? finalAmountToPay
                                                              : 0.0,
                                                      paymentMethod:
                                                          _selectedPaymentMethod,
                                                      paymentAccount: 'نقدي',
                                                    );
                                                    if (!context.mounted) return;
                                                    if (Navigator.canPop(ctx)) {
                                                      Navigator.pop(ctx);
                                                    }
                                                    setState(() =>
                                                        _currentIndex = 2);
                                                    _showCleanSnackBar(
                                                      context,
                                                      'تم إرسال الطلب بنجاح. رمز المتابعة: ${appState.lastOrderTrackingCode ?? '—'}',
                                                    );
                                                  } catch (e) {
                                                    if (context.mounted) {
                                                      _showCleanSnackBar(
                                                        context,
                                                        'تعذر إرسال الطلب: ${e.toString().replaceAll('Exception: ', '')}',
                                                        backgroundColor:
                                                            Colors.redAccent,
                                                      );
                                                    }
                                                  } finally {
                                                    _isSubmittingCheckout =
                                                        false;
                                                    if (context.mounted) {
                                                      setDialogState(() =>
                                                          isSubmittingOrder =
                                                              false);
                                                    }
                                                  }
                                                },
                                          child: Text(
                                            isSubmittingOrder
                                                ? 'جاري الإرسال...'
                                                : 'تأكيد وإرسال',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _checkAndShowPricingDialog(
      BuildContext context, AppState appState, Color cardBg, Color textColor) {
    if (_isPrivacyDialogOpen ||
        !appState.hasAcceptedPrivacyPolicy ||
        appState.userProfile == null ||
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
                      style: TextStyle(color: textColor, fontSize: 13),
                    ),
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
                      _showCleanSnackBar(context,
                          'تم تأكيد الطلب وإرساله للمندوب بنجاح!');
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
                      _showCleanSnackBar(context, 'تم رفض الطلب وإلغاؤه');
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
              selectedStoreSubCategory = 'الكل';
            });
            scrollHomeToTop(animated: true);
          } else if (_currentIndex == 0 && selectedCategory != 'الكل') {
            setState(() {
              selectedCategory = 'الكل';
              selectedRestaurantName = null;
              selectedStoreSubCategory = 'الكل';
            });
            scrollHomeToTop(animated: true);
          } else if (_currentIndex != 0) {
            _resetToHomeView(clearSearch: false, animateScroll: true);
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
              title: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  HapticFeedback.selectionClick();
                  _resetToHomeView(clearSearch: true, animateScroll: true);
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 40,
                        height: 40,
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
                ),
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
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        _isSearching ? Icons.search_off_rounded : Icons.search,
                        color: accent,
                        size: 24,
                      ),
                      tooltip: 'البحث والأقسام',
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _currentIndex = 0;
                          _isSearching = !_isSearching;
                          if (!_isSearching) {
                            _clearSearchState();
                            _searchScope = 'all';
                          }
                        });
                        if (_isSearching) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              FocusScope.of(context)
                                  .requestFocus(_searchFocusNode);
                            }
                          });
                        }
                      },
                    ),
                    if (_searchController.text.trim().isNotEmpty ||
                        _searchScope != 'all')
                      Positioned(
                        top: 9,
                        right: 9,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
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
                      if (_currentIndex == 0 && _showScrollToTop)
                        Positioned(
                          left: 16,
                          bottom: appState.cartItems.isNotEmpty ? 84 : 18,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: _showScrollToTop ? 1.0 : 0.0,
                            child: FloatingActionButton.small(
                              heroTag: 'scrollToTopBtn',
                              backgroundColor: cardBg,
                              foregroundColor: accent,
                              elevation: 4,
                              shape: CircleBorder(
                                side: BorderSide(
                                    color: accent.withOpacity(0.5), width: 1.2),
                              ),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                scrollHomeToTop(animated: true);
                              },
                              child: const Icon(Icons.keyboard_arrow_up_rounded),
                            ),
                          ),
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
                if (index == 0) {
                  _resetToHomeView(clearSearch: true, animateScroll: true);
                  return;
                }
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
                  _showCleanSnackBar(context,
                      'يجب تسجيل الدخول برقم الهاتف للوصول إلى السلة');
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
          controller: _otherOrdersScrollController,
          physics: const BouncingScrollPhysics(),
          children: [
            _buildStoreHoursStatusBar(appState, cardBg, textColor),
            _buildWasalliAndOtherOrdersRow(
                context, appState, appState.userProfile?['id'] ?? 'guest'),
            _buildCategoriesHorizontalList(appState, textColor, cardBg),
            _buildBreadcrumbBar(appState, cardBg, textColor),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withOpacity(0.35)),
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
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customItemNotesController,
                    style: TextStyle(color: textColor),
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'وصف الطلب للمندوب (اختياري)',
                        isDense: true),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    onPressed: () {
                      if (_customItemNameController.text.isNotEmpty &&
                          _customItemPriceController.text.isNotEmpty) {
                        final price =
                            double.tryParse(_customItemPriceController.text) ??
                                1000.0;
                        final nameText = _customItemNameController.text.trim();
                        final notesText =
                            _customItemNotesController.text.trim();
                        final combinedName = notesText.isNotEmpty
                            ? '$nameText — ملاحظة للمندوب: $notesText'
                            : nameText;
                        appState.addCustomOrderToCart(
                            customName: combinedName,
                            estimatedPrice: price);
                        _customItemNameController.clear();
                        _customItemPriceController.clear();
                        _customItemNotesController.clear();
                        FocusScope.of(context).unfocus();
                        _showCleanSnackBar(
                            context, 'تمت إضافة الطلب الخاص للسلة');
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

    final searchQuery = _debouncedSearchQuery;
    final bool hasActiveSearch = searchQuery.isNotEmpty;
    final bool isPharmacyDirect =
        _isPharmacyCategory(selectedCategory) && !hasActiveSearch;
    final bool isGiftSelected =
        _isGiftCategory(selectedCategory) && !hasActiveSearch;

    List filteredProducts = [];
    final bool isCategoryWithShops = selectedCategory == 'المطاعم' ||
        selectedCategory == 'حلويات ومعجنات' ||
        selectedCategory == 'هدايا واكسسوارات' ||
        selectedCategory == 'هدايا' ||
        selectedCategory == 'البقالات' ||
        selectedCategory == 'مشاريع منزلية' ||
        selectedCategory == 'المشاريع المنزلية';

    if (isPharmacyDirect) {
      filteredProducts = const [];
    } else if (isCategoryWithShops && selectedRestaurantName != null) {
      filteredProducts = appState.products.where((p) {
        final pCat = p.category.trim().toLowerCase();
        final sCat = selectedCategory.trim().toLowerCase();
        final matchesCategory = selectedCategory == 'الكل' ||
            pCat == sCat ||
            ((sCat == 'مشاريع منزلية' || sCat == 'المشاريع المنزلية') &&
                (pCat == 'مشاريع منزلية' || pCat == 'المشاريع المنزلية')) ||
            (_isGiftCategory(sCat) && _isGiftCategory(pCat));
        final matchesRestaurant =
            p.restaurantName.trim().toLowerCase() ==
                selectedRestaurantName!.trim().toLowerCase();
        final matchesSubCategory = selectedStoreSubCategory == 'الكل' ||
            p.subCategory.trim().toLowerCase() ==
                selectedStoreSubCategory.trim().toLowerCase();
        final matchesSearch = _matchesProductSearch(p, searchQuery);
        return matchesCategory &&
            matchesRestaurant &&
            matchesSubCategory &&
            matchesSearch;
      }).toList();
    } else if (!isCategoryWithShops ||
        selectedCategory == 'الكل' ||
        hasActiveSearch) {
      filteredProducts = appState.products.where((p) {
        if (_isPharmacyCategory(p.category) && !hasActiveSearch) {
          return false;
        }
        final matchesCategory = selectedCategory == 'الكل' ||
            hasActiveSearch ||
            p.category.trim().toLowerCase() ==
                selectedCategory.trim().toLowerCase();
        final matchesSearch = _matchesProductSearch(p, searchQuery);
        return matchesCategory && matchesSearch;
      }).toList();
    }

    return RefreshIndicator(
      color: accent,
      onRefresh: () async {
        setState(() {
          _promoBannersFuture = _fetchActivePromoBanners();
        });
        await Future.wait([
          appState.fetchStoreSettings(),
          appState.fetchRestaurantsAndCategories(),
          appState.fetchProductsFromSupabase(),
          _fetchCustomerRatingsSummaries(),
        ]);
      },
      child: ListView(
        controller: _shopScrollController,
        cacheExtent: 650,
        addAutomaticKeepAlives: false,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        children: [
          _buildStoreHoursStatusBar(appState, cardBg, textColor),
          _buildIntegratedSearchBar(appState, cardBg, textColor),
          _buildDynamicPromoBanners(appState),
          _buildWasalliAndOtherOrdersRow(
              context, appState, appState.userProfile?['id'] ?? 'guest'),
          _buildAdBannerWidget(appState, cardBg, textColor),
          _buildCategoriesHorizontalList(appState, textColor, cardBg),
          _buildBreadcrumbBar(appState, cardBg, textColor),
          if (_isInitialFetching && appState.products.isEmpty) ...[
            _buildLoadingGridSkeleton(cardBg, accent),
          ] else if (isPharmacyDirect) ...[
            _buildGiftOrPharmacyOrderForm(context, appState, cardBg, textColor),
          ] else if (isCategoryWithShops &&
              selectedRestaurantName == null &&
              !hasActiveSearch) ...[
            Builder(
              builder: (context) {
                final targetCat = selectedCategory.trim().toLowerCase();
                final isHomeProjCat = targetCat == 'مشاريع منزلية' ||
                    targetCat == 'المشاريع المنزلية';
                final isGiftCat = _isGiftCategory(targetCat);

                bool matchesTargetCategory(String rawCat) {
                  final c = rawCat.trim().toLowerCase();
                  if (isHomeProjCat) {
                    return c == 'مشاريع منزلية' ||
                        c == 'المشاريع المنزلية' ||
                        c == 'home_projects';
                  }
                  if (isGiftCat) {
                    return _isGiftCategory(c);
                  }
                  return c == targetCat;
                }

                final List<Map<String, dynamic>> dbStores = [];
                final Map<String, int> nameToIndex = {};
                void addOrEnrichStore(Map<String, dynamic> rawStore) {
                  final isActive = rawStore['is_active'] ?? true;
                  if (isActive == false) return;
                  final name = (rawStore['name'] ?? '').toString().trim();
                  if (name.isEmpty) return;
                  final key = name.toLowerCase();
                  final incomingLogo =
                      (rawStore['logo_url'] ?? rawStore['image_url'] ?? '')
                          .toString()
                          .trim();
                  if (!nameToIndex.containsKey(key)) {
                    nameToIndex[key] = dbStores.length;
                    dbStores.add({
                      ...rawStore,
                      'name': name,
                      'logo_url': incomingLogo,
                    });
                  } else {
                    final idx = nameToIndex[key]!;
                    final existingLogo =
                        (dbStores[idx]['logo_url'] ?? '').toString().trim();
                    if (existingLogo.isEmpty && incomingLogo.isNotEmpty) {
                      dbStores[idx]['logo_url'] = incomingLogo;
                    }
                  }
                }

                for (final r in appState.restaurantsList) {
                  final rCat = (r['category'] ?? r['type'] ?? '').toString();
                  if (matchesTargetCategory(rCat)) {
                    addOrEnrichStore(Map<String, dynamic>.from(r));
                  }
                }
                if (isHomeProjCat) {
                  for (final hp in appState.homeProjectsList) {
                    addOrEnrichStore(Map<String, dynamic>.from(hp));
                  }
                }
                for (final p in appState.products) {
                  if (matchesTargetCategory(p.category) &&
                      p.restaurantName.trim().isNotEmpty) {
                    addOrEnrichStore({
                      'name': p.restaurantName.trim(),
                      'logo_url': '',
                    });
                  }
                }
                if (isGiftCat) {
                  for (final defaultGiftStore in [
                    'شغف',
                    'فلاورز',
                    'دار التحف والهدايا',
                    'قصر التحف والهدايا',
                  ]) {
                    addOrEnrichStore({
                      'name': defaultGiftStore,
                      'logo_url': '',
                    });
                  }
                }

                final categoryStores = dbStores;
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
                          horizontal: 8, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            isGiftCat
                                ? Icons.card_giftcard
                                : (isHomeProjCat
                                    ? Icons.home_work
                                    : Icons.storefront),
                            color: accent,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isGiftCat
                                ? 'اختر متجر الهدايا والإكسسوارات'
                                : (isHomeProjCat
                                    ? 'اختر مشروعاً منزلياً'
                                    : 'اختر متجراً'),
                            style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 1.25,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: categoryStores.length,
                      itemBuilder: (context, index) {
                        final store = categoryStores[index];
                        final storeName = store['name']?.toString() ?? 'متجر';
                        final logoUrl = (store['logo_url'] ??
                                store['image_url'] ??
                                '')
                            .toString()
                            .trim();
                        final double? storeRating = _resolveStoreRating(
                            appState, storeName,
                            storeMap: store);
                        final bool isStoreOpenNow = appState.isStoreOpen;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              selectedRestaurantName = storeName;
                              selectedStoreSubCategory = 'الكل';
                            });
                            scrollHomeToTop(animated: true);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: accent.withOpacity(0.4), width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Stack(
                              children: [
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (isStoreOpenNow
                                              ? Colors.green
                                              : Colors.redAccent)
                                          .withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isStoreOpenNow ? 'متاح' : 'مغلق',
                                      style: TextStyle(
                                        color: isStoreOpenNow
                                            ? Colors.green
                                            : Colors.redAccent,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundColor:
                                            accent.withOpacity(0.18),
                                        backgroundImage: logoUrl.isNotEmpty
                                            ? CachedNetworkImageProvider(
                                                logoUrl)
                                            : null,
                                        onBackgroundImageError:
                                            logoUrl.isNotEmpty
                                                ? (_, __) {}
                                                : null,
                                        child: logoUrl.isEmpty
                                            ? Icon(
                                                isGiftCat
                                                    ? Icons.card_giftcard
                                                    : (isHomeProjCat
                                                        ? Icons.home_work
                                                        : Icons.store),
                                                color: accent,
                                                size: 22)
                                            : null,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        storeName,
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12.5),
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.star_rounded,
                                              size: 13,
                                              color: appState.isDarkMode
                                                  ? Colors.amber
                                                  : Colors.amber.shade700),
                                          const SizedBox(width: 2),
                                          Text(
                                            storeRating != null
                                                ? storeRating.toStringAsFixed(1)
                                                : 'جديد',
                                            style: TextStyle(
                                                color:
                                                    textColor.withOpacity(0.85),
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ] else ...[
            if (isCategoryWithShops && selectedRestaurantName != null) ...[
              Builder(
                builder: (context) {
                  final double? activeStoreRating = _resolveStoreRating(
                      appState, selectedRestaurantName!);
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                    isGiftSelected
                                        ? 'متجر: $selectedRestaurantName'
                                        : 'منتجات: $selectedRestaurantName',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5)),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accent.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.star_rounded,
                                        size: 13,
                                        color: appState.isDarkMode
                                            ? Colors.amber
                                            : Colors.amber.shade700),
                                    const SizedBox(width: 2),
                                    Text(
                                      activeStoreRating != null
                                          ? activeStoreRating.toStringAsFixed(1)
                                          : 'جديد',
                                      style: TextStyle(
                                          color: accent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              selectedRestaurantName = null;
                              selectedStoreSubCategory = 'الكل';
                            });
                            scrollHomeToTop(animated: true);
                          },
                          icon: Icon(Icons.swap_horiz, size: 16, color: accent),
                          label: Text('تغيير المتجر',
                              style: TextStyle(color: accent, fontSize: 12)),
                        ),
                      ],
                    ),
                  );
                },
              ),
              if (isGiftSelected)
                _buildGiftOrPharmacyOrderForm(
                    context, appState, cardBg, textColor),
              Builder(
                builder: (context) {
                  final storeSubCategories = appState.getSubCategoriesForStore(
                    selectedRestaurantName!,
                    category: selectedCategory,
                  );
                  if (storeSubCategories.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final chips = ['الكل', ...storeSubCategories];
                  return SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      itemCount: chips.length,
                      itemBuilder: (context, idx) {
                        final sectionName = chips[idx];
                        final isSelected =
                            selectedStoreSubCategory == sectionName;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(
                              sectionName,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? (appState.isDarkMode
                                        ? Colors.black
                                        : Colors.white)
                                    : textColor,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: accent,
                            backgroundColor: cardBg,
                            onSelected: (_) {
                              HapticFeedback.selectionClick();
                              setState(() {
                                selectedStoreSubCategory = sectionName;
                              });
                              scrollHomeToTop(animated: true);
                            },
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ],
            if (filteredProducts.isEmpty && !isGiftSelected)
              const Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(
                    child: Text('لا توجد منتجات مطابقة',
                        style: TextStyle(color: Colors.grey, fontSize: 13))),
              )
            else if (filteredProducts.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                cacheExtent: 650,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                physics: const NeverScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.72,
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
                  final pKey = product.id.trim().toLowerCase();
                  final double? pRating = _productAvgRatings[pKey];
                  final int pCount = _productRatingCounts[pKey] ?? 0;
                  return RepaintBoundary(
                    child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        if (isVariable) {
                          _showEnterPriceDialog(context, appState, product);
                        } else {
                          _handleProductTapOrAdd(context, appState, product);
                        }
                      },
                      child: Ink(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: accent.withOpacity(0.35)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.12),
                              blurRadius: 6,
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
                                      borderRadius:
                                          BorderRadius.circular(10),
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
                                                              strokeWidth:
                                                                  2)),
                                              errorWidget: (context, url,
                                                      error) =>
                                                  Container(
                                                color:
                                                    accent.withOpacity(0.1),
                                                child: Icon(Icons.fastfood,
                                                    color: accent,
                                                    size: 32),
                                              ),
                                            )
                                          : Container(
                                              width: double.infinity,
                                              color:
                                                  accent.withOpacity(0.15),
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
                                        _showCleanSnackBar(
                                          context,
                                          !isFav
                                              ? 'تمت إضافة ${product.name} إلى المفضلة'
                                              : 'تمت إزالة ${product.name} من المفضلة',
                                          duration:
                                              const Duration(milliseconds: 800),
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: BoxDecoration(
                                          color:
                                              Colors.black.withOpacity(0.55),
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
                            if (pRating != null) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(Icons.star_rounded,
                                      size: 14,
                                      color: appState.isDarkMode
                                          ? Colors.amber
                                          : Colors.amber.shade700),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${pRating.toStringAsFixed(1)} ($pCount)',
                                    style: TextStyle(
                                      color: textColor.withOpacity(0.85),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
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
                                    height: 36,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: accent,
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                      onPressed: () =>
                                          _showEnterPriceDialog(
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
                                        height: 36,
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: accent,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        10)),
                                          ),
                                          onPressed: () =>
                                              _handleProductTapOrAdd(
                                                  context,
                                                  appState,
                                                  product),
                                          child: Text('إضافة',
                                              style: TextStyle(
                                                  color: appState.isDarkMode
                                                      ? Colors.black
                                                      : Colors.white,
                                                  fontSize: 12,
                                                  fontWeight:
                                                      FontWeight.bold)),
                                        ),
                                      )
                                    : Container(
                                        height: 36,
                                        decoration: BoxDecoration(
                                            color: accent,
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceAround,
                                          children: [
                                            InkWell(
                                                onTap: () {
                                                  HapticFeedback
                                                      .selectionClick();
                                                  appState.updateQuantity(
                                                      product.id, -1);
                                                },
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(
                                                          6.0),
                                                  child: Icon(Icons.remove,
                                                      size: 16,
                                                      color: appState
                                                              .isDarkMode
                                                          ? Colors.black
                                                          : Colors.white),
                                                )),
                                            Text('$qtyInCart',
                                                style: TextStyle(
                                                    color:
                                                        appState.isDarkMode
                                                            ? Colors.black
                                                            : Colors.white,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 13)),
                                            InkWell(
                                                onTap: () {
                                                  HapticFeedback
                                                      .selectionClick();
                                                  appState.updateQuantity(
                                                      product.id, 1);
                                                },
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(
                                                          6.0),
                                                  child: Icon(Icons.add,
                                                      size: 16,
                                                      color: appState
                                                              .isDarkMode
                                                          ? Colors.black
                                                          : Colors.white),
                                                )),
                                          ],
                                        ),
                                      )),
                          ],
                        ),
                      ),
                    ),
                  ),
                  );
                },
              ),
          ],
          const SizedBox(height: 64),
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
              physics: const BouncingScrollPhysics(),
              itemCount: appState.cartItems.length,
              itemBuilder: (context, index) {
                final CartItemModel item = appState.cartItems[index];
                return Card(
                  color: cardBg,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
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
                  _showCleanSnackBar(context,
                      'تم نسخ رقم حاسب الكريمي (2655872) بنجاح');
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
                    _resetToHomeView(clearSearch: true, animateScroll: true);
                  },
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
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
                                              '''فاتورة تطبيق FAST - تعز
رقم الطلب: #${order['id']}
المنتجات: ${order['items_desc'] ?? order['items_description']}
العنوان: $formattedAddress
سعر المنتجات: ${finalProductsPrice.toStringAsFixed(0)} ر.ي
رسوم التوصيل: ${deliveryFee.toStringAsFixed(0)} ر.ي
الإجمالي الكلي: ${grandTotal.toStringAsFixed(0)} ر.ي
الحالة: $arabicStatus''';
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
                                                _showCleanSnackBar(context,
                                                    'تم تأكيد الطلب وإرساله للمندوب بنجاح!');
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
                                                _showCleanSnackBar(context,
                                                    'تم رفض الطلب وإلغاؤه');
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
      physics: const BouncingScrollPhysics(),
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
        if (profile != null) ...[
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
        ],
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
          _showCleanSnackBar(
              context, 'تطبيق FAST مخصص لخدمة مدينة تعز بكل سرعة');
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
