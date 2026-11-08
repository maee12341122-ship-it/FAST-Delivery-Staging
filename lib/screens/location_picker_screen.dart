import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_service.dart';
import '../utils/constants.dart';

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialPoint;
  const LocationPickerScreen({super.key, this.initialPoint});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  // إحداثيات مركز مدينة تعز الافتراضية
  static const LatLng _taizCenter = LatLng(13.5795, 44.0209);
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();
  LatLng? _selectedPoint;
  bool _gettingLocation = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedPoint = widget.initialPoint ?? _taizCenter;
  }

  Future<void> _useGps() async {
    setState(() {
      _gettingLocation = true;
      _error = null;
    });
    try {
      final position = await _locationService.getCurrentPosition();
      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _selectedPoint = point);
      _mapController.move(point, 16);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          elevation: 2,
          title: const Text('تحديد موقع التوصيل على الخريطة 🗺️', style: TextStyle(color: AppConstants.gold, fontWeight: FontWeight.bold, fontSize: 16)),
          iconTheme: const IconThemeData(color: AppConstants.gold),
        ),
        body: Column(
          children: [
            // شريط التحكم العلوي (زر الـ GPS وحالة الموقع)
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF1E1E1E),
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
                      label: const Text('موقعي الحالي GPS', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedPoint == null ? 'اضغط على الخريطة لوضع المؤشر' : 'تم اختيار نقطة التوصيل ✅',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
              ),
            
            // خريطة OpenStreetMap التفاعلية
            Expanded(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: widget.initialPoint ?? _taizCenter,
                  initialZoom: widget.initialPoint == null ? 14 : 16,
                  onTap: (tapPosition, point) => setState(() => _selectedPoint = point),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.taiz_express',
                  ),
                  if (_selectedPoint != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _selectedPoint!,
                          width: 52,
                          height: 52,
                          child: const Icon(Icons.location_pin, size: 48, color: Colors.redAccent),
                        ),
                      ],
                    ),
                  const RichAttributionWidget(
                    attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
                  ),
                ],
              ),
            ),

            // شريط تأكيد الموقع السفلي
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF1E1E1E),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.gold,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _selectedPoint == null ? null : () => Navigator.pop(context, _selectedPoint),
                child: const Text('تأكيد واعتماد هذا الموقع 📍', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
