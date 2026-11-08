import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/app_state.dart';
import '../../models/address_model.dart';
import 'map_location_screen.dart'; // 🗺️ استيراد شاشة الخريطة

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({Key? key}) : super(key: key);

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  final _titleController = TextEditingController(text: 'المنزل 🏠');
  final _areaController = TextEditingController();
  final _detailsController = TextEditingController();
  final _instructionsController = TextEditingController();
  
  // حفظ الإحداثيات إذا أردت استخدامها لاحقاً مع المندوب
  LatLng? _selectedLatLng;

  @override
  void dispose() {
    _titleController.dispose();
    _areaController.dispose();
    _detailsController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  void _showAddAddressDialog(BuildContext context, AppState appState) {
    _titleController.text = 'المنزل 🏠';
    _areaController.clear();
    _detailsController.clear();
    _instructionsController.clear();
    _selectedLatLng = null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('إضافة عنوان جديد 📍', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'تسمية العنوان (مثل: البيت، العمل، بيت الأهل)',
                      labelStyle: TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Color(0xFF121212),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 🗺️ زر فتح الخريطة لتحديد الموقع بدقة وجلب العنوان تلقائياً
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.amber,
                      side: const BorderSide(color: Colors.amber),
                      minimumSize: const Size(double.infinity, 45),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const MapLocationScreen()),
                      );
                      if (result != null && result is Map) {
                        setDialogState(() {
                          _detailsController.text = result['address'] ?? '';
                          _selectedLatLng = result['latLng'];
                        });
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تم تحديد الموقع والعنوان من الخريطة بنجاح ✅')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.map, color: Colors.amber),
                    label: Text(
                      _detailsController.text.isEmpty ? 'تحديد الموقع من الخريطة والـ GPS 🗺️' : 'تحديث الموقع من الخريطة 📌',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _areaController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'المنطقة أو الحي (مثل: المسبح، الدحي، العريش)',
                      labelStyle: TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Color(0xFF121212),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _detailsController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'التفاصيل (الشارع، بجوار...)',
                      labelStyle: TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Color(0xFF121212),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _instructionsController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'تعليمات للمندوب (اختياري)',
                      labelStyle: TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Color(0xFF121212),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                onPressed: () {
                  if (_titleController.text.isNotEmpty && _areaController.text.isNotEmpty) {
                    final newAddress = AddressModel(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      title: _titleController.text.trim(),
                      area: _areaController.text.trim(),
                      details: _detailsController.text.trim(),
                      instructions: _instructionsController.text.trim(),
                    );
                    
                    appState.addUserAddress(newAddress);
                    Navigator.pop(context);
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تمت حفظ العنوان بنجاح 📍')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('يرجى كتابة تسمية العنوان والمنطقة على الأقل ⚠️')),
                    );
                  }
                },
                child: const Text('حفظ العنوان', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final addresses = appState.userAddresses;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('عناويني المحفوظة 📍', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: Colors.amber),
        ),
        body: addresses.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_off, size: 60, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text('ليس لديك أي عناوين محفوظة حالياً', style: TextStyle(color: Colors.grey, fontSize: 15)),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                      onPressed: () => _showAddAddressDialog(context, appState),
                      icon: const Icon(Icons.add, color: Colors.black),
                      label: const Text('إضافة عنوان جديد', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: addresses.length,
                itemBuilder: (context, index) {
                  final address = addresses[index];
                  return Card(
                    color: const Color(0xFF1E1E1E),
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.location_on, color: Colors.amber),
                      title: Text(address.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text('${address.area} - ${address.details}\nتعليمات: ${address.instructions.isNotEmpty ? address.instructions : "لا توجد"}', style: constTextStyle(color: Colors.grey, fontSize: 13)),
                      isThreeLine: true,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => appState.removeUserAddress(address.id),
                      ),
                      onTap: () {
                        appState.selectDefaultAddress(address);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('تم اختيار "${address.title}" عنواناً للطلب الحالي 🎯')),
                        );
                      },
                    ),
                  );
                },
              ),
        floatingActionButton: addresses.isNotEmpty
            ? FloatingActionButton(
                backgroundColor: Colors.amber,
                onPressed: () => _showAddAddressDialog(context, appState),
                child: const Icon(Icons.add, color: Colors.black),
              ),
            : null,
      ),
    );
  }
}
