class ProductModel {
  final String id;
  final String name;
  final String description; // 👈 تم إضافة حقل وصف المنتج هنا بنجاح
  final String restaurantName;
  final double price;
  final String category; // المطاعم، البقالات، الخضار والفواكه، الصيدلية الآمنة
  final bool available;
  final String imageUrl;
  final String unit; // كيلو، حبة، صندوق، جرام (مهم للخضار والفواكه)
  final bool isVariablePrice; // لتحديد ما إذا كان المنتج بدون سعر ثابت ويحتاج تسعير وزني

  ProductModel({
    required this.id,
    required this.name,
    required this.description, // 👈 إضافته في المُنشئ الإلزامي
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
      'description': description, // 👈 إضافته عند إرسال البيانات لقاعدة البيانات
      'restaurantName': restaurantName,
      'price': price,
      'category': category,
      'available': available,
      'imageUrl': imageUrl,
      'unit': unit,
      'is_variable_price': isVariablePrice,
    };
  }

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '', // 👈 قراءة الوصف من قاعدة البيانات مع قيمة افتراضية فارغة
      restaurantName: map['restaurantName'] ?? '',
      price: (map['price'] ?? 0.0).toDouble(),
      category: map['category'] ?? 'المطاعم',
      available: map['available'] ?? true,
      imageUrl: map['imageUrl'] ?? '',
      unit: map['unit'] ?? 'حبة',
      isVariablePrice: map['is_variable_price'] ?? false,
    );
  }
}
