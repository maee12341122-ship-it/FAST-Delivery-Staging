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
      for (var p in productsList) {
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
  RealtimeChannel? _ordersChannel;

  static const bool _useTestOtpBypass = true;
  static const String _testOtpCode = '1234';

  bool _isCreatingOrder = false;

  AppState() {
    _initializeApplicationState();
    _initAuthListener();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _settingsSub?.cancel();
    if (_ordersChannel != null) {
      supabase.removeChannel(_ordersChannel!);
    }
    _httpClient.close();
    super.dispose();
  }

  String? get _accessToken => supabase.auth.currentSession?.accessToken;

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
    JsonMap body,
  ) async {
    final response = await _httpClient
        .post(
          _buildBackendUri(path),
          headers: _backendHeaders(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(milliseconds: 1500));

    final decoded =
        response.body.isNotEmpty ? jsonDecode(response.body) : <String, dynamic>{};

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

  bool _isCourierSession(User? user) {
    return user?.appMetadata['role']?.toString() == 'courier';
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

  Future<void> _syncAdminProfileFromAuth(User? user) async {
    if (user == null) return;
    var adminPhone = '';
    var adminName = user.userMetadata?['name']?.toString() ?? 'المشرف';

    try {
      final adminRow = await supabase
          .from('admins')
          .select()
          .or('auth_user_id.eq.${user.id},email.eq.${user.email ?? ''}')
          .maybeSingle();
      if (adminRow != null) {
        adminPhone = _normalizePhone(adminRow['phone']?.toString() ?? '');
        if ((adminRow['name']?.toString() ?? '').trim().isNotEmpty) {
          adminName = adminRow['name'].toString().trim();
        }
      }
    } catch (_) {}

    if (adminPhone.isEmpty) {
      adminPhone = _normalizePhone(
        user.phone ??
            user.userMetadata?['phone']?.toString() ??
            userProfile?['phone']?.toString() ??
            '',
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
          isAdminLoggedIn = true;
          currentCourier = null;
          await _syncAdminProfileFromAuth(session.user);
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
        isAdminLoggedIn = true;
        currentCourier = null;
        await _syncAdminProfileFromAuth(session.user);
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
      if (isAdminLoggedIn && token != null && token.isNotEmpty) {
        try {
          final backendOrders = await ApiService.fetchAdminOrders(token)
              .timeout(const Duration(milliseconds: 1500));
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
      fetchProductsFromSupabase();
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

  // حساب قيمة المنتجات فقط دون إضافة رسوم أو عمولات تلقائية زيادة
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

      for (var order in response) {
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
    if (code.trim().isEmpty) {
      return 'الرجاء إدخال رمز الكوبون';
    }

    try {
      final response = await ApiService.validateCoupon(
        code.trim(),
        cartSubtotal,
        explicitToken: _accessToken,
      );

      couponDiscountAmount =
          double.tryParse(response['discount_amount'].toString()) ?? 0.0;
      activeCouponCode = response['code']?.toString() ?? code.trim();

      notifyListeners();
      return response['message']?.toString() ?? 'تم تطبيق الكوبون بنجاح';
    } catch (e) {
      return e.toString().replaceAll('Exception: ', '');
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

      for (var row in response) {
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
      userProfile!['address'] = formattedAddress;
      notifyListeners();
    }
  }

  Future<void> fetchUserAddressesFromSupabase() async {
    if (userProfile == null ||
        userProfile!['phone'] == null ||
        userProfile!['phone']!.isEmpty) {
      _loadUserAddressesFromPrefs();
      return;
    }

    try {
      final cleanPhone = _normalizePhone(userProfile!['phone']!);
      final response = await supabase
          .from('customer_addresses')
          .select()
          .eq('customer_phone', cleanPhone);

      _userAddresses.clear();
      for (var row in response) {
        _userAddresses.add(AddressModel(
          id: row['id'].toString(),
          title: row['title']?.toString() ?? 'عنوان',
          area: row['area']?.toString() ?? '',
          details: row['details']?.toString() ?? '',
          instructions: row['instructions']?.toString() ?? '',
        ));
      }
      _saveUserAddressesFromPrefs();
      notifyListeners();
    } catch (e) {
      _loadUserAddressesFromPrefs();
    }
  }

  Future<void> addUserAddress(AddressModel address) async {
    _userAddresses.add(address);
    if (_userAddresses.length == 1) {
      selectDefaultAddress(address);
    }
    _saveUserAddressesFromPrefs();
    notifyListeners();

    if (userProfile != null && userProfile!['phone'] != null) {
      try {
        final cleanPhone = _normalizePhone(userProfile!['phone'] ?? '');
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
    _saveUserAddressesFromPrefs();
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
        for (var item in decodedList) {
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
    return phone;
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

      var query = supabase
          .from('ratings_and_reviews')
          .select('id')
          .eq('order_id', intOrderId)
          .eq('target_type', 'courier');

      if (customerPhone.isNotEmpty) {
        query = query.eq('customer_phone', customerPhone);
      }

      final existing = await query.maybeSingle();

      final payload = <String, dynamic>{
        'order_id': intOrderId,
        'target_type': 'courier',
        'target_id': targetId,
        'rating': rating,
        'comment': reviewText.trim(),
        if (customerPhone.isNotEmpty) 'customer_phone': customerPhone,
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

      var query = supabase
          .from('ratings_and_reviews')
          .select('id')
          .eq('order_id', intOrderId)
          .eq('target_type', 'restaurant');

      if (customerPhone.isNotEmpty) {
        query = query.eq('customer_phone', customerPhone);
      }

      final existing = await query.maybeSingle();

      final payload = <String, dynamic>{
        'order_id': intOrderId,
        'target_type': 'restaurant',
        'target_id': targetId,
        'rating': rating,
        'comment': reviewText.trim(),
        if (customerPhone.isNotEmpty) 'customer_phone': customerPhone,
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
    return null;
  }

  Future<void> sendAutoNotification({
    String? playerId,
    String? targetPlayerId,
    required String title,
    String? message,
    String? body,
  }) async {}

  int startHour = 8;
  int endHour = 24;
  int deliveryFee = 500;

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
    if (userProfile != null) {
      userProfile!['city'] = city;
    }
    notifyListeners();
  }

  Stream<JsonList> getMessagesForOrder(dynamic orderId, String targetChat) {
    return supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('order_id', orderId)
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

    final newMessage = {
      'order_id': orderId,
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
    Share.share(
      'حمل تطبيق Fast Delivery App - أسرع خدمة توصيل\nhttps://play.google.com/store/apps/details?id=com.example.taiz_express',
      subject: 'تطبيق Fast Delivery App',
    );
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

  Future<void> fetchStoreSettings() async {
    try {
      final response = await supabase.from('settings').select().maybeSingle();
      if (response != null) {
        startHour = int.tryParse(response['start_hour'].toString()) ?? 8;
        endHour = int.tryParse(response['end_hour'].toString()) ?? 24;
        deliveryFee =
            int.tryParse(response['delivery_fee']?.toString() ?? '500') ?? 500;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('خطأ في الإعدادات: $e');
    }
  }

  void listenToStoreSettingsRealtime() {
    try {
      _settingsSub?.cancel();
      _settingsSub =
          supabase.from('settings').stream(primaryKey: ['id']).listen((data) {
        if (data.isNotEmpty) {
          startHour = int.tryParse(data.first['start_hour'].toString()) ?? 8;
          endHour = int.tryParse(data.first['end_hour'].toString()) ?? 24;
          deliveryFee =
              int.tryParse(data.first['delivery_fee']?.toString() ?? '500') ??
                  500;
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('خطأ: $e');
    }
  }

  Future<void> updateStoreHours(int start, int end) async {
    startHour = start;
    endHour = end;
    notifyListeners();
    try {
      await supabase.from('settings').upsert({
        'id': 1,
        'start_hour': start,
        'end_hour': end,
        'delivery_fee': deliveryFee,
      });
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
    await supabase.from('settings').upsert({
      'id': 1,
      'start_hour': startHour,
      'end_hour': endHour,
      'delivery_fee': deliveryFee,
    });
    notifyListeners();
  }

  bool get isStoreOpen {
    final now = DateTime.now();
    final currentHour = now.hour;
    if (endHour > startHour) {
      return currentHour >= startHour && currentHour < endHour;
    } else {
      return currentHour >= startHour || currentHour < endHour;
    }
  }

  bool isAdminLoggedIn = false;

  Future<bool> loginAdminFromSupabase(String username, String password) async {
    try {
      final raw = username.trim().toLowerCase();
      final email = raw.contains('@') ? raw : '$raw@fast.local';
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.user == null || _isCourierSession(response.user)) {
        await supabase.auth.signOut();
        isAdminLoggedIn = false;
        return false;
      }
      isAdminLoggedIn = true;
      currentCourier = null;
      await _syncAdminProfileFromAuth(response.user);
      await fetchCouriersFromSupabase();
      listenToOrdersRealtime();
      notifyListeners();
      return true;
    } catch (e) {
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
      : _UserMock(userProfile!['name'] ?? '', userProfile!['phone'] ?? '');

  String? get currentUserId => userProfile?['phone'];

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
    final record = await supabase
        .from('customers')
        .select()
        .or('phone.eq.$cleanPhone,phone.eq.$formattedPhone')
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
          .eq('id', orderId)
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

    if (_useTestOtpBypass) {
      var existsInDb = false;
      try {
        final dbRecord = await fetchCustomerRecordByPhone(cleanPhone);
        existsInDb = dbRecord != null;
        if (existsInDb) {
          await restoreLastCustomerOrder();
        }
      } catch (e) {
        debugPrint('خطأ في التحقق من العميل في قاعدة البيانات: $e');
      }
      notifyListeners();
      return {
        'exists': existsInDb,
        'message': existsInDb
            ? 'تم العثور على حسابك وجلب بياناتك. رمز التحقق التجريبي هو $_testOtpCode'
            : 'رمز التحقق التجريبي هو $_testOtpCode',
      };
    }

    try {
      final response = await _postBackend('/api/auth/otp/request', {
        'phone': cleanPhone,
      });
      return {
        'exists': response['exists'] ?? false,
        'message':
            response['message']?.toString() ?? 'تم إرسال رمز التحقق بنجاح',
      };
    } catch (e) {
      debugPrint('خطأ في طلب رمز التحقق');
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    } finally {
      notifyListeners();
    }
  }

  Future<bool> verifyOtpAndLogin(String phone, String enteredOtp) async {
    if (enteredOtp.trim().isEmpty) return false;
    final cleanPhone = _normalizePhone(phone);
    if (cleanPhone.isEmpty) return false;

    if (_useTestOtpBypass) {
      if (enteredOtp.trim() != _testOtpCode) return false;

      try {
        final dbRecord = await fetchCustomerRecordByPhone(cleanPhone);
        if (dbRecord != null) {
          await restoreLastCustomerOrder();
          return true;
        }
      } catch (e) {
        debugPrint('خطأ في جلب سجل العميل بعد التحقق: $e');
      }

      userProfile = {
        'phone': cleanPhone,
        'name': '',
        'address': '',
        'city': currentCity,
      };
      await _persistUserSessionToPrefs(userProfile!);
      await fetchUserAddressesFromSupabase();
      notifyListeners();
      return true;
    }

    try {
      final response = await _postBackend('/api/auth/otp/verify', {
        'phone': cleanPhone,
        'otp_code': enteredOtp.trim(),
      });

      final verified =
          response['verified'] == true || response['success'] == true;
      if (!verified) return false;

      if (response['session'] is Map) {
        final sessionMap = response['session'] as Map;
        final refreshToken = sessionMap['refresh_token']?.toString();
        if (refreshToken != null && refreshToken.isNotEmpty) {
          try {
            await supabase.auth.setSession(refreshToken);
          } catch (_) {}
        }
      }

      final dbRecord = await fetchCustomerRecordByPhone(cleanPhone);
      if (dbRecord != null) {
        await restoreLastCustomerOrder();
        return true;
      }

      if (userProfile == null) {
        userProfile = {
          'phone': cleanPhone,
          'name': response['name']?.toString() ?? '',
          'address': response['address']?.toString() ?? '',
          'city': currentCity,
        };
        await _persistUserSessionToPrefs(userProfile!);
        notifyListeners();
      }
      return true;
    } catch (e) {
      debugPrint('خطأ في التحقق من الرمز');
      return false;
    }
  }

  Future<void> updateUser({String? name, String? address, String? phone}) async {
    if (userProfile != null) {
      if (phone != null && phone.trim().isNotEmpty) {
        userProfile!['phone'] = _normalizePhone(phone);
      }
      if (name != null) {
        userProfile!['name'] = name;
      }
      if (address != null) {
        userProfile!['address'] = address;
      }
    }
    await saveUserProfileDetails(
      name ?? userProfile?['name'] ?? '',
      address ?? userProfile?['address'] ?? '',
    );
  }

  Future<void> saveUserProfileDetails(String name, String address) async {
    if (userProfile != null) {
      final cleanPhone = _normalizePhone(userProfile!['phone'] ?? '');
      userProfile!['name'] = name;
      userProfile!['address'] = address;
      userProfile!['phone'] = cleanPhone;

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

  Future<void> _loadCourierSession() async {
    final user = supabase.auth.currentUser;
    if (!_isCourierSession(user)) {
      return;
    }
    try {
      final row = await supabase
          .from('couriers')
          .select()
          .eq('auth_user_id', user!.id)
          .maybeSingle();
      if (row != null) {
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

    final email = '${username.trim().toLowerCase()}@courier.fast.local';

    final authRes = await supabase.auth.signUp(
      email: email,
      password: password,
      data: {'role': 'courier', 'name': name.trim()},
    );

    final newUserId = authRes.user?.id;

    await supabase.from('couriers').insert({
      'name': name.trim(),
      'phone': phone.trim(),
      'username': username.trim(),
      if (newUserId != null) 'auth_user_id': newUserId,
      'status': 'available',
      'is_logged_in': false,
    });

    await fetchCouriersFromSupabase();
  }

  Future<void> updateCourier(DeliveryModel courier) async {
    final status = !courier.isEnabled
        ? 'disabled'
        : (courier.isAvailable ? 'available' : 'busy');
    final intId = int.tryParse(courier.id);
    if (intId != null) {
      await supabase.from('couriers').update({
        'name': courier.name.trim(),
        'phone': courier.phone.trim(),
        'status': status,
      }).eq('id', intId);
    } else {
      await supabase.from('couriers').update({
        'name': courier.name.trim(),
        'phone': courier.phone.trim(),
        'status': status,
      }).eq('id', courier.id);
    }
    await fetchCouriersFromSupabase();
  }

  Future<void> setCourierAvailability(String courierId, bool available) async {
    final status = available ? 'available' : 'busy';
    final intId = int.tryParse(courierId);
    if (intId != null) {
      await supabase
          .from('couriers')
          .update({'status': status})
          .eq('id', intId);
    } else {
      await supabase
          .from('couriers')
          .update({'status': status})
          .eq('id', courierId);
    }
    await fetchCouriersFromSupabase();
  }

  Future<void> removeCourier(String courierId) async {
    final intId = int.tryParse(courierId);
    if (intId != null) {
      await supabase.from('couriers').delete().eq('id', intId);
    } else {
      await supabase.from('couriers').delete().eq('id', courierId);
    }
    await fetchCouriersFromSupabase();
  }

  // تسوية مستحقات المندوب بناءً على رسوم التوصيل الفعلية المسجلة فقط
  Future<void> settleCourierEarnings(String courierName) async {
    try {
      final cleanCourierName = courierName.trim();
      if (cleanCourierName.isEmpty) {
        throw Exception('اسم المندوب مطلوب لتسوية المستحقات.');
      }

      final unsettledRows = await supabase
          .from('orders')
          .select('id, delivery_fee, is_settled')
          .eq('assigned_courier', cleanCourierName)
          .eq('status', 'delivered')
          .or('is_settled.is.null,is_settled.eq.false');

      final eligibleOrders = List<Map<String, dynamic>>.from(unsettledRows);
      if (eligibleOrders.isEmpty) {
        throw Exception('لا توجد طلبات مكتملة وغير مسوّاة لهذا المندوب.');
      }

      var totalSettledAmount = 0.0;
      final List<int> orderIds = [];
      for (final row in eligibleOrders) {
        final idVal = int.tryParse(row['id'].toString());
        if (idVal != null) {
          orderIds.add(idVal);
        }
        final amount =
            double.tryParse((row['delivery_fee'] ?? '0').toString()) ?? 0.0;
        totalSettledAmount += amount;
      }

      if (orderIds.isEmpty) {
        throw Exception('تعذر تحديد معرفات الطلبات المستحقة للتسوية.');
      }

      await supabase.from('courier_settlements').insert({
        'courier_name': cleanCourierName,
        'orders_count': orderIds.length,
        'total_amount': totalSettledAmount,
        'settled_at': DateTime.now().toIso8601String(),
      });

      await supabase
          .from('orders')
          .update({'is_settled': true})
          .inFilter('id', orderIds)
          .eq('status', 'delivered');

      debugPrint(
        'تمت تسوية ${orderIds.length} طلبات للمندوب $cleanCourierName بإجمالي: $totalSettledAmount',
      );

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
      final email = '${username.trim().toLowerCase()}@courier.fast.local';
      final auth = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (auth.user == null || !_isCourierSession(auth.user)) {
        await supabase.auth.signOut();
        return false;
      }

      final row = await supabase
          .from('couriers')
          .select()
          .eq('auth_user_id', auth.user!.id)
          .maybeSingle();

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
    try {
      final res = await ApiService.adminUpdateOrderStatus(
        _accessToken ?? '',
        intId,
        status,
      ).timeout(const Duration(milliseconds: 1500));
      if (res['order'] is Map) {
        _upsertOrderInList(res['order']);
      } else {
        await fetchOrders();
      }
    } catch (_) {
      final updatedRow = await supabase
          .from('orders')
          .update({'status': status})
          .eq('id', intId)
          .select()
          .maybeSingle();
      if (updatedRow != null) {
        _upsertOrderInList(updatedRow);
      }
    }
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
    await supabase.from('products').delete().eq('id', id);
    await fetchProductsFromSupabase();
    notifyListeners();
  }

  Future<void> upsertProduct(ProductModel product) async {
    await supabase.from('products').upsert({
      'id': product.id,
      'name': product.name.trim(),
      'description': product.description.trim(),
      'restaurant_name': product.restaurantName.trim(),
      'price': product.price,
      'category': product.category,
      'available': product.available,
      'image_url': product.imageUrl,
      'unit': product.unit,
      'is_variable_price': product.isVariablePrice,
    }, onConflict: 'id');
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
    if (clean.startsWith('0')) {
      clean = clean.substring(1);
    }
    if (clean.startsWith('967')) {
      clean = clean.substring(3);
    }
    return clean;
  }

  List<Map<String, dynamic>> get customerOrders {
    if (userProfile == null ||
        userProfile!['phone'] == null ||
        userProfile!['phone']!.isEmpty) {
      return [];
    }
    final myPhone = _normalizePhone(userProfile!['phone']!);

    return orders.where((o) {
      final orderPhone = _normalizePhone(o['phone']?.toString() ?? '');
      return orderPhone.isNotEmpty && orderPhone == myPhone;
    }).toList();
  }

  void addNotification(String title, String body) {
    notifications.insert(
        0, {'title': title, 'body': body, 'time': DateTime.now()});
    NotificationService.showLocalNotification(title, body);
    notifyListeners();
  }

  void addLocalNotification(String title, String body, {String? type}) {
    notifications.insert(0, {
      'title': title,
      'body': body,
      'time': DateTime.now(),
      'type': type ?? 'general',
    });
    NotificationService.showLocalNotification(title, body);
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

  void listenToOrdersRealtime() async {
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

  // إنشاء الطلب بدون إضافة أي عمولات أو رسوم تلقائية إضافية
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
      final double cleanProductsTotal = productsTotal > 0 ? productsTotal : 0.0;

      final itemsPayload = _cartItems.map((cartItem) {
        return {
          'product_id': cartItem.id,
          'quantity': cartItem.quantity,
        };
      }).toList();

      JsonMap order = {};
      var trackingCode = (10000000 + Random().nextInt(90000000)).toString();

      final responseData = await ApiService.createOrder(
        items: itemsPayload,
        address: address.trim(),
        notes: itemsDesc.trim(),
        customerName: customerName.trim(),
        phone: normalizedPhone,
        couponCode: activeCouponCode,
        paymentMethod: paymentMethod,
        paymentAccount: paymentAccount,
        productsTotal: cleanProductsTotal,
        trackingCode: trackingCode,
        token: _accessToken,
      );

      if (responseData['order'] is Map) {
        order = Map<String, dynamic>.from(responseData['order']);
        trackingCode =
            order['tracking_code']?.toString().trim().isNotEmpty == true
                ? order['tracking_code'].toString()
                : trackingCode;
      }

      // اعتماد قيمة المنتجات المدخلة مباشرة دون زيادة تلقائية
      order['products_total'] = cleanProductsTotal;
      order['total_price'] = cleanProductsTotal;

      if (order['id'] != null) {
        try {
          await supabase
              .from('orders')
              .update({
                'total_price': cleanProductsTotal,
                'products_total': cleanProductsTotal,
              })
              .eq('id', order['id']);
        } catch (_) {}
      }

      final orderId = order['id'];
      lastOrderTrackingCode = trackingCode;
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
      throw Exception('تعذر إرسال الطلب: $e');
    } finally {
      _isCreatingOrder = false;
    }
  }

  // تحديد رسوم التوصيل وحساب الإجمالي بجمع قيمة المنتجات + رسوم التوصيل المحددة فقط
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

      final existingIndex =
          orders.indexWhere((o) => o['id'].toString() == orderId.toString());
      final existingOrder = existingIndex >= 0
          ? Map<String, dynamic>.from(orders[existingIndex])
          : <String, dynamic>{};

      final productsTotal = _extractOrderProductsTotal(existingOrder);
      final newTotal = productsTotal + cleanFee;

      try {
        final responseData = await ApiService.adminPricingOrder(
          _accessToken ?? '',
          intOrderId,
          cleanFee,
          cleanCourierName,
        ).timeout(const Duration(milliseconds: 1500));

        if (responseData['order'] is Map) {
          updatedOrder = Map<String, dynamic>.from(responseData['order']);
        }
      } catch (_) {}

      final dbRow = await supabase
          .from('orders')
          .update({
            'delivery_fee': cleanFee,
            'total_price': newTotal,
            'products_total': productsTotal,
            'assigned_courier': cleanCourierName,
            'status': 'pricingSentToCustomer',
          })
          .eq('id', intOrderId)
          .select()
          .maybeSingle();

      if (dbRow != null) {
        updatedOrder = {
          ...updatedOrder,
          ...Map<String, dynamic>.from(dbRow),
        };
      }

      updatedOrder['id'] = updatedOrder['id'] ?? intOrderId;
      updatedOrder['delivery_fee'] = cleanFee;
      updatedOrder['products_total'] = productsTotal;
      updatedOrder['total_price'] = newTotal;
      updatedOrder['assigned_courier'] = cleanCourierName;
      updatedOrder['status'] = updatedOrder['status'] ?? 'pricingSentToCustomer';

      _upsertOrderInList(updatedOrder);
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
    final phone = userProfile?['phone'];
    if (phone == null) {
      throw Exception('رمز متابعة الطلب غير موجود أو لم يتم تسجيل الدخول.');
    }

    final intOrderId = int.tryParse(orderId.toString());
    if (intOrderId == null) {
      throw Exception('معرف الطلب غير صالح.');
    }

    final newStatus =
        action == 'approve' ? 'waitingCourierApproval' : 'cancelled';

    try {
      final responseData =
          await _postBackend('/api/orders/$intOrderId/customer-action', {
        'action': action,
        'status': newStatus,
        'phone': _normalizePhone(phone.toString()),
      });

      if (responseData['order'] is Map) {
        _upsertOrderInList(responseData['order']);
      } else {
        await fetchOrders();
      }
    } catch (_) {
      final updatedRow = await supabase
          .from('orders')
          .update({'status': newStatus})
          .eq('id', intOrderId)
          .select()
          .maybeSingle();
      if (updatedRow != null) {
        _upsertOrderInList(updatedRow);
      }
    }

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

    try {
      final responseData = await ApiService.courierUpdateOrderStatus(
        _accessToken ?? '',
        intOrderId,
        newStatus,
      ).timeout(const Duration(milliseconds: 1500));

      if (responseData['order'] is Map) {
        _upsertOrderInList(responseData['order']);
      } else {
        await fetchOrders();
      }
    } catch (_) {
      final updatedRow = await supabase
          .from('orders')
          .update({'status': newStatus})
          .eq('id', intOrderId)
          .select()
          .maybeSingle();
      if (updatedRow != null) {
        _upsertOrderInList(updatedRow);
      }
    }

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
