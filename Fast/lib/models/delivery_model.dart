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

  bool get canReceiveOrders =>
      isEnabled && isAvailable && (currentOrderId == null || currentOrderId!.isEmpty);

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
      currentOrderId:
          clearCurrentOrder ? null : (currentOrderId ?? this.currentOrderId),
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

  static bool _parseBool(dynamic raw, {required bool fallback}) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw != null) {
      final s = raw.toString().trim().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return fallback;
  }

  static int _parseInt(dynamic raw, {int fallback = 0}) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString().trim() ?? '') ?? fallback;
  }

  factory DeliveryModel.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status']?.toString().trim().toLowerCase();
    final hasStatus = statusStr != null && statusStr.isNotEmpty;

    final resolvedEnabled = hasStatus
        ? statusStr != 'disabled'
        : _parseBool(
            json['isEnabled'] ?? json['is_enabled'],
            fallback: true,
          );

    final resolvedAvailable = hasStatus
        ? statusStr == 'available'
        : _parseBool(
            json['isAvailable'] ?? json['is_available'],
            fallback: false,
          );

    final rawOrderId = json['currentOrderId'] ?? json['current_order_id'];
    final resolvedOrderId =
        rawOrderId == null || rawOrderId.toString().trim().isEmpty
            ? null
            : rawOrderId.toString().trim();

    return DeliveryModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      isAvailable: resolvedAvailable,
      isEnabled: resolvedEnabled,
      currentOrderId: resolvedOrderId,
      completedToday: _parseInt(
        json['completedToday'] ?? json['completed_orders'],
        fallback: 0,
      ),
    );
  }
}
