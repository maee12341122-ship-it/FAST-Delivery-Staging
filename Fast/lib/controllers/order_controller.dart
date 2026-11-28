import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order_model.dart';
import '../services/notification_service.dart';

class OrderController extends GetxController {
  final SupabaseClient _supabase = Supabase.instance.client;

  var isLoading = false.obs;
  var ordersList = <OrderModel>[].obs;
  var currentOrder = Rxn<OrderModel>();

  String _normalizePhone(String phone) {
    var clean = phone.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (clean.startsWith('+967')) {
      clean = clean.substring(4);
    } else if (clean.startsWith('00967')) {
      clean = clean.substring(5);
    } else if (clean.startsWith('967') && clean.length > 9) {
      clean = clean.substring(3);
    }
    if (clean.startsWith('0') && clean.length > 9) {
      clean = clean.substring(1);
    }
    return clean;
  }

  List<String> _phoneVariants(String phone) {
    final clean = _normalizePhone(phone);
    if (clean.isEmpty) return const [];
    return <String>{
      clean,
      '0$clean',
      '967$clean',
      '+967$clean',
    }.toList();
  }

  Future<bool> createNewOrder(OrderModel newOrder) async {
    try {
      isLoading.value = true;

      final cleanPhone = _normalizePhone(newOrder.customerPhone);
      final Map<String, dynamic> orderData = {
        'customer_name': newOrder.customerName,
        'phone': cleanPhone.isNotEmpty ? cleanPhone : newOrder.customerPhone,
        'address':
            '${newOrder.address.area} - ${newOrder.address.details} (${newOrder.address.title})',
        'items_description': newOrder.itemsDescription,
        'products_total': newOrder.subtotal,
        'delivery_fee': newOrder.deliveryFee,
        'total_price': newOrder.total,
        'status': newOrder.status,
        'assigned_courier': newOrder.assignedCourier,
        'is_fee_sent': newOrder.isFeeSent,
        'notes': newOrder.notes,
      };

      final response = await _supabase
          .from('orders')
          .insert(orderData)
          .select()
          .single();

      final int generatedOrderId = response['id'];

      if (newOrder.items.isNotEmpty) {
        final List<Map<String, dynamic>> itemsData = newOrder.items
            .map((item) => {
                  'order_id': generatedOrderId,
                  'product_name': item.name,
                  'price': item.price,
                  'quantity': item.quantity,
                  'total_price': item.totalPrice,
                })
            .toList();

        await _supabase.from('order_items').insert(itemsData);
      }

      Get.snackbar('نجاح', 'تم إرسال طلبك بنجاح',
          snackPosition: SnackPosition.BOTTOM);
      return true;
    } catch (e) {
      Get.snackbar('خطأ', 'فشل إرسال الطلب: $e',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> fetchCustomerOrders(String phone) async {
    final variants = _phoneVariants(phone);
    if (variants.isEmpty) return;

    try {
      isLoading.value = true;
      final response = await _supabase
          .from('orders')
          .select('*, order_items(*)')
          .inFilter('phone', variants)
          .order('created_at', ascending: false);

      final list = response as List;
      ordersList.value = list.map((json) => OrderModel.fromJson(json)).toList();
    } catch (e) {
      Get.snackbar('خطأ', 'تعذر جلب الطلبات: $e',
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    try {
      final parsedId = int.tryParse(orderId.trim()) ?? orderId.trim();
      final updatedRow = await _supabase
          .from('orders')
          .update({
            'status': newStatus,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', parsedId)
          .select('id, phone, assigned_courier')
          .maybeSingle();

      if (updatedRow != null) {
        final customerPhone = updatedRow['phone']?.toString().trim() ?? '';
        final variants = _phoneVariants(customerPhone);
        if (variants.isNotEmpty) {
          final customerRow = await _supabase
              .from('customers')
              .select('fcm_token')
              .inFilter('phone', variants)
              .not('fcm_token', 'is', null)
              .limit(1)
              .maybeSingle();
          final fcmToken =
              customerRow?['fcm_token']?.toString().trim() ?? '';
          if (fcmToken.isNotEmpty) {
            await NotificationService.sendNotificationToUser(
              targetPlayerId: fcmToken,
              title: 'تحديث حالة الطلب #$orderId 🔔',
              body: 'تم تحديث حالة طلبك إلى: ${OrderStatuses.label(newStatus)}',
              orderId: orderId,
              eventType: 'order_status_updated',
              additionalData: {
                'order_id': orderId.toString(),
                'status': newStatus,
              },
            );
          }
        }
      }

      Get.snackbar('تحديث',
          'تم تغيير حالة الطلب إلى ${OrderStatuses.label(newStatus)}',
          snackPosition: SnackPosition.BOTTOM);

      final currentPhone = currentOrder.value?.customerPhone ?? '';
      if (currentPhone.trim().isNotEmpty) {
        await fetchCustomerOrders(currentPhone);
      }
    } catch (e) {
      Get.snackbar('خطأ', 'فشل تحديث الحالة: $e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }
}
