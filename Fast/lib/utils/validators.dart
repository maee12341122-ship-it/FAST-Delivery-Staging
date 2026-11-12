class Validators {
  static String? requiredText(String? value, {String message = 'هذا الحقل مطلوب'}) {
    if (value == null || value.trim().isEmpty) return message;
    return null;
  }

  static String normalizeYemeniPhone(String value) {
    var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00967')) digits = digits.substring(5);
    if (digits.startsWith('967')) digits = digits.substring(3);
    if (digits.startsWith('0')) digits = digits.substring(1);
    return digits;
  }

  static bool isValidYemeniPhone(String value) {
    final digits = normalizeYemeniPhone(value);
    return RegExp(r'^(70|71|73|77|78)\d{7}$').hasMatch(digits);
  }

  static String? yemeniPhone(String? value) {
    if (value == null || value.trim().isEmpty) return 'يرجى إدخال رقم الهاتف';
    if (!isValidYemeniPhone(value)) {
      return 'أدخل رقماً يمنياً صحيحاً مثل 77xxxxxxx أو +96777xxxxxxx';
    }
    return null;
  }

  static String toInternationalYemeniPhone(String value) {
    return '+967${normalizeYemeniPhone(value)}';
  }
}
