import 'package:flutter/material.dart';

class OrderTimeHelper {
  /// تحويل قيمة التاريخ/الوقت من قاعدة البيانات (UTC غالباً) إلى التوقيت المحلي
  static DateTime? parseLocal(dynamic rawValue) {
    if (rawValue == null) return null;
    if (rawValue is DateTime) return rawValue.toLocal();
    final str = rawValue.toString().trim();
    if (str.isEmpty) return null;
    final parsed = DateTime.tryParse(str);
    return parsed?.toLocal();
  }

  /// تنسيق التاريخ والوقت بشكل عربي واضح (12 ساعة مع ص/م)
  static String formatDateTime(dynamic rawValue) {
    final dt = parseLocal(rawValue);
    if (dt == null) return 'غير محدد';

    final year = dt.year.toString().padLeft(4, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');

    final hour12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'م' : 'ص';

    return '$year/$month/$day • $hour12:$minute $period';
  }

  /// التحقق مما إذا كان الطلب يقع ضمن فترة زمنية محددة
  /// يدعم الاستدعاء الموضعي: isWithinRange(val, start, end)
  /// ويدعم الاستدعاء المسمّى: isWithinRange(val, start: s, end: e)
  static bool isWithinRange(
    dynamic rawValue, [
    DateTime? positionalStart,
    DateTime? positionalEnd,
    DateTime? start,
    DateTime? end,
  ]) {
    final rangeStart = start ?? positionalStart;
    final rangeEnd = end ?? positionalEnd;

    final dt = parseLocal(rawValue);
    if (dt == null) return false;

    if (rangeStart != null) {
      final startOfDay = DateTime(
        rangeStart.year,
        rangeStart.month,
        rangeStart.day,
        0,
        0,
        0,
      );
      if (dt.isBefore(startOfDay)) return false;
    }

    if (rangeEnd != null) {
      final endOfDay = DateTime(
        rangeEnd.year,
        rangeEnd.month,
        rangeEnd.day,
        23,
        59,
        59,
      );
      if (dt.isAfter(endOfDay)) return false;
    }

    return true;
  }

  /// التحقق مما إذا كان الطلب يقع ضمن اليوم الحالي
  static bool isToday(dynamic rawValue) {
    final dt = parseLocal(rawValue);
    if (dt == null) return false;
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  /// التحقق مما إذا كان الوقت الحالي ضمن ساعات عمل المتجر المحددة (startHour إلى endHour)
  /// يدعم أيضاً الفترات التي تمتد بعد منتصف الليل (مثلاً من 14 إلى 2)
  static bool isWithinStoreHours(
    int startHour,
    int endHour, {
    DateTime? referenceTime,
  }) {
    final now = referenceTime ?? DateTime.now();
    final currentHour = now.hour;

    if (startHour == endHour) return true;

    if (startHour < endHour) {
      return currentHour >= startHour && currentHour < endHour;
    } else {
      // فترة تمتد عبر منتصف الليل
      return currentHour >= startHour || currentHour < endHour;
    }
  }

  /// رسالة تنبيه واضحة عند محاولة الطلب خارج ساعات العمل
  static String workingHoursMessage(int startHour, int endHour) {
    String fmtHour(int h) {
      final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      final p = h >= 12 ? 'م' : 'ص';
      return '$h12:00 $p';
    }

    return 'عذراً، التطبيق خارج أوقات العمل حالياً.\nساعات العمل: من ${fmtHour(startHour)} إلى ${fmtHour(endHour)}';
  }
}
