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
  
  LatLng? _selectedLatLng;

  @override
  void dispose() {
    _titleController.dispose();
    _areaController.dispose();
    _detailsController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  // 🛠️ دالة موحدة لإضافة أو تعديل العنوان
  void _showAddressDialog(BuildContext context, AppState appState, Color cardBg, Color textColor, {AddressModel? addressToEdit}) {
    final bool isEditing = addressToEdit != null;

    if (isEditing) {
      _titleController.text = addressToEdit.title;
      _areaController.text = addressToEdit.area;
      _detailsController.text = addressToEdit.details;
      _instructionsController.text = addressToEdit.instructions;
    } else {
      _titleController.text = 'المنزل 🏠';
      _areaController.clear();
      _detailsController.clear();
      _instructionsController.clear();
      _selectedLatLng = null;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: cardBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.amber.withOpacity(0.4)),
            ),
            title: Text(
              isEditing ? 'تعديل العنوان ✏️' : 'إضافة عنوان جديد 📍',
              style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _titleController,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      labelText: 'تسمية العنوان (مثل: منزل هشام المريش)',
                      labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                      filled: true,
                      fillColor: appState.isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 🗺️ زر فتح الخريطة لتحديد الموقع بدقة
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
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _areaController,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      labelText: 'المنطقة أو الحي (مثل: المسبح، ديلوكس)*',
                      labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                      filled: true,
                      fillColor: appState.isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _detailsController,
                    style: TextStyle(color: textColor),
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'التفاصيل والإحداثيات (الشارع، بجوار...)*',
                      labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                      filled: true,
                      fillColor: appState.isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _instructionsController,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      labelText: 'تعليمات للمندوب (اختياري)',
                      labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                      filled: true,
                      fillColor: appState.isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  if (_titleController.text.isNotEmpty && _areaController.text.isNotEmpty) {
                    if (isEditing) {
                      final updatedAddress = AddressModel(
                        id: addressToEdit.id,
                        title: _titleController.text.trim(),
                        area: _areaController.text.trim(),
                        details: _detailsController.text.trim(),
                        instructions: _instructionsController.text.trim(),
                      );
                      appState.removeUserAddress(addressToEdit.id);
                      appState.addUserAddress(updatedAddress);
                      
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم تعديل العنوان بنجاح ✏️')),
                      );
                    } else {
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
                        const SnackBar(content: Text('تم حفظ العنوان بنجاح 📍')),
                      );
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('يرجى كتابة تسمية العنوان والمنطقة على الأقل ⚠️')),
                    );
                  }
                },
                child: Text(isEditing ? 'حفظ التعديلات' : 'حفظ العنوان', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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

    final themeBg = appState.isDarkMode ? const Color(0xFF121212) : const Color(0xFFF0F2F5);
    final cardBg = appState.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = appState.isDarkMode ? Colors.white : Colors.black87;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: themeBg,
        appBar: AppBar(
          backgroundColor: cardBg,
          title: Text('عناويني المحفوظة 📍', style: TextStyle(color: Colors.amber[700], fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: Colors.amber),
        ),
        body: addresses.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_off, size: 60, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text('ليس لديك أي عناوين محفوظة حالياً', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                      onPressed: () => _showAddressDialog(context, appState, cardBg, textColor),
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
                    color: cardBg,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.location_on, color: Colors.amber),
                                  const SizedBox(width: 8),
                                  Text(address.title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                                ],
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: Colors.amber),
                                    tooltip: 'تعديل العنوان',
                                    onPressed: () => _showAddressDialog(context, appState, cardBg, textColor, addressToEdit: address),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    tooltip: 'حذف العنوان',
                                    onPressed: () => appState.removeUserAddress(address.id),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white12),
                          Text('• المنطقة: ${address.area}', style: TextStyle(color: textColor, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text('• التفاصيل: ${address.details}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                          if (address.instructions.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('• تعليمات المندوب: ${address.instructions}', style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
                          ],
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.amber,
                                side: const BorderSide(color: Colors.amber),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () {
                                appState.selectDefaultAddress(address);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('تم اختيار "${address.title}" عنواناً للطلب الحالي 🎯')),
                                );
                              },
                              icon: const Icon(Icons.check_circle_outline, size: 16),
                              label: const Text('تعيين كعنوان افتراضي للطلب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
        floatingActionButton: addresses.isNotEmpty
            ? FloatingActionButton(
                backgroundColor: Colors.amber,
                onPressed: () => _showAddressDialog(context, appState, cardBg, textColor),
                child: const Icon(Icons.add, color: Colors.black),
              )
            : null,
      ),
    );
  }
}
