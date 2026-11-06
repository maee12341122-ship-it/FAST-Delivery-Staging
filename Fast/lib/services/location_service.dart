import 'package:geolocator/geolocator.dart';

class LocationService {
  /// 📍 دالة لجلب الموقع الحالي بدقة عالية مع التحقق الكامل من الأذونات والـ GPS
  Future<Position> getCurrentPosition() async {
    // 1. التحقق مما إذا كانت خدمة تحديد الموقع (GPS) مفعلة في الجهاز
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw StateError('خدمة الموقع GPS مغلقة. يرجى تفعيلها من إعدادات الهاتف 📍');
    }

    // 2. التحقق من حالة أذونات الوصول للموقع
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    if (permission == LocationPermission.denied) {
      throw StateError('لم تقم بمنح إذن الوصول للموقع للتطبيق ❌');
    }
    
    if (permission == LocationPermission.deniedForever) {
      throw StateError('تم رفض إذن الموقع نهائياً. يرجى فتحه يدوياً من إعدادات التطبيق ⚙️');
    }

    // 3. جلب الموقع الجغرافي الحالي بدقة عالية بالتنسيق المتوافق مع الإصدار
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }
}
