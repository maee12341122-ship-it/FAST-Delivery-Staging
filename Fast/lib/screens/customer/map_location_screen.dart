import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../utils/constants.dart';

class MapLocationScreen extends StatefulWidget {
  final LatLng? initialPoint;
  const MapLocationScreen({Key? key, this.initialPoint}) : super(key: key);

  @override
  State<MapLocationScreen> createState() => _MapLocationScreenState();
}

class _MapLocationScreenState extends State<MapLocationScreen> {
  // إحداثيات مركز مدينة تعز الافتراضية
  static const LatLng _taizCenter = LatLng(13.5795, 44.0209);
  final MapController _mapController = MapController();
  LatLng? _selectedPoint;
  bool _gettingLocation = false;
  String? _error;
  
  // حقل إدخال العنوان التفصيلي يدوياً
  final TextEditingController _customAddressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedPoint = widget.initialPoint ?? _taizCenter;
  }

  // دالة تحقق واشتراط إدخال العنوان والموقع قبل العودة
  void _saveAndReturn() {
    final addressText = _customAddressController.text.trim();

    // ⛔ الشرط الإجباري: يلزم وجود عنوان نصي وموقع محدد على الخريطة
    if (addressText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى كتابة عنوانك التفصيلي أولاً! ⚠️'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_selectedPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تحديد موقعك على الخريطة أو عبر GPS! 📍'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // 🎯 تنسيق الإحداثيات بشكل نظيف وموحد ومنع التداخل النصي
    final double lat = _selectedPoint!.latitude;
    final double lng = _selectedPoint!.longitude;
    final formattedCoords = '(${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
    
    // دمج العنوان النصي مع الإحداثيات المنسقة بوضوح
    final finalFullAddress = '$addressText (الإحداثيات: $formattedCoords)';

    // إذا تحققت الشروط يتم حفظ وإرسال البيانات
    Navigator.pop(context, {
      'address': finalFullAddress,
      'latLng': _selectedPoint,
    });
  }

  // دالة لجلب الموقع الحالي عبر الـ GPS وتحديث الخريطة
  Future<void> _useGps() async {
    setState(() {
      _gettingLocation = true;
      _error = null;
    });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'خدمة الموقع (GPS) مغلقة، يرجى تفعيلها من إعدادات الهاتف.';
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'تم رفض صلاحية الوصول إلى الموقع.';
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw 'صلاحية الموقع مرفوضة بشكل دائم من الإعدادات.';
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _selectedPoint = point);
      
      // تحريك الخريطة إلى الموقع الحالي بسلاسة
      _mapController.move(point, 16.0);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  @override
  void dispose() {
    _customAddressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cardColor = Color(0xFF1E1E1E);
    const backgroundColor = Color(0xFF121212);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: cardColor,
          title: const Text(
            'تحديد موقع التوصيل في تعز 📍', 
            style: TextStyle(color: AppConstants.gold, fontSize: 15, fontWeight: FontWeight.bold)
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward, color: AppConstants.gold),
            onPressed: _saveAndReturn,
          ),
        ),
        body: Column(
          children: [
            // حقل إدخال العنوان التفصيلي يدوياً
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppConstants.gold.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'أكتب عنوانك التفصيلي بدقة (مطلوب): *',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _customAddressController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'مثال: حي الروضة، بجوار الشارع العام',
                        hintStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: backgroundColor,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.location_on, color: AppConstants.gold),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // شريط زر الـ GPS
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppConstants.gold,
                        side: const BorderSide(color: AppConstants.gold),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _gettingLocation ? null : _useGps,
                      icon: _gettingLocation
                          ? const SizedBox(
                              width: 16, 
                              height: 16, 
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppConstants.gold)
                            )
                          : const Icon(Icons.my_location),
                      label: const Text('موقعي الحالي GPS 🛰️', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12), textAlign: TextAlign.center),
              ),
            
            const SizedBox(height: 8),

            // الخريطة التفاعلية
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                ),
                clipBehavior: Clip.antiAlias,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: widget.initialPoint ?? _taizCenter,
                    initialZoom: 15.0,
                    onTap: (tapPosition, point) {
                      setState(() => _selectedPoint = point);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
                      userAgentPackageName: 'com.fast.taiz',
                    ),
                    if (_selectedPoint != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _selectedPoint!,
                            width: 50,
                            height: 50,
                            child: const Icon(
                              Icons.location_pin,
                              color: Colors.red,
                              size: 45,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // زر الحفظ النهائي والعودة
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.gold,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _saveAndReturn,
                child: const Text('تثبيت الموقع والعنوان والعودة ✅', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
