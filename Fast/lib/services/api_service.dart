import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// تعريفات مخصصة لتجنب أخطاء الأقواس نهائياً
typedef JsonMap = Map<String, dynamic>;
typedef JsonList = List<JsonMap>;

class ApiService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // 1. جلب الكتالوج العام (المطاعم والمنتجات المتاحة من Supabase)
  static Future<JsonMap> fetchCatalog() async {
    try {
      final response = await _supabase.from('products').select();
      return {'products': response};
    } catch (e) {
      debugPrint('❌ خطأ في جلب الكتالوج: $e');
      rethrow;
    }
  }

  // 1. أ) جلب قائمة المطاعم/المتاجر من جدول restaurants (لضمان تقسيم الأقسام مثل الشميري وو)
  static Future<List<dynamic>> fetchRestaurants() async {
    try {
      final response = await _supabase.from('restaurants').select().eq('is_active', true);
      return response;
    } catch (e) {
      debugPrint('❌ خطأ في جلب المطاعم: $e');
      return [];
    }
  }

  // 1. ب) جلب الأقسام العامة من جدول categories
  static Future<List<dynamic>> fetchCategories() async {
    try {
      final response = await _supabase.from('categories').select().eq('is_active', true);
      return response;
    } catch (e) {
      debugPrint('❌ خطأ في جلب الأقسام: $e');
      return [];
    }
  }

  // 2. التحقق من الكوبون وتطبيق الخصم
  static Future<JsonMap> validateCoupon(String code, double subtotal) async {
    try {
      final response = await _supabase
          .from('coupons')
          .select()
          .eq('code', code.trim())
          .maybeSingle();

      if (response == null) {
        throw Exception('كود الخصم غير صالح أو منتهي الصلاحية.');
      }

      double discountValue = double.tryParse(response['discount_value']?.toString() ?? '0') ?? 0.0;
      String discountType = response['discount_type']?.toString() ?? 'percentage';
      
      double discountAmount = 0.0;
      if (discountType == 'percentage') {
        discountAmount = subtotal * (discountValue / 100);
      } else {
        discountAmount = discountValue; // خصم مبلغ ثابت
      }

      return {
        'code': response['code'],
        'discount_amount': discountAmount,
        'message': 'تم تطبيق الكوبون بنجاح! 🎉'
      };
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من الكوبون: $e');
      rethrow;
    }
  }

  // 3. إنشاء طلب جديد مباشرة في جدول orders في Supabase
  static Future<JsonMap> createOrder({
    required JsonList items,
    required String address,
    required String notes,
    required String token, // رقم هاتف العميل المنقى
  }) async {
    try {
      double productsTotal = 0.0;
      for (var item in items) {
        double price = double.tryParse(item['price'].toString()) ?? 0.0;
        int qty = int.tryParse(item['quantity'].toString()) ?? 1;
        productsTotal += price * qty;
      }

      final response = await _supabase.from('orders').insert({
        'phone': token,
        'address': address.trim(),
        'items_description': notes.trim(),
        'products_total': productsTotal,
        'total_price': productsTotal,
        'status': 'waitingForPricing', // بانتظار تسعير الإدارة
        'admin_message': 'بانتظار تحديد رسوم التوصيل من المشرف',
        'created_at': DateTime.now().toIso8601String(),
      }).select().single();

      return {
        'order': response,
        'message': 'تم إرسال الطلب بنجاح'
      };
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء الطلب (Supabase): $e');
      throw Exception('تعذر إرسال الطلب: $e');
    }
  }

  // 4. جلب طلبات العميل الشخصية بناءً على رقم الهاتف
  static Future<List<dynamic>> fetchMyOrders(String phone) async {
    try {
      final response = await _supabase.from('orders').select().eq('phone', phone);
      return response;
    } catch (e) {
      debugPrint('❌ خطأ في جلب طلبات العميل: $e');
      return [];
    }
  }

  // 5. [لوحة المشرف] جلب جميع الطلبات
  static Future<List<dynamic>> fetchAdminOrders(String token, {String? status}) async {
    try {
      var query = _supabase.from('orders').select();
      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status) as dynamic;
      }
      final response = await query;
      return response;
    } catch (e) {
      debugPrint('❌ خطأ في جلب طلبات المشرف: $e');
      rethrow;
    }
  }

  // 6. [لوحة المشرف] تحديد رسوم التوصيل وتعيين المندوب (التسعير)
  static Future<JsonMap> adminPricingOrder(
    String token,
    int orderId,
    double deliveryFee,
    String assignedCourier,
  ) async {
    try {
      final orderRes = await _supabase.from('orders').select('products_total, total_price').eq('id', orderId).single();
      double productsTotal = double.tryParse(orderRes['products_total']?.toString() ?? orderRes['total_price']?.toString() ?? '0') ?? 0.0;
      double totalPrice = productsTotal + deliveryFee;

      final response = await _supabase.from('orders').update({
        'delivery_fee': deliveryFee,
        'products_total': productsTotal,
        'total_price': totalPrice,
        'assigned_courier': assignedCourier.trim(),
        'status': 'pricingSentToCustomer',
        'is_fee_sent': true,
        'admin_message': 'تم تحديد رسوم التوصيل ($deliveryFee ر.ي). بانتظار موافقة العميل ⏳',
      }).eq('id', orderId).select().single();

      return {'order': response, 'message': 'تم تحديث السعر بنجاح'};
    } catch (e) {
      debugPrint('❌ خطأ في تسعير الطلب: $e');
      rethrow;
    }
  }

  // 7. [لوحة المشرف] تحديث حالة الطلب مباشرة
  static Future<JsonMap> adminUpdateOrderStatus(
    String token,
    int orderId,
    String status,
  ) async {
    title:
    try {
      final response = await _supabase.from('orders').update({
        'status': status,
      }).eq('id', orderId).select().single();

      return {'order': response, 'message': 'تم تحديث الحالة بنجاح'};
    } catch (e) {
      debugPrint('❌ خطأ في تحديث حالة الطلب للمشرف: $e');
      rethrow;
    }
  }

  // 8. [لوحة المندوب] جلب الطلبات المسندة للمندوب الحالي
  static Future<List<dynamic>> fetchCourierOrders(String courierName) async {
    try {
      final response = await _supabase.from('orders').select().eq('assigned_courier', courierName.trim());
      return response;
    } catch (e) {
      debugPrint('❌ خطأ في جلب طلبات المندوب: $e');
      return [];
    }
  }

  // 9. [لوحة المندوب] تحديث حالة الطلب
  static Future<JsonMap> courierUpdateOrderStatus(
    String token,
    int orderId,
    String status,
  ) async {
    try {
      final response = await _supabase.from('orders').update({
        'status': status,
      }).eq('id', orderId).select().single();

      return {'order': response, 'message': 'تم تحديث الحالة بنجاح'};
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
      debugPrint('📍 تحديث الموقع: $latitude, $longitude');
    } catch (e) {
      debugPrint('❌ خطأ في تحديث موقع المندوب: $e');
      rethrow;
    }
  }
}
