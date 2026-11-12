class ProductModel {
  final String id;
  final String name;
  final String description; // وصف المنتج
  final String restaurantName;
  final double price;
  final String category; // المطاعم، البقالات، الخضار والفواكه، الصيدلية الآمنة
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
      'restaurant_name': restaurantName, // مطابق تماماً لعمود جدول Supabase
      'price': price,
      'category': category,
      'available': available,
      'image_url': imageUrl,             // مطابق تماماً لعمود جدول Supabase
      'unit': unit,
      'is_variable_price': isVariablePrice, // مطابق تماماً لعمود جدول Supabase
    };
  }

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      restaurantName: map['restaurant_name']?.toString() ?? map['restaurantName']?.toString() ?? '',
      price: double.tryParse(map['price']?.toString() ?? '0.0') ?? 0.0,
      category: map['category']?.toString() ?? 'المطاعم',
      available: map['available'] ?? true,
      imageUrl: map['image_url']?.toString() ?? map['imageUrl']?.toString() ?? '',
      unit: map['unit']?.toString() ?? 'حبة',
      isVariablePrice: map['is_variable_price'] ?? map['isVariablePrice'] ?? false,
    );
  }
}
