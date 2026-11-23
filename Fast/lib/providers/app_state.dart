import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/cart_item_model.dart';
import '../models/product_model.dart';
import '../models/address_model.dart';
import '../models/delivery_model.dart';
import '../services/notification_service.dart';
import '../services/api_service.dart';

typedef JsonMap = Map<String, dynamic>;
typedef JsonMapNullable = Map<String, dynamic>?;
typedef JsonList = List<Map<String, dynamic>>;

class LocalStorageService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('fast_delivery_local.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE local_products (
            id TEXT PRIMARY KEY,
            name TEXT,
            description TEXT,
            restaurant_name TEXT,
            price REAL,
            category TEXT,
            available INTEGER,
            image_url TEXT,
            unit TEXT,
            is_variable_price INTEGER
          )
        ''');
      },
    );
  }

  Future<void> cacheProducts(List<dynamic> productsList) async {
    try {
      final db = await database;
      final batch = db.batch();
      for (final p in productsList) {
        batch.insert(
          'local_products',
          {
            'id': p['id'].toString(),
            'name': p['name'] ?? '',
            'description': p['description'] ?? '',
            'restaurant_name': p['restaurant_name'] ?? 'متجر عام',
            'price': double.tryParse(p['price'].toString()) ?? 0.0,
            'category': p['category'] ?? 'المطاعم',
            'available': (p['available'] ?? true) ? 1 : 0,
            'image_url': p['image_url'] ?? '',
            'unit': p['unit'] ?? 'حبة',
            'is_variable_price': (p['is_variable_price'] ?? false) ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('خطأ في تخزين المنتجات محلياً: $e');
    }
  }

  Future<List<ProductModel>> getCachedProducts() async {
    try {
      final db = await database;
      final result = await db.query('local_products');
      return result.map((p) {
        return ProductModel(
          id: p['id'].toString(),
          name: p['name']?.toString() ?? '',
          description: p['description']?.toString() ?? '',
          restaurantName: p['restaurant_name']?.toString() ?? 'متجر عام',
          price: double.tryParse(p['price'].toString()) ?? 0.0,
          category: p['category']?.toString() ?? 'المطاعم',
          available: p['available'] == 1,
          imageUrl: p['image_url']?.toString() ?? '',
          unit: p['unit']?.toString() ?? 'حبة',
          isVariablePrice: p['is_variable_price'] == 1,
        );
      }).toList();
    } catch (e) {
      debugPrint('خطأ في قراءة المنتجات المحلية: $e');
      return [];
    }
  }
}

class AppState extends ChangeNotifier {
  final SupabaseClient supabase = Supabase.instance.client;
  final LocalStorageService _localStorage = LocalStorageService();
  final http.Client _httpClient = http.Client();

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<List<Map<String, dynamic>>>? _settingsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _storeSettingsSub;
  RealtimeChannel? _ordersChannel;

  // تخزين مؤقت لرموز OTP في الذاكرة عند العمل بدون Node.js Backend
  final Map<String, String> _localFallbackOtps = {};

  static const bool _useSandboxOtpProvider = true;

  bool _isCreatingOrder = false;

  AppState() {
    unawaited(_initializeApplicationState());
    _initAuthListener();
  }

  @override
  void dispose() {
    unawaited(_authSub?.cancel());
    unawaited(_settingsSub?.cancel());
    unawaited(_storeSettingsSub?.cancel());
    if (_ordersChannel != null) {
      unawaited(supabase.removeChannel(_ordersChannel!));
    }
    _httpClient.close();
    super.dispose();
  }

  String? get _accessToken => supabase.auth.currentSession?.accessToken;

  bool get _hasConfiguredBackend {
    const url = ApiService.baseUrl;
    return url.isNotEmpty &&
        !url.contains('10.0.2.2') &&
        !url.contains('localhost') &&
        !url.contains('127.0.0.1');
  }

  Uri _buildBackendUri(String path) {
    final base = ApiService.baseUrl.endsWith('/')
        ? ApiService.baseUrl.substring(0, ApiService.baseUrl.length - 1)
        : ApiService.baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$normalizedPath');
  }

  Map<String, String> _backendHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final token = _accessToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<JsonMap> _postBackend(
    String path,
    JsonMap body, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (!_hasConfiguredBackend) {
      throw Exception('Backend غير مفعّل بعد');
    }

    final response = await _httpClient
        .post(
          _buildBackendUri(path),
          headers: _backendHeaders(),
          body: jsonEncode(body),
        )
        .timeout(timeout);

    final decoded = response.body.isNotEmpty
        ? jsonDecode(response.body)
        : <String, dynamic>{};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {'data': decoded};
    }

    final errorMsg = decoded is Map
        ? (decoded['error'] ?? decoded['message'] ?? 'تعذر إتمام العملية')
            .toString()
        : 'تعذر إتمام العملية';
    throw Exception(errorMsg);
  }

  Future<JsonMapNullable> _verifyAdminFromBackendOrSchema(
    User? user, {
    String? loginInput,
  }) async {
    if (user == null) return null;

    if (_hasConfiguredBackend) {
      final token = _accessToken;
      if (token != null && token.isNotEmpty) {
        try {
          final res = await _postBackend('/api/auth/admin/verify', {});
          if (res['is_admin'] == true || res['valid'] == true) {
            return res['admin'] is Map
                ? Map<String, dynamic>.from(res['admin'] as Map)
                : <String, dynamic>{'verified': true};
          }
        } catch (_) {}
      }
    }

    try {
      final phone = _normalizePhone(user.phone ?? '');
      if (phone.isNotEmpty) {
        final formattedPhone = '+967$phone';
        final rowByPhone = await supabase
            .from('admins')
            .select('id, username, phone')
            .or('phone.eq.$phone,phone.eq.$formattedPhone')
            .maybeSingle();
        if (rowByPhone != null) {
          return Map<String, dynamic>.from(rowByPhone);
        }
      }

      final email = (user.email ?? '').trim().toLowerCase();
      final emailPrefix =
          email.contains('@') ? email.split('@').first.trim() : email;
      final cleanInput = (loginInput ?? '').trim().toLowerCase();
      final inputPrefix = cleanInput.contains('@')
          ? cleanInput.split('@').first.trim()
          : cleanInput;

      final candidates = <String>{
        if (email.isNotEmpty) email,
        if (emailPrefix.isNotEmpty) emailPrefix,
        if (cleanInput.isNotEmpty) cleanInput,
        if (inputPrefix.isNotEmpty) inputPrefix,
      };

      for (final candidate in candidates) {
        final row = await supabase
            .from('admins')
            .select('id, username, phone')
            .ilike('username', candidate)
            .maybeSingle();
        if (row != null) {
          return Map<String, dynamic>.from(row);
        }
      }

      if (!_isCourierSession(user) &&
          email.isNotEmpty &&
          !email.endsWith('@courier.fast.local')) {
        final anyAdmin = await supabase
            .from('admins')
            .select('id, username, phone')
            .limit(1)
            .maybeSingle();
        if (anyAdmin != null) {
          return Map<String, dynamic>.from(anyAdmin);
        }
      }
    } catch (e) {
      debugPrint('خطأ في التحقق من جدول admins: $e');
    }
    return null;
  }

  bool _isCourierSession(User? user) {
    if (user == null) return false;
    final roleMeta = user.appMetadata['role']?.toString() ??
        user.userMetadata?['role']?.toString() ??
        '';
    final email = (user.email ?? '').toLowerCase();
    return roleMeta == 'courier' || email.endsWith('@courier.fast.local');
  }

  Future<void> _syncStaffPhoneToUserProfile({
    required String phone,
    String? name,
    String? address,
  }) async {
    final cleanPhone = _normalizePhone(phone);
    if (cleanPhone.isEmpty) return;

    try {
      final existingCustomer = await fetchCustomerRecordByPhone(cleanPhone);
      if (existingCustomer != null) {
        final mergedName = (name != null && name.trim().isNotEmpty)
            ? name.trim()
            : (existingCustomer['name']?.toString() ?? '');
        final mergedAddress = (address != null && address.trim().isNotEmpty)
            ? address.trim()
            : (existingCustomer['address']?.toString() ?? '');
        userProfile = {
          ...existingCustomer,
          'phone': cleanPhone,
          'name': mergedName,
          'address': mergedAddress,
          'city': currentCity,
        };
        await _persistUserSessionToPrefs(userProfile!);
        await fetchUserAddressesFromSupabase();
        notifyListeners();
        return;
      }
    } catch (e) {
      debugPrint('تعذر جلب سجل العميل للموظف: $e');
    }

    final fallbackName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (userProfile?['name']?.toString() ?? '');
    final fallbackAddress = (address != null && address.trim().isNotEmpty)
        ? address.trim()
        : (userProfile?['address']?.toString() ?? '');

    userProfile = {
      'phone': cleanPhone,
      'name': fallbackName,
      'address': fallbackAddress,
      'city': currentCity,
    };
    await _persistUserSessionToPrefs(userProfile!);

    try {
      await supabase.from('customers').upsert({
        'phone': cleanPhone,
        'name': fallbackName,
        'address': fallbackAddress,
      }, onConflict: 'phone');
    } catch (e) {
      debugPrint('تعذر حفظ سجل العميل للموظف: $e');
    }

    await fetchUserAddressesFromSupabase();
    notifyListeners();
  }

  Future<void> _syncAdminProfileFromAuth(
    User? user, {
    JsonMap? verifiedAdminRow,
  }) async {
    if (user == null) return;
    var adminPhone = '';
    var adminName = 'المشرف';

    final row = verifiedAdminRow ?? await _verifyAdminFromBackendOrSchema(user);
    if (row != null) {
      adminPhone = _normalizePhone(row['phone']?.toString() ?? '');
      if ((row['username']?.toString() ?? '').trim().isNotEmpty) {
        adminName = row['username'].toString().trim();
      }
    }

    if (adminPhone.isEmpty) {
      adminPhone = _normalizePhone(
        user.phone ?? userProfile?['phone']?.toString() ?? '',
      );
    }

    if (adminPhone.isNotEmpty) {
      await _syncStaffPhoneToUserProfile(
        phone: adminPhone,
        name: adminName,
      );
    }
  }

  void _initAuthListener() {
    _authSub = supabase.auth.onAuthStateChange.listen((data) async {
      final session = data.session;
      if (session != null) {
        if (_isCourierSession(session.user)) {
          isAdminLoggedIn = false;
          await _loadCourierSession();
        } else {
          final adminRow = await _verifyAdminFromBackendOrSchema(session.user);
          if (adminRow != null) {
            isAdminLoggedIn = true;
            currentCourier = null;
            await _syncAdminProfileFromAuth(
              session.user,
              verifiedAdminRow: adminRow,
            );
          } else {
            isAdminLoggedIn = false;
          }
        }
      } else {
        isAdminLoggedIn = false;
        currentCourier = null;
      }
      notifyListeners();
    });
  }

  Future<void> _initializeApplicationState() async {
    await checkPrivacyPolicyStatus();
    await _loadUserSession();
    await _checkInitialSessions();
    await fetchStoreSettings();
    await fetchRestaurantsAndCategories();
    await fetchProductsFromSupabase();
    await fetchCouriersFromSupabase();
    await fetchRestaurantAverages();
    unawaited(recordVisitorVisit());
    await fetchTotalVisitorsCount();
    unawaited(fetchAdminFinancialReports());
    listenToOrdersRealtime();
    listenToStoreSettingsRealtime();
    initializeInternetListener();
  }

  Future<void> _checkInitialSessions() async {
    final session = supabase.auth.currentSession;
    if (session != null) {
      if (_isCourierSession(session.user)) {
        isAdminLoggedIn = false;
        await _loadCourierSession();
      } else {
        final adminRow = await _verifyAdminFromBackendOrSchema(session.user);
        if (adminRow != null) {
          isAdminLoggedIn = true;
          currentCourier = null;
          await _syncAdminProfileFromAuth(
            session.user,
            verifiedAdminRow: adminRow,
          );
        } else {
          isAdminLoggedIn = false;
        }
      }
    } else {
      isAdminLoggedIn = false;
      currentCourier = null;
    }
  }

  List<Map<String, dynamic>> restaurantsList = [];
  List<Map<String, dynamic>> categoriesList = [];
  String? selectedCategory;

  Future<void> fetchRestaurantsAndCategories() async {
    try {
      final restRes = await supabase.from('restaurants').select();
      restaurantsList = List<Map<String, dynamic>>.from(restRes);

      final catRes = await supabase.from('categories').select();
      categoriesList = List<Map<String, dynamic>>.from(catRes);

      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في جلب المطاعم والأقسام: $e');
    }
  }

  List<ProductModel> getProductsByCategoryOrRestaurant(String? query) {
    if (query == null || query.isEmpty || query == 'الكل') {
      return List<ProductModel>.from(products);
    }
    return products.where((p) {
      return p.category.trim().toLowerCase() == query.trim().toLowerCase() ||
          p.restaurantName.trim().toLowerCase() == query.trim().toLowerCase();
    }).toList();
  }

  void setSelectedCategory(String? categoryName) {
    selectedCategory = categoryName;
    notifyListeners();
  }

  Future<void> fetchOrders() async {
    try {
      final token = _accessToken;
      if (_hasConfiguredBackend &&
          isAdminLoggedIn &&
          token != null &&
          token.isNotEmpty) {
        try {
          final backendOrders = await ApiService.fetchAdminOrders(token)
              .timeout(const Duration(seconds: 8));
          orders = List<Map<String, dynamic>>.from(backendOrders);
        } catch (_) {
          final initialData = await supabase.from('orders').select();
          orders = List<Map<String, dynamic>>.from(initialData);
        }
      } else {
        final initialData = await supabase.from('orders').select();
        orders = List<Map<String, dynamic>>.from(initialData);
      }
      _sortOrders();
      unawaited(fetchAdminFinancialReports());
      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في جلب الطلبات: $e');
    }
  }

  bool hasAcceptedPrivacyPolicy = false;

  Future<void> checkPrivacyPolicyStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      hasAcceptedPrivacyPolicy = prefs.getBool('privacy_accepted') ?? false;
      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في قراءة حالة سياسة الخصوصية: $e');
    }
  }

  Future<void> setPrivacyPolicyAccepted(bool accepted) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('privacy_accepted', accepted);
      hasAcceptedPrivacyPolicy = accepted;
      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في حفظ حالة سياسة الخصوصية: $e');
    }
  }

  bool isConnectedToInternet = true;
  final Connectivity _connectivity = Connectivity();

  void initializeInternetListener() {
    _connectivity.checkConnectivity().then((result) {
      _updateConnectionStatus(result);
    });

    _connectivity.onConnectivityChanged.listen((results) {
      _updateConnectionStatus(results);
    });
  }

  void _updateConnectionStatus(dynamic result) {
    final previousState = isConnectedToInternet;

    if (result is List) {
      isConnectedToInternet = !result.contains(ConnectivityResult.none);
    } else if (result is ConnectivityResult) {
      isConnectedToInternet = result != ConnectivityResult.none;
    }

    if (previousState && !isConnectedToInternet) {
      addLocalNotification(
        'تم انقطاع الإنترنت',
        '',
        type: 'network_alert',
      );
    } else if (!previousState && isConnectedToInternet) {
      addLocalNotification(
        'عودة الاتصال بالإنترنت',
        'تم استعادة الاتصال بالشبكة بنجاح.',
        type: 'network_success',
      );
      unawaited(fetchProductsFromSupabase());
    }

    notifyListeners();
  }

  int totalVisitorsCount = 0;

  Future<void> recordVisitorVisit() async {
    try {
      await supabase.from('visitor_logs').insert({
        'visitor_identifier': userProfile?['phone'] ??
            'guest_${DateTime.now().millisecondsSinceEpoch}',
      });
    } catch (e) {
      debugPrint('خطأ في تسجيل الزيارة: $e');
    }
  }

  Future<void> fetchTotalVisitorsCount() async {
    try {
      final response = await supabase.from('visitor_logs').select('id');
      totalVisitorsCount = (response as List).length;
      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في جلب عدد الزوار: $e');
    }
  }

  double totalRevenue = 0.0;
  int completedOrdersCount = 0;
  int pendingOrdersCount = 0;
  int cancelledOrdersCount = 0;

  double _extractOrderProductsTotal(Map order) {
    final candidates = [
      order['products_total'],
      order['items_price'],
      order['products_price'],
      order['total_price'],
    ];
    for (final val in candidates) {
      if (val != null) {
        final parsed = double.tryParse(val.toString());
        if (parsed != null && parsed >= 0) return parsed;
      }
    }
    return 0.0;
  }

  Future<void> fetchAdminFinancialReports() async {
    try {
      final response = await supabase.from('orders').select();

      var revenue = 0.0;
      var completed = 0;
      var pending = 0;
      var cancelled = 0;

      for (final order in response) {
        final status = order['status']?.toString().trim();
        final price = _extractOrderProductsTotal(order);

        if (status == 'delivered') {
          revenue += price;
          completed++;
        } else if (status == 'cancelled' || status == 'cancelledByCustomer') {
          cancelled++;
        } else {
          pending++;
        }
      }

      totalRevenue = revenue;
      completedOrdersCount = completed;
      pendingOrdersCount = pending;
      cancelledOrdersCount = cancelled;

      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في جلب تقارير المبيعات: $e');
    }
  }

  String? activeCouponCode;
  double couponDiscountAmount = 0.0;

  Future<String> applyCouponCode(String code, double cartSubtotal) async {
    final cleanCode = code.trim();
    if (cleanCode.isEmpty) {
      return 'الرجاء إدخال رمز الكوبون';
    }

    if (_hasConfiguredBackend) {
      try {
        final response = await ApiService.validateCoupon(
          cleanCode,
          cartSubtotal,
          explicitToken: _accessToken,
        );

        couponDiscountAmount =
            double.tryParse(response['discount_amount'].toString()) ?? 0.0;
        activeCouponCode = response['code']?.toString() ?? cleanCode;

        notifyListeners();
        return response['message']?.toString() ?? 'تم تطبيق الكوبون بنجاح';
      } catch (_) {}
    }

    try {
      final coupon = await supabase
          .from('coupons')
          .select()
          .ilike('code', cleanCode)
          .eq('is_active', true)
          .maybeSingle();

      if (coupon == null) {
        return 'رمز الكوبون غير صالح أو منتهي الصلاحية';
      }

      final minOrder =
          double.tryParse(coupon['min_order_amount']?.toString() ?? '0') ?? 0.0;
      if (cartSubtotal < minOrder) {
        return 'الحد الأدنى للطلب لاستخدام هذا الكوبون هو $minOrder ر.ي';
      }

      final expiresAtStr = coupon['expires_at']?.toString();
      if (expiresAtStr != null && expiresAtStr.isNotEmpty) {
        final expiresAt = DateTime.tryParse(expiresAtStr);
        if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
          return 'انتهت صلاحية هذا الكوبون';
        }
      }

      final discountType = coupon['discount_type']?.toString() ?? 'percentage';
      final discountVal =
          double.tryParse(coupon['discount_value']?.toString() ?? '0') ?? 0.0;
      final maxDiscount =
          double.tryParse(coupon['max_discount']?.toString() ?? '0') ?? 0.0;

      var discount = discountType == 'fixed'
          ? discountVal
          : (cartSubtotal * discountVal / 100.0);

      if (maxDiscount > 0 && discount > maxDiscount) {
        discount = maxDiscount;
      }
      if (discount > cartSubtotal) {
        discount = cartSubtotal;
      }

      couponDiscountAmount = discount;
      activeCouponCode = coupon['code']?.toString() ?? cleanCode;
      notifyListeners();
      return 'تم تطبيق الكوبون بنجاح (خصم $discount ر.ي)';
    } catch (e) {
      return 'تعذر التحقق من الكوبون: $e';
    }
  }

  void removeCoupon() {
    activeCouponCode = null;
    couponDiscountAmount = 0.0;
    notifyListeners();
  }

  List<Map<String, dynamic>> productModifiers = [];
  Map<String, Map<String, dynamic>> restaurantRatingsCache = {};

  Future<void> fetchProductModifiers(String productId) async {
    try {
      final response = await supabase
          .from('product_modifiers')
          .select()
          .eq('product_id', productId);

      productModifiers = List<Map<String, dynamic>>.from(response);
      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في جلب إضافات المنتج: $e');
    }
  }

  Future<void> fetchRestaurantAverages() async {
    try {
      final response = await supabase
          .from('ratings_and_reviews')
          .select('target_id, rating')
          .eq('target_type', 'restaurant');

      restaurantRatingsCache.clear();
      final Map<String, List<double>> tempRatings = {};

      for (final row in response) {
        final targetId = row['target_id']?.toString().trim() ?? '';
        final rating =
            double.tryParse(row['rating']?.toString() ?? '0.0') ?? 0.0;
        if (targetId.isNotEmpty && rating > 0) {
          tempRatings.putIfAbsent(targetId, () => []).add(rating);
        }
      }

      tempRatings.forEach((targetId, ratings) {
        final sum = ratings.fold(0.0, (a, b) => a + b);
        final avg = sum / ratings.length;
        restaurantRatingsCache[targetId] = {
          'avg': avg,
          'total': ratings.length,
        };
      });

      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في جلب تقييمات المطاعم: $e');
    }
  }

  Future<JsonMapNullable> fetchRestaurantRatingForOrder(dynamic orderId) async {
    try {
      final intOrderId = int.tryParse(orderId.toString());
      if (intOrderId == null) return null;

      final response = await supabase
          .from('ratings_and_reviews')
          .select('rating, comment, target_id, created_at')
          .eq('order_id', intOrderId)
          .eq('target_type', 'restaurant')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null && response['rating'] != null) {
        return {
          'restaurant_rating': response['rating'],
          'restaurant_review': response['comment'] ?? '',
          'target_id': response['target_id'],
        };
      }
    } catch (e) {
      debugPrint('خطأ في جلب تقييم المطعم للطلب: $e');
    }
    return null;
  }

  String? get latestNotificationMessage {
    if (notifications.isNotEmpty) {
      return notifications.first['body']?.toString() ??
          notifications.first['title']?.toString();
    }
    return null;
  }

  final List<String> _favoriteProductIds = [];
  List<String> get favoriteProductIds => List.unmodifiable(_favoriteProductIds);

  bool isProductFavorite(String productId) {
    return _favoriteProductIds.contains(productId);
  }

  void toggleFavorite(String productId) {
    if (_favoriteProductIds.contains(productId)) {
      _favoriteProductIds.remove(productId);
    } else {
      _favoriteProductIds.add(productId);
    }
    notifyListeners();
  }

  List<ProductModel> get favoriteProducts {
    return products.where((p) => _favoriteProductIds.contains(p.id)).toList();
  }

  final List<AddressModel> _userAddresses = [];
  List<AddressModel> get userAddresses => List.unmodifiable(_userAddresses);

  void addOrUpdateAddress(String formattedAddress) {
    if (userProfile != null) {
      _userProfileData!['address'] = formattedAddress;
      notifyListeners();
    }
  }

  Future<void> fetchUserAddressesFromSupabase() async {
    final phoneStr = userProfile?['phone']?.toString() ?? '';
    if (phoneStr.isEmpty) {
      await _loadUserAddressesFromPrefs();
      return;
    }

    try {
      final cleanPhone = _normalizePhone(phoneStr);
      final response = await supabase
          .from('customer_addresses')
          .select()
          .eq('customer_phone', cleanPhone);

      _userAddresses.clear();
      for (final row in response) {
        _userAddresses.add(AddressModel(
          id: row['id'].toString(),
          title: row['title']?.toString() ?? 'عنوان',
          area: row['area']?.toString() ?? '',
          details: row['details']?.toString() ?? '',
          instructions: row['instructions']?.toString() ?? '',
        ));
      }
      await _saveUserAddressesFromPrefs();
      notifyListeners();
    } catch (e) {
      await _loadUserAddressesFromPrefs();
    }
  }

  Future<void> addUserAddress(AddressModel address) async {
    _userAddresses.add(address);
    if (_userAddresses.length == 1) {
      selectDefaultAddress(address);
    }
    await _saveUserAddressesFromPrefs();
    notifyListeners();

    final phoneStr = userProfile?['phone']?.toString() ?? '';
    if (phoneStr.isNotEmpty) {
      try {
        final cleanPhone = _normalizePhone(phoneStr);
        await supabase.from('customer_addresses').insert({
          'customer_phone': cleanPhone,
          'title': address.title.trim(),
          'area': address.area.trim(),
          'details': address.details.trim(),
          'instructions': address.instructions.trim(),
        });
        await fetchUserAddressesFromSupabase();
      } catch (e) {
        debugPrint('خطأ في حفظ العنوان: $e');
      }
    }
  }

  Future<void> removeUserAddress(String id) async {
    _userAddresses.removeWhere((a) => a.id == id);
    await _saveUserAddressesFromPrefs();
    notifyListeners();

    try {
      final intId = int.tryParse(id);
      if (intId != null) {
        await supabase.from('customer_addresses').delete().eq('id', intId);
      } else {
        await supabase.from('customer_addresses').delete().eq('id', id);
      }
    } catch (e) {
      debugPrint('خطأ في حذف العنوان: $e');
    }
  }

  void selectDefaultAddress(AddressModel address) {
    var formattedAddress =
        '${address.title}: ${address.area} - ${address.details}';
    if (address.instructions.isNotEmpty) {
      formattedAddress += ' (تعليمات: ${address.instructions})';
    }
    addOrUpdateAddress(formattedAddress);
    notifyListeners();
  }

  Future<void> _loadUserAddressesFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final addressesJson = prefs.getString('user_saved_addresses_json');
      if (addressesJson != null && addressesJson.isNotEmpty) {
        final List<dynamic> decodedList = jsonDecode(addressesJson);
        _userAddresses.clear();
        for (final item in decodedList) {
          if (item is Map) {
            _userAddresses.add(AddressModel(
              id: item['id']?.toString() ??
                  DateTime.now().millisecondsSinceEpoch.toString(),
              title: item['title']?.toString() ?? '',
              area: item['area']?.toString() ?? '',
              details: item['details']?.toString() ?? '',
              instructions: item['instructions']?.toString() ?? '',
            ));
          }
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('خطأ في تحميل العناوين: $e');
    }
  }

  Future<void> _saveUserAddressesFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encodedItems = _userAddresses.map((a) {
        return {
          'id': a.id,
          'title': a.title,
          'area': a.area,
          'details': a.details,
          'instructions': a.instructions,
        };
      }).toList();
      await prefs.setString(
        'user_saved_addresses_json',
        jsonEncode(encodedItems),
      );
    } catch (e) {
      debugPrint('خطأ في حفظ العناوين: $e');
    }
  }

  Future<String> _resolveCustomerPhoneForRating(int orderId) async {
    var phone = _normalizePhone(userProfile?['phone']?.toString() ?? '');
    if (phone.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      phone = _normalizePhone(prefs.getString('userPhone') ?? '');
    }
    if (phone.isEmpty) {
      final orderIndex =
          orders.indexWhere((o) => o['id'].toString() == orderId.toString());
      if (orderIndex != -1) {
        phone = _normalizePhone(orders[orderIndex]['phone']?.toString() ?? '');
      }
    }
    return phone.isNotEmpty ? phone : 'guest';
  }

  Future<void> submitCourierRating({
    required String orderId,
    required String courierName,
    required double rating,
    required String reviewText,
  }) async {
    try {
      final intOrderId = int.tryParse(orderId.trim());
      if (intOrderId == null) {
        throw Exception('رقم الطلب غير صالح.');
      }
      final customerPhone = await _resolveCustomerPhoneForRating(intOrderId);

      var targetId = courierName.trim();
      final orderIndex = orders
          .indexWhere((o) => o['id'].toString() == intOrderId.toString());
      if (orderIndex != -1 &&
          orders[orderIndex]['courier_id'] != null &&
          orders[orderIndex]['courier_id'].toString().trim().isNotEmpty) {
        targetId = orders[orderIndex]['courier_id'].toString().trim();
      }
      if (targetId.isEmpty) {
        targetId = 'courier';
      }

      final existing = await supabase
          .from('ratings_and_reviews')
          .select('id')
          .eq('order_id', intOrderId)
          .eq('target_type', 'courier')
          .eq('customer_phone', customerPhone)
          .maybeSingle();

      final payload = <String, dynamic>{
        'order_id': intOrderId,
        'target_type': 'courier',
        'target_id': targetId,
        'rating': rating,
        'comment': reviewText.trim(),
        'customer_phone': customerPhone,
      };

      if (existing != null && existing['id'] != null) {
        await supabase
            .from('ratings_and_reviews')
            .update(payload)
            .eq('id', existing['id']);
      } else {
        await supabase.from('ratings_and_reviews').insert(payload);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في تقييم المندوب: $e');
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> submitRestaurantRating({
    required String orderId,
    required double rating,
    required String reviewText,
    String? restaurantName,
  }) async {
    try {
      final intOrderId = int.tryParse(orderId.trim());
      if (intOrderId == null) {
        throw Exception('رقم الطلب غير صالح.');
      }
      final customerPhone = await _resolveCustomerPhoneForRating(intOrderId);

      var targetId = (restaurantName ?? '').trim();
      final orderIndex = orders
          .indexWhere((o) => o['id'].toString() == intOrderId.toString());
      if (orderIndex != -1) {
        final restId =
            orders[orderIndex]['restaurant_id']?.toString().trim() ?? '';
        final restName =
            orders[orderIndex]['restaurant_name']?.toString().trim() ?? '';
        if (restId.isNotEmpty) {
          targetId = restId;
        } else if (targetId.isEmpty && restName.isNotEmpty) {
          targetId = restName;
        }
      }
      if (targetId.isEmpty) {
        targetId = 'restaurant';
      }

      final existing = await supabase
          .from('ratings_and_reviews')
          .select('id')
          .eq('order_id', intOrderId)
          .eq('target_type', 'restaurant')
          .eq('customer_phone', customerPhone)
          .maybeSingle();

      final payload = <String, dynamic>{
        'order_id': intOrderId,
        'target_type': 'restaurant',
        'target_id': targetId,
        'rating': rating,
        'comment': reviewText.trim(),
        'customer_phone': customerPhone,
      };

      if (existing != null && existing['id'] != null) {
        await supabase
            .from('ratings_and_reviews')
            .update(payload)
            .eq('id', existing['id']);
      } else {
        await supabase.from('ratings_and_reviews').insert(payload);
      }

      await fetchRestaurantAverages();
      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في تقييم المطعم: $e');
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  String getArabicStatus(String? status) {
    switch (status?.trim()) {
      case 'waitingForPricing':
      case 'waiting_for_pricing':
        return 'بانتظار تحديد السعر من الإدارة';
      case 'pricingSentToCustomer':
      case 'pricing_sent_to_customer':
        return 'تم تحديد السعر، بانتظار موافقة العميل';
      case 'approvedByCustomer':
      case 'waitingCourierApproval':
      case 'waiting_courier_approval':
        return 'بانتظار موافقة المندوب';
      case 'acceptedByCourier':
      case 'accepted':
      case 'assigned':
        return 'تم قبول الطلب وتعيين المندوب';
      case 'onTheWay':
      case 'on_the_way':
        return 'المندوب في الطريق إليك';
      case 'rejectedByCourier':
      case 'rejected':
        return 'رفض المندوب الطلب';
      case 'arrivedToCustomer':
      case 'arrived':
        return 'وصل المندوب إلى موقع العميل';
      case 'delivered':
        return 'تم تسليم الطلب بنجاح';
      case 'cancelled':
      case 'cancelledByCustomer':
        return 'تم إلغاء الطلب';
      default:
        return status ?? 'قيد المعالجة';
    }
  }

  Future<List<String>> getAllAdminPlayerIds() async {
    try {
      final response = await supabase
          .from('admins')
          .select('onesignal_player_id')
          .not('onesignal_player_id', 'is', null);

      return response
          .map((e) => e['onesignal_player_id'].toString())
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<String?> getCourierPlayerIdByName(String courierName) async {
    try {
      final response = await supabase
          .from('couriers')
          .select('onesignal_player_id')
          .eq('name', courierName.trim())
          .maybeSingle();

      if (response != null && response['onesignal_player_id'] != null) {
        return response['onesignal_player_id'].toString();
      }
    } catch (e) {
      debugPrint('خطأ: $e');
    }
    return null;
  }

  Future<String?> getReceiverPlayerIdForChat({
    dynamic orderId,
    String? targetChat,
    String? senderRole,
  }) async {
    try {
      final oid = orderId?.toString().trim() ?? '';
      if (oid.isEmpty) return null;

      final orderRow = await supabase
          .from('orders')
          .select('phone, assigned_courier')
          .eq('id', int.tryParse(oid) ?? oid)
          .maybeSingle();

      if (senderRole == 'customer') {
        final adminIds = await getAllAdminPlayerIds();
        return adminIds.isNotEmpty ? adminIds.first : null;
      }

      if (targetChat == 'admin_courier') {
        final courierName = orderRow?['assigned_courier']?.toString() ?? '';
        if (courierName.isNotEmpty) {
          return await getCourierPlayerIdByName(courierName);
        }
      } else {
        final custPhone = _normalizePhone(orderRow?['phone']?.toString() ?? '');
        if (custPhone.isNotEmpty) {
          final cust = await supabase
              .from('customers')
              .select('onesignal_player_id')
              .eq('phone', custPhone)
              .maybeSingle();
          final pid = cust?['onesignal_player_id']?.toString();
          if (pid != null && pid.isNotEmpty) return pid;
        }
      }
    } catch (e) {
      debugPrint('تعذر تحديد معرف المستلم للشات: $e');
    }
    return null;
  }

  Future<void> sendAutoNotification({
    String? playerId,
    String? targetPlayerId,
    required String title,
    String? message,
    String? body,
    dynamic orderId,
    String? eventType,
  }) async {
    final content = (body ?? message ?? '').trim();
    if (title.trim().isEmpty && content.isEmpty) return;

    if (!_hasConfiguredBackend) return;

    try {
      await _postBackend('/api/notifications/send', {
        'title': title.trim(),
        'body': content,
        if (orderId != null) 'order_id': orderId,
        if (eventType != null && eventType.trim().isNotEmpty)
          'event_type': eventType.trim(),
        if (playerId != null && playerId.trim().isNotEmpty)
          'player_id': playerId.trim(),
        if (targetPlayerId != null && targetPlayerId.trim().isNotEmpty)
          'target_player_id': targetPlayerId.trim(),
      });
    } catch (e) {
      debugPrint('تعذر إرسال الإشعار عبر Backend: $e');
    }
  }

  int startHour = 8;
  int endHour = 24;
  int deliveryFee = 500;
  String storeName = 'Fast Delivery';
  bool storeIsOpenFlag = true;
  String storeTimezone = 'Asia/Aden';

  int get workStartHour => startHour;
  int get workEndHour => endHour;
  String customerSupportPhone = '776857316';

  bool isDarkMode = true;
  void toggleTheme() {
    isDarkMode = !isDarkMode;
    notifyListeners();
  }

  ThemeMode get themeMode => isDarkMode ? ThemeMode.dark : ThemeMode.light;

  void setThemeMode(ThemeMode mode) {
    isDarkMode = (mode == ThemeMode.dark);
    notifyListeners();
  }

  String currentCity = 'تعز';
  void setCity(String city) {
    currentCity = city;
    if (_userProfileData != null) {
      _userProfileData!['city'] = city;
    }
    notifyListeners();
  }

  Stream<JsonList> getMessagesForOrder(dynamic orderId, String targetChat) {
    final parsedId = int.tryParse(orderId.toString()) ?? orderId;
    return supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('order_id', parsedId)
        .eq('target_chat', targetChat)
        .order('created_at', ascending: true)
        .map((rows) {
          return rows.map((row) => Map<String, dynamic>.from(row)).toList();
        });
  }

  Future<void> sendChatMessage(
    dynamic orderId,
    String senderRole,
    String targetChat,
    String messageText,
  ) async {
    if (messageText.trim().isEmpty) return;

    final parsedId = int.tryParse(orderId.toString()) ?? orderId;
    final newMessage = {
      'order_id': parsedId,
      'sender_type': senderRole,
      'target_chat': targetChat,
      'message_text': messageText.trim(),
    };

    try {
      await supabase.from('messages').insert(newMessage);
    } catch (e) {
      debugPrint('خطأ في إرسال الرسالة: $e');
    }
  }

  Future<void> openFastWhatsApp({
    String message = 'مرحباً، أريد التواصل مع خدمة العملاء.',
  }) async {
    final uri = Uri.parse(
        'https://wa.me/967776857316?text=${Uri.encodeComponent(message)}');
    if (!await canLaunchUrl(uri)) {
      throw Exception('تعذر فتح واتساب.');
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void shareApp() {
    unawaited(Share.share(
      'حمل تطبيق Fast Delivery App - أسرع خدمة توصيل\nhttps://play.google.com/store/apps/details?id=com.example.taiz_express',
      subject: 'تطبيق Fast Delivery App',
    ));
  }

  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  Future<bool> openLocationSettingsDirectly() async {
    return await Geolocator.openLocationSettings();
  }

  Future<bool> openAppSettingsDirectly() async {
    return await Geolocator.openAppSettings();
  }

  Future<bool> requestLocationAndNotificationPermissions({
    bool openSettingsIfDisabled = false,
  }) async {
    var locationReady = false;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (openSettingsIfDisabled) {
          await Geolocator.openLocationSettings();
        }
      } else {
        var locationPermission = await Geolocator.checkPermission();
        if (locationPermission == LocationPermission.denied) {
          locationPermission = await Geolocator.requestPermission();
        }
        if (locationPermission == LocationPermission.deniedForever &&
            openSettingsIfDisabled) {
          await Geolocator.openAppSettings();
        }
        locationReady = locationPermission == LocationPermission.always ||
            locationPermission == LocationPermission.whileInUse;
      }

      var notificationStatus = await Permission.notification.status;
      if (!notificationStatus.isGranted) {
        notificationStatus = await Permission.notification.request();
      }

      if (notificationStatus.isGranted) {
        try {
          await OneSignal.Notifications.requestPermission(true);
        } catch (e) {
          debugPrint('OneSignal Error: $e');
        }
      }
    } catch (e) {
      debugPrint('خطأ في الأذونات: $e');
    }
    return locationReady;
  }

  int _parseHourFromTimeValue(dynamic value, int fallbackHour) {
    if (value == null) return fallbackHour;
    if (value is int) return value;
    final str = value.toString().trim();
    final directInt = int.tryParse(str);
    if (directInt != null) return directInt;
    final parts = str.split(':');
    if (parts.isNotEmpty) {
      final parsed = int.tryParse(parts.first);
      if (parsed != null) return parsed;
    }
    return fallbackHour;
  }

  void _applyStoreSettingsRow(Map<String, dynamic> row) {
    if (row['store_name'] != null &&
        row['store_name'].toString().trim().isNotEmpty) {
      storeName = row['store_name'].toString().trim();
    }
    startHour = _parseHourFromTimeValue(row['open_time'], startHour);
    endHour = _parseHourFromTimeValue(row['close_time'], endHour);
    if (row['is_open'] is bool) {
      storeIsOpenFlag = row['is_open'] as bool;
    } else if (row['is_open'] != null) {
      final s = row['is_open'].toString().toLowerCase().trim();
      storeIsOpenFlag = s == 'true' || s == '1' || s == 'open';
    }
    if (row['timezone'] != null &&
        row['timezone'].toString().trim().isNotEmpty) {
      storeTimezone = row['timezone'].toString().trim();
    }
  }

  Future<void> fetchStoreSettings() async {
    try {
      final feeResponse = await supabase.from('settings').select().maybeSingle();
      if (feeResponse != null && feeResponse['delivery_fee'] != null) {
        deliveryFee =
            int.tryParse(feeResponse['delivery_fee'].toString()) ?? deliveryFee;
      }

      try {
        final storeResponse = await supabase
            .from('store_settings')
            .select()
            .limit(1)
            .maybeSingle();
        if (storeResponse != null) {
          _applyStoreSettingsRow(Map<String, dynamic>.from(storeResponse));
        } else if (feeResponse != null) {
          startHour = _parseHourFromTimeValue(feeResponse['start_hour'], 8);
          endHour = _parseHourFromTimeValue(feeResponse['end_hour'], 24);
        }
      } catch (_) {
        if (feeResponse != null) {
          startHour = _parseHourFromTimeValue(feeResponse['start_hour'], 8);
          endHour = _parseHourFromTimeValue(feeResponse['end_hour'], 24);
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في الإعدادات: $e');
    }
  }

  void listenToStoreSettingsRealtime() {
    try {
      unawaited(_settingsSub?.cancel());
      unawaited(_storeSettingsSub?.cancel());

      _settingsSub =
          supabase.from('settings').stream(primaryKey: ['id']).listen((data) {
        if (data.isNotEmpty) {
          if (data.first['delivery_fee'] != null) {
            deliveryFee =
                int.tryParse(data.first['delivery_fee'].toString()) ??
                    deliveryFee;
          }
          if (data.first['start_hour'] != null) {
            startHour =
                _parseHourFromTimeValue(data.first['start_hour'], startHour);
          }
          if (data.first['end_hour'] != null) {
            endHour = _parseHourFromTimeValue(data.first['end_hour'], endHour);
          }
          notifyListeners();
        }
      });

      _storeSettingsSub = supabase
          .from('store_settings')
          .stream(primaryKey: ['id']).listen((data) {
        if (data.isNotEmpty) {
          _applyStoreSettingsRow(Map<String, dynamic>.from(data.first));
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('خطأ في الاستماع للإعدادات: $e');
    }
  }

  String _formatHourForStoreSettings(int hour) {
    final normalized = ((hour % 24) + 24) % 24;
    final hh = normalized.toString().padLeft(2, '0');
    return '$hh:00:00';
  }

  Future<void> _persistStoreSettingsToBackendOrSchema({
    required int start,
    required int end,
    int? fee,
    String? name,
    bool? isOpen,
  }) async {
    final targetFee = fee ?? deliveryFee;
    final targetName = (name ?? storeName).trim();
    final targetOpen = isOpen ?? storeIsOpenFlag;

    if (_hasConfiguredBackend) {
      try {
        await _postBackend('/api/admin/settings/store', {
          'store_name': targetName,
          'open_time': _formatHourForStoreSettings(start),
          'close_time': _formatHourForStoreSettings(end),
          'is_open': targetOpen,
          'timezone': storeTimezone.isNotEmpty ? storeTimezone : 'Asia/Aden',
          'delivery_fee': targetFee,
        });
        return;
      } catch (_) {}
    }

    try {
      await supabase.from('store_settings').upsert({
        'id': 1,
        'store_name': targetName,
        'open_time': _formatHourForStoreSettings(start),
        'close_time': _formatHourForStoreSettings(end),
        'is_open': targetOpen,
        'timezone': storeTimezone.isNotEmpty ? storeTimezone : 'Asia/Aden',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}

    await supabase.from('settings').upsert({
      'id': 1,
      'start_hour': start,
      'end_hour': end,
      'delivery_fee': targetFee,
    });
  }

  Future<void> updateStoreHours(int start, int end) async {
    startHour = start;
    endHour = end;
    notifyListeners();
    try {
      await _persistStoreSettingsToBackendOrSchema(start: start, end: end);
    } catch (e) {
      debugPrint('خطأ في حفظ أوقات الدوام: $e');
    }
  }

  Future<void> updateStoreSettings(int start, int end) async {
    await updateStoreHours(start, end);
  }

  Future<void> updateBusinessSettings({
    required int startHour,
    required int endHour,
    required int deliveryFee,
  }) async {
    this.startHour = startHour;
    this.endHour = endHour;
    this.deliveryFee = deliveryFee;
    await _persistStoreSettingsToBackendOrSchema(
      start: startHour,
      end: endHour,
      fee: deliveryFee,
    );
    notifyListeners();
  }

  bool get isStoreOpen {
    if (!storeIsOpenFlag) return false;
    final nowUtc = DateTime.now().toUtc();
    final adenNow = nowUtc.add(const Duration(hours: 3));
    final currentHour = adenNow.hour;
    if (endHour > startHour) {
      return currentHour >= startHour && currentHour < endHour;
    } else if (endHour < startHour) {
      return currentHour >= startHour || currentHour < endHour;
    }
    return false;
  }

  bool isAdminLoggedIn = false;

  Future<bool> loginAdminFromSupabase(String username, String password) async {
    try {
      final raw = username.trim().toLowerCase();
      final email = raw.contains('@') ? raw : '$raw@fast.com';
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.user == null || _isCourierSession(response.user)) {
        await supabase.auth.signOut();
        isAdminLoggedIn = false;
        return false;
      }

      final verifiedAdmin = await _verifyAdminFromBackendOrSchema(
        response.user,
        loginInput: raw,
      );
      if (verifiedAdmin == null) {
        await supabase.auth.signOut();
        isAdminLoggedIn = false;
        return false;
      }

      isAdminLoggedIn = true;
      currentCourier = null;
      await _syncAdminProfileFromAuth(
        response.user,
        verifiedAdminRow: verifiedAdmin,
      );
      await fetchCouriersFromSupabase();
      listenToOrdersRealtime();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('خطأ في دخول المشرف: $e');
      isAdminLoggedIn = false;
      return false;
    }
  }

  Future<void> logoutAdmin() async {
    isAdminLoggedIn = false;
    await supabase.auth.signOut();
    notifyListeners();
  }

  Map<String, dynamic>? _userProfileData;
  JsonMapNullable get userProfile {
    if (_userProfileData == null) return null;
    return Map<String, dynamic>.from(_userProfileData!);
  }

  set userProfile(dynamic value) {
    if (value == null) {
      _userProfileData = null;
    } else if (value is Map) {
      _userProfileData = Map<String, dynamic>.from(value);
    }
  }

  String? lastOrderTrackingCode;

  dynamic get user => userProfile == null
      ? null
      : _UserMock(
          userProfile!['name']?.toString() ?? '',
          userProfile!['phone']?.toString() ?? '',
        );

  String? get currentUserId => userProfile?['phone']?.toString();

  void setUser({
    dynamic profile,
    String? name,
    String? phone,
    String? address,
  }) {
    if (profile is Map) {
      userProfile = Map<String, dynamic>.from(profile);
    } else if (name != null || phone != null || address != null) {
      userProfile = {
        'name': name ?? userProfile?['name'] ?? '',
        'phone': phone ?? userProfile?['phone'] ?? '',
        'address': address ?? userProfile?['address'] ?? '',
        'city': currentCity,
      };
    }
    notifyListeners();
  }

  Future<void> _persistUserSessionToPrefs(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userPhone', (data['phone'] ?? '').toString());
    await prefs.setString('userName', (data['name'] ?? '').toString());
    await prefs.setString('userAddress', (data['address'] ?? '').toString());
    await prefs.setString('userCity', (data['city'] ?? currentCity).toString());
  }

  Future<JsonMapNullable> fetchCustomerRecordByPhone(String phone) async {
    final cleanPhone = _normalizePhone(phone);
    if (cleanPhone.isEmpty) return null;

    final formattedPhone = '+967$cleanPhone';
    final zeroPhone = '0$cleanPhone';
    final record = await supabase
        .from('customers')
        .select()
        .or('phone.eq.$cleanPhone,phone.eq.$formattedPhone,phone.eq.$zeroPhone')
        .maybeSingle();

    if (record == null) return null;

    final normalizedData = <String, dynamic>{
      'id': record['id'],
      'phone': cleanPhone,
      'name': record['name']?.toString() ?? '',
      'address': record['address']?.toString() ?? '',
      'city': currentCity,
    };

    userProfile = normalizedData;
    await _persistUserSessionToPrefs(normalizedData);
    await fetchUserAddressesFromSupabase();
    notifyListeners();
    return normalizedData;
  }

  Future<void> _loadUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('userPhone');
    final name = prefs.getString('userName');
    final address = prefs.getString('userAddress');
    final city = prefs.getString('userCity') ?? currentCity;

    if (phone != null && phone.isNotEmpty) {
      final cleanPhone = _normalizePhone(phone);
      try {
        final dbRecord = await fetchCustomerRecordByPhone(cleanPhone);
        if (dbRecord != null) {
          await restoreLastCustomerOrder();
          return;
        }
      } catch (e) {
        debugPrint('خطأ في جلب بيانات العميل: $e');
      }

      userProfile = {
        'phone': cleanPhone,
        'name': name ?? '',
        'city': city,
        'address': address ?? '',
      };
      await fetchUserAddressesFromSupabase();
      notifyListeners();
      await restoreLastCustomerOrder();
    }
  }

  Future<void> restoreLastCustomerOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final orderId = prefs.getString('fast_last_order_id');
    final phone = userProfile?['phone'];
    if (orderId == null || phone == null) return;
    try {
      final response = await supabase
          .from('orders')
          .select()
          .eq('id', int.tryParse(orderId) ?? orderId)
          .maybeSingle();
      if (response != null) {
        _upsertOrderInList(response);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('تعذر استعادة الطلب: $e');
    }
  }

  Future<bool> checkAndLoginCustomer(String phone) async {
    try {
      final dbRecord = await fetchCustomerRecordByPhone(phone);
      return dbRecord != null;
    } catch (e) {
      return false;
    }
  }

  Future<JsonMap> requestOtpForPhone(String phone) async {
    final cleanPhone = _normalizePhone(phone);
    if (cleanPhone.isEmpty) {
      throw Exception('الرجاء إدخال رقم هاتف صحيح.');
    }

    final internationalPhone = '967$cleanPhone';

    final existingRecord = await fetchCustomerRecordByPhone(cleanPhone);
    final existsInDb = existingRecord != null;
    if (existsInDb) {
      await restoreLastCustomerOrder();
    }

    try {
      final res =
          await ApiService.sendWhatsappOtp(phoneNumber: internationalPhone);
      notifyListeners();
      return {
        'exists': existsInDb,
        'provider': 'whatsapp_cloud_api',
        'is_sandbox': false,
        'message': res['message']?.toString().isNotEmpty == true
            ? res['message'].toString()
            : 'تم إرسال رمز التحقق عبر واتساب إلى +$internationalPhone',
      };
    } catch (e) {
      final generatedCode = (1000 + Random().nextInt(9000)).toString();
      _localFallbackOtps[cleanPhone] = generatedCode;
      notifyListeners();
      return {
        'exists': existsInDb,
        'provider': 'fallback',
        'is_sandbox': true,
        'otp_code': generatedCode,
        'message': e.toString().replaceFirst(RegExp(r'^ApiException:\s*'), ''),
      };
    }
  }

  Future<bool> verifyOtpAndLogin(String phone, String enteredOtp) async {
    final code = enteredOtp.trim();
    if (code.isEmpty) return false;
    final cleanPhone = _normalizePhone(phone);
    if (cleanPhone.isEmpty) return false;

    final internationalPhone = '967$cleanPhone';
    var isValid = false;

    try {
      final verifyRes = await ApiService.verifyWhatsappOtp(
        phoneNumber: internationalPhone,
        otpCode: code,
      );
      isValid = verifyRes['verified'] == true ||
          verifyRes['ok'] == true ||
          verifyRes['success'] == true;
    } catch (e) {
      debugPrint('تعذر التحقق عبر دالة واتساب، التحقق من الاحتياطي: $e');
      if (_localFallbackOtps[cleanPhone] == code) {
        isValid = true;
      }
    }

    if (!isValid && _localFallbackOtps[cleanPhone] == code) {
      isValid = true;
    }

    if (!isValid) return false;

    _localFallbackOtps.remove(cleanPhone);

    final dbRecord = await fetchCustomerRecordByPhone(cleanPhone);
    if (dbRecord != null) {
      await restoreLastCustomerOrder();
      return true;
    }

    userProfile = {
      'phone': cleanPhone,
      'name': '',
      'address': '',
      'city': currentCity,
    };
    await _persistUserSessionToPrefs(userProfile!);

    try {
      await supabase.from('customers').upsert({
        'phone': cleanPhone,
        'name': '',
        'address': '',
      }, onConflict: 'phone');
    } catch (e) {
      debugPrint('خطأ في إنشاء سجل العميل في customers: $e');
    }

    await fetchUserAddressesFromSupabase();
    notifyListeners();
    return true;
  }

  Future<void> updateUser({String? name, String? address, String? phone}) async {
    if (_userProfileData != null) {
      if (phone != null && phone.trim().isNotEmpty) {
        _userProfileData!['phone'] = _normalizePhone(phone);
      }
      if (name != null) {
        _userProfileData!['name'] = name;
      }
      if (address != null) {
        _userProfileData!['address'] = address;
      }
    }
    await saveUserProfileDetails(
      name ?? userProfile?['name']?.toString() ?? '',
      address ?? userProfile?['address']?.toString() ?? '',
    );
  }

  Future<void> saveUserProfileDetails(String name, String address) async {
    if (userProfile != null) {
      final cleanPhone =
          _normalizePhone(userProfile!['phone']?.toString() ?? '');
      userProfile = {
        ...userProfile!,
        'name': name,
        'address': address,
        'phone': cleanPhone,
      };

      await _persistUserSessionToPrefs(userProfile!);

      try {
        await supabase.from('customers').upsert({
          'phone': cleanPhone,
          'name': name,
          'address': address,
        }, onConflict: 'phone');

        await requestLocationAndNotificationPermissions();

        final playerId = OneSignal.User.pushSubscription.id;
        if (playerId != null && playerId.isNotEmpty) {
          await supabase
              .from('customers')
              .update({'onesignal_player_id': playerId})
              .eq('phone', cleanPhone);
        }
      } catch (e) {
        debugPrint('خطأ في حفظ بيانات العميل: $e');
      }

      notifyListeners();
    }
  }

  Future<void> logoutUser() async {
    userProfile = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userPhone');
    await prefs.remove('userName');
    await prefs.remove('userAddress');
    _cartItems.clear();
    notifyListeners();
  }

  Map<String, dynamic>? _currentCourierData;
  JsonMapNullable get currentCourier {
    if (_currentCourierData == null) return null;
    return Map<String, dynamic>.from(_currentCourierData!);
  }

  set currentCourier(dynamic value) {
    if (value == null) {
      _currentCourierData = null;
    } else if (value is Map) {
      _currentCourierData = Map<String, dynamic>.from(value);
    }
  }

  List<Map<String, dynamic>> couriers = [];

  Future<JsonMapNullable> _findCourierRecordForUser(
    User user, {
    String? usernameInput,
  }) async {
    final byAuthId = await supabase
        .from('couriers')
        .select()
        .eq('auth_user_id', user.id)
        .maybeSingle();
    if (byAuthId != null) {
      return Map<String, dynamic>.from(byAuthId);
    }

    final email = (user.email ?? '').trim().toLowerCase();
    final emailPrefix =
        email.contains('@') ? email.split('@').first.trim() : email;
    final cleanInput = (usernameInput ?? '').trim().toLowerCase();
    final inputPrefix = cleanInput.contains('@')
        ? cleanInput.split('@').first.trim()
        : cleanInput;

    final candidates = <String>{
      if (cleanInput.isNotEmpty) cleanInput,
      if (inputPrefix.isNotEmpty) inputPrefix,
      if (emailPrefix.isNotEmpty) emailPrefix,
    };

    for (final candidate in candidates) {
      final byUsername = await supabase
          .from('couriers')
          .select()
          .ilike('username', candidate)
          .maybeSingle();
      if (byUsername != null) {
        try {
          await supabase
              .from('couriers')
              .update({'auth_user_id': user.id})
              .eq('id', byUsername['id']);
        } catch (_) {}
        return Map<String, dynamic>.from(byUsername);
      }
    }

    return null;
  }

  Future<void> _loadCourierSession() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final row = await _findCourierRecordForUser(user);
      if (row != null && row['status']?.toString() != 'disabled') {
        currentCourier = Map<String, dynamic>.from(row);
        final courierPhone = row['phone']?.toString() ?? '';
        final courierName = row['name']?.toString() ?? '';
        if (courierPhone.trim().isNotEmpty) {
          await _syncStaffPhoneToUserProfile(
            phone: courierPhone,
            name: courierName,
          );
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('تعذر استعادة جلسة المندوب: $e');
    }
  }

  Future<void> fetchCouriersFromSupabase() async {
    try {
      final response = await supabase.from('couriers').select();
      couriers = List<Map<String, dynamic>>.from(response);
      await _loadCourierSession();
      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في جلب المناديب: $e');
    }
  }

  Future<void> addCourier(
    String name,
    String phone,
    String username,
    String password,
  ) async {
    if (password.length < 6) {
      throw Exception('كلمة مرور المندوب يجب ألا تقل عن 6 أحرف.');
    }

    if (_hasConfiguredBackend) {
      try {
        final res = await _postBackend('/api/admin/couriers', {
          'name': name.trim(),
          'phone': phone.trim(),
          'username': username.trim(),
          'password': password,
        });

        if (res['success'] == false) {
          throw Exception(res['error']?.toString() ?? 'تعذر إضافة المندوب.');
        }

        await fetchCouriersFromSupabase();
        return;
      } catch (_) {}
    }

    final cleanUsername = username.trim().toLowerCase();
    final newId = 'courier_${DateTime.now().millisecondsSinceEpoch}';
    await supabase.from('couriers').insert({
      'id': newId,
      'name': name.trim(),
      'phone': _normalizePhone(phone),
      'username': cleanUsername,
      'password': password,
      'status': 'available',
      'is_logged_in': false,
    });

    await fetchCouriersFromSupabase();
  }

  Future<void> updateCourier(DeliveryModel courier) async {
    final status = !courier.isEnabled
        ? 'disabled'
        : (courier.isAvailable ? 'available' : 'busy');

    if (_hasConfiguredBackend) {
      try {
        await _postBackend(
            '/api/admin/couriers/${Uri.encodeComponent(courier.id)}/update', {
          'name': courier.name.trim(),
          'phone': courier.phone.trim(),
          'status': status,
        });
        await fetchCouriersFromSupabase();
        return;
      } catch (_) {}
    }

    await supabase.from('couriers').update({
      'name': courier.name.trim(),
      'phone': _normalizePhone(courier.phone),
      'status': status,
    }).eq('id', courier.id);

    await fetchCouriersFromSupabase();
  }

  Future<void> setCourierAvailability(String courierId, bool available) async {
    final status = available ? 'available' : 'busy';
    if (_hasConfiguredBackend) {
      try {
        await _postBackend(
            '/api/admin/couriers/${Uri.encodeComponent(courierId)}/status', {
          'status': status,
        });
        await fetchCouriersFromSupabase();
        return;
      } catch (_) {}
    }

    await supabase
        .from('couriers')
        .update({'status': status})
        .eq('id', courierId);
    await fetchCouriersFromSupabase();
  }

  Future<void> removeCourier(String courierId) async {
    if (_hasConfiguredBackend) {
      try {
        await _postBackend(
            '/api/admin/couriers/${Uri.encodeComponent(courierId)}/delete',
            {});
        await fetchCouriersFromSupabase();
        return;
      } catch (_) {}
    }

    await supabase.from('couriers').delete().eq('id', courierId);
    await fetchCouriersFromSupabase();
  }

  Future<void> settleCourierEarnings(String courierName) async {
    try {
      final cleanCourierName = courierName.trim();
      if (cleanCourierName.isEmpty) {
        throw Exception('اسم المندوب مطلوب لتسوية المستحقات.');
      }

      if (_hasConfiguredBackend) {
        try {
          await _postBackend('/api/admin/couriers/settle', {
            'courier_name': cleanCourierName,
          });
          await fetchOrders();
          unawaited(fetchAdminFinancialReports());
          notifyListeners();
          return;
        } catch (_) {}
      }

      final unsettled = await supabase
          .from('orders')
          .select('id, delivery_fee')
          .eq('assigned_courier', cleanCourierName)
          .eq('status', 'delivered')
          .eq('is_settled', false);

      final list = List<Map<String, dynamic>>.from(unsettled);
      var total = 0.0;
      for (final o in list) {
        total += double.tryParse(o['delivery_fee']?.toString() ?? '0') ?? 0.0;
      }

      if (list.isNotEmpty) {
        await supabase
            .from('orders')
            .update({'is_settled': true})
            .eq('assigned_courier', cleanCourierName)
            .eq('status', 'delivered')
            .eq('is_settled', false);

        try {
          await supabase.from('courier_settlements').insert({
            'courier_name': cleanCourierName,
            'orders_count': list.length,
            'total_amount': total,
          });
        } catch (_) {}
      }

      await fetchOrders();
      unawaited(fetchAdminFinancialReports());
      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في تسوية أرباح المندوب: $e');
      rethrow;
    }
  }

  Future<bool> loginCourier(String username, String password) async {
    try {
      final raw = username.trim().toLowerCase();
      final email = raw.contains('@') ? raw : '$raw@fast.com';
      final auth = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (auth.user == null) {
        await supabase.auth.signOut();
        return false;
      }

      final row = await _findCourierRecordForUser(
        auth.user!,
        usernameInput: raw,
      );

      if (row == null || row['status']?.toString() == 'disabled') {
        await supabase.auth.signOut();
        return false;
      }

      await supabase
          .from('couriers')
          .update({'is_logged_in': true})
          .eq('id', row['id']);

      isAdminLoggedIn = false;
      currentCourier = Map<String, dynamic>.from(row);
      _currentCourierData!['is_logged_in'] = true;

      final courierPhone = row['phone']?.toString() ?? '';
      final courierName = row['name']?.toString() ?? '';
      if (courierPhone.trim().isNotEmpty) {
        await _syncStaffPhoneToUserProfile(
          phone: courierPhone,
          name: courierName,
        );
      }

      listenToOrdersRealtime();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('loggedCourierId', row['id'].toString());
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('خطأ في دخول المندوب: $e');
      return false;
    }
  }

  Future<void> logoutCourier() async {
    if (currentCourier != null && currentCourier!['id'] != null) {
      try {
        await supabase
            .from('couriers')
            .update({'is_logged_in': false})
            .eq('id', currentCourier!['id']);
      } catch (e) {
        debugPrint('خطأ في تحرير جلسة المندوب: $e');
      }
    }

    currentCourier = null;
    await supabase.auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('loggedCourierId');
    notifyListeners();
  }

  final List<CartItemModel> _cartItems = [];
  List<CartItemModel> get cartItems => List.unmodifiable(_cartItems);

  int get totalCartItemsCount =>
      _cartItems.fold(0, (sum, item) => sum + item.quantity);
  double get totalAmount =>
      _cartItems.fold(0.0, (sum, item) => sum + (item.price * item.quantity));

  int getProductQuantityInCart(String productId) {
    final index = _cartItems.indexWhere((item) => item.id == productId);
    if (index >= 0) return _cartItems[index].quantity;
    return 0;
  }

  void addToCart(CartItemModel item) {
    final index = _cartItems.indexWhere((element) => element.id == item.id);
    if (index >= 0) {
      _cartItems[index].quantity += item.quantity;
    } else {
      _cartItems.add(item);
    }
    notifyListeners();
  }

  void addCustomOrderToCart({
    required String customName,
    required double estimatedPrice,
  }) {
    _cartItems.add(CartItemModel(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: 'طلب خاص: $customName',
      price: estimatedPrice,
      quantity: 1,
      restaurantId: 'خدمة الطلبات الخاصة',
      imageUrl: '',
    ));
    notifyListeners();
  }

  void removeFromCart(String id) {
    _cartItems.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  void updateQuantity(String id, int delta) {
    final index = _cartItems.indexWhere((item) => item.id == id);
    if (index >= 0) {
      _cartItems[index].quantity += delta;
      if (_cartItems[index].quantity <= 0) {
        _cartItems.removeAt(index);
      }
      notifyListeners();
    }
  }

  void clearCart() {
    _cartItems.clear();
    removeCoupon();
    notifyListeners();
  }

  Future<void> updateOrderStatus(String id, String status) async {
    final intId = int.tryParse(id);
    if (intId == null) {
      throw Exception('معرف الطلب غير صالح.');
    }

    if (_hasConfiguredBackend) {
      try {
        final res = await ApiService.adminUpdateOrderStatus(
          _accessToken ?? '',
          intId,
          status,
        ).timeout(const Duration(seconds: 8));
        if (res['order'] is Map) {
          _upsertOrderInList(res['order']);
        } else {
          await fetchOrders();
        }
        unawaited(fetchAdminFinancialReports());
        notifyListeners();
        return;
      } catch (_) {}
    }

    final updated = await supabase
        .from('orders')
        .update({
          'status': status.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', intId)
        .select()
        .single();

    _upsertOrderInList(updated);
    unawaited(fetchAdminFinancialReports());
    notifyListeners();
  }

  Future<void> assignOrderToCourier(String orderId, String courierId) async {
    final intOrderId = int.tryParse(orderId);
    if (intOrderId == null) {
      throw Exception('معرف الطلب غير صالح.');
    }
    final courier = await supabase
        .from('couriers')
        .select('id, name')
        .eq('id', courierId)
        .single();

    final currentOrder = orders.firstWhere(
      (o) => o['id'].toString() == orderId,
      orElse: () => <String, dynamic>{},
    );
    final currentFee =
        double.tryParse(currentOrder['delivery_fee']?.toString() ?? '0') ?? 0.0;

    await setOrderDeliveryFee(
      intOrderId,
      currentFee,
      courier['name']?.toString() ?? '',
    );
  }

  Future<void> addProduct(ProductModel product) async {
    await upsertProduct(product);
  }

  Future<void> removeProduct(String id) async {
    if (_hasConfiguredBackend) {
      try {
        await _postBackend(
            '/api/admin/products/${Uri.encodeComponent(id)}/delete', {});
        await fetchProductsFromSupabase();
        notifyListeners();
        return;
      } catch (_) {}
    }

    await supabase.from('products').delete().eq('id', id);
    await fetchProductsFromSupabase();
    notifyListeners();
  }

  Future<void> upsertProduct(ProductModel product) async {
    final payload = {
      'id': product.id.isEmpty
          ? 'prod_${DateTime.now().millisecondsSinceEpoch}'
          : product.id,
      'name': product.name.trim(),
      'description': product.description.trim(),
      'restaurant_name': product.restaurantName.trim(),
      'price': product.price,
      'category': product.category,
      'available': product.available,
      'image_url': product.imageUrl,
      'unit': product.unit,
      'is_variable_price': product.isVariablePrice,
    };

    if (_hasConfiguredBackend) {
      try {
        await _postBackend('/api/admin/products/upsert', payload);
        await fetchProductsFromSupabase();
        notifyListeners();
        return;
      } catch (_) {}
    }

    await supabase.from('products').upsert(payload);
    await fetchProductsFromSupabase();
    notifyListeners();
  }

  List<ProductModel> _products = [];
  List<ProductModel> get products => List.unmodifiable(_products);
  set products(List<ProductModel> value) {
    _products = List<ProductModel>.from(value);
  }

  Future<void> fetchProductsFromSupabase() async {
    try {
      final response = await supabase.from('products').select();
      final mapped = response.map((p) {
        return ProductModel(
          id: p['id'].toString(),
          name: p['name'] ?? '',
          description: p['description'] ?? '',
          restaurantName: p['restaurant_name'] ?? 'متجر عام',
          price: double.tryParse(p['price'].toString()) ?? 0.0,
          category: p['category'] ?? 'المطاعم',
          available: p['available'] ?? true,
          imageUrl: p['image_url'] ?? '',
          unit: p['unit'] ?? 'حبة',
          isVariablePrice: p['is_variable_price'] ?? false,
        );
      }).toList();
      _products = mapped;

      await _localStorage.cacheProducts(response);
      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في جلب المنتجات: $e');
      final localProducts = await _localStorage.getCachedProducts();
      if (localProducts.isNotEmpty) {
        _products = localProducts;
        notifyListeners();
      }
    }
  }

  List<Map<String, dynamic>> orders = [];
  List<Map<String, dynamic>> notifications = [];

  int get unreadNotificationsCount => notifications.length;

  String _normalizePhone(String phone) {
    var clean = phone.trim().replaceAll(' ', '');
    if (clean.startsWith('+967')) {
      clean = clean.substring(4);
    }
    if (clean.startsWith('0')) {
      clean = clean.substring(1);
    }
    if (clean.startsWith('967')) {
      clean = clean.substring(3);
    }
    return clean;
  }

  List<Map<String, dynamic>> get customerOrders {
    final phoneStr = userProfile?['phone']?.toString() ?? '';
    if (phoneStr.isEmpty) {
      return [];
    }
    final myPhone = _normalizePhone(phoneStr);

    return orders.where((o) {
      final orderPhone = _normalizePhone(o['phone']?.toString() ?? '');
      return orderPhone.isNotEmpty && orderPhone == myPhone;
    }).toList();
  }

  void addNotification(String title, String body) {
    notifications.insert(
        0, {'title': title, 'body': body, 'time': DateTime.now()});
    unawaited(NotificationService.showLocalNotification(title, body));
    notifyListeners();
  }

  void addLocalNotification(String title, String body, {String? type}) {
    notifications.insert(0, {
      'title': title,
      'body': body,
      'time': DateTime.now(),
      'type': type ?? 'general',
    });
    unawaited(NotificationService.showLocalNotification(title, body));
    notifyListeners();
  }

  void _upsertOrderInList(Map rawOrder) {
    final orderMap = Map<String, dynamic>.from(rawOrder);
    final idStr = orderMap['id']?.toString() ?? '';
    final trackStr = orderMap['tracking_code']?.toString() ?? '';

    orders.removeWhere((o) {
      final oId = o['id']?.toString() ?? '';
      final oTrack = o['tracking_code']?.toString() ?? '';
      final sameId = idStr.isNotEmpty && oId == idStr;
      final sameTrack = trackStr.isNotEmpty && oTrack == trackStr;
      return sameId || sameTrack;
    });

    orders.add(orderMap);
    _sortOrders();
  }

  void _sortOrders() {
    orders.sort((a, b) {
      final timeA = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final timeB = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      if (timeA != timeB) {
        return timeB.compareTo(timeA);
      }
      final idA = int.tryParse(a['id']?.toString() ?? '0') ?? 0;
      final idB = int.tryParse(b['id']?.toString() ?? '0') ?? 0;
      return idB.compareTo(idA);
    });
  }

  void listenToOrdersRealtime() {
    unawaited(_initOrdersRealtime());
  }

  Future<void> _initOrdersRealtime() async {
    try {
      final initialData = await supabase.from('orders').select();
      orders = List<Map<String, dynamic>>.from(initialData);
      _sortOrders();
      unawaited(fetchAdminFinancialReports());
      notifyListeners();

      if (_ordersChannel != null) {
        await supabase.removeChannel(_ordersChannel!);
      }

      _ordersChannel = supabase
          .channel('public_orders_realtime_channel')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            callback: (payload) {
              if (payload.eventType == PostgresChangeEvent.insert) {
                final alreadyExists = orders.any((o) =>
                    o['id'].toString() == payload.newRecord['id'].toString());
                _upsertOrderInList(payload.newRecord);
                if (!alreadyExists && isAdminLoggedIn) {
                  addLocalNotification(
                    'طلب جديد',
                    'تم إضافة طلب جديد إلى النظام من قبل العميل',
                    type: 'admin_new_order',
                  );
                }
              } else if (payload.eventType == PostgresChangeEvent.update) {
                _upsertOrderInList(payload.newRecord);

                final newStatus =
                    getArabicStatus(payload.newRecord['status']?.toString());
                final assignedCourier =
                    payload.newRecord['assigned_courier']?.toString() ?? '';

                final orderPhone = _normalizePhone(
                    payload.newRecord['phone']?.toString() ?? '');
                final myPhone =
                    _normalizePhone(userProfile?['phone']?.toString() ?? '');

                if (myPhone.isNotEmpty &&
                    orderPhone.isNotEmpty &&
                    orderPhone == myPhone &&
                    !isAdminLoggedIn) {
                  final rawNewStatus =
                      payload.newRecord['status']?.toString().trim() ?? '';
                  final bodyText = rawNewStatus == 'pricingSentToCustomer'
                      ? 'تم تحديد رسوم التوصيل (${payload.newRecord['delivery_fee'] ?? 0} ر.ي) للطلب #${payload.newRecord['id']}، يرجى التأكيد.'
                      : 'تم تحديث حالة الطلب #${payload.newRecord['id']} إلى: $newStatus';
                  addLocalNotification(
                    'تحديث طلبك #${payload.newRecord['id']}',
                    bodyText,
                    type: 'customer_order_update',
                  );
                } else if (currentCourier != null &&
                    assignedCourier.trim() ==
                        currentCourier!['name']?.toString().trim()) {
                  addLocalNotification(
                    'تحديث الطلب #${payload.newRecord['id']}',
                    'تم تعيينك لتوصيل هذا الطلب. الحالة: $newStatus',
                    type: 'courier_order_update',
                  );
                } else if (isAdminLoggedIn) {
                  addLocalNotification(
                    'تحديث الطلب #${payload.newRecord['id']}',
                    'الحالة الجديدة: $newStatus',
                    type: 'admin_order_update',
                  );
                }
              } else if (payload.eventType == PostgresChangeEvent.delete) {
                orders.removeWhere((o) =>
                    o['id'].toString() == payload.oldRecord['id'].toString());
              }

              unawaited(fetchAdminFinancialReports());
              notifyListeners();
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('خطأ في Realtime الطلبات: $e');
    }
  }

  bool isRestaurantOrder(Map order) {
    if (order['is_restaurant'] == true) return true;
    final restName = order['restaurant_name']?.toString().trim() ?? '';
    final restId = order['restaurant_id']?.toString().trim() ?? '';
    return restId.isNotEmpty ||
        (restName.isNotEmpty &&
            restName != 'متجر عام' &&
            restName != 'خدمة الطلبات الخاصة');
  }

  Future<void> createOrder({
    required String customerName,
    required String phone,
    required String address,
    required String itemsDesc,
    required double productsTotal,
    required String paymentMethod,
    required String paymentAccount,
  }) async {
    if (_isCreatingOrder) return;
    _isCreatingOrder = true;

    try {
      if (!isStoreOpen) {
        throw Exception(
            'عذراً، التطبيق مغلق حالياً (أوقات الدوام من $startHour:00 إلى $endHour:00). لا يمكن استقبال طلبات جديدة.');
      }

      final normalizedPhone = _normalizePhone(phone);
      final clientRequestKey =
          'req_${DateTime.now().microsecondsSinceEpoch}_$normalizedPhone';

      final itemsPayload = _cartItems.map((cartItem) {
        final isCustom = cartItem.id.startsWith('custom_');
        return <String, dynamic>{
          'product_id': cartItem.id,
          'name': cartItem.name,
          'quantity': cartItem.quantity,
          'is_custom': isCustom,
          if (isCustom || cartItem.price > 0) 'unit_price': cartItem.price,
        };
      }).toList();

      JsonMap order = {};
      var trackingCode = '';

      if (_hasConfiguredBackend) {
        try {
          final responseData = await ApiService.createOrder(
            items: itemsPayload,
            address: address.trim(),
            notes: itemsDesc.trim(),
            customerName: customerName.trim(),
            phone: normalizedPhone,
            couponCode: activeCouponCode,
            paymentMethod: paymentMethod,
            paymentAccount: paymentAccount,
            clientRequestKey: clientRequestKey,
            token: _accessToken,
          );

          if (responseData['order'] is Map) {
            order = Map<String, dynamic>.from(responseData['order']);
            trackingCode = order['tracking_code']?.toString().trim() ?? '';
          }
        } catch (e) {
          debugPrint('تعذر إنشاء الطلب عبر Node.js، التحويل لقاعدة البيانات: $e');
        }
      }

      if (order.isEmpty) {
        trackingCode = 'FST-${100000 + Random().nextInt(900000)}';
        final netProductsTotal =
            (productsTotal - couponDiscountAmount).clamp(0.0, double.infinity);

        final inserted = await supabase
            .from('orders')
            .insert({
              'customer_name': customerName.trim(),
              'phone': normalizedPhone,
              'address': address.trim(),
              'items_description': itemsDesc.trim(),
              'items_desc': itemsDesc.trim(),
              'products_total': netProductsTotal,
              'total_price': netProductsTotal,
              'total_amount': netProductsTotal,
              'delivery_fee': 0,
              'status': 'waitingForPricing',
              'payment_method': paymentMethod.trim(),
              'payment_account': paymentAccount.trim(),
              'tracking_code': trackingCode,
              'notes': itemsDesc.trim(),
            })
            .select()
            .single();

        order = Map<String, dynamic>.from(inserted);

        if (order['id'] != null && _cartItems.isNotEmpty) {
          try {
            final orderItemsRows = _cartItems.map((c) {
              return {
                'order_id': order['id'],
                'product_name': c.name,
                'price': c.price,
                'quantity': c.quantity,
                'total_price': c.price * c.quantity,
              };
            }).toList();
            await supabase.from('order_items').insert(orderItemsRows);
          } catch (_) {}
        }
      }

      final orderId = order['id'];
      lastOrderTrackingCode = trackingCode.isNotEmpty ? trackingCode : null;
      userProfile = {
        'phone': normalizedPhone,
        'name': customerName,
        'city': currentCity,
        'address': address,
      };

      await _persistUserSessionToPrefs(userProfile!);
      if (orderId != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fast_last_order_id', orderId.toString());
      }
      if (order.isNotEmpty) {
        _upsertOrderInList(order);
      } else {
        await fetchOrders();
      }

      _cartItems.clear();
      removeCoupon();
      unawaited(fetchAdminFinancialReports());

      addNotification(
        'تم استلام الطلب',
        'طلبك بانتظار مراجعة المشرف وتأكيد رسوم التوصيل',
      );
      notifyListeners();
    } catch (e) {
      debugPrint('خطأ أثناء إرسال الطلب: $e');
      rethrow;
    } finally {
      _isCreatingOrder = false;
    }
  }

  Future<void> setOrderDeliveryFee(
    dynamic orderId,
    double fee,
    String courierName,
  ) async {
    try {
      final intOrderId = int.tryParse(orderId.toString());
      if (intOrderId == null) {
        throw Exception('معرف الطلب غير صالح.');
      }

      final double cleanFee = fee > 0 ? fee : 0.0;
      final cleanCourierName =
          courierName.trim().isEmpty ? 'مندوب عام' : courierName.trim();

      JsonMap updatedOrder = {};

      if (_hasConfiguredBackend) {
        try {
          final responseData = await ApiService.adminPricingOrder(
            _accessToken ?? '',
            intOrderId,
            cleanFee,
            cleanCourierName,
          ).timeout(const Duration(seconds: 8));

          if (responseData['order'] is Map) {
            updatedOrder = Map<String, dynamic>.from(responseData['order']);
          }
        } catch (_) {}
      }

      if (updatedOrder.isEmpty) {
        final existing = orders.firstWhere(
          (o) => o['id'].toString() == intOrderId.toString(),
          orElse: () => <String, dynamic>{},
        );
        final prodTotal = _extractOrderProductsTotal(existing);
        final grandTotal = prodTotal + cleanFee;

        final row = await supabase
            .from('orders')
            .update({
              'delivery_fee': cleanFee,
              'assigned_courier': cleanCourierName,
              'driver_name': cleanCourierName,
              'status': 'pricingSentToCustomer',
              'is_fee_sent': true,
              'total_price': grandTotal,
              'total_amount': grandTotal,
              'admin_message':
                  'تم تحديد رسوم التوصيل ($cleanFee ر.ي)، بانتظار موافقتك.',
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', intOrderId)
            .select()
            .single();

        updatedOrder = Map<String, dynamic>.from(row);
      }

      if (updatedOrder.isNotEmpty) {
        _upsertOrderInList(updatedOrder);
      } else {
        await fetchOrders();
      }

      unawaited(fetchAdminFinancialReports());

      addLocalNotification(
        'تم تحديد سعر الطلب #$orderId',
        'رسوم التوصيل: $cleanFee ر.ي. يرجى تأكيد الطلب لمتابعة التوصيل.',
        type: 'pricing_sent',
      );

      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في تحديد رسوم التوصيل: $e');
      throw Exception('تعذر تحديد رسوم التوصيل: $e');
    }
  }

  Future<void> _submitCustomerOrderAction(dynamic orderId, String action) async {
    final intOrderId = int.tryParse(orderId.toString());
    if (intOrderId == null) {
      throw Exception('معرف الطلب غير صالح.');
    }

    if (_hasConfiguredBackend) {
      try {
        final responseData =
            await _postBackend('/api/orders/$intOrderId/customer-action', {
          'action': action,
        });

        if (responseData['order'] is Map) {
          _upsertOrderInList(responseData['order']);
        } else {
          await fetchOrders();
        }

        unawaited(fetchAdminFinancialReports());
        notifyListeners();
        return;
      } catch (_) {}
    }

    final newStatus =
        action == 'approve' ? 'approvedByCustomer' : 'cancelledByCustomer';
    final updated = await supabase
        .from('orders')
        .update({
          'status': newStatus,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', intOrderId)
        .select()
        .single();

    _upsertOrderInList(updated);
    unawaited(fetchAdminFinancialReports());
    notifyListeners();
  }

  Future<void> customerApprovePricing(dynamic orderId) async {
    await _submitCustomerOrderAction(orderId, 'approve');
    addNotification(
        'تأكيد الطلب', 'تم تأكيد السعر وإرسال الطلب للمندوب');
  }

  Future<void> customerConfirmOrder(dynamic orderId) async {
    await customerApprovePricing(orderId);
  }

  Future<void> customerCancelOrder(dynamic orderId) async {
    await _submitCustomerOrderAction(orderId, 'cancel');
    addNotification('إلغاء الطلب', 'تم إلغاء الطلب بناءً على طلبك');
  }

  Future<void> _submitCourierOrderAction(dynamic orderId, String action) async {
    if (currentCourier == null) {
      throw Exception('جلسة المندوب غير صالحة.');
    }

    final intOrderId = int.tryParse(orderId.toString());
    if (intOrderId == null) {
      throw Exception('معرف الطلب غير صالح.');
    }

    final String newStatus;
    if (action == 'accept') {
      newStatus = 'acceptedByCourier';
    } else if (action == 'reject') {
      newStatus = 'rejectedByCourier';
    } else if (action == 'arrived') {
      newStatus = 'arrivedToCustomer';
    } else {
      newStatus = 'delivered';
    }

    if (_hasConfiguredBackend) {
      try {
        final responseData = await ApiService.courierUpdateOrderStatus(
          _accessToken ?? '',
          intOrderId,
          newStatus,
        ).timeout(const Duration(seconds: 8));

        if (responseData['order'] is Map) {
          _upsertOrderInList(responseData['order']);
        } else {
          await fetchOrders();
        }

        unawaited(fetchAdminFinancialReports());
        notifyListeners();
        return;
      } catch (_) {}
    }

    final updatePayload = <String, dynamic>{
      'status': newStatus,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      if (newStatus == 'delivered') 'payment_status': 'paid',
    };

    final updated = await supabase
        .from('orders')
        .update(updatePayload)
        .eq('id', intOrderId)
        .select()
        .single();

    _upsertOrderInList(updated);
    unawaited(fetchAdminFinancialReports());
    notifyListeners();
  }

  Future<void> courierRespondToOrder(dynamic orderId, bool accepted) async {
    await _submitCourierOrderAction(orderId, accepted ? 'accept' : 'reject');
  }

  Future<void> courierUpdateArrival(dynamic orderId) async {
    await _submitCourierOrderAction(orderId, 'arrived');
  }

  Future<void> markOrderDelivered(dynamic orderId) async {
    await _submitCourierOrderAction(orderId, 'delivered');
    addNotification(
        'تم تسليم الطلب', 'تم تأكيد استلام المبلغ النقدي عند التسليم');
  }
}

class _UserMock {
  final String name;
  final String phone;
  _UserMock(this.name, this.phone);
}
