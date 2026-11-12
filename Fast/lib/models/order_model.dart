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
    required this.createdAt,
    required this.updatedAt,
  });

  OrderModel copyWith({String? status, String? paymentStatus, String? deliveryManId, String? assignedCourier, DateTime? updatedAt}) {
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
      notes: notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'customer_name': customerName,
    'phone': customerPhone,
    'address': address is String ? address : address.toString(),
    'items_description': itemsDescription,
    'products_total': subtotal,
    'delivery_fee': deliveryFee,
    'total_price': total,
    'assigned_courier': assignedCourier,
    'status': status,
    'notes': notes,
  };

  factory OrderModel.fromJson(Map<String, dynamic> json) => OrderModel(
    id: json['id']?.toString() ?? '',
    customerId: json['customer_id']?.toString() ?? json['customerId']?.toString() ?? '',
    customerName: json['customer_name']?.toString() ?? json['customerName']?.toString() ?? 'بدون اسم',
    customerPhone: json['phone']?.toString() ?? json['customerPhone']?.toString() ?? '',
    address: json['address'] is Map
        ? AddressModel.fromJson(Map<String, dynamic>.from(json['address']))
        : AddressModel(id: 'legacy-${json['id'] ?? ''}', title: 'العنوان', area: json['address']?.toString() ?? 'تعز', details: ''),
    items: (json['items'] is List)
        ? (json['items'] as List).whereType<Map<String, dynamic>>().map(CartItemModel.fromMap).toList()
        : [],
    subtotal: int.tryParse(json['products_total']?.toString() ?? json['subtotal']?.toString() ?? '0') ?? 0,
    deliveryFee: int.tryParse(json['delivery_fee']?.toString() ?? json['deliveryFee']?.toString() ?? '0') ?? 0,
    discount: int.tryParse(json['discount']?.toString() ?? '0') ?? 0,
    total: int.tryParse(json['total_price']?.toString() ?? json['total']?.toString() ?? '0') ?? 0,
    paymentMethod: json['payment_method']?.toString() ?? json['paymentMethod']?.toString() ?? 'cash',
    paymentStatus: json['payment_status']?.toString() ?? json['paymentStatus']?.toString() ?? 'unpaid',
    paymentAccount: json['payment_account']?.toString() ?? '',
    status: json['status']?.toString() ?? 'waitingForPricing',
    deliveryManId: json['delivery_man_id']?.toString() ?? json['deliveryManId']?.toString(),
    assignedCourier: json['assigned_courier']?.toString() ?? 'لم يتم التعيين',
    itemsDescription: json['items_description']?.toString() ?? '',
    notes: json['notes']?.toString() ?? '',
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? json['createdAt']?.toString() ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
  );
}
class OrderStatuses {
  static const pending = 'pending';
  static const accepted = 'accepted';
  static const preparing = 'preparing';
  static const ready = 'ready';
  static const assigned = 'assigned';
  static const delivered = 'delivered';
  static const cancelled = 'cancelled';

  static String label(String status) {
    const labels = <String, String>{
      pending: 'قيد الانتظار', accepted: 'تم القبول', preparing: 'قيد التجهيز',
      ready: 'جاهز للاستلام', assigned: 'تم الإسناد', delivered: 'تم التسليم', cancelled: 'ملغي',
    };
    return labels[status] ?? status;
  }
}
