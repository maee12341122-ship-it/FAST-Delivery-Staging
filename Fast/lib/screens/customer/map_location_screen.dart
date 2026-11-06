import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  GoogleMapController? _mapController;
  LatLng? _selectedPoint;
  bool _gettingLocation = false;
  String? _error;
  final TextEditingController _customAddressController = 
      TextEditingController(text: 'تعز - ديلوكس / بجوار الشارع العام');

  @override
  void initState() {
    super.initState();
    _selectedPoint = widget.initialPoint ?? _taizCenter;
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
        throw 'خدمة الموقع (GPS) مغلقة، يرجى تفعيلها.';
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
      
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: point, zoom: 16),
        ),
      );
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
    _mapController?.dispose();
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
          title: const Text('تحديد موقع التوصيل في تعز 📍', style: TextStyle(color: AppConstants.gold, fontSize: 15, fontWeight: FontWeight.bold)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward, color: AppConstants.gold),
            onPressed: () => Navigator.pop(context, {
              'address': _customAddressController.text.trim(),
              'latLng': _selectedPoint,
            }),
          ),
        ),
        body: Column(
          children: [
            // حقل إدخال العنوان التفصيلي
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
                      'أكتب عنوانك التفصيلي بدقة:',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _customAddressController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'مثال: تعز - حي الروضة، قرب الشارع العام',
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

            // شريط التحكم العلوي (زر الـ GPS)
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
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppConstants.gold))
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

            // خريطة جوجل التفاعلية الفعلية
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                ),
                clipBehavior: Clip.antiAlias,
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: widget.initialPoint ?? _taizCenter,
                    zoom: 15,
                  ),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: true,
                  onMapCreated: (controller) => _mapController = controller,
                  onTap: (point) {
                    setState(() => _selectedPoint = point);
                  },
                  markers: _selectedPoint == null ? {} : {
                    Marker(
                      markerId: const MarkerId('selected_location'),
                      position: _selectedPoint!,
                      infoWindow: const InfoWindow(title: 'موقع التوصيل المحدد'),
                    ),
                  },
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
                onPressed: () {
                  Navigator.pop(context, {
                    'address': _customAddressController.text.trim(),
                    'latLng': _selectedPoint,
                  });
                },
                child: const Text('تثبيت الموقع والعنوان والعودة ✅', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
