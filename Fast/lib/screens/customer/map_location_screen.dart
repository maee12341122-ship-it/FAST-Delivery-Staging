import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../utils/constants.dart';

class _TaizLandmark {
  final String name;
  final LatLng point;
  final List<String> aliases;

  const _TaizLandmark({
    required this.name,
    required this.point,
    this.aliases = const [],
  });
}

class MapLocationScreen extends StatefulWidget {
  final LatLng? initialPoint;
  const MapLocationScreen({Key? key, this.initialPoint}) : super(key: key);

  @override
  State<MapLocationScreen> createState() => _MapLocationScreenState();
}

class _MapLocationScreenState extends State<MapLocationScreen> {
  static const LatLng _taizCenter = LatLng(13.5795, 44.0209);
  final MapController _mapController = MapController();

  // مصادر بلاطات مرتبة بحيث تبدأ بمصدر أكثر توافقاً وتبدّل تلقائياً عند الفشل
  static const List<String> _tileUrls = [
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
    'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  ];

  // مرجع محلي سريع لأحياء ومناطق تعز ليعمل البحث والتحديد بدون الاعتماد الكلي على Nominatim
  static const List<_TaizLandmark> _taizLandmarks = [
    _TaizLandmark(
      name: 'شارع جمال',
      point: LatLng(13.5795, 44.0209),
      aliases: ['جمال', 'وسط المدينة', 'شارع جمال تعز'],
    ),
    _TaizLandmark(
      name: 'التحرير الأسفل / شارع التحرير',
      point: LatLng(13.5778, 44.0122),
      aliases: ['التحرير', 'التحرير الاسفل', 'التحرير الأعلى', 'شارع التحرير'],
    ),
    _TaizLandmark(
      name: 'منطقة دي لوكس',
      point: LatLng(13.5725, 44.0025),
      aliases: ['دي لوكس', 'ديلوكس'],
    ),
    _TaizLandmark(
      name: 'حي المسبح',
      point: LatLng(13.5685, 44.0190),
      aliases: ['المسبح', 'حي المسبح تعز'],
    ),
    _TaizLandmark(
      name: 'حي الروضة',
      point: LatLng(13.5885, 44.0285),
      aliases: ['الروضة', 'حي الروضة تعز'],
    ),
    _TaizLandmark(
      name: 'منطقة الحصب',
      point: LatLng(13.5840, 43.9865),
      aliases: ['الحصب', 'الحصب تعز'],
    ),
    _TaizLandmark(
      name: 'منطقة نقطة الرابع',
      point: LatLng(13.5610, 44.0125),
      aliases: ['نقطة الرابع', 'الرابع'],
    ),
    _TaizLandmark(
      name: 'بير باشا',
      point: LatLng(13.5760, 43.9940),
      aliases: ['بير باشا', 'بئر باشا'],
    ),
    _TaizLandmark(
      name: 'الجحملية',
      point: LatLng(13.5740, 44.0340),
      aliases: ['الجحملية', 'جحملية'],
    ),
    _TaizLandmark(
      name: 'عصيفرة',
      point: LatLng(13.6050, 44.0180),
      aliases: ['عصيفرة', 'عصيفره'],
    ),
    _TaizLandmark(
      name: 'وادي القاضي',
      point: LatLng(13.5850, 44.0160),
      aliases: ['وادي القاضي', 'وادي القاضي تعز'],
    ),
    _TaizLandmark(
      name: 'جولة سنان',
      point: LatLng(13.5665, 44.0055),
      aliases: ['جولة سنان', 'سنان'],
    ),
  ];

  int _tileUrlIndex = 0;
  int _tileErrorStreak = 0;
  Key _tileLayerKey = const ValueKey('tile_layer_0');

  LatLng? _selectedPoint;
  bool _gettingLocation = false;
  bool _searchingPlace = false;
  String? _error;
  bool _isServiceDisabled = false;
  bool _isPermissionDeniedForever = false;
  String _detectedAreaLabel = 'تعز - منطقة معتمدة 📍';
  Timer? _geocodeDebounce;

  final TextEditingController _customAddressController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _addressFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _selectedPoint = widget.initialPoint ?? _taizCenter;
    _detectedAreaLabel = getTaizAreaName(_selectedPoint!);
    unawaited(_reverseGeocodePoint(_selectedPoint!, autoFillIfEmpty: false));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialLocationStatus();
    });
  }

  void _switchToNextTileSource() {
    if (!mounted) return;
    if (_tileUrlIndex + 1 < _tileUrls.length) {
      setState(() {
        _tileUrlIndex++;
        _tileErrorStreak = 0;
        _tileLayerKey = ValueKey('tile_layer_$_tileUrlIndex');
      });
    }
  }

  void _handleTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    _tileErrorStreak++;
    if (_tileErrorStreak >= 4 && _tileUrlIndex + 1 < _tileUrls.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _switchToNextTileSource();
      });
    }
  }

  Future<void> _checkInitialLocationStatus() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      if (!mounted) return;

      if (!serviceEnabled) {
        setState(() {
          _isServiceDisabled = true;
          _error =
              'الموقع غير مفعّل حالياً! يرجى تفعيل الموقع (GPS) لتحديد موقعك بدقة.';
        });
      } else if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isPermissionDeniedForever = true;
          _error =
              'إذن الموقع مغلق من الإعدادات! يرجى تفعيل الموقع من إعدادات الهاتف.';
        });
      } else if (permission == LocationPermission.denied) {
        setState(() {
          _error = 'يرجى السماح بتفعيل الموقع لتحديد عنوانك بدقة.';
        });
      }
    } catch (_) {}
  }

  String getTaizAreaName(LatLng point) {
    final double lat = point.latitude;
    final double lng = point.longitude;

    if (lat >= 13.568 && lat <= 13.577 && lng >= 43.996 && lng <= 44.009) {
      return 'منطقة دي لوكس 📍';
    } else if (lat >= 13.577 &&
        lat <= 13.587 &&
        lng >= 44.010 &&
        lng <= 44.024) {
      return 'شارع جمال / التحرير 📍';
    } else if (lat >= 13.564 &&
        lat <= 13.573 &&
        lng >= 44.012 &&
        lng <= 44.026) {
      return 'حي المسبح 📍';
    } else if (lat >= 13.582 &&
        lat <= 13.595 &&
        lng >= 44.022 &&
        lng <= 44.035) {
      return 'حي الروضة 📍';
    } else if (lat >= 13.578 &&
        lat <= 13.590 &&
        lng >= 43.978 &&
        lng <= 43.995) {
      return 'منطقة الحصب 📍';
    } else if (lat >= 13.555 &&
        lat <= 13.567 &&
        lng >= 44.005 &&
        lng <= 44.020) {
      return 'منطقة نقطة الرابع 📍';
    } else if (lat >= 13.570 &&
        lat <= 13.582 &&
        lng >= 43.989 &&
        lng <= 44.000) {
      return 'بير باشا 📍';
    } else if (lat >= 13.568 &&
        lat <= 13.580 &&
        lng >= 44.028 &&
        lng <= 44.042) {
      return 'الجحملية 📍';
    } else if (lat >= 13.596 &&
        lat <= 13.615 &&
        lng >= 44.010 &&
        lng <= 44.028) {
      return 'عصيفرة 📍';
    } else {
      return 'تعز - منطقة معتمدة 📍';
    }
  }

  _TaizLandmark? _findLocalTaizMatch(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    for (final item in _taizLandmarks) {
      if (item.name.toLowerCase().contains(normalized) ||
          normalized.contains(item.name.toLowerCase())) {
        return item;
      }
      for (final alias in item.aliases) {
        final a = alias.toLowerCase();
        if (a.contains(normalized) || normalized.contains(a)) {
          return item;
        }
      }
    }
    return null;
  }

  Future<void> _reverseGeocodePoint(
    LatLng point, {
    bool autoFillIfEmpty = true,
  }) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${point.latitude}&lon=${point.longitude}&accept-language=ar',
      );
      final res = await http.get(
        uri,
        headers: {
          'User-Agent': 'FastDeliveryTaizApp/1.0 (com.fast.taiz)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 4));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map<String, dynamic>) {
          final addr = data['address'];
          String placeTitle = '';
          if (addr is Map<String, dynamic>) {
            final parts = <String>[
              if ((addr['suburb'] ?? addr['neighbourhood'] ?? addr['quarter'])
                      ?.toString()
                      .trim()
                      .isNotEmpty ==
                  true)
                (addr['suburb'] ?? addr['neighbourhood'] ?? addr['quarter'])
                    .toString()
                    .trim(),
              if ((addr['road'] ?? addr['street'])
                      ?.toString()
                      .trim()
                      .isNotEmpty ==
                  true)
                (addr['road'] ?? addr['street']).toString().trim(),
              if ((addr['city'] ?? addr['town'] ?? addr['county'])
                      ?.toString()
                      .trim()
                      .isNotEmpty ==
                  true)
                (addr['city'] ?? addr['town'] ?? addr['county'])
                    .toString()
                    .trim(),
            ];
            placeTitle = parts.join(' - ');
          }
          if (placeTitle.isEmpty && data['display_name'] != null) {
            final fullName = data['display_name'].toString();
            placeTitle = fullName.split(',').take(2).join(' - ').trim();
          }

          if (placeTitle.isNotEmpty) {
            setState(() {
              _detectedAreaLabel = '$placeTitle 📍';
              if (autoFillIfEmpty &&
                  _customAddressController.text.trim().isEmpty) {
                _customAddressController.text = placeTitle;
              }
            });
          }
        }
      }
    } catch (_) {
      // في حال حظر أو بطء Nominatim على بعض الشبكات يبقى على اسم المنطقة المحلي في تعز
      if (mounted) {
        final localLabel = getTaizAreaName(point);
        setState(() {
          _detectedAreaLabel = localLabel;
        });
      }
    }
  }

  Future<void> _searchPlaceOnMap() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() => _searchingPlace = true);

    try {
      // أولاً: محاولة البحث عبر Nominatim مع مهلة قصيرة حتى لا ينتظر المستخدم طويلاً إذا كان محجوباً على الشبكة
      final searchQuery = query.contains('تعز') || query.contains('اليمن')
          ? query
          : '$query تعز';
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&accept-language=ar&q=${Uri.encodeComponent(searchQuery)}',
      );

      final res = await http.get(
        uri,
        headers: {
          'User-Agent': 'FastDeliveryTaizApp/1.0 (com.fast.taiz)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 4));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body);
        if (list is List && list.isNotEmpty) {
          final first = list.first as Map<String, dynamic>;
          final lat = double.tryParse(first['lat']?.toString() ?? '');
          final lon = double.tryParse(first['lon']?.toString() ?? '');
          if (lat != null && lon != null) {
            final target = LatLng(lat, lon);
            final display = (first['display_name']?.toString() ?? query)
                .split(',')
                .first
                .trim();
            setState(() {
              _selectedPoint = target;
              _detectedAreaLabel = '$display 📍';
              if (_customAddressController.text.trim().isEmpty) {
                _customAddressController.text = display;
              }
            });
            _mapController.move(target, 16.5);
            return;
          }
        }
      }
    } catch (_) {
      // ننتقل مباشرة للبحث المحلي في تعز عند تعذر الاتصال بالخدمة الخارجية
    }

    if (!mounted) return;

    // ثانياً: البحث المحلي الفوري في مناطق تعز
    final localMatch = _findLocalTaizMatch(query);
    if (localMatch != null) {
      setState(() {
        _selectedPoint = localMatch.point;
        _detectedAreaLabel = '${localMatch.name} 📍';
        if (_customAddressController.text.trim().isEmpty) {
          _customAddressController.text = localMatch.name;
        }
      });
      _mapController.move(localMatch.point, 16.5);
      setState(() => _searchingPlace = false);
      return;
    }

    setState(() => _searchingPlace = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'تعذر الوصول لخدمة البحث الخارجية؛ جرّب اسم منطقة في تعز أو حرّك الخريطة مباشرة.'),
        ),
      );
    }
  }

  Future<void> _showEnableLocationDialog(
      {required bool openAppSettingsMode}) async {
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
              Icon(Icons.location_off_rounded,
                  color: AppConstants.gold, size: 26),
              SizedBox(width: 8),
              Text(
                'يرجى تفعيل الموقع 📍',
                style: TextStyle(
                    color: AppConstants.gold,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            openAppSettingsMode
                ? 'الموقع غير مفعّل أو تم رفض الإذن سابقاً. يرجى تفعيل الموقع والسماح بالوصول من إعدادات الهاتف لتحديد موقعك بدقة.'
                : 'الموقع غير مفعّل حالياً! يرجى تفعيل خدمة الموقع (GPS) لتحديد موقعك بدقة على الخريطة.',
            style: const TextStyle(
                color: Colors.white70, fontSize: 13, height: 1.5),
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
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
              label: const Text('تفعيل الموقع',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

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

    final areaName = _detectedAreaLabel.isNotEmpty
        ? _detectedAreaLabel
        : getTaizAreaName(_selectedPoint!);
    final finalFullAddress =
        addressText.contains(areaName) ? addressText : '$addressText - $areaName';

    Navigator.pop(context, {
      'address': finalFullAddress,
      'latLng': _selectedPoint,
    });
  }

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
        const msg = 'الموقع غير مفعّل! يرجى تفعيل الموقع (GPS) للمتابعة.';
        setState(() {
          _isServiceDisabled = true;
          _error = msg;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
        );
        await _showEnableLocationDialog(openAppSettingsMode: false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          const msg =
              'الموقع غير مفعّل! يرجى السماح بتفعيل الموقع لتحديد عنوانك بدقة.';
          setState(() {
            _error = msg;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
          );
          await _showEnableLocationDialog(openAppSettingsMode: false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        const msg =
            'الموقع غير مفعّل من الإعدادات! اضغط "تفعيل الموقع" لفتحه من الإعدادات.';
        setState(() {
          _isPermissionDeniedForever = true;
          _error = msg;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
        );
        await _showEnableLocationDialog(openAppSettingsMode: true);
        return;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 18),
        );
      } on TimeoutException {
        position = await Geolocator.getLastKnownPosition();
        if (position == null) {
          if (!mounted) return;
          setState(() {
            _error =
                'تأخر التقاط إشارة الـ GPS؛ يمكنك سحب الدبوس على موقعك مباشرة أو المحاولة مجدداً.';
          });
          return;
        }
      }

      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;

      setState(() {
        _selectedPoint = point;
        _detectedAreaLabel = getTaizAreaName(point);
        _error = null;
      });

      _mapController.move(point, 17.5);
      unawaited(_reverseGeocodePoint(point, autoFillIfEmpty: true));
    } catch (error) {
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null && mounted) {
          final fallbackPoint = LatLng(lastKnown.latitude, lastKnown.longitude);
          setState(() {
            _selectedPoint = fallbackPoint;
            _detectedAreaLabel = getTaizAreaName(fallbackPoint);
            _error =
                'تم جلب آخر موقع معروف؛ يمكنك تحريك الدبوس لتعديل الموضع بدقة.';
          });
          _mapController.move(fallbackPoint, 17.0);
          return;
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _error =
              'تعذر جلب الموقع تلقائياً حالياً؛ يمكنك تحريك الدبوس على الخريطة يدوياً.';
        });
      }
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    final center = camera.center;
    final prev = _selectedPoint;
    if (prev == null ||
        (prev.latitude - center.latitude).abs() > 0.00015 ||
        (prev.longitude - center.longitude).abs() > 0.00015) {
      setState(() {
        _selectedPoint = center;
        _detectedAreaLabel = getTaizAreaName(center);
      });
      _geocodeDebounce?.cancel();
      _geocodeDebounce = Timer(const Duration(milliseconds: 600), () {
        unawaited(_reverseGeocodePoint(center, autoFillIfEmpty: false));
      });
    }
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    _customAddressController.dispose();
    _searchController.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cardColor = Color(0xFF1E1E1E);
    const backgroundColor = Color(0xFF121212);
    final currentTileUrl = _tileUrls[_tileUrlIndex];
    final nextTileUrl = _tileUrlIndex + 1 < _tileUrls.length
        ? _tileUrls[_tileUrlIndex + 1]
        : null;

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
              style: TextStyle(
                  color: AppConstants.gold,
                  fontSize: 15,
                  fontWeight: FontWeight.bold),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_forward, color: AppConstants.gold),
              onPressed: _saveAndReturn,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.layers_outlined, color: AppConstants.gold),
                tooltip: 'تبديل مصدر الخريطة',
                onPressed: () {
                  setState(() {
                    _tileUrlIndex = (_tileUrlIndex + 1) % _tileUrls.length;
                    _tileErrorStreak = 0;
                    _tileLayerKey = ValueKey('tile_layer_$_tileUrlIndex');
                  });
                },
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: AppConstants.gold.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _searchPlaceOnMap(),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                              decoration: InputDecoration(
                                hintText: 'ابحث عن حي أو شارع أو معلم...',
                                hintStyle: const TextStyle(color: Colors.grey),
                                isDense: true,
                                filled: true,
                                fillColor: backgroundColor,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                prefixIcon: const Icon(Icons.search,
                                    color: AppConstants.gold, size: 20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConstants.gold,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed:
                                _searchingPlace ? null : _searchPlaceOnMap,
                            child: _searchingPlace
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.black),
                                  )
                                : const Text('بحث',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'أكتب عنوانك التفصيلي بدقة (مطلوب): *',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _customAddressController,
                        focusNode: _addressFocus,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _saveAndReturn(),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'مثال: حي الروضة، بجوار الشارع العام',
                          hintStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: backgroundColor,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          prefixIcon: const Icon(Icons.location_on,
                              color: AppConstants.gold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppConstants.gold,
                          side: const BorderSide(color: AppConstants.gold),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _gettingLocation ? null : _useGps,
                        icon: _gettingLocation
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppConstants.gold),
                              )
                            : const Icon(Icons.my_location),
                        label: const Text(
                            'جلب موقعي الحالي بدقة GPS القصوى 🛰️',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12.0, vertical: 6.0),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: Colors.redAccent.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_disabled,
                            color: Colors.redAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
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
                              'تفعيل الموقع',
                              style: TextStyle(
                                  color: AppConstants.gold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Expanded(
                child: SizedBox(
                  width: double.infinity,
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
                          key: const ValueKey('fast_map_location_view'),
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: widget.initialPoint ?? _taizCenter,
                            initialZoom: 17.0,
                            onPositionChanged: _onMapPositionChanged,
                          ),
                          children: [
                            TileLayer(
                              key: _tileLayerKey,
                              urlTemplate: currentTileUrl,
                              fallbackUrl: nextTileUrl,
                              userAgentPackageName: 'com.fast.taiz',
                              tileProvider: NetworkTileProvider(),
                              maxZoom: 19,
                              errorTileCallback: _handleTileError,
                            ),
                          ],
                        ),
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
                        Positioned(
                          top: 10,
                          left: 16,
                          right: 16,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: AppConstants.gold.withOpacity(0.5)),
                              ),
                              child: Text(
                                _selectedPoint != null
                                    ? '$_detectedAreaLabel • (${_selectedPoint!.latitude.toStringAsFixed(4)}, ${_selectedPoint!.longitude.toStringAsFixed(4)})'
                                    : 'اسحب الخريطة لتحديد الموقع بدقة 🎯',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.amberAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.gold,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _saveAndReturn,
                  child: const Text('تثبيت الموقع والعنوان والعودة ✅',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
