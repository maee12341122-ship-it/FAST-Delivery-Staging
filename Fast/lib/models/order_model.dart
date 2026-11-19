import 'address_model.dart';
import 'cart_item_model.dart';

class OrderModel {
  final String id;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final AddressModel address;
  final List<CartItemModel> items;
  final int subtotal;
  final int deliveryFee;
  final int discount;
  final int total;
  final String paymentMethod;
  final String paymentStatus;
  final String paymentAccount;
  final String status;
  final String? deliveryManId;
  final String assignedCourier;
  final String itemsDescription;
  final String notes;
  final bool isFeeSent;
  final DateTime createdAt;
  final DateTime updatedAt;

  const OrderModel({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.address,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.discount,
    required this.total,
    required this.paymentMethod,
    required this.paymentStatus,
    this.paymentAccount = '',
    required this.status,
    this.deliveryManId,
    this.assignedCourier = 'لم يتم التعيين',
    this.itemsDescription = '',
    this.notes = '',
    this.isFeeSent = false,
    required this.createdAt,
    required this.updatedAt,
  });

  OrderModel copyWith({
    String? status,
    String? paymentStatus,
    String? deliveryManId,
    String? assignedCourier,
    bool? isFeeSent,
    DateTime? updatedAt,
  }) {
    return OrderModel(
      id: id,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      address: address,
      items: items,
      subtotal: subtotal,
      deliveryFee: deliveryFee,
      discount: discount,
      total: total,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentAccount: paymentAccount,
      status: status ?? this.status,
      deliveryManId: deliveryManId ?? this.deliveryManId,
      assignedCourier: assignedCourier ?? this.assignedCourier,
      itemsDescription: itemsDescription,
      notes: notes,
      isFeeSent: isFeeSent ?? this.isFeeSent,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer_name': customerName,
        'phone': customerPhone,
        // تحويل AddressModel إلى نص متناسق ليتم حفظه في عمود text بجدول orders
        'address': '${address.area} - ${address.details} (${address.title})',
        'items_description': itemsDescription,
        'products_total': subtotal,
        'delivery_fee': deliveryFee,
        'total_price': total,
        'payment_method': paymentMethod,
        'payment_account': paymentAccount,
        'assigned_courier': assignedCourier,
        'status': status,
        'notes': notes,
        'is_fee_sent': isFeeSent,
      };

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    // دعم قراءة العناصر سواء جاءت تحت مفتاح 'items' أو 'order_items' (عبر الـ Join)
    final rawItems = json['items'] ?? json['order_items'];
    List<CartItemModel> parsedItems = [];
    if (rawItems is List) {
      parsedItems = rawItems
          .where((i) => i != null)
          .map((i) => CartItemModel.fromMap(Map<String, dynamic>.from(i)))
          .toList();
    }

    return OrderModel(
      id: json['id']?.toString() ?? '',
      customerId: json['customer_id']?.toString() ??
          json['customerId']?.toString() ??
          '',
      customerName: json['customer_name']?.toString() ??
          json['customerName']?.toString() ??
          'بدون اسم',
      customerPhone: json['phone']?.toString() ??
          json['customerPhone']?.toString() ??
          '',
      // معالجة العنوان في حال كان مخزناً كنص عادي في قاعدة البيانات أو كـ Map
      address: json['address'] is Map
          ? AddressModel.fromJson(Map<String, dynamic>.from(json['address']))
          : AddressModel(
              id: 'legacy-${json['id'] ?? ''}',
              title: 'العنوان',
              area: json['address']?.toString() ?? 'تعز',
              details: '',
            ),
      items: parsedItems,
      // استخدام double.tryParse ثم .toInt() لتفادي مشكلة الأرقام العشرية من قاعدة البيانات (مثل 7000.0)
      subtotal: (double.tryParse(json['products_total']?.toString() ??
                  json['subtotal']?.toString() ??
                  '0') ??
              0)
          .toInt(),
      deliveryFee: (double.tryParse(json['delivery_fee']?.toString() ??
                  json['deliveryFee']?.toString() ??
                  '0') ??
              0)
          .toInt(),
      discount: (double.tryParse(json['discount']?.toString() ?? '0') ?? 0)
          .toInt(),
      total: (double.tryParse(json['total_price']?.toString() ??
                  json['total']?.toString() ??
                  '0') ??
              0)
          .toInt(),
      paymentMethod: json['payment_method']?.toString() ??
          json['paymentMethod']?.toString() ??
          'cash',
      paymentStatus: json['payment_status']?.toString() ??
          json['paymentStatus']?.toString() ??
          'unpaid',
      paymentAccount: json['payment_account']?.toString() ?? '',
      status: json['status']?.toString() ?? 'waitingForPricing',
      deliveryManId: json['delivery_man_id']?.toString() ??
          json['deliveryManId']?.toString(),
      assignedCourier: json['assigned_courier']?.toString() ?? 'لم يتم التعيين',
      itemsDescription: json['items_description']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      isFeeSent: json['is_fee_sent'] == true || json['isFeeSent'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ??
              json['createdAt']?.toString() ??
              '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ??
              json['updatedAt']?.toString() ??
              '') ??
          DateTime.now(),
    );
  }
}

class OrderStatuses {
  static const pending = 'pending';
  static const accepted = 'accepted';
  static const preparing = 'preparing';
  static const ready = 'ready';
  static const assigned = 'assigned';
  static const waitingForPricing = 'waitingForPricing';
  static const pricingSentToCustomer = 'pricingSentToCustomer';
  static const waitingCourierApproval = 'waitingCourierApproval';
  static const acceptedByCourier = 'acceptedByCourier';
  static const onTheWay = 'onTheWay';
  static const arrivedToCustomer = 'arrivedToCustomer';
  static const arrived = 'arrived';
  static const delivered = 'delivered';
  static const cancelled = 'cancelled';

  static String label(String status) {
    const labels = <String, String>{
      pending: 'قيد الانتظار',
      accepted: 'تم القبول',
      preparing: 'قيد التجهيز',
      ready: 'جاهز للاستلام',
      assigned: 'تم الإسناد',
      waitingForPricing: 'بانتظار التسعير',
      pricingSentToCustomer: 'بانتظار موافقة العميل',
      waitingCourierApproval: 'بانتظار موافقة المندوب',
      acceptedByCourier: 'قبل المندوب الطلب',
      onTheWay: 'في الطريق',
      arrivedToCustomer: 'وصل للموقع',
      arrived: 'وصل للموقع',
      delivered: 'تم التسليم',
      cancelled: 'ملغي',
    };
    return labels[status] ?? status;
  }
}
