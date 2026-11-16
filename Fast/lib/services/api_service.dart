import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class ApiService {
  // قم بتغيير هذا الرابط إلى رابط الخادم الخاص بك (مثلاً عند التشغيل المحلي على المحاكي أو الإنتاج)
  static const String baseUrl = 'https://your-node-backend-url.com/api'; 

  // 1. إنشاء طلب جديد عبر خادم Node.js الآمن
  static Future> createOrder({
    required List> items,
    required String address,
    required String notes,
    String? token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/orders'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
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

  // 2. التحقق من الكوبون وتطبيق الخصم
  static Future> validateCoupon(String code, double subtotal) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/coupons/validate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'cart_subtotal': subtotal,
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

  // 3. جلب الكتالوج العام (المطاعم والمنتجات)
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
}
