import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order_model.dart';
import '../services/notification_service.dart';

class OrderController extends GetxController {
  final SupabaseClient _supabase = Supabase.instance.client;

  var isLoading = false.obs;
  var ordersList = <OrderModel>[].obs;
  var currentOrder = Rxn<OrderModel>();

  @override
  void onInit() {
    super.onInit();
  }

  Future<bool> createNewOrder(OrderModel newOrder) async {
    try {
      isLoading.value = true;

      final Map<String, dynamic> orderData = {
        'customer_name': newOrder.customerName,
        'phone': newOrder.customerPhone,
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
    try {
      isLoading.value = true;
      final response = await _supabase
          .from('orders')
          .select('*, order_items(*)')
          .eq('phone', phone)
          .order('created_at', ascending: false);

      var list = response as List;
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
      final updatedRow = await _supabase
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId)
          .select('id, phone, assigned_courier')
          .maybeSingle();

      if (updatedRow != null) {
        final customerPhone = updatedRow['phone']?.toString().trim() ?? '';
        if (customerPhone.isNotEmpty) {
          final customerRow = await _supabase
              .from('customers')
              .select('onesignal_player_id')
              .eq('phone', customerPhone)
              .maybeSingle();
          final playerId =
              customerRow?['onesignal_player_id']?.toString().trim() ?? '';
          if (playerId.isNotEmpty) {
            await NotificationService.sendNotificationToUser(
              targetPlayerId: playerId,
              title: 'تحديث حالة الطلب #$orderId 🔔',
              body: 'تم تحديث حالة طلبك إلى: ${OrderStatuses.label(newStatus)}',
              orderId: orderId,
              eventType: 'order_status_updated',
              additionalData: {
                'order_id': orderId,
                'status': newStatus,
              },
            );
          }
        }
      }

      Get.snackbar('تحديث',
          'تم تغيير حالة الطلب إلى ${OrderStatuses.label(newStatus)}',
          snackPosition: SnackPosition.BOTTOM);

      fetchCustomerOrders(currentOrder.value?.customerPhone ?? '');
    } catch (e) {
      Get.snackbar('خطأ', 'فشل تحديث الحالة: $e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }
}
