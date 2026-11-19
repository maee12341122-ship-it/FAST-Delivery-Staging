import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

typedef JsonMap = Map<String, dynamic>;
typedef JsonList = List<JsonMap>;

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final http.Client _httpClient = http.Client();

  static const Duration _requestTimeout = Duration(seconds: 20);
  static const Duration _orderTimeout = Duration(seconds: 3);
  static bool _isCreatingOrder = false;

  // عنوان الخادم المركزي للـ Node.js Backend (يُضبط عبر --dart-define=BACKEND_URL=...)
  static const String baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static Uri _buildUri(String path, [Map<String, String>? queryParams]) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$normalizedBase$normalizedPath');
    if (queryParams == null || queryParams.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      ...queryParams,
    });
  }

  static String? _resolveAccessToken([String? explicitToken]) {
    final sessionToken = _supabase.auth.currentSession?.accessToken;
    if (sessionToken != null && sessionToken.isNotEmpty) {
      return sessionToken;
    }
    if (explicitToken != null &&
        explicitToken.trim().isNotEmpty &&
        explicitToken.trim().contains('.')) {
      return explicitToken.trim();
    }
    return null;
  }

  static Map<String, String> _headers({String? explicitToken}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final token = _resolveAccessToken(explicitToken);
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static dynamic _decodeBody(http.Response response) {
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw ApiException(
        'استجابة غير صالحة من الخادم (رمز الحالة ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
  }

  static Future<dynamic> _sendJsonRequest({
    required String method,
    required String path,
    Map<String, String>? queryParams,
    Map<String, dynamic>? body,
    String? explicitToken,
    Duration? timeoutOverride,
  }) async {
    final uri = _buildUri(path, queryParams);
    final headers = _headers(explicitToken: explicitToken);
    final timeout = timeoutOverride ?? _requestTimeout;

    try {
      http.Response response;
      switch (method.toUpperCase()) {
        case 'GET':
          response =
              await _httpClient.get(uri, headers: headers).timeout(timeout);
          break;
        case 'POST':
          response = await _httpClient
              .post(uri,
                  headers: headers,
                  body: jsonEncode(body ?? <String, dynamic>{}))
              .timeout(timeout);
          break;
        case 'PATCH':
          response = await _httpClient
              .patch(uri,
                  headers: headers,
                  body: jsonEncode(body ?? <String, dynamic>{}))
              .timeout(timeout);
          break;
        case 'PUT':
          response = await _httpClient
              .put(uri,
                  headers: headers,
                  body: jsonEncode(body ?? <String, dynamic>{}))
              .timeout(timeout);
          break;
        default:
          throw ApiException('طريقة طلب غير مدعومة: $method');
      }

      final decoded = _decodeBody(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }

      final serverMessage = decoded is Map<String, dynamic>
          ? (decoded['error'] ?? decoded['message'] ?? 'حدث خطأ في الخادم')
              .toString()
          : 'حدث خطأ في الخادم';
      throw ApiException(serverMessage, statusCode: response.statusCode);
    } on TimeoutException {
      throw ApiException(
          'انتهت مهلة الاتصال بالخادم، يرجى المحاولة مرة أخرى.');
    } on http.ClientException {
      throw ApiException(
          'تعذر الاتصال بالخادم، تحقق من الاتصال بالإنترنت.');
    } on ApiException {
      rethrow;
    } catch (e) {
      debugPrint('❌ خطأ في طلب HTTP ($method $path): $e');
      throw ApiException('تعذر إتمام الطلب: $e');
    }
  }

  // 1. جلب الكتالوج العام من جدول products في Supabase
  static Future<JsonMap> fetchCatalog() async {
    try {
      final response = await _supabase.from('products').select();
      return {'products': response};
    } catch (e) {
      debugPrint('❌ خطأ في جلب الكتالوج: $e');
      rethrow;
    }
  }

  // 1. أ) جلب قائمة المطاعم/المتاجر النشطة من جدول restaurants
  static Future<List<dynamic>> fetchRestaurants() async {
    try {
      final response = await _supabase
          .from('restaurants')
          .select()
          .eq('is_active', true);
      return response;
    } catch (e) {
      debugPrint('❌ خطأ في جلب المطاعم: $e');
      return [];
    }
  }

  // 1. ب) جلب الأقسام العامة النشطة من جدول categories
  static Future<List<dynamic>> fetchCategories() async {
    try {
      final response = await _supabase
          .from('categories')
          .select()
          .eq('is_active', true);
      return response;
    } catch (e) {
      debugPrint('❌ خطأ في جلب الأقسام: $e');
      return [];
    }
  }

  // 2. التحقق من الكوبون وحساب الخصم عبر Node.js Backend
  static Future<JsonMap> validateCoupon(
    String code,
    double subtotal, {
    String? explicitToken,
  }) async {
    try {
      final data = await _sendJsonRequest(
        method: 'POST',
        path: '/api/coupons/validate',
        body: {
          'code': code.trim(),
          'subtotal': subtotal,
        },
        explicitToken: explicitToken,
      );

      if (data is Map<String, dynamic>) {
        return data;
      }
      throw ApiException('استجابة غير متوقعة من خدمة التحقق من الكوبون.');
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من الكوبون: $e');
      rethrow;
    }
  }

  // 3. تمرير الطلب خلال 3 ثوانٍ كحد أقصى للـ Backend ثم التمرير السريع إلى Supabase
  static Future<JsonMap> createOrder({
    required JsonList items,
    required String address,
    required String notes,
    String? customerName,
    String? phone,
    String? couponCode,
    String? paymentMethod,
    String? paymentAccount,
    double? productsTotal,
    String? token,
  }) async {
    if (_isCreatingOrder) {
      throw ApiException('جاري إرسال الطلب بالفعل، يرجى الانتظار.');
    }
    _isCreatingOrder = true;

    try {
      final sanitizedItems = items.map((item) {
        final rawProductId = item['product_id'] ?? item['id'];
        final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
        return {
          'product_id': rawProductId?.toString() ?? '',
          'quantity': qty > 0 ? qty : 1,
        };
      }).toList();

      final payload = <String, dynamic>{
        'items': sanitizedItems,
        'address': address.trim(),
        'notes': notes.trim(),
        if (customerName != null && customerName.trim().isNotEmpty)
          'customer_name': customerName.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (couponCode != null && couponCode.trim().isNotEmpty)
          'coupon_code': couponCode.trim(),
        if (paymentMethod != null && paymentMethod.trim().isNotEmpty)
          'payment_method': paymentMethod.trim(),
        if (paymentAccount != null && paymentAccount.trim().isNotEmpty)
          'payment_account': paymentAccount.trim(),
      };

      try {
        final data = await _sendJsonRequest(
          method: 'POST',
          path: '/api/orders',
          body: payload,
          explicitToken: token,
          timeoutOverride: _orderTimeout,
        );

        if (data is Map<String, dynamic>) {
          return data;
        }
      } catch (e) {
        debugPrint(
            '⚠️ تجاوز مهلة 3 ثوانٍ أو تعذر الوصول للـ Backend، التمرير إلى Supabase: $e');
      }

      final trackingCode = Random().nextDouble().toString().substring(2, 10);
      final inserted = await _supabase
          .from('orders')
          .insert({
            'customer_name': (customerName ?? '').trim(),
            'phone': (phone ?? '').trim(),
            'address': address.trim(),
            'items_desc': notes.trim(),
            'total_price': productsTotal ?? 0.0,
            'payment_method': (paymentMethod ?? 'cash').trim(),
            'payment_account': (paymentAccount ?? 'نقدي').trim(),
            'status': 'waitingForPricing',
            'tracking_code': trackingCode,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .maybeSingle();

      final orderMap = inserted != null
          ? Map<String, dynamic>.from(inserted)
          : <String, dynamic>{
              'customer_name': (customerName ?? '').trim(),
              'phone': (phone ?? '').trim(),
              'address': address.trim(),
              'items_desc': notes.trim(),
              'total_price': productsTotal ?? 0.0,
              'payment_method': (paymentMethod ?? 'cash').trim(),
              'payment_account': (paymentAccount ?? 'نقدي').trim(),
              'status': 'waitingForPricing',
              'tracking_code': trackingCode,
            };

      return {
        'success': true,
        'order': orderMap,
      };
    } finally {
      _isCreatingOrder = false;
    }
  }

  // 4. جلب طلبات العميل الشخصية عبر Node.js Backend
  static Future<List<dynamic>> fetchMyOrders(String phone,
      {String? token}) async {
    try {
      final data = await _sendJsonRequest(
        method: 'GET',
        path: '/api/orders/my',
        queryParams: {'phone': phone.trim()},
        explicitToken: token,
      );

      if (data is List) return data;
      if (data is Map<String, dynamic> && data['orders'] is List) {
        return data['orders'] as List<dynamic>;
      }
      return [];
    } catch (e) {
      debugPrint('❌ خطأ في جلب طلبات العميل: $e');
      return [];
    }
  }

  // 5. [لوحة المشرف] جلب جميع الطلبات عبر Node.js Backend
  static Future<List<dynamic>> fetchAdminOrders(
    String token, {
    String? status,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (status != null && status.trim().isNotEmpty) {
        queryParams['status'] = status.trim();
      }

      final data = await _sendJsonRequest(
        method: 'GET',
        path: '/api/orders',
        queryParams: queryParams,
        explicitToken: token,
      );

      if (data is List) return data;
      if (data is Map<String, dynamic> && data['orders'] is List) {
        return data['orders'] as List<dynamic>;
      }
      return [];
    } catch (e) {
      debugPrint('❌ خطأ في جلب طلبات المشرف: $e');
      rethrow;
    }
  }

  // 6. [لوحة المشرف] تحديد رسوم التوصيل وتعيين المندوب عبر Node.js Backend
  static Future<JsonMap> adminPricingOrder(
    String token,
    int orderId,
    double deliveryFee,
    String assignedCourier, {
    String? courierId,
  }) async {
    try {
      final data = await _sendJsonRequest(
        method: 'POST',
        path: '/api/orders/$orderId/pricing',
        body: {
          'delivery_fee': deliveryFee,
          'assigned_courier': assignedCourier.trim(),
          if (courierId != null && courierId.trim().isNotEmpty)
            'courier_id': courierId.trim(),
        },
        explicitToken: token,
      );

      if (data is Map<String, dynamic>) {
        return data;
      }
      throw ApiException('استجابة غير متوقعة عند تسعير الطلب.');
    } catch (e) {
      debugPrint('❌ خطأ في تسعير الطلب: $e');
      rethrow;
    }
  }

  // 7. [لوحة المشرف] تحديث حالة الطلب عبر Node.js Backend
  static Future<JsonMap> adminUpdateOrderStatus(
    String token,
    int orderId,
    String status,
  ) async {
    try {
      final data = await _sendJsonRequest(
        method: 'PATCH',
        path: '/api/orders/$orderId/status',
        body: {'status': status.trim()},
        explicitToken: token,
      );

      if (data is Map<String, dynamic>) {
        return data;
      }
      throw ApiException('استجابة غير متوقعة عند تحديث حالة الطلب.');
    } catch (e) {
      debugPrint('❌ خطأ في تحديث حالة الطلب للمشرف: $e');
      rethrow;
    }
  }

  // 8. [لوحة المندوب] جلب الطلبات المسندة للمندوب عبر Node.js Backend
  static Future<List<dynamic>> fetchCourierOrders(
    String courierName, {
    String? courierId,
    String? token,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (courierId != null && courierId.trim().isNotEmpty) {
        queryParams['courier_id'] = courierId.trim();
      }
      if (courierName.trim().isNotEmpty) {
        queryParams['courier_name'] = courierName.trim();
      }

      final data = await _sendJsonRequest(
        method: 'GET',
        path: '/api/orders',
        queryParams: queryParams,
        explicitToken: token,
      );

      if (data is List) return data;
      if (data is Map<String, dynamic> && data['orders'] is List) {
        return data['orders'] as List<dynamic>;
      }
      return [];
    } catch (e) {
      debugPrint('❌ خطأ في جلب طلبات المندوب: $e');
      return [];
    }
  }

  // 9. [لوحة المندوب] تحديث حالة الطلب عبر Node.js Backend
  static Future<JsonMap> courierUpdateOrderStatus(
    String token,
    int orderId,
    String status,
  ) async {
    try {
      final data = await _sendJsonRequest(
        method: 'PATCH',
        path: '/api/orders/$orderId/status',
        body: {'status': status.trim()},
        explicitToken: token,
      );

      if (data is Map<String, dynamic>) {
        return data;
      }
      throw ApiException('استجابة غير متوقعة عند تحديث حالة الطلب.');
    } catch (e) {
      debugPrint('❌ خطأ في تحديث حالة الطلب للمندوب: $e');
      rethrow;
    }
  }

  // 10. [لوحة المندوب] إرسال وتحديث الموقع الجغرافي للمندوب عبر Node.js Backend
  static Future<void> updateCourierLocation(
    String token,
    double latitude,
    double longitude, {
    int? orderId,
  }) async {
    try {
      await _sendJsonRequest(
        method: 'POST',
        path: '/api/courier/location',
        body: {
          'latitude': latitude,
          'longitude': longitude,
          if (orderId != null) 'order_id': orderId,
        },
        explicitToken: token,
      );
    } catch (e) {
      debugPrint('❌ خطأ في تحديث موقع المندوب: $e');
      rethrow;
    }
  }
}
