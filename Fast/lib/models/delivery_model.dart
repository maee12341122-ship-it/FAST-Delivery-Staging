class DeliveryModel {
  final String id;
  final String name;
  final String phone;
  final bool isAvailable;
  final bool isEnabled;
  final String? currentOrderId;
  final int completedToday;

  const DeliveryModel({
    required this.id,
    required this.name,
    required this.phone,
    this.isAvailable = true,
    this.isEnabled = true,
    this.currentOrderId,
    this.completedToday = 0,
  });

  bool get canReceiveOrders => isEnabled && isAvailable && currentOrderId == null;

  DeliveryModel copyWith({
    String? name,
    String? phone,
    bool? isAvailable,
    bool? isEnabled,
    String? currentOrderId,
    bool clearCurrentOrder = false,
    int? completedToday,
  }) {
    return DeliveryModel(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      isAvailable: isAvailable ?? this.isAvailable,
      isEnabled: isEnabled ?? this.isEnabled,
      currentOrderId: clearCurrentOrder ? null : (currentOrderId ?? this.currentOrderId),
      completedToday: completedToday ?? this.completedToday,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'isAvailable': isAvailable,
        'isEnabled': isEnabled,
        'currentOrderId': currentOrderId,
        'completedToday': completedToday,
      };

  factory DeliveryModel.fromJson(Map<String, dynamic> json) => DeliveryModel(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        isAvailable: json['isAvailable'] as bool? ?? false,
        isEnabled: json['isEnabled'] as bool? ?? true,
        currentOrderId: json['currentOrderId'] as String?,
        completedToday: (json['completedToday'] as num?)?.toInt() ?? 0,
      );
}
