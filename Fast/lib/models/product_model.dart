class ProductModel {
  final String id;
  final String name;
  final String description; // وصف المنتج
  final String restaurantName;
  final double price;
  final String category; // المطاعم، حلويات ومعجنات، البقالات، الخضار والفواكه، الصيدلية الآمنة، هدايا واكسسوارات
  final String subCategory; // القسم الداخلي الخاص بالمتجر/المطعم
  final bool available;
  final String imageUrl;
  final String unit; // كيلو، حبة، صندوق، جرام (مهم للخضار والفواكه)
  final bool isVariablePrice; // لتحديد ما إذا كان المنتج يتطلب تحديد السعر يدوياً من العميل

  ProductModel({
    required this.id,
    required this.name,
    required this.description,
    required this.restaurantName,
    required this.price,
    required this.category,
    this.subCategory = '',
    required this.available,
    required this.imageUrl,
    this.unit = 'حبة',
    this.isVariablePrice = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'restaurant_name': restaurantName,
      'price': price,
      'category': category,
      'sub_category': subCategory,
      'available': available,
      'image_url': imageUrl,
      'unit': unit,
      'is_variable_price': isVariablePrice,
    };
  }

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

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    final rawAvailable = map['available'];
    final rawVariablePrice =
        map['is_variable_price'] ?? map['isVariablePrice'];

    return ProductModel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      restaurantName: map['restaurant_name']?.toString() ??
          map['restaurantName']?.toString() ??
          '',
      price: double.tryParse(map['price']?.toString() ?? '0.0') ?? 0.0,
      category: map['category']?.toString() ?? 'المطاعم',
      subCategory: map['sub_category']?.toString().trim() ??
          map['subCategory']?.toString().trim() ??
          '',
      available: _parseBool(rawAvailable, fallback: true),
      imageUrl:
          map['image_url']?.toString() ?? map['imageUrl']?.toString() ?? '',
      unit: map['unit']?.toString() ?? 'حبة',
      isVariablePrice: _parseBool(rawVariablePrice, fallback: false),
    );
  }
}
