import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class ApiService {
  // قم بتغيير هذا الرابط إلى رابط الخادم الخاص بك 
  // (مثلاً للمحاكي المحلي: 'http://10.0.2.2:3000/api')
  static const String baseUrl = 'https://your-node-backend-url.com/api'; 

  // 1. جلب الكتالوج العام (المطاعم والمنتجات المتاحة)
  static Future> fetchCatalog() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/catalog'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('تعذر جلب البيانات من الخادم.');
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب الكتالوج: $e');
      rethrow;
    }
  }

  // 2. التحقق من الكوبون وتطبيق الخصم (متطابق مع Backend subtotal)
  static Future> validateCoupon(String code, double subtotal) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/coupons/validate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'subtotal': subtotal,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return data;
      } else {
        throw Exception(data['error'] ?? 'الكوبون غير صالح.');
      }
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من الكوبون: $e');
      rethrow;
    }
  }

  // 3. إنشاء طلب جديد عبر خادم Node.js الآمن
  static Future> createOrder({
    required List> items,
    required String address,
    required String notes,
    required String token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/orders'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'items': items,
          'address': address,
          'notes': notes,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return data;
      } else {
        throw Exception(data['error'] ?? 'فشل إنشاء الطلب.');
      }
    } catch (e) {
      debugPrint('❌ خطأ في الاتصال بالـ Backend (createOrder): $e');
      rethrow;
    }
  }

  // 4. جلب طلبات العميل الشخصية
  static Future<List<dynamic>> fetchMyOrders(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/orders/mine'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return data['orders'] ?? [];
      } else {
        throw Exception(data['error'] ?? 'تعذر جلب الطلبات.');
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب طلبات العميل: $e');
      rethrow;
    }
  }

  // 5. [لوحة المشرف] جلب جميع الطلبات
  static Future<List<dynamic>> fetchAdminOrders(String token, {String? status}) async {
    try {
      String url = '$baseUrl/admin/orders';
      if (status != null && status.isNotEmpty) {
        url += '?status=$status';
      }
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return data['orders'] ?? [];
      } else {
        throw Exception(data['error'] ?? 'تعذر جلب طلبات المشرف.');
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب طلبات المشرف: $e');
      rethrow;
    }
  }

  // 6. [لوحة المشرف] تحديد رسوم التوصيل وتعيين المندوب (التسعير)
  static Future> adminPricingOrder(
    String token,
    int orderId,
    double deliveryFee,
    String assignedCourier,
  ) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/admin/orders/$orderId/pricing'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'deliveryFee': deliveryFee,
          'assignedCourier': assignedCourier,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return data;
      } else {
        throw Exception(data['error'] ?? 'فشل تحديد السعر.');
      }
    } catch (e) {
      debugPrint('❌ خطأ في تسعير الطلب: $e');
      rethrow;
    }
  }

  // 7. [لوحة المشرف] تحديث حالة الطلب مباشرة
  static Future> adminUpdateOrderStatus(
    String token,
    int orderId,
    String status,
  ) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/admin/orders/$orderId/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'status': status}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return data;
      } else {
        throw Exception(data['error'] ?? 'فشل تحديث الحالة.');
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحديث حالة الطلب للمشرف: $e');
      rethrow;
    }
  }

  // 8. [لوحة المندوب] جلب الطلبات المسندة للمندوب الحالي
  static Future<List<dynamic>> fetchCourierOrders(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/courier/orders'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return data['orders'] ?? [];
      } else {
        throw Exception(data['error'] ?? 'تعذر جلب طلبات المندوب.');
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب طلبات المندوب: $e');
      rethrow;
    }
  }

  // 9. [لوحة المندوب] تحديث حالة الطلب (قبول، في الطريق، تم التوصيل)
  static Future> courierUpdateOrderStatus(
    String token,
    int orderId,
    String status,
  ) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/courier/orders/$orderId/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'status': status}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return data;
      } else {
        throw Exception(data['error'] ?? 'فشل تحديث حالة الطلب.');
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحديث حالة الطلب للمندوب: $e');
      rethrow;
    }
  }

  // 10. [لوحة المندوب] إرسال وتحديث الموقع الجغرافي للمندوب
  static Future<void> updateCourierLocation(
    String token,
    double latitude,
    double longitude,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/courier/location'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
        }),
      );

      if (response.statusCode != 201) {
        final data = jsonDecode(response.body);
        throw Exception(data['error'] ?? 'فشل تحديث الموقع.');
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحديث موقع المندوب: $e');
      rethrow;
    }
  }
}
