import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // 👈 استيراد سوبابيس للتحقق من الرقم
import '../../providers/app_state.dart';
import '../home_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({Key? key}) : super(key: key);

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressDescriptionController = TextEditingController();
  final _paymentAccountController = TextEditingController();

  // 👈 متغير لتخزين طريقة الدفع المختارة (نقدي افتراضياً)
  String _selectedPaymentMethod = 'cash'; 

  // إحداثيات افتراضية لمدينة تعز (مركز المدينة)
  LatLng _selectedLocation = const LatLng(13.5779, 44.0219);
  GoogleMapController? _mapController;
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.userProfile != null) {
      _nameController.text = appState.userProfile!['name'] ?? '';
      _phoneController.text = appState.userProfile!['phone'] ?? '';
      _addressDescriptionController.text = appState.userProfile!['address'] ?? '';
    }
    // طلب أذونات الموقع وفحصها فور فتح شاشة إتمام الطلب
    _determinePosition();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressDescriptionController.dispose();
    _paymentAccountController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // --- دالة طلب أذونات الموقع وجلب الإحداثيات الحالية ---
  Future<void> _determinePosition() async {
    setState(() => _isLoadingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('الرجاء تفعيل خدمة الموقع (GPS) في جهازك')),
          );
        }
        setState(() => _isLoadingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم رفض إذن الوصول إلى الموقع')),
            );
          }
          setState(() => _isLoadingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('إذن الموقع مرفوض بشكل دائم، يرجى تفعيله من الإعدادات')),
          );
        }
        setState(() => _isLoadingLocation = false);
        return;
      }

      // جلب الموقع الحالي بدقة عالية
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _selectedLocation = LatLng(position.latitude, position.longitude);
          _isLoadingLocation = false;
        });

        // تحريك الكاميرا بسلاسة إلى موقع العميل الحالي
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _selectedLocation, zoom: 16.0),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
      debugPrint('❌ خطأ في تحديد الموقع: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isDark = appState.isDarkMode;
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[100],
        appBar: AppBar(
          backgroundColor: cardBg,
          title: const Text('تأكيد الطلب وتحديد الموقع 🚀', style: TextStyle(color: Colors.amber, fontSize: 16)),
          iconTheme: const IconThemeData(color: Colors.amber),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // حقول البيانات الشخصية
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('بيانات المستلم', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      labelText: 'الاسم الكامل',
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF121212) : Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      labelText: 'رقم الهاتف',
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF121212) : Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _addressDescriptionController,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      labelText: 'تفاصيل العنوان (مثلاً: شارع جمال، بجوار...)',
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF121212) : Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // قسم اختيار طريقة الدفع
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('طريقة الدفع 💳', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _selectedPaymentMethod,
                    dropdownColor: cardBg,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark ? const Color(0xFF121212) : Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('💵 الدفع نقداً عند الاستلام فقط')),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedPaymentMethod = val ?? 'cash';
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // خريطة جوجل الحقيقية التفاعلية لتحديد موقع التوصيل
            const Text('حدد موقعك بدقة على الخريطة 📍', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Container(
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber, width: 1.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _selectedLocation,
                        zoom: 15.0,
                      ),
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: true,
                      onMapCreated: (controller) {
                        _mapController = controller;
                      },
                      onTap: (point) {
                        setState(() {
                          _selectedLocation = point;
                        });
                      },
                      markers: {
                        Marker(
                          markerId: const MarkerId('delivery_location'),
                          position: _selectedLocation,
                          infoWindow: const InfoWindow(title: 'موقع التوصيل المحدد'),
                        ),
                      },
                    ),
                    if (_isLoadingLocation)
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.amber),
                        ),
                      ),
                    Positioned(
                      bottom: 10,
                      left: 10,
                      child: FloatingActionButton.small(
                        backgroundColor: Colors.amber,
                        onPressed: _determinePosition,
                        child: const Icon(Icons.my_location, color: Colors.black),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ملخص السلة
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('إجمالي المنتجات:', style: TextStyle(color: textColor, fontSize: 15)),
                  Text('${appState.totalAmount} ر.ي', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // زر إرسال الطلب النهائي مع التحقق من وجود الرقم في قاعدة البيانات
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final phone = _phoneController.text.trim();
                if (_nameController.text.isEmpty || phone.isEmpty || _addressDescriptionController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('الرجاء إكمال جميع بيانات الاسم ورقم الهاتف والعنوان')),
                  );
                  return;
                }

                setState(() => _isLoadingLocation = true);

                try {
                  // 1. فحص ما إذا كان رقم الهاتف مسجلاً في جدول customers في Supabase
                  final customerCheck = await Supabase.instance.client
                      .from('customers')
                      .select()
                      .eq('phone', phone)
                      .maybeSingle();

                  if (customerCheck == null) {
                    setState(() => _isLoadingLocation = false);
                    
                    // تنبيه المستخدم بأن الرقم غير مسجل وتوجيهه للواتساب
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('هذا الرقم غير مسجل في قاعدة البيانات. جاري تحويلك للواتساب للتسجيل...')),
                      );
                    }

                    // فتح واتساب عبر الدالة الموجودة في AppState
                    await appState.openFastWhatsApp(
                      message: 'مرحباً، أريد إنشاء حساب وتسجيل طلب في تطبيق FAST. رقم الهاتف: $phone، الاسم: ${_nameController.text}'
                    );
                    return;
                  }

                  // 2. إذا كان الرقم مسجلاً، نتابع إتمام الطلب بشكل طبيعي
                  final fullAddress = '${_addressDescriptionController.text} (الإحداثيات: ${_selectedLocation.latitude.toStringAsFixed(4)}, ${_selectedLocation.longitude.toStringAsFixed(4)})';
                  final itemsDesc = appState.cartItems.map((item) => '${item.name} (x${item.quantity})').join(', ');

                  await appState.saveUserProfileDetails(_nameController.text, fullAddress);
                  
                  await appState.createOrder(
                    customerName: _nameController.text,
                    phone: phone,
                    address: fullAddress,
                    itemsDesc: itemsDesc,
                    productsTotal: appState.totalAmount,
                    paymentMethod: _selectedPaymentMethod,
                    paymentAccount: 'نقدي',
                  );

                  setState(() => _isLoadingLocation = false);

                  if (context.mounted) {
                    final trackingCode = appState.lastOrderTrackingCode ?? '—';
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const HomeScreen()),
                      (route) => false,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم استلام الطلب بنجاح. رمز المتابعة: $trackingCode')),
                    );
                  }
                } catch (e) {
                  setState(() => _isLoadingLocation = false);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تعذر إرسال الطلب: $e')),
                    );
                  }
                }
              },
              child: const Text('تأكيد وإرسال الطلب للمشرف 🚀', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
