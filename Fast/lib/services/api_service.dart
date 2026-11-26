import 'dart:async';
import 'dart:convert';
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

  static const Duration _requestTimeout = Duration(seconds: 12);
  static const Duration _orderTimeout = Duration(seconds: 12);
  static const Duration _otpTimeout = Duration(seconds: 12);
  static bool _isCreatingOrder = false;

  static const String baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static bool get _isUnconfiguredLocalhost {
    final trimmed = baseUrl.trim().toLowerCase();
    return trimmed.isEmpty ||
        trimmed.contains('10.0.2.2') ||
        trimmed.contains('localhost') ||
        trimmed.contains('127.0.0.1');
  }

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
    final timeout = timeoutOverride ??
        (_isUnconfiguredLocalhost
            ? const Duration(milliseconds: 2000)
            : _requestTimeout);

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

  static JsonMap _parseFunctionPayload(dynamic rawData) {
    if (rawData is Map<String, dynamic>) {
      return rawData;
    }
    if (rawData is Map) {
      return Map<String, dynamic>.from(rawData);
    }
    if (rawData is String && rawData.trim().isNotEmpty) {
      final decoded = jsonDecode(rawData);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }
    return <String, dynamic>{};
  }

  static Future<JsonMap> fetchCatalog() async {
    try {
      final response = await _supabase
          .from('products')
          .select()
          .timeout(_requestTimeout);
      return {'products': response};
    } catch (e) {
      debugPrint('❌ خطأ في جلب الكتالوج: $e');
      rethrow;
    }
  }

  static Future<List<dynamic>> fetchRestaurants() async {
    try {
      final response = await _supabase
          .from('restaurants')
          .select()
          .eq('is_active', true)
          .timeout(_requestTimeout);
      return response;
    } catch (e) {
      debugPrint('❌ خطأ في جلب المطاعم: $e');
      return [];
    }
  }

  static Future<List<dynamic>> fetchCategories() async {
    try {
      final response = await _supabase
          .from('categories')
          .select()
          .eq('is_active', true)
          .timeout(_requestTimeout);
      return response;
    } catch (e) {
      debugPrint('❌ خطأ في جلب الأقسام: $e');
      return [];
    }
  }

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

  static Future<JsonMap> createOrder({
    required JsonList items,
    required String address,
    required String notes,
    String? customerName,
    String? phone,
    String? couponCode,
    String? paymentMethod,
    String? paymentAccount,
    String? clientRequestKey,
    String? token,
  }) async {
    if (_isCreatingOrder) {
      throw ApiException('جاري إرسال الطلب بالفعل، يرجى الانتظار.');
    }
    _isCreatingOrder = true;

    try {
      if (items.isEmpty) {
        throw ApiException('لا يمكن إنشاء طلب بدون عناصر.');
      }

      final sanitizedItems = items.map((item) {
        final rawProductId =
            (item['product_id'] ?? item['id'] ?? '').toString().trim();
        final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
        final isCustomItem =
            rawProductId.startsWith('custom_') || item['is_custom'] == true;

        final parsedPrice = double.tryParse(
          (item['unit_price'] ?? item['price'] ?? item['custom_price'] ?? '')
              .toString(),
        );

        final sanitized = <String, dynamic>{
          'product_id': isCustomItem
              ? (rawProductId.startsWith('custom_')
                  ? rawProductId
                  : 'custom_${rawProductId.isNotEmpty ? rawProductId : DateTime.now().millisecondsSinceEpoch}')
              : rawProductId,
          'quantity': qty > 0 ? qty : 1,
          'is_custom': isCustomItem,
        };

        final itemName = (item['name'] ?? item['title'] ?? '').toString().trim();
        if (itemName.isNotEmpty) {
          sanitized['name'] = itemName;
        }

        if (isCustomItem && parsedPrice != null && parsedPrice >= 0) {
          sanitized['unit_price'] = parsedPrice;
        } else if (!isCustomItem && parsedPrice != null && parsedPrice >= 0) {
          sanitized['suggested_unit_price'] = parsedPrice;
        }

        return sanitized;
      }).toList();

      final payload = <String, dynamic>{
        'items': sanitizedItems,
        'address': address.trim(),
        'notes': notes.trim(),
        if (clientRequestKey != null && clientRequestKey.trim().isNotEmpty)
          'client_request_key': clientRequestKey.trim(),
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

      final data = await _sendJsonRequest(
        method: 'POST',
        path: '/api/orders',
        body: payload,
        explicitToken: token,
        timeoutOverride: _isUnconfiguredLocalhost
            ? const Duration(milliseconds: 2000)
            : _orderTimeout,
      );

      if (data is Map<String, dynamic>) {
        if (data['order'] is Map) {
          return {
            ...data,
            'order': Map<String, dynamic>.from(data['order'] as Map),
          };
        }
        return data;
      }

      throw ApiException('استجابة غير صالحة من الخادم عند إنشاء الطلب.');
    } finally {
      _isCreatingOrder = false;
    }
  }

  static Future<List<dynamic>> fetchMyOrders({String? token}) async {
    try {
      final data = await _sendJsonRequest(
        method: 'GET',
        path: '/api/orders/my',
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

  static Future<JsonMap> sendWhatsappOtp({
    required String phoneNumber,
  }) async {
    try {
      final cleanedPhone = phoneNumber.trim();
      if (cleanedPhone.isEmpty) {
        throw ApiException('يرجى إدخال رقم الهاتف.');
      }

      final FunctionResponse res = await _supabase.functions
          .invoke(
            'whatsapp-otp',
            body: {
              'action': 'send',
              'phone_number': cleanedPhone,
            },
          )
          .timeout(_otpTimeout);

      final parsed = _parseFunctionPayload(res.data);
      if (parsed['ok'] == false) {
        throw ApiException(
          (parsed['error'] ??
                  parsed['message'] ??
                  'تعذر إرسال رمز التحقق عبر واتساب')
              .toString(),
          statusCode: res.status,
        );
      }

      if (parsed.isNotEmpty) {
        return parsed;
      }

      return {'ok': true, 'message': 'تم إرسال رمز التحقق بنجاح'};
    } on ApiException {
      rethrow;
    } on FunctionException catch (e) {
      debugPrint(
          '❌ خطأ FunctionException في إرسال OTP: status=${e.status}, details=${e.details}');
      throw ApiException(
        'تعذر إرسال رمز التحقق (${e.status}): ${e.details ?? e.reasonPhrase ?? 'خطأ في الدالة'}',
        statusCode: e.status,
      );
    } on TimeoutException {
      throw ApiException(
        'انتهت مهلة إرسال رمز التحقق، يرجى المحاولة مرة أخرى.',
      );
    } catch (e) {
      debugPrint('❌ خطأ في إرسال OTP واتساب: $e');
      throw ApiException('تعذر إرسال رمز التحقق: $e');
    }
  }

  static Future<JsonMap> verifyWhatsappOtp({
    required String phoneNumber,
    required String otpCode,
  }) async {
    try {
      final cleanedPhone = phoneNumber.trim();
      final cleanedCode = otpCode.trim();

      if (cleanedPhone.isEmpty || cleanedCode.isEmpty) {
        throw ApiException('يرجى إدخال رقم الهاتف ورمز التحقق.');
      }

      final FunctionResponse res = await _supabase.functions
          .invoke(
            'whatsapp-otp',
            body: {
              'action': 'verify',
              'phone_number': cleanedPhone,
              'otp_code': cleanedCode,
            },
          )
          .timeout(_otpTimeout);

      final parsed = _parseFunctionPayload(res.data);
      if (parsed.isEmpty) {
        throw ApiException('استجابة غير متوقعة أثناء التحقق من الرمز.');
      }

      final bool isVerified = parsed['verified'] == true ||
          parsed['ok'] == true ||
          parsed['success'] == true;
      if (!isVerified) {
        throw ApiException(
          (parsed['error'] ??
                  parsed['message'] ??
                  'رمز التحقق غير صحيح أو انتهت صلاحيته')
              .toString(),
          statusCode: res.status,
        );
      }

      return {
        ...parsed,
        'verified': true,
      };
    } on ApiException {
      rethrow;
    } on FunctionException catch (e) {
      debugPrint(
          '❌ خطأ FunctionException في التحقق من OTP: status=${e.status}, details=${e.details}');
      throw ApiException(
        'تعذر التحقق من الرمز (${e.status}): ${e.details ?? e.reasonPhrase ?? 'خطأ في الدالة'}',
        statusCode: e.status,
      );
    } on TimeoutException {
      throw ApiException(
        'انتهت مهلة التحقق من الرمز، يرجى المحاولة مرة أخرى.',
      );
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من OTP واتساب: $e');
      throw ApiException('تعذر التحقق من رمز التحقق: $e');
    }
  }
}
