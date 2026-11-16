import 'package:flutter/material.dart';

class AppConstants {
  // اللون الذهبي الأساسي لتصميم التطبيق الفاخر 🌟
  static const Color gold = Color(0xFFFFD700);
  
  // الألوان الثابتة للخلفيات
  static const Color darkBackground = Color(0xFF121212);
  static const Color surfaceColor = Color(0xFF1E1E1E);

  // رابط الخادم الأساسي الموحد (يتم تعديله إلى رابط الإنتاج السحابي عند النشر النهائي)
  static const String baseUrl = 'https://your-node-backend-url.com/api';

  // أوقات الدوام الرسمي
  static const int openingHour = 11; // 11 صباحاً
  static const int closingHour = 22; // 10 مساءً

  // مفاتيح التخزين المحلي (SharedPreferences)
  static const String acceptedTermsKey = 'ACCEPTED_TERMS';
  static const String hoursStartKey = 'HOURS_START';
}

// تصنيفات الأقسام والمنتجات لتجنب خطأ Undefined name
enum ProductCategories {
  restaurants,
  groceries,
  produce, // الخضار والفواكه
  pharmacy,
  others,
}
