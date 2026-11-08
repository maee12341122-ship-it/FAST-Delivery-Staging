class PaymentModel {
  final String id;
  final String orderId;
  final String method;
  final String status;
  final int amount;
  final String? transferReference;
  final String? receiptPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PaymentModel({
    required this.id,
    required this.orderId,
    required this.method,
    required this.status,
    required this.amount,
    this.transferReference,
    this.receiptPath,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'orderId': orderId,
        'method': method,
        'status': status,
        'amount': amount,
        'transferReference': transferReference,
        'receiptPath': receiptPath,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory PaymentModel.fromJson(Map<String, dynamic> json) => PaymentModel(
        id: json['id'] as String? ?? '',
        orderId: json['orderId'] as String? ?? '',
        method: json['method'] as String? ?? 'cash',
        status: json['status'] as String? ?? 'unpaid',
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        transferReference: json['transferReference'] as String?,
        receiptPath: json['receiptPath'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}
