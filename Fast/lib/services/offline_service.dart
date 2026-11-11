import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineService {
  static const String _cachedOrdersKey = 'cached_orders_key';
  static const String _cachedCartKey = 'cached_cart_key';

  // حفظ الطلبات محلياً لعرضها عند انقطاع الإنترنت
  static Future<void> cacheOrders(List> orders) async {
    final prefs = await SharedPreferences.getInstance();
    String encodedData = jsonEncode(orders);
    await prefs.setString(_cachedOrdersKey, encodedData);
  }

  // جلب الطلبات المخزنة محلياً
  static Future<List>> getCachedOrders() async {
    final prefs = await SharedPreferences.getInstance();
    String? encodedData = prefs.getString(_cachedOrdersKey);
    if (encodedData == null) return [];
    
    List<dynamic> decodedList = jsonDecode(encodedData);
    return decodedList.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  // حفظ السلة مؤقتاً في حال انقطاع الشبكة أثناء التسوق
  static Future<void> cacheCart(List> cartItems) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedCartKey, jsonEncode(cartItems));
  }

  // استرجاع السلة المخزنة محلياً
  static Future<List>> getCachedCart() async {
    final prefs = await SharedPreferences.getInstance();
    String? encodedData = prefs.getString(_cachedCartKey);
    if (encodedData == null) return [];

    List<dynamic> decodedList = jsonDecode(encodedData);
    return decodedList.map((item) => Map<String, dynamic>.from(item)).toList();
  }
}
