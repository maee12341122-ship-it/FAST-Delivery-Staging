import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/cart_item_model.dart';
import '../models/product_model.dart';
import '../models/address_model.dart';
import '../models/delivery_model.dart';
import '../services/notification_service.dart';

/// ===========================================================================
/// 🚀 مدير حالة التطبيق الشامل (AppState) - النسخة الآمنة والمحدثة
/// ===========================================================================
class AppState extends ChangeNotifier {
  final SupabaseClient supabase = Supabase.instance.client;

  AppState() {
    _initializeApplicationState();
  }

  Future<void> _initializeApplicationState() async {
    await checkPrivacyPolicyStatus(); // 🛡️ قراءة حالة الموافقة على سياسة الخصوصية
    _loadAdminSession();
    _loadCourierSession();
    _loadUserSession();
    await fetchStoreSettings();
    await fetchProductsFromSupabase();
    await fetchCouriersFromSupabase();
    await recordVisitorVisit(); 
    await fetchTotalVisitorsCount(); 
    await fetchAdminFinancialReports(); 
    listenToOrdersRealtime();
    listenToStoreSettingsRealtime();
    initializeInternetListener(); 
  }

  // ==========================================
  // --- 🛡️ قسم سياسة الخصوصية والاستخدام ---
  // ==========================================
  bool hasAcceptedPrivacyPolicy = false;

  /// 1️⃣ قراءة حالة الموافقة محلياً من ذاكرة الهاتف
  Future<void> checkPrivacyPolicyStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      hasAcceptedPrivacyPolicy = prefs.getBool('privacy_accepted') ?? false;
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ خطأ في قراءة حالة سياسة الخصوصية: $e');
    }
  }

  /// 2️⃣ حفظ موافقة العميل دائمياً عند الضغط على "موافق واستمرار"
  Future<void> setPrivacyPolicyAccepted(bool accepted) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('privacy_accepted', accepted);
      hasAcceptedPrivacyPolicy = accepted;
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ خطأ في حفظ حالة سياسة الخصوصية: $e');
    }
  }

  // ==========================================
  // --- 🌐 قسم مراقبة اتصال الإنترنت لحظياً ---
  // ==========================================
  bool isConnectedToInternet = true;
  final Connectivity _connectivity = Connectivity();

  void initializeInternetListener() {
    _connectivity.checkConnectivity().then((result) {
      _updateConnectionStatus(result);
    });

    _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      _updateConnectionStatus(results);
    });
  }

  void _updateConnectionStatus(dynamic result) {
    bool previousState = isConnectedToInternet;
    
    if (result is List<ConnectivityResult>) {
      isConnectedToInternet = !result.contains(ConnectivityResult.none);
    } else if (result is ConnectivityResult) {
      isConnectedToInternet = result != ConnectivityResult.none;
    }

    if (previousState && !isConnectedToInternet) {
      addLocalNotification(
        '⚠️ انقطاع الاتصال بالإنترنت',
        'تم فقدان الاتصال بالشبكة! يرجى التحقق من الإنترنت لتحديث بيانات الطلبات والمراسلات.',
        type: 'network_alert',
      );
    } else if (!previousState && isConnectedToInternet) {
      addLocalNotification(
        '🟢 عودة الاتصال بالإنترنت',
        'تم استعادة الاتصال بالشبكة بنجاح.',
        type: 'network_success',
      );
    }
    
    notifyListeners();
  }

  // ==========================================
  // --- 📊 قسم عداد الزوار والتتبع ---
  // ==========================================
  int totalVisitorsCount = 0;

  Future<void> recordVisitorVisit() async {
    try {
      await supabase.from('visitor_logs').insert({
        'visitor_identifier': userProfile?['phone'] ?? 'guest_${DateTime.now().millisecondsSinceEpoch}',
      });
      debugPrint('📊 تم تسجيل زيارة جديدة بنجاح في قاعدة البيانات');
    } catch (e) {
      debugPrint('⚠️ خطأ في تسجيل الزيارة: $e');
    }
  }

  Future<void> fetchTotalVisitorsCount() async {
    try {
      final response = await supabase.from('visitor_logs').select('id');
      totalVisitorsCount = (response as List).length;
      notifyListeners();
      debugPrint('📊 إجمالي عدد الزوار الحالي: $totalVisitorsCount');
    } catch (e) {
      debugPrint('❌ خطأ في جلب عدد الزوار: $e');
    }
  }

  // ==========================================
  // --- 📈 قسم تقارير المبيعات والأرباح للمشرف ---
  // ==========================================
  double totalRevenue = 0.0;
  int completedOrdersCount = 0;
  int pendingOrdersCount = 0;
  int cancelledOrdersCount = 0;

  Future<void> fetchAdminFinancialReports() async {
    try {
      final response = await supabase.from('orders').select('total_price, status');
      
      double revenue = 0.0;
      int completed = 0;
      int pending = 0;
      int cancelled = 0;

      for (var order in response) {
        final status = order['status']?.toString().trim();
        final price = double.tryParse(order['total_price'].toString()) ?? 0.0;

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
      debugPrint('📊 تم تحديث تقارير المبيعات بنجاح: إجمالي الأرباح = $revenue');
    } catch (e) {
      debugPrint('❌ خطأ في جلب تقارير المبيعات: $e');
    }
  }

  // ==========================================
  // --- 🎟️ قسم كوبونات الخصم والعروض ---
  // ==========================================
  String? activeCouponCode;
  double couponDiscountAmount = 0.0;

  Future<String> applyCouponCode(String code, double cartSubtotal) async {
    if (code.trim().isEmpty) {
      return 'الرجاء إدخال رمز الكوبون ⚠️';
    }

    try {
      final cleanCode = code.trim().toUpperCase();
      final response = await supabase
          .from('coupons')
          .select()
          .eq('code', cleanCode)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) {
        return 'عذراً، هذا الكوبون غير موجود أو غير صالح ❌';
      }

      final int maxUses = int.tryParse(response['max_uses'].toString()) ?? 100;
      final int timesUsed = int.tryParse(response['times_used'].toString()) ?? 0;

      if (timesUsed >= maxUses) {
        return 'عذراً، انتهت صلاحية هذا الكوبون (استنفذ الحد الأقصى للاستخدام) 🚫';
      }

      final double discountValue = double.tryParse(response['discount_percentage'].toString()) ?? 0.0;
      final String discountType = response['discount_type']?.toString() ?? 'percentage';

      if (discountType == 'percentage') {
        couponDiscountAmount = (cartSubtotal * discountValue) / 100;
      } else {
        couponDiscountAmount = discountValue;
      }

      if (couponDiscountAmount > cartSubtotal) {
        couponDiscountAmount = cartSubtotal;
      }

      activeCouponCode = cleanCode;
      notifyListeners();
      return 'تم تطبيق الكوبون بنجاح! خصم بقيمة ${couponDiscountAmount.toStringAsFixed(0)} ر.ي 🎉';
    } catch (e) {
      debugPrint('❌ خطأ في تطبيق الكوبون: $e');
      return 'حدث خطأ أثناء التحقق من الكوبون. حاول مرة أخرى.';
    }
  }

  void removeCoupon() {
    activeCouponCode = null;
    couponDiscountAmount = 0.0;
    notifyListeners();
  }

  // ==========================================
  // --- 🍔 قسم إضافات وخصائص المنتجات (Modifiers) ---
  // ==========================================
  List productModifiers = [];

  Future<void> fetchProductModifiers(String productId) async {
    try {
      final response = await supabase
          .from('product_modifiers')
          .select()
          .eq('product_id', productId);
      
      productModifiers = response;
      notifyListeners();
    } catch (e) {
      debugPrint('❌ خطأ في جلب إضافات المنتج: $e');
    }
  }

  // ==========================================
  // --- 🔔 قسم الإشعارات ---
  // ==========================================
  
  String? get latestNotificationMessage {
    if (notifications.isNotEmpty) {
      return notifications.first['body']?.toString() ?? notifications.first['title']?.toString();
    }
    return null;
  }

  Future<void> sendAutoNotification({
    required String targetPlayerId,
    required String title,
    required String body,
  }) async {
    if (targetPlayerId.isEmpty) return;
    debugPrint('ℹ️ تنبيه: تم تعطيل الإرسال المباشر للمفاتيح السرية من التطبيق لأسباب أمنية.');
  }

  // ==========================================
  // --- ❤️ إدارة المنتجات المفضلة ---
  // ==========================================
  final List<String> _favoriteProductIds = [];
  List<String> get favoriteProductIds => _favoriteProductIds;

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
    return products
        .where((p) => _favoriteProductIds.contains(p.id))
        .toList()
        .cast<ProductModel>();
  }

  // ==========================================
  // --- 🏠 قائمة وعناوين العميل المحفوظة ---
  // ==========================================
  final List<AddressModel> _userAddresses = [];
  List<AddressModel> get userAddresses => _userAddresses;

  Future<void> fetchUserAddressesFromSupabase() async {
    if (userProfile == null || userProfile!['phone'] == null || userProfile!['phone']!.isEmpty) {
      _loadUserAddressesFromPrefs(); 
      return;
    }

    try {
      final cleanPhone = _normalizePhone(userProfile!['phone']!);
      final response = await supabase
          .from('customer_addresses')
          .select()
          .eq('customer_phone', cleanPhone);

      if (response != null) {
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
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في جلب العناوين من Supabase: $e');
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
        final cleanPhone = _normalizePhone(userProfile!['phone']!);
        await supabase.from('customer_addresses').insert({
          'customer_phone': cleanPhone,
          'title': address.title.trim(),
          'area': address.area.trim(),
          'details': address.details.trim(),
          'instructions': address.instructions.trim(),
        });
        await fetchUserAddressesFromSupabase();
      } catch (e) {
        debugPrint('❌ خطأ في حفظ العنوان سحابياً: $e');
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
      debugPrint('❌ خطأ في حذف العنوان من Supabase: $e');
    }
  }

  void selectDefaultAddress(AddressModel address) {
    String formattedAddress = '${address.title}: ${address.area} - ${address.details}';
    if (address.instructions.isNotEmpty) {
      formattedAddress += ' (تعليمات: ${address.instructions})';
    }
    addOrUpdateAddress(formattedAddress);
    notifyListeners();
  }

  Future<void> _loadUserAddressesFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? addressesJson = prefs.getString('user_saved_addresses_json');
      if (addressesJson != null && addressesJson.isNotEmpty) {
        final List<dynamic> decodedList = jsonDecode(addressesJson);
        _userAddresses.clear();
        for (var item in decodedList) {
          if (item is Map<String, dynamic>) {
            _userAddresses.add(AddressModel(
              id: item['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
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
      debugPrint('⚠️ خطأ في تحميل العناوين المحفوظة محلياً: $e');
    }
  }

  Future<void> _saveUserAddressesFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listToEncode = _userAddresses.map((a) => {
        'id': a.id,
        'title': a.title,
        'area': a.area,
        'details': a.details,
        'instructions': a.instructions,
      }).toList();
      await prefs.setString('user_saved_addresses_json', jsonEncode(listToEncode));
    } catch (e) {
      debugPrint('⚠️ خطأ في حفظ العناوين محلياً: $e');
    }
  }

  // ==========================================
  // --- 🗺️ ترجمة الحالات ومعرفات المشرفين ---
  // ==========================================
  String getArabicStatus(String? status) {
    switch (status?.trim()) {
      case 'waitingForPricing':
      case 'waiting_for_pricing':
        return 'بانتظار تحديد السعر من الإدارة ⏳';
      case 'pricingSentToCustomer':
      case 'pricing_sent_to_customer':
        return 'تم تحديد السعر، بانتظار موافقة العميل 💰';
      case 'approvedByCustomer':
      case 'waitingCourierApproval':
      case 'waiting_courier_approval':
        return 'بانتظار موافقة المندوب 🛵';
      case 'acceptedByCourier':
      case 'accepted':
        return 'وافق المندوب على التوصيل 🚀';
      case 'rejectedByCourier':
      case 'rejected':
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
      debugPrint('⚠️ خطأ في جلب معرفات المشرفين: $e');
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
      debugPrint('⚠️ خطأ في جلب Player ID للمندوب بالاسم: $e');
    }
    return null;
  }

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

  // ==========================================
  // --- 💬 إدارة المحادثات والشات ---
  // ==========================================
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

  Future<void> openFastWhatsApp({String message = 'مرحباً، أريد التسجيل في تطبيق Fast Delivery App.'}) async {
    final uri = Uri.parse('https://wa.me/967775145534?text=${Uri.encodeComponent(message)}');
    if (!await canLaunchUrl(uri)) {
      throw Exception('تعذر فتح واتساب أو المتصفح.');
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void shareApp() {
    Share.share(
      'حمل تطبيق Fast Delivery App - أسرع خدمة توصيل! 🚀\nhttps://play.google.com/store/apps/details?id=com.example.taiz_express',
      subject: 'تطبيق Fast Delivery App',
    );
  }

  // ==========================================
  // --- 📍 الأذونات والإعدادات والدوام ---
  // ==========================================
  Future<void> requestLocationAndNotificationPermissions() async {
    try {
      LocationPermission locationPermission = await Geolocator.checkPermission();
      if (locationPermission == LocationPermission.denied) {
        locationPermission = await Geolocator.requestPermission();
      }

      PermissionStatus notificationStatus = await Permission.notification.status;
      if (!notificationStatus.isGranted) {
        notificationStatus = await Permission.notification.request();
      }

      if (notificationStatus.isGranted) {
        try {
          await OneSignal.Notifications.requestPermission(true);
        } catch (e) {
          debugPrint('⚠️ خطأ في تفعيل OneSignal بعد الاذن: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في طلب الأذونات: $e');
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

  // ==========================================
  // --- 👑 إدارة جلسة المشرف (Admin Session) ---
  // ==========================================
  bool isAdminLoggedIn = false;

  void _loadAdminSession() async {
    final user = supabase.auth.currentUser;
    isAdminLoggedIn = user != null; 
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
      if (response.user == null) {
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

  // ==========================================
  // --- 👤 إدارة جلسة المستخدم / العميل ---
  // ==========================================
  Map<String, dynamic>? userProfile;
  dynamic generatedDynamicOtp;
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
          await fetchUserAddressesFromSupabase();
          notifyListeners();
          await restoreLastCustomerOrder();
          return;
        }
      } catch (e) {
        debugPrint('⚠️ خطأ في استعادة الجلسة: $e');
      }

      userProfile = {
        'phone': phone,
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
      if (cleanPhone.length > 9) {
        cleanPhone = cleanPhone.substring(cleanPhone.length - 9);
      }

      final response = await supabase
          .from('customers')
          .select()
          .ilike('phone', '%$cleanPhone')
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

        await fetchUserAddressesFromSupabase();

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

  Future<dynamic> requestOtpForPhone(String phone) async {
    final cleanPhone = _normalizePhone(phone);

    try {
      debugPrint('🚀 جاري التحقق من رقم الهاتف...');
      generatedDynamicOtp = (1000 + Random().nextInt(9000)).toString();
      
      await openFastWhatsApp(
        message: 'مرحباً، رمز التحقق الخاص بك لتطبيق Fast Delivery App هو: $generatedDynamicOtp'
      );

      return {'exists': false, 'message': 'تم إرسال رمز التحقق بنجاح عبر واتساب'};
    } catch (e) {
      debugPrint('❌ خطأ أثناء إرسال الرمز: $e');
      throw Exception('تعذر إرسال رمز التحقق. يرجى المحاولة لاحقاً.');
    } finally {
      notifyListeners();
    }
  }

  bool verifyOtpAndLogin(String phone, String enteredOtp) {
    if (enteredOtp.trim().isEmpty) return false;
    if (generatedDynamicOtp != null && enteredOtp.trim() == generatedDynamicOtp.toString()) {
      checkAndLoginCustomer(phone);
      return true;
    }
    return false;
  }

  Future<void> saveUserProfileDetails(String name, String address) async {
    if (userProfile != null) {
      userProfile!['name'] = name;
      userProfile!['address'] = address;
      String phone = userProfile!['phone'] ?? '';

      final prefs = await SharedPreferences.getInstance();
      prefs.setString('userName', name);
      prefs.setString('userAddress', address);
      prefs.setString('userPhone', phone);

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

    fetchUserAddressesFromSupabase();

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
    _userAddresses.clear();
    final prefs = await SharedPreferences.getInstance();
    prefs.remove('userPhone');
    prefs.remove('userName');
    prefs.remove('userAddress');
    prefs.remove('userCity');
    prefs.remove('user_saved_addresses_json');
    notifyListeners();
  }

  // ==========================================
  // --- 🛵 إدارة المناديب وعملياتهم ---
  // ==========================================
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
    if (password.length < 6) throw Exception('كلمة مرور المندوب يجب ألا تقل عن 6 أحرف.');
    
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

  // ==========================================
  // --- 🛒 إدارة سلة المشتريات (Cart) ---
  // ==========================================
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
    removeCoupon(); 
    notifyListeners();
  }

  void addCustomItem({required String name, required int price, required int quantity, required String notes}) {
    _cartItems.add(CartItemModel(
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      name: notes.isNotEmpty ? '$name ($notes)' : name,
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
    if (startHour < 0 || startHour > 23 || endHour < 1 || endHour > 24 || deliveryFee < 0) throw Exception('إعدادات غير صحيحة.');
    this.startHour = startHour; this.endHour = endHour; this.deliveryFee = deliveryFee;
    await supabase.from('settings').upsert({'id': 1, 'start_hour': startHour, 'end_hour': endHour, 'delivery_fee': deliveryFee});
    notifyListeners();
  }

  Future<void> updateCourier(DeliveryModel courier) async {
    await supabase.from('couriers').update({
      'name': courier.name, 'phone': courier.phone,
      'status': courier.isEnabled ? (courier.isAvailable ? 'available' : 'busy') : 'disabled',
    }).eq('id', courier.id);
    await fetchCouriersFromSupabase();
  }

  Future<void> setCourierAvailability(String id, bool available) async {
    await supabase.from('couriers').update({'status': available ? 'available' : 'busy'}).eq('id', id);
    await fetchCouriersFromSupabase();
  }

  Future<void> removeCourier(String id) async {
    await supabase.from('couriers').update({'status': 'disabled'}).eq('id', id);
    await fetchCouriersFromSupabase();
  }

  Future<void> updateOrderStatus(String id, String status) async {
    await supabase.from('orders').update({'status': status, 'admin_message': 'تم تحديث حالة الطلب من المشرف'}).eq('id', id);
    listenToOrdersRealtime();
  }

  Future<void> assignOrderToCourier(String orderId, String courierId) async {
    final courier = await supabase.from('couriers').select('name').eq('id', courierId).single();
    await supabase.from('orders').update({'assigned_courier': courier['name'], 'status': 'assigned'}).eq('id', orderId);
    listenToOrdersRealtime();
  }

  // ==========================================
  // --- 📦 إدارة المنتجات والطلبات ---
  // ==========================================
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

  List products = [];

  Future<void> fetchProductsFromSupabase() async {
    try {
      final response = await supabase.from('products').select();
      products = response.map((p) => ProductModel(
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
      )).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('❌ خطأ في جلب المنتجات: $e');
    }
  }

  Future<void> addProduct(ProductModel product) async {
    await supabase.from('products').insert({
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
    });
    await fetchProductsFromSupabase();
  }

  List orders = [];
  List notifications = [];
  
  int get unreadNotificationsCount => notifications.length;

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

  void addLocalNotification(String title, String body, {String? type}) {
    notifications.insert(0, {'title': title, 'body': body, 'time': DateTime.now(), 'type': type ?? 'general'});
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
      await fetchAdminFinancialReports(); 
      notifyListeners();

      supabase
          .channel('public_orders_realtime_channel')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            callback: (payload) {
              if (payload.eventType == PostgresChangeEvent.insert) {
                orders.add(payload.newRecord);
                addLocalNotification('طلب جديد 📦', 'تم إضافة طلب جديد إلى النظام');
              } else if (payload.eventType == PostgresChangeEvent.update) {
                final index = orders.indexWhere((o) => o['id'].toString() == payload.newRecord['id'].toString());
                if (index != -1) {
                  orders[index] = payload.newRecord;
                } else {
                  orders.add(payload.newRecord);
                }
                String newStatus = getArabicStatus(payload.newRecord['status']?.toString());
                addLocalNotification('تحديث الطلب #${payload.newRecord['id']} 🔔', 'الحالة الجديدة: $newStatus');
              } else if (payload.eventType == PostgresChangeEvent.delete) {
                orders.removeWhere((o) => o['id'].toString() == payload.oldRecord['id'].toString());
              }

              _sortOrders();
              fetchAdminFinancialReports(); 
              notifyListeners();
            },
          )
          .subscribe();

    } catch (e) {
      debugPrint('❌ خطأ في تفعيل Realtime للطلبات: $e');
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
    if (!isStoreOpen) {
      throw Exception('عذراً، التطبيق مغلق حالياً (أوقات الدوام من $startHour:00 إلى $endHour:00). لا يمكن استقبال طلبات جديدة.');
    }

    if (paymentMethod != 'cash' && paymentMethod != 'cash_on_delivery') {
      throw Exception('الدفع النقدي عند الاستلام هو طريقة الدفع الوحيدة في المرحلة الأولى.');
    }

    if (productsTotal <= 0) {
      throw Exception('لا يمكن إنشاء طلب بمبلغ اجمالي صفر أو سالب.');
    }

    final trackingCode = Random().nextDouble().toString().substring(2, 10);
    final normalizedPhone = _normalizePhone(phone);

    try {
      debugPrint('🚀 جاري إرسال الطلب الآمن إلى Supabase...');

      final response = await supabase.from('orders').insert({
        'customer_name': customerName.trim(),
        'phone': normalizedPhone,
        'address': address.trim(),
        'items_description': itemsDesc,
        'total_price': productsTotal,
        'tracking_code': trackingCode,
        'status': 'waitingForPricing',
        'payment_method': paymentMethod,
        'payment_account': paymentAccount,
      }).select().single();

      final order = Map<String, dynamic>.from(response);

      final orderId = order['id'];
      if (_cartItems.isNotEmpty && orderId != null) {
        final List orderItemsRows = _cartItems.map((cartItem) {
          return {
            'order_id': orderId,
            'product_name': cartItem.name,
            'price': cartItem.price,
            'quantity': cartItem.quantity,
            'total_price': cartItem.price * cartItem.quantity,
          };
        }).toList();

        await supabase.from('order_items').insert(orderItemsRows);
      }

      lastOrderTrackingCode = trackingCode;
      userProfile = {'phone': normalizedPhone, 'name': customerName, 'city': currentCity, 'address': address};
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userPhone', normalizedPhone);
      await prefs.setString('userName', customerName);
      await prefs.setString('userAddress', address);
      await prefs.setString('userCity', currentCity);
      await prefs.setString('fast_last_order_id', orderId.toString());
      await prefs.setString('fast_last_order_token', trackingCode);
      
      orders.removeWhere((o) => o['id'].toString() == orderId.toString());
      orders.add(order);
      _sortOrders();
      
      _cartItems.clear();
      removeCoupon(); 
      await fetchAdminFinancialReports(); 
      
      addNotification('تم استلام الطلب ⏳', 'طلبك بانتظار مراجعة المشرف وتأكيد رسوم التوصيل');
      notifyListeners();

    } catch (e) {
      debugPrint('❌ خطأ أثناء إرسال الطلب: $e');
      throw Exception('تعذر إرسال الطلب بسبب: $e');
    }
  }

  Future<void> setOrderDeliveryFee(dynamic orderId, double fee, String courierName) async {
    try {
      final orderIndex = orders.indexWhere((o) => o['id'].toString() == orderId.toString());
      if (orderIndex != -1) {
        final currentStatus = orders[orderIndex]['status']?.toString();
        if (currentStatus != null && currentStatus != 'waitingForPricing' && currentStatus != 'pricingSentToCustomer') {
          return;
        }
      }

      double productsTotal = orderIndex != -1 ? double.tryParse(orders[orderIndex]['total_price'].toString()) ?? 0.0 : 0.0;
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

      await fetchAdminFinancialReports();
      addNotification('تم تسعير الطلب #$orderId 💰', 'تم تحديد رسوم التوصيل ($fee ر.ي).');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ خطأ تحديث الرسوم: $e');
    }
  }

  Future<String?> getPlayerIdForUser(String userIdOrPhone, String tableName) async {
    try {
      final response = await supabase
          .from(tableName)
          .select('onesignal_player_id')
          .eq(tableName == 'customers' ? 'phone' : 'id', userIdOrPhone)
          .maybeSingle();
      
      if (response != null && response['onesignal_player_id'] != null) {
        return response['onesignal_player_id'].toString();
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في جلب Player ID: $e');
    }
    return null;
  }

  Future<void> _submitCustomerOrderAction(dynamic orderId, String action) async {
    final phone = userProfile?['phone'];
    if (phone == null) throw Exception('رمز متابعة الطلب غير موجود أو لم يتم تسجيل الدخول.');

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
    await fetchAdminFinancialReports();
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
      throw Exception('جلسة المندوب غير صالحة.');
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
    await fetchAdminFinancialReports();
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

  Future<void> submitCourierRating({
    required String orderId,
    required String courierName,
    required double rating,
    required String reviewText,
  }) async {
    try {
      await supabase.from('orders').update({
        'courier_rating': rating,
        'courier_review': reviewText,
      }).eq('id', orderId);

      final index = orders.indexWhere((o) => o['id'].toString() == orderId.toString());
      if (index != -1) {
        orders[index]['courier_rating'] = rating;
        orders[index]['courier_review'] = reviewText;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ خطأ في تقديم تقييم المندوب: $e');
    }
  }

  Future<void> submitRestaurantRating({
    required String orderId,
    required double rating,
    required String reviewText,
  }) async {
    try {
      await supabase.from('orders').update({
        'restaurant_rating': rating,
        'restaurant_review': reviewText,
      }).eq('id', orderId);

      final index = orders.indexWhere((o) => o['id'].toString() == orderId.toString());
      if (index != -1) {
        orders[index]['restaurant_rating'] = rating;
        orders[index]['restaurant_review'] = reviewText;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ خطأ في تقديم تقييم المطعم: $e');
    }
  }
}

class _UserMock {
  final String name;
  final String phone;
  _UserMock(this.name, this.phone);
}
