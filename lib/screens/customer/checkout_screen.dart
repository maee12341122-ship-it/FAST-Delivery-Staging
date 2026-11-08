import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  String _selectedPaymentMethod = 'cash'; // cash

  // إحداثيات افتراضية لمدينة تعز (مركز المدينة)
  LatLng _selectedLocation = const LatLng(13.5779, 44.0219);
  final MapController _mapController = MapController();
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
    _determinePosition();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressDescriptionController.dispose();
    _paymentAccountController.dispose();
    super.dispose();
  }

  Future<void> _determinePosition() async {
    setState(() => _isLoadingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _isLoadingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _isLoadingLocation = false);
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _selectedLocation = LatLng(position.latitude, position.longitude);
          _isLoadingLocation = false;
        });
        _mapController.move(_selectedLocation, 16.0);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  // 📍 نافذة اختيار العنوان من العناوين المحفوظة أو إضافة عنوان جديد
  void _showAddressBookBottomSheet(BuildContext context, Color cardBg, Color textColor) {
    final userId = Supabase.instance.client.auth.currentUser?.id;

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('عناويني المحفوظة 📍', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Colors.amber),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('إضافة عنوان جديد'),
                      onPressed: () {
                        Navigator.pop(context);
                        _showAddNewAddressDialog(context);
                      },
                    ),
                  ],
                ),
                const Divider(color: Colors.white24),
                SizedBox(
                  height: 250,
                  child: FutureBuilder<List>>(
                    future: Supabase.instance.client
                        .from('user_addresses')
                        .select()
                        .eq('user_id', userId ?? ''),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Colors.amber));
                      }
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(
                          child: Text('لا توجد عناوين محفوظة. أضف عنوانك الأول!', style: TextStyle(color: Colors.grey)),
                        );
                      }

                      final addresses = snapshot.data!;
                      return ListView.builder(
                        itemCount: addresses.length,
                        itemBuilder: (context, index) {
                          final addr = addresses[index];
                          return Card(
                            color: const Color(0xFF2A2A2A),
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                              leading: const Icon(Icons.location_on, color: Colors.amber),
                              title: Text(addr['title'] ?? 'عنوان', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              subtitle: Text(addr['address_text'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              trailing: const Icon(Icons.check_circle_outline, color: Colors.amber),
                              onTap: () {
                                setState(() {
                                  _addressDescriptionController.text = "${addr['title']}: ${addr['address_text']}";
                                });
                                Navigator.pop(context);
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // نافذة منبثقة لإضافة عنوان جديد مباشرة وحفظه في سوبابيس
  void _showAddNewAddressDialog(BuildContext context) {
    final titleController = TextEditingController();
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text('إضافة عنوان توصيل جديد 🏠', style: TextStyle(color: Colors.amber, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'تسمية العنوان (مثل: المنزل، العمل)', labelStyle: TextStyle(color: Colors.grey)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: textController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'تفاصيل العنوان (الشارع، المعلم القريب)', labelStyle: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                onPressed: () async {
                  if (titleController.text.isNotEmpty && textController.text.isNotEmpty) {
                    final userId = Supabase.instance.client.auth.currentUser?.id;
                    await Supabase.instance.client.from('user_addresses').insert({
                      'user_id': userId,
                      'title': titleController.text.trim(),
                      'address_text': textController.text.trim(),
                    });
                    if (context.mounted) {
                      Navigator.pop(context);
                      _addressDescriptionController.text = "${titleController.text}: ${textController.text}";
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة وحفظ العنوان بنجاح ✅')));
                    }
                  }
                },
                child: const Text('حفظ واختيار', style: TextStyle(color: Colors.black)),
              ),
            ],
          ),
        );
      },
    );
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('بيانات المستلم', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
                      // 📍 زر اختيار من العناوين المحفوظة
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Colors.amber),
                        icon: const Icon(Icons.bookmarks, size: 16),
                        label: const Text('عناويني المحفوظة', style: TextStyle(fontSize: 12)),
                        onPressed: () => _showAddressBookBottomSheet(context, cardBg, textColor),
                      ),
                    ],
                  ),
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
                      labelText: 'تفاصيل العنوان (شارع، معلم قريب...)',
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

            // طريقة الدفع
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
                      DropdownMenuItem(value: 'cash', child: Text('💵 الدفع نقداً عند الاستلام')),
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

            // الخريطة التفاعلية
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
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _selectedLocation,
                        initialZoom: 15.0,
                        onTap: (tapPosition, point) {
                          setState(() {
                            _selectedLocation = point;
                          });
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                          subdomains: const ['a', 'b', 'c', 'd'],
                          userAgentPackageName: 'com.fast.taiz',
                          tileProvider: NetworkTileProvider(),
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _selectedLocation,
                              width: 80,
                              height: 80,
                              child: const Icon(Icons.location_pin, color: Colors.red, size: 45),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (_isLoadingLocation)
                      Container(
                        color: Colors.black54,
                        child: const Center(child: CircularProgressIndicator(color: Colors.amber)),
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

            // زر إرسال الطلب النهائي
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (_nameController.text.isEmpty || _phoneController.text.isEmpty || _addressDescriptionController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('الرجاء إكمال جميع بيانات الاسم ورقم الهاتف والعنوان')),
                  );
                  return;
                }

                final fullAddress = '${_addressDescriptionController.text} (الإحداثيات: ${_selectedLocation.latitude.toStringAsFixed(4)}, ${_selectedLocation.longitude.toStringAsFixed(4)})';
                final itemsDesc = appState.cartItems.map((item) => '${item.name} (x${item.quantity})').join(', ');

                await appState.saveUserProfileDetails(_nameController.text, fullAddress);
                try {
                  await appState.createOrder(
                    customerName: _nameController.text,
                    phone: _phoneController.text,
                    address: fullAddress,
                    itemsDesc: itemsDesc,
                    productsTotal: appState.totalAmount,
                    paymentMethod: _selectedPaymentMethod,
                    paymentAccount: 'نقدي',
                  );
                  if (context.mounted) {
                    final trackingCode = appState.lastOrderTrackingCode ?? '—';
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const HomeScreen()),
                      (route) => false,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم استلام الطلب. رمز المتابعة: $trackingCode')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إرسال الطلب: $e')));
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
