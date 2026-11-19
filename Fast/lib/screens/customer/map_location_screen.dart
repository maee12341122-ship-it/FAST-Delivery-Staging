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

  // الإحداثيات الحالية التي يشير إليها منتصف الخريطة بدقة فائقة
  LatLng? _selectedPoint;
  bool _gettingLocation = false;
  String? _error;
  bool _isServiceDisabled = false;
  bool _isPermissionDeniedForever = false;

  // حقل إدخال العنوان التفصيلي يدوياً وموجه التركيز
  final TextEditingController _customAddressController = TextEditingController();
  final FocusNode _addressFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _selectedPoint = widget.initialPoint ?? _taizCenter;
  }

  // 📍 دالة تحويل الإحداثيات الجغرافية إلى اسم منطقة واضحة في تعز بدلاً من الأرقام
  String getTaizAreaName(LatLng point) {
    final double lat = point.latitude;
    final double lng = point.longitude;

    if (lat >= 13.568 && lat <= 13.577 && lng >= 43.996 && lng <= 44.009) {
      return 'منطقة دي لوكس 📍';
    } else if (lat >= 13.577 && lat <= 13.587 && lng >= 44.010 && lng <= 44.024) {
      return 'شارع جمال / التحرير 📍';
    } else if (lat >= 13.564 && lat <= 13.573 && lng >= 44.012 && lng <= 44.026) {
      return 'حي المسبح 📍';
    } else if (lat >= 13.582 && lat <= 13.595 && lng >= 44.022 && lng <= 44.035) {
      return 'حي الروضة 📍';
    } else if (lat >= 13.578 && lat <= 13.590 && lng >= 43.978 && lng <= 43.995) {
      return 'منطقة الحصب 📍';
    } else if (lat >= 13.555 && lat <= 13.567 && lng >= 44.005 && lng <= 44.020) {
      return 'منطقة نقطة الرابع 📍';
    } else {
      return 'تعز - منطقة معتمدة 📍';
    }
  }

  // نافذة تطلب من المستخدم تشغيل الموقع بشكل مباشر
  Future<void> _showEnableLocationDialog({required bool openAppSettingsMode}) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppConstants.gold.withOpacity(0.5)),
          ),
          title: const Row(
            children: [
              Icon(Icons.location_off_rounded, color: AppConstants.gold, size: 26),
              SizedBox(width: 8),
              Text(
                'تشغيل الموقع مطلوب 📍',
                style: TextStyle(color: AppConstants.gold, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            openAppSettingsMode
                ? 'تم رفض إذن الموقع سابقاً. يرجى تشغيل الموقع والسماح بالوصول من إعدادات الهاتف لتحديد موقعك بدقة.'
                : 'خدمة الموقع متوقفة حالياً. يرجى تشغيل الموقع لتحديد موقعك بدقة على الخريطة.',
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                if (openAppSettingsMode) {
                  await Geolocator.openAppSettings();
                } else {
                  await Geolocator.openLocationSettings();
                }
              },
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: const Text('تشغيل الموقع', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // دالة تحقق واشتراط إدخال العنوان والموقع قبل العودة
  void _saveAndReturn() {
    final addressText = _customAddressController.text.trim();

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

    final areaName = getTaizAreaName(_selectedPoint!);
    final finalFullAddress = '$addressText - $areaName';

    Navigator.pop(context, {
      'address': finalFullAddress,
      'latLng': _selectedPoint,
    });
  }

  // دالة لجلب الموقع الحالي عبر الـ GPS بأقصى دقة متاح وتوسيط الخريطة تلقائياً
  Future<void> _useGps() async {
    setState(() {
      _gettingLocation = true;
      _error = null;
      _isServiceDisabled = false;
      _isPermissionDeniedForever = false;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _isServiceDisabled = true;
          _error = 'يرجى تشغيل الموقع (GPS) للمتابعة.';
        });
        await _showEnableLocationDialog(openAppSettingsMode: false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          setState(() {
            _error = 'يرجى السماح بتشغيل الموقع لتحديد عنوانك بدقة.';
          });
          await _showEnableLocationDialog(openAppSettingsMode: false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _isPermissionDeniedForever = true;
          _error = 'إذن الموقع مغلق من الإعدادات. اضغط "تشغيل الموقع" لتفعيله.';
        });
        await _showEnableLocationDialog(openAppSettingsMode: true);
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );

      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;

      setState(() {
        _selectedPoint = point;
        _error = null;
      });

      _mapController.move(point, 17.5);
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
    _addressFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cardColor = Color(0xFF1E1E1E);
    const backgroundColor = Color(0xFF121212);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: backgroundColor,
          appBar: AppBar(
            backgroundColor: cardColor,
            title: const Text(
              'تحديد موقع التوصيل بدقة فائقة 📍',
              style: TextStyle(color: AppConstants.gold, fontSize: 15, fontWeight: FontWeight.bold),
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
                        focusNode: _addressFocus,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _saveAndReturn(),
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

              // شريط زر الـ GPS الفائق
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
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppConstants.gold),
                              )
                            : const Icon(Icons.my_location),
                        label: const Text('جلب موقعي الحالي بدقة GPS القصوى 🛰️', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_disabled, color: Colors.redAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (_isServiceDisabled || _isPermissionDeniedForever)
                          TextButton(
                            onPressed: () async {
                              if (_isPermissionDeniedForever) {
                                await Geolocator.openAppSettings();
                              } else {
                                await Geolocator.openLocationSettings();
                              }
                            },
                            child: const Text(
                              'تشغيل الموقع',
                              style: TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 6),

              // الخريطة الاحترافية مع الخادم البديل السريع
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: widget.initialPoint ?? _taizCenter,
                          initialZoom: 17.0,
                          onPositionChanged: (position, hasGesture) {
                            if (position.center != null) {
                              setState(() {
                                _selectedPoint = position.center;
                              });
                            }
                          },
                        ),
                        children: [
                          // 🚀 استخدام الخادم البديل السريع لتجنب الحجب ومشاكل الاتصال المحلي
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.fast.taiz',
                            maxZoom: 19,
                          ),
                        ],
                      ),
                      // 📌 الدبوس المركزي الثابت (Center Pin)
                      const IgnorePointer(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 35),
                          child: Icon(
                            Icons.location_pin,
                            color: Colors.red,
                            size: 50,
                          ),
                        ),
                      ),
                      // شريط توجيهي علوي مع إظهار الإحداثيات الحية للمستخدم
                      Positioned(
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppConstants.gold.withOpacity(0.5)),
                          ),
                          child: Text(
                            _selectedPoint != null
                                ? 'إحداثيات الدبوس: (${_selectedPoint!.latitude.toStringAsFixed(4)}, ${_selectedPoint!.longitude.toStringAsFixed(4)})'
                                : 'اسحب الخريطة لتحديد الموقع بدقة 🎯',
                            style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
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
      ),
    );
  }
}
