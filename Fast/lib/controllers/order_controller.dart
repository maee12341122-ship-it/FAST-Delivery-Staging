import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order_model.dart';

class OrderController extends GetxController {
  final SupabaseClient _supabase = Supabase.instance.client;

  // المتغيرات التفاعلية (Reactive)
  var isLoading = false.obs;
  var ordersList = <OrderModel>[].obs;
  var currentOrder = Rxn<OrderModel>();

  @override
  onInit() {
    super.onInit();
    // يمكنك جلب الطلبات أو تفعيل الاستماع الفوري هنا
  }

  /// 1. إرسال طلب جديد إلى Supabase
  Future<bool> createNewOrder(OrderModel newOrder) async {
    try {
      isLoading.value = true;
      
      // تجهيز بيانات الطلب لترسل إلى جدول orders
      final Map<String, dynamic> orderData = {
        'customer_name': newOrder.customerName,
        'phone': newOrder.customerPhone,
        'address': '${newOrder.address.area} - ${newOrder.address.details} (${newOrder.address.title})',
        'items_description': newOrder.itemsDescription,
        'products_total': newOrder.subtotal,
        'delivery_fee': newOrder.deliveryFee,
        'total_price': newOrder.total,
        'status': newOrder.status,
        'assigned_courier': newOrder.assignedCourier,
        'is_fee_sent': newOrder.isFeeSent,
        'notes': newOrder.notes,
      };

      // 1. إدخال الطلب الأساسي وجلب الـ ID المتولد
      final response = await _supabase
          .from('orders')
          .insert(orderData)
          .select()
          .single();

      final int generatedOrderId = response['id'];

      // 2. إذا كانت هناك أصناف مرتبطة بالطلب، قم بإدخالها في جدول order_items
      if (newOrder.items.isNotEmpty) {
        final List> itemsData = newOrder.items.map((item) => {
          'order_id': generatedOrderId,
          'product_name': item.name,
          'price': item.price,
          'quantity': item.quantity,
          'total_price': item.totalPrice,
        }).toList();

        await _supabase.from('order_items').insert(itemsData);
      }

      Get.snackbar('نجاح', 'تم إرسال طلبك بنجاح', snackPosition: SnackPosition.BOTTOM);
      return true;
    } catch (e) {
      Get.snackbar('خطأ', 'فشل إرسال الطلب: $e', snackPosition: SnackPosition.BOTTOM);
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /// 2. جلب طلبات العميل بناءً على رقم الهواتف
  Future<void> fetchCustomerOrders(String phone) async {
    try {
      isLoading.value = true;
      final response = await _supabase
          .from('orders')
          .select('*, order_items(*)') // جلب الطلب مع عناصره عبر الـ Join
          .eq('phone', phone)
          .order('created_at', ascending: false);

      var list = response as List;
      ordersList.value = list.map((json) => OrderModel.fromJson(json)).toList();
    } catch (e) {
      Get.snackbar('خطأ', 'تعذر جلب الطلبات: $e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
    }
  }

  /// 3. تحديث حالة الطلب (مثلاً للمندوب أو المسؤول)
  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    try {
      await _supabase
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId);

      Get.snackbar('تحديث', 'تم تغيير حالة الطلب إلى ${OrderStatuses.label(newStatus)}', 
          snackPosition: SnackPosition.BOTTOM);
          
      // تحديث القائمة المحلية إن وجدت
      fetchCustomerOrders(currentOrder.value?.customerPhone ?? '');
    } catch (e) {
      Get.snackbar('خطأ', 'فشل تحديث الحالة: $e', snackPosition: SnackPosition.BOTTOM);
    }
  }
}
