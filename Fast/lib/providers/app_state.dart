import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http; // 👈 مكتبة الاتصال لإرسال إشعارات OneSignal التلقائية
import '../models/cart_item_model.dart';
import '../models/product_model.dart';
import '../models/address_model.dart';
import '../models/delivery_model.dart';
import '../services/notification_service.dart';

class AppState extends ChangeNotifier {
  final supabase = Supabase.instance.client;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  AppState() {
    _loadAdminSession();
    _loadCourierSession();
    _loadUserSession();
    fetchStoreSettings();
    fetchProductsFromSupabase();
    fetchCouriersFromSupabase();
    listenToOrdersRealtime();
    listenToStoreSettingsRealtime();
  }

  // --- 🔔 دالة إرسال الإشعارات التلقائية الفورية عبر OneSignal ---
  Future<void> sendAutoNotification({
    required String targetPlayerId,
    required String title,
    required String body,
  }) async {
    if (targetPlayerId.isEmpty) return;

    // استبدل المفاتيح أدناه بمفاتيح تطبيقك من لوحة OneSignal
    const String oneSignalAppId = 'YOUR_ONESIGNAL_APP_ID'; 
    const String oneSignalRestApiKey = 'YOUR_ONESIGNAL_REST_API_KEY'; 

    try {
      await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Basic $oneSignalRestApiKey',
        },
        body: jsonEncode({
          'app_id': oneSignalAppId,
          'include_player_ids': [targetPlayerId],
          'headings': {'en': title, 'ar': title},
          'contents': {'en': body, 'ar': body},
        }),
      );
      debugPrint('✅ تم إرسال الإشعار التلقائي بنجاح عبر OneSignal');
    } catch (e) {
      debugPrint('❌ خطأ في إرسال الإشعار التلقائي: $e');
    }
  }

  // --- ❤️ إدارة المنتجات المفضلة ---
  final List<String> _favoriteProductIds = [];
  List<String> get favoriteProductIds => _favoriteProductIds;

  bool isProductFavorite(String productId) {
    return _favoriteProductIds.contains(productId);
  }

  void toggleFavorite(String productId) {
    if (_favoriteProductIds.contains(productId)) {
      _favoriteProductIds.remove(productId);
      debugPrint('❤️ تم إزالة المنتج من المفضلة: $productId');
    } else {
      _favoriteProductIds.add(productId);
      debugPrint('❤️ تم إضافة المنتج للمفضلة: $productId');
    }
    notifyListeners();
  }

  List<ProductModel> get favoriteProducts {
    return products.where((p) => _favoriteProductIds.contains(p.id)).toList().cast<ProductModel>();
  }

  // --- 🏠 قائمة وعناوين العميل المحفوظة (تعدد العناوين) ---
  final List<AddressModel> _userAddresses = [];
  List<AddressModel> get userAddresses => _userAddresses;

  void addUserAddress(AddressModel address) {
    _userAddresses.add(address);
    if (_userAddresses.length == 1) {
      selectDefaultAddress(address);
    }
    notifyListeners();
  }

  void removeUserAddress(String id) {
    _userAddresses.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  void selectDefaultAddress(AddressModel address) {
    String formattedAddress = '${address.title}: ${address.area} - ${address.details}';
    if (address.instructions.isNotEmpty) {
      formattedAddress += ' (تعليمات: ${address.instructions})';
    }
    addOrUpdateAddress(formattedAddress);
    notifyListeners();
  }

  // --- 🗺️ دالة ترجمة حالات الطلبات إلى اللغة العربية ---
  String getArabicStatus(String? status) {
    switch (status?.trim()) {
      case 'waitingForPricing':
        return 'بانتظار تحديد السعر من الإدارة ⏳';
      case 'pricingSentToCustomer':
        return 'تم تحديد السعر، بانتظار موافقة العميل 💰';
      case 'approvedByCustomer':
      case 'waitingCourierApproval':
        return 'بانتظار موافقة المندوب 🛵';
      case 'acceptedByCourier':
        return 'وافق المندوب على التوصيل 🚀';
      case 'rejectedByCourier':
        return 'رفض المندوب الطلب ⚠️';
      case 'arrivedToCustomer':
      case 'arrived':
        return 'وصل المندوب إلى موقع العميل 📍';
      case 'delivered':
        return 'تم تسليم الطلب بنجاح ✅';
      case 'cancelled':
        return 'تم إلغاء الطلب 🚫';
      default:
        return status ?? 'قيد المعالجة 🔄';
    }
  }

  // --- دوال مساعدة لجلب OneSignal Player ID لمختلف الأطراف من قاعدة البيانات ---
  
  Future<String?> getPlayerIdForUser(String userIdOrPhone, String tableName) async {
    try {
      if (tableName == 'customers') {
        final response = await supabase
            .from(tableName)
            .select('onesignal_player_id')
            .eq('phone', userIdOrPhone)
            .maybeSingle();
        
        if (response != null && response['onesignal_player_id'] != null) {
          return response['onesignal_player_id'].toString();
        }
      } else {
        final response = await supabase
            .from(tableName)
            .select('onesignal_player_id')
            .eq('id', userIdOrPhone)
            .maybeSingle();
        
        if (response != null && response['onesignal_player_id'] != null) {
          return response['onesignal_player_id'].toString();
        }
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في جلب Player ID للمستخدم من $tableName: $e');
    }
    return null;
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
      debugPrint('⚠️ خطأ في جلب Player ID للمندوب بالاسم: $e');
    }
    return null;
  }

  Future<List<String>> getAllAdminPlayerIds() async => [];

  Future<String?> getReceiverPlayerIdForChat({
    required String orderId,
    required String senderRole,
    required String targetChat,
  }) async {
    try {
      final orderRes = await supabase
          .from('orders')
          .select('*')
          .eq('id', orderId)
          .maybeSingle();

      if (orderRes == null) return null;

      if (targetChat == 'admin_customer') {
        if (senderRole == 'admin') {
          String customerPhone = orderRes['phone']?.toString() ?? '';
          if (customerPhone.isNotEmpty) {
            final custRes = await supabase
                .from('customers')
                .select('onesignal_player_id')
                .eq('phone', customerPhone)
                .maybeSingle();
            return custRes?['onesignal_player_id']?.toString();
          }
        } else {
          List<String> admins = await getAllAdminPlayerIds();
          return admins.isNotEmpty ? admins.first : null;
        }
      } else if (targetChat == 'admin_courier') {
        if (senderRole == 'admin') {
          String courierName = orderRes['assigned_courier']?.toString() ?? '';
          return await getCourierPlayerIdByName(courierName);
        } else {
          List<String> admins = await getAllAdminPlayerIds();
          return admins.isNotEmpty ? admins.first : null;
        }
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في تحديد المستقبل للشات: $e');
    }
    return null;
  }

  // --- إعدادات أوقات الدوام والدعم ---
  int startHour = 8;
  int endHour = 24;
  int deliveryFee = 500;
  int get workStartHour => startHour;
  int get workEndHour => endHour;
  String customerSupportPhone = '775145534';

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

  // --- إدارة رسائل الشات اللحظية المعزولة ---
  Stream getMessagesForOrder(dynamic orderId, String targetChat) {
    return supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('order_id', orderId)
        .order('created_at', ascending: true);
  }

  Future<void> sendChatMessage(dynamic orderId, String senderRole, String targetChat, String messageText) async {
    if (messageText.trim().isEmpty) return;

    final newMessage = {
      'order_id': orderId,
      'sender_type': senderRole,
      'target_chat': targetChat,
      'message_text': messageText,
    };

    try {
      await supabase.from('messages').insert(newMessage);
      debugPrint('✅ تم إرسال الرسالة بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في إرسال رسالة الشات: $e');
    }
  }

  Future<void> openFastWhatsApp({String message = 'مرحباً، أريد التسجيل في تطبيق FAST - تعز.'}) async {
    final uri = Uri.parse('https://wa.me/967775145534?text=${Uri.encodeComponent(message)}');
    if (!await canLaunchUrl(uri)) {
      throw Exception('تعذر فتح واتساب أو المتصفح.');
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void shareApp() {
    Share.share(
      'حمل تطبيق FAST - أسرع خدمة توصيل في تعز! 🚀\nhttps://play.google.com/store/apps/details?id=com.example.taiz_express',
      subject: 'تطبيق FAST تعز',
    );
  }

  Future<void> requestLocationAndNotificationPermissions() async {
    try {
      LocationPermission locationPermission = await Geolocator.checkPermission();
      if (locationPermission == LocationPermission.denied) {
        locationPermission = await Geolocator.requestPermission();
      }

      if (locationPermission == LocationPermission.deniedForever) {
        debugPrint('⚠️ إذن الموقع مرفوض نهائياً من إعدادات الهاتف');
      } else {
        debugPrint('📍 تم التعامل مع إذن الموقع بنجاح');
      }

      PermissionStatus notificationStatus = await Permission.notification.status;
      if (!notificationStatus.isGranted) {
        notificationStatus = await Permission.notification.request();
      }

      if (notificationStatus.isGranted) {
        debugPrint('🔔 تم منح إذن الإشعارات بنجاح عبر النظام');
        
        try {
          await OneSignal.Notifications.requestPermission(true);
        } catch (e) {
          debugPrint('⚠️ خطأ في تفعيل OneSignal بعد الاذن: $e');
        }

        addNotification('تطبيق FAST - تعز', 'تم تفعيل الإشعارات وتحديد الموقع بنجاح 🚀');
      } else {
        debugPrint('⚠️ تم رفض إذن الإشعارات من المستخدم أو تم تجاهله من النظام');
      }

    } catch (e) {
      debugPrint('❌ خطأ في طلب الأذونات المتسلسلة: $e');
    }
  }

  Future<void> fetchStoreSettings() async {
    try {
      final response = await supabase.from('settings').select().maybeSingle();
      if (response != null) {
        startHour = int.tryParse(response['start_hour'].toString()) ?? 8;
        endHour = int.tryParse(response['end_hour'].toString()) ?? 24;
        deliveryFee = int.tryParse(response['delivery_fee']?.toString() ?? '500') ?? 500;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في جلب إعدادات الدوام: $e');
    }
  }

  void listenToStoreSettingsRealtime() {
    try {
      supabase.from('settings').stream(primaryKey: ['id']).listen((data) {
        if (data.isNotEmpty) {
          startHour = int.tryParse(data.first['start_hour'].toString()) ?? 8;
          endHour = int.tryParse(data.first['end_hour'].toString()) ?? 24;
          deliveryFee = int.tryParse(data.first['delivery_fee']?.toString() ?? '500') ?? 500;
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('⚠️ خطأ في الاستماع للإعدادات: $e');
    }
  }

  Future<void> updateStoreSettings(int start, int end) async {
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
      debugPrint('❌ خطأ في حفظ أوقات الدوام: $e');
    }
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

  void _loadAdminSession() async {
    final user = supabase.auth.currentUser;
    isAdminLoggedIn = user != null && user.appMetadata['role']?.toString() == 'admin';
    notifyListeners();
  }

  Future<bool> loginAdminFromSupabase(String username, String password) async {
    try {
      final raw = username.trim().toLowerCase();
      final email = raw.contains('@') ? raw : '$raw@fast.local';
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final role = response.user?.appMetadata['role']?.toString();
      if (response.user == null || role != 'admin') {
        await supabase.auth.signOut();
        return false;
      }
      isAdminLoggedIn = true;
      await fetchCouriersFromSupabase();
      listenToOrdersRealtime();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Admin auth failed: $e');
      return false;
    }
  }

  Future<void> logoutAdmin() async {
    isAdminLoggedIn = false;
    await supabase.auth.signOut();
    notifyListeners();
  }

  Map<String, String>? userProfile;
  String? generatedDynamicOtp;
  String? lastOrderTrackingCode;

  dynamic get user => userProfile == null ? null : _UserMock(userProfile!['name'] ?? '', userProfile!['phone'] ?? '');

  String? get currentUserId => userProfile?['phone'];

  void _loadUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('userPhone');
    final name = prefs.getString('userName');
    final address = prefs.getString('userAddress');
    final city = prefs.getString('userCity') ?? currentCity;

    if (phone != null && phone.isNotEmpty) {
      try {
        final cleanPhone = _normalizePhone(phone);
        final response = await supabase
            .from('customers')
            .select()
            .eq('phone', cleanPhone)
            .maybeSingle();

        if (response != null) {
          userProfile = {
            'phone': cleanPhone,
            'name': response['name']?.toString() ?? name ?? '',
            'city': city,
            'address': response['address']?.toString() ?? address ?? '',
          };
          notifyListeners();
          await restoreLastCustomerOrder();
          return;
        }
      } catch (e) {
        debugPrint('⚠️ خطأ في استعادة الجلسة الفريدة: $e');
      }

      userProfile = {
        'phone': phone,
        'name': name ?? '',
        'city': city,
        'address': address ?? '',
      };
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
        final row = Map<String, dynamic>.from(response);
        orders.removeWhere((o) => o['id'].toString() == orderId);
        orders.add(row);
        _sortOrders();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('تعذر استعادة الطلب الأخير: $e');
    }
  }

  Future<bool> checkAndLoginCustomer(String phone) async {
    try {
      String cleanPhone = _normalizePhone(phone);
      String fullPhoneWithZero = '0$cleanPhone';
      String fullPhoneWith967 = '967$cleanPhone';

      final response = await supabase
          .from('customers')
          .select()
          .or('phone.eq.$cleanPhone,phone.eq.$fullPhoneWithZero,phone.eq.$fullPhoneWith967')
          .maybeSingle();

      if (response != null) {
        String name = response['name']?.toString() ?? '';
        String address = response['address']?.toString() ?? '';
        String dbPhone = response['phone']?.toString() ?? cleanPhone;

        userProfile = {
          'phone': dbPhone,
          'name': name,
          'city': currentCity,
          'address': address,
        };

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userPhone', dbPhone);
        await prefs.setString('userName', name);
        await prefs.setString('userAddress', address);
        await prefs.setString('userCity', currentCity);

        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ خطأ في فحص العميل: $e');
      return false;
    }
  }

  void requestOtpForPhone(String phone) {
    generatedDynamicOtp = null;
    openFastWhatsApp(message: 'مرحباً، أريد التسجيل في تطبيق FAST. رقم الهاتف: ${phone.trim()}').catchError((e) { debugPrint('WhatsApp unavailable: $e'); });
    notifyListeners();
  }

  bool continueWithoutPhoneVerification(String phone) {
    final cleanPhone = _normalizePhone(phone);
    if (cleanPhone.length < 9) return false;
    userProfile = {'phone': cleanPhone, 'name': '', 'city': currentCity, 'address': ''};
    notifyListeners();
    return true;
  }

  bool verifyOtpAndLogin(String phone, String enteredOtp) => false;

  Future<void> saveUserProfileDetails(String name, String address) async {
    if (userProfile != null) {
      userProfile!['name'] = name;
      userProfile!['address'] = address;
      String phone = userProfile!['phone'] ?? '';

      final prefs = await SharedPreferences.getInstance();
      prefs.setString('userName', name);
      prefs.setString('userAddress', address);

      try {
        await supabase.from('customers').upsert({
          'phone': phone,
          'name': name,
          'address': address,
        }, onConflict: 'phone');

        await requestLocationAndNotificationPermissions();

        String? playerId = OneSignal.User.pushSubscription.id;
        if (playerId != null && playerId.isNotEmpty) {
          await supabase.from('customers').update({'onesignal_player_id': playerId}).eq('phone', phone);
        }
      } catch (e) {
        debugPrint('❌ خطأ في حفظ العميل: $e');
      }

      notifyListeners();
    }
  }

  Future<void> updateUser({required String name, required String phone}) async {
    if (userProfile != null) {
      userProfile!['name'] = name;
      userProfile!['phone'] = _normalizePhone(phone);
      final prefs = await SharedPreferences.getInstance();
      prefs.setString('userName', name);
      prefs.setString('userPhone', userProfile!['phone']!);
      notifyListeners();
    }
  }

  Future<void> addOrUpdateAddress(dynamic addressModel) async {
    String addressDetails = addressModel is String ? addressModel : (addressModel.details ?? '');
    if (userProfile != null) {
      userProfile!['address'] = addressDetails;
      final prefs = await SharedPreferences.getInstance();
      prefs.setString('userAddress', addressDetails);
      notifyListeners();
    }
  }

  Future<void> setDefaultAddress(String addressId) async {
    notifyListeners();
  }

  void clearUser() => logoutUser();

  void setUser({required String name, required String phone, required dynamic address}) {
    String cleanPhone = _normalizePhone(phone);
    String addressDetails = address is String ? address : (address.details ?? '');

    userProfile = {
      'phone': cleanPhone,
      'name': name,
      'city': currentCity,
      'address': addressDetails,
    };

    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('userPhone', cleanPhone);
      prefs.setString('userName', name);
      prefs.setString('userAddress', addressDetails);
      prefs.setString('userCity', currentCity);
    });

    saveUserProfileDetails(name, addressDetails);
    notifyListeners();
  }

  void logoutUser() async {
    userProfile = null;
    final prefs = await SharedPreferences.getInstance();
    prefs.remove('userPhone');
    prefs.remove('userName');
    prefs.remove('userAddress');
    notifyListeners();
  }

  // --- إدارة جلسة وتأمين المناديب (جلسة واحدة فقط) ---
  Map<String, dynamic>? currentCourier;
  List couriers = [];

  void _loadCourierSession() async {
    final user = supabase.auth.currentUser;
    if (user == null || user.appMetadata['role']?.toString() != 'courier') return;
    try {
      final row = await supabase.from('couriers').select().eq('auth_user_id', user.id).maybeSingle();
      if (row != null) {
        currentCourier = Map<String, dynamic>.from(row);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('تعذر استعادة جلسة المندوب: $e');
    }
  }

  Future<void> fetchCouriersFromSupabase() async {
    try {
      final response = await supabase.from('couriers').select();
      couriers = response;
      _loadCourierSession();
      notifyListeners();
    } catch (e) {
      debugPrint('❌ خطأ في جلب المناديب: $e');
    }
  }

  Future<void> addCourier(String name, String phone, String username, String password) async {
    if (!isAdminLoggedIn || supabase.auth.currentUser?.appMetadata['role'] != 'admin') {
      throw Exception('يجب تسجيل دخول المشرف أولاً.');
    }
    if (password.length < 10) throw Exception('كلمة مرور المندوب يجب ألا تقل عن 10 أحرف.');
    final result = await supabase.functions.invoke('admin-create-courier', body: {
      'name': name.trim(),
      'phone': phone.trim(),
      'username': username.trim(),
      'password': password,
    });
    if (result.status < 200 || result.status >= 300) {
      throw Exception('تعذر إنشاء حساب المندوب: ${result.data}');
    }
    await fetchCouriersFromSupabase();
  }

  Future<bool> loginCourier(String username, String password) async {
    try {
      final email = '${username.trim().toLowerCase()}@courier.fast.local';
      final auth = await supabase.auth.signInWithPassword(email: email, password: password);
      
      if (auth.user == null || auth.user!.appMetadata['role']?.toString() != 'courier') {
        await supabase.auth.signOut();
        return false;
      }

      final row = await supabase.from('couriers').select().eq('auth_user_id', auth.user!.id).maybeSingle();
      
      if (row == null || row['status']?.toString() == 'disabled') {
        await supabase.auth.signOut();
        return false;
      }

      await supabase.from('couriers').update({'is_logged_in': true}).eq('id', row['id']);

      isAdminLoggedIn = false;
      currentCourier = Map<String, dynamic>.from(row);
      currentCourier!['is_logged_in'] = true;

      listenToOrdersRealtime();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('loggedCourierId', row['id'].toString());
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Courier authentication failed: $e');
      return false;
    }
  }

  Future<void> logoutCourier() async {
    if (currentCourier != null && currentCourier!['id'] != null) {
      try {
        await supabase.from('couriers').update({'is_logged_in': false}).eq('id', currentCourier!['id']);
      } catch (e) {
        debugPrint('⚠️ خطأ في تحرير جلسة المندوب: $e');
      }
    }

    currentCourier = null;
    await supabase.auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('loggedCourierId');
    notifyListeners();
  }

  final List<CartItemModel> _cartItems = [];
  List<CartItemModel> get cartItems => _cartItems;

  int get totalCartItemsCount => _cartItems.fold(0, (sum, item) => sum + item.quantity);
  double get totalAmount => _cartItems.fold(0.0, (sum, item) => sum + (item.price * item.quantity));

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
    notifyListeners();
  }

  void addCustomItem({required String name, required int price, required int quantity, required String notes}) {
    _cartItems.add(CartItemModel(
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      name: '$name (ملاحظات: $notes)',
      price: price.toDouble(),
      quantity: quantity,
      restaurantId: 'طلبات خاصة',
      imageUrl: '',
    ));
    notifyListeners();
  }

  void addCustomOrderToCart({required String customName, required double estimatedPrice}) {
    addCustomItem(name: customName, price: estimatedPrice.toInt(), quantity: 1, notes: '');
  }

  Future<void> updateBusinessSettings({required int startHour, required int endHour, required int deliveryFee}) async {
    if (!isAdminLoggedIn || supabase.auth.currentUser?.appMetadata['role'] != 'admin') throw Exception('صلاحية المشرف مطلوبة.');
    if (startHour < 0 || startHour > 23 || endHour < 1 || endHour > 24 || deliveryFee < 0) throw Exception('إعدادات غير صحيحة.');
    this.startHour = startHour; this.endHour = endHour; this.deliveryFee = deliveryFee;
    await supabase.from('settings').upsert({'id': 1, 'start_hour': startHour, 'end_hour': endHour, 'delivery_fee': deliveryFee});
    notifyListeners();
  }

  Future<void> updateCourier(DeliveryModel courier) async {
    if (!isAdminLoggedIn) throw Exception('صلاحية المشرف مطلوبة.');
    await supabase.from('couriers').update({
      'name': courier.name, 'phone': courier.phone,
      'status': courier.isEnabled ? (courier.isAvailable ? 'available' : 'busy') : 'disabled',
    }).eq('id', courier.id);
    await fetchCouriersFromSupabase();
  }

  Future<void> setCourierAvailability(String id, bool available) async {
    if (!isAdminLoggedIn) throw Exception('صلاحية المشرف مطلوبة.');
    await supabase.from('couriers').update({'status': available ? 'available' : 'busy'}).eq('id', id);
    await fetchCouriersFromSupabase();
  }

  Future<void> removeCourier(String id) async {
    if (!isAdminLoggedIn) throw Exception('صلاحية المشرف مطلوبة.');
    await supabase.from('couriers').update({'status': 'disabled'}).eq('id', id);
    await fetchCouriersFromSupabase();
  }

  Future<void> updateOrderStatus(String id, String status) async {
    if (!isAdminLoggedIn) throw Exception('صلاحية المشرف مطلوبة.');
    await supabase.from('orders').update({'status': status, 'admin_message': 'تم تحديث حالة الطلب من المشرف'}).eq('id', id);
    listenToOrdersRealtime();
  }

  Future<void> assignOrderToCourier(String orderId, String courierId) async {
    if (!isAdminLoggedIn) throw Exception('صلاحية المشرف مطلوبة.');
    final courier = await supabase.from('couriers').select('name').eq('id', courierId).single();
    await supabase.from('orders').update({'assigned_courier': courier['name'], 'status': 'assigned'}).eq('id', orderId);
    listenToOrdersRealtime();
  }

  // --- 🍔 إدارة وتعديل وحذف المنتجات للمشرف ---
  Future<void> removeProduct(String id) async {
    if (!isAdminLoggedIn || supabase.auth.currentUser?.appMetadata['role'] != 'admin') {
      throw Exception('صلاحية المشرف مطلوبة.');
    }
    await supabase.from('products').delete().eq('id', id);
    await fetchProductsFromSupabase();
    notifyListeners();
  }

  Future<void> upsertProduct(ProductModel product) async {
    if (!isAdminLoggedIn || supabase.auth.currentUser?.appMetadata['role'] != 'admin') {
      throw Exception('صلاحية المشرف مطلوبة.');
    }
    await supabase.from('products').upsert({
      'id': product.id,
      'name': product.name.trim(),
      'restaurant_name': product.restaurantName.trim(),
      'price': product.price,
      'category': product.category,
      'available': product.available,
      'image_url': product.imageUrl,
    }, onConflict: 'id');
    await fetchProductsFromSupabase();
    notifyListeners();
  }

  List products = [];

  Future<void> fetchProductsFromSupabase() async {
    try {
      final response = await supabase.from('products').select();
      products = response.map((p) => ProductModel(
        id: p['id'].toString(),
        name: p['name'] ?? '',
        restaurantName: p['restaurant_name'] ?? 'متجر عام',
        price: double.tryParse(p['price'].toString()) ?? 0.0,
        category: p['category'] ?? 'المطاعم',
        available: p['available'] ?? true,
        imageUrl: p['image_url'] ?? '',
      )).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('❌ خطأ في جلب المنتجات: $e');
    }
  }

  Future<void> addProduct(ProductModel product) async {
    if (!isAdminLoggedIn || supabase.auth.currentUser?.appMetadata['role'] != 'admin') {
      throw Exception('يجب تسجيل دخول المشرف بصلاحية صحيحة أولاً.');
    }
    await supabase.from('products').insert({
      'id': product.id,
      'name': product.name.trim(),
      'restaurant_name': product.restaurantName.trim(),
      'price': product.price,
      'category': product.category,
      'available': product.available,
      'image_url': product.imageUrl,
    });
    await fetchProductsFromSupabase();
  }

  List orders = [];
  List notifications = [];

  String _normalizePhone(String phone) {
    String clean = phone.trim().replaceAll(' ', '');
    if (clean.startsWith('0')) {
      clean = clean.substring(1);
    }
    if (clean.startsWith('967')) {
      clean = clean.substring(3);
    }
    return clean;
  }

  List get customerOrders {
    if (userProfile == null || userProfile!['phone'] == null || userProfile!['phone']!.isEmpty) {
      return [];
    }
    String myPhone = _normalizePhone(userProfile!['phone']!);

    return orders.where((o) {
      String orderPhone = _normalizePhone(o['phone']?.toString() ?? '');
      return orderPhone.isNotEmpty && orderPhone == myPhone;
    }).toList();
  }

  void addNotification(String title, String body) {
    notifications.insert(0, {'title': title, 'body': body, 'time': DateTime.now()});
    NotificationService.showLocalNotification(title, body);
    notifyListeners();
  }

  void _sortOrders() {
    orders.sort((a, b) {
      final timeA = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final timeB = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
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
      orders = List.from(initialData);
      _sortOrders();
      notifyListeners();

      supabase.from('orders').stream(primaryKey: ['id']).listen((data) {
        orders = List.from(data);
        _sortOrders();
        notifyListeners();
      }, onError: (error) {
        debugPrint('⚠️ خطأ في الاستماع للطلبات: $error');
      });
    } catch (e) {
      debugPrint('❌ خطأ في جلب الطلبات: $e');
    }
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
    if (paymentMethod != 'cash' && paymentMethod != 'cash_on_delivery') {
      throw Exception('الدفع النقدي عند الاستلام هو طريقة الدفع الوحيدة في المرحلة الأولى.');
    }

    final trackingCode = Random().nextDouble().toString().substring(2, 10);
    final normalizedPhone = _normalizePhone(phone);

    try {
      debugPrint('🚀 جاري إرسال الطلب إلى Supabase...');

      final response = await supabase.from('orders').insert({
        'customer_name': customerName.trim(),
        'customerName': customerName.trim(),
        'phone': normalizedPhone,
        'address': address.trim(),
        'itemsDesc': itemsDesc,
        'items_description': itemsDesc,
        'itemsdesc': itemsDesc,
        'items_desc': itemsDesc,
        'products_total': productsTotal,
        'total_price': productsTotal,
        'tracking_code': trackingCode,
        'status': 'waitingForPricing',
        'payment_method': paymentMethod,
        'payment_account': paymentAccount,
      }).select().single();

      final order = Map<String, dynamic>.from(response);
      debugPrint('✅ تم إرسال الطلب بنجاح برقم ID: ${order['id']}');

      lastOrderTrackingCode = trackingCode;
      userProfile = {'phone': normalizedPhone, 'name': customerName, 'city': currentCity, 'address': address};
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userPhone', normalizedPhone);
      await prefs.setString('userName', customerName);
      await prefs.setString('userAddress', address);
      await prefs.setString('userCity', currentCity);
      await prefs.setString('fast_last_order_id', order['id'].toString());
      await _secureStorage.write(key: 'fast_last_order_token', value: trackingCode);
      
      orders.removeWhere((o) => o['id'].toString() == order['id'].toString());
      orders.add(order);
      _sortOrders();
      
      _cartItems.clear();
      
      addNotification('تم استلاستيلام الطلب ⏳', 'طلبك بانتظار مراجعة المشرف وتأكيد رسوم التوصيل');
      notifyListeners();

    } catch (e) {
      debugPrint('❌ خطأ حقيقي أثناء إرسال الطلب: $e');
      throw Exception('تعذر إرسال الطلب بسبب: $e');
    }
  }

  Future<void> setOrderDeliveryFee(dynamic orderId, double fee, String courierName) async {
    try {
      final orderIndex = orders.indexWhere((o) => o['id'].toString() == orderId.toString());
      if (orderIndex != -1) {
        final currentStatus = orders[orderIndex]['status']?.toString();
        if (currentStatus != null && currentStatus != 'waitingForPricing' && currentStatus != 'pricingSentToCustomer') {
          debugPrint('⚠️ الطلب مؤكد أو منتهي، لا يمكن تعديل تسعيره!');
          return;
        }
      }

      double productsTotal = orderIndex != -1 ? double.tryParse(orders[orderIndex]['products_total'].toString()) ?? 0.0 : 0.0;
      double totalPrice = productsTotal + fee;

      await supabase.from('orders').update({
        'delivery_fee': fee,
        'total_price': totalPrice,
        'assigned_courier': courierName.trim(),
        'status': 'pricingSentToCustomer',
        'is_fee_sent': true,
        'admin_message': 'تم تحديد رسوم التوصيل ($fee ر.ي). بانتظار موافقة العميل ⏳',
      }).eq('id', orderId);

      if (orderIndex != -1) {
        orders[orderIndex]['delivery_fee'] = fee;
        orders[orderIndex]['total_price'] = totalPrice;
        orders[orderIndex]['assigned_courier'] = courierName.trim();
        orders[orderIndex]['status'] = 'pricingSentToCustomer';
        orders[orderIndex]['admin_message'] = 'تم تحديد رسوم التوصيل ($fee ر.ي). بانتظار موافقة العميل ⏳';
        _sortOrders();
      }

      addNotification('تم تسعير الطلب #$orderId 💰', 'تم تحديد رسوم التوصيل ($fee ر.ي). يرجى من العميل تأكيد الطلب!');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ خطأ تحديث الرسوم: $e');
    }
  }

  Future<void> _submitCustomerOrderAction(dynamic orderId, String action) async {
    final token = await _secureStorage.read(key: 'fast_last_order_token');
    final phone = userProfile?['phone'];
    if (token == null || phone == null) throw Exception('رمز متابعة الطلب غير موجود على هذا الجهاز.');

    String newStatus = action == 'approve' ? 'waitingCourierApproval' : 'cancelled';
    String adminMsg = action == 'approve' ? 'تم تأكيد السعر من قبل العميل، بانتظار موافقة المندوب ✅' : 'تم إلغاء الطلب من قبل العميل ❌';

    final response = await supabase.from('orders').update({
      'status': newStatus,
      'admin_message': adminMsg,
    }).eq('id', orderId).select().single();

    final updated = Map<String, dynamic>.from(response);
    final index = orders.indexWhere((o) => o['id'].toString() == orderId.toString());
    if (index >= 0) orders[index] = updated; else orders.add(updated);
    _sortOrders();
    notifyListeners();
  }

  Future<void> customerApprovePricing(dynamic orderId) async {
    await _submitCustomerOrderAction(orderId, 'approve');
    addNotification('تأكيد الطلب 👍', 'تم تأكيد السعر وإرسال الطلب للمندوب');
  }

  Future<void> customerConfirmOrder(dynamic orderId) async {
    await customerApprovePricing(orderId);
  }

  Future<void> customerCancelOrder(dynamic orderId) async {
    await _submitCustomerOrderAction(orderId, 'cancel');
    addNotification('إلغاء الطلب ❌', 'تم إلغاء الطلب بناءً على طلبك');
  }

  Future<void> _submitCourierOrderAction(dynamic orderId, String action) async {
    if (currentCourier == null || supabase.auth.currentUser?.appMetadata['role'] != 'courier') {
      throw Exception('جلسة المندوب غير صالحة. سجّل الدخول مجدداً.');
    }

    String newStatus;
    String adminMsg;
    if (action == 'accept') {
      newStatus = 'acceptedByCourier';
      adminMsg = 'وافق المندوب على توصيل الطلب 🛵';
    } else if (action == 'reject') {
      newStatus = 'rejectedByCourier';
      adminMsg = 'رفض المندوب الطلب ⚠️';
    } else if (action == 'arrived') {
      newStatus = 'arrivedToCustomer';
      adminMsg = 'وصل المندوب إلى موقع العميل 📍';
    } else {
      newStatus = 'delivered';
      adminMsg = 'تم تسليم الطلب بنجاح ✅';
    }

    final response = await supabase.from('orders').update({
      'status': newStatus,
      'admin_message': adminMsg,
    }).eq('id', orderId).select().single();

    final updated = Map<String, dynamic>.from(response);
    final index = orders.indexWhere((o) => o['id'].toString() == orderId.toString());
    if (index >= 0) orders[index] = updated;
    else orders.add(updated);
    _sortOrders();
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
    addNotification('تم تسليم الطلب', 'تم تأكيد استلام المبلغ النقدي عند التسليم');
  }
}

class _UserMock {
  final String name;
  final String phone;
  _UserMock(this.name, this.phone);
}
