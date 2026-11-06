class ProductModel {
  final String id;
  final String name;
  final String restaurantName;
  final double price;
  final String category; // المطاعم، البقالات، الخضار والفواكه، الصيدلية الآمنة
  final bool available;
  final String imageUrl;
  final String unit; // كيلو، حبة، صندوق، جرام (مهم للخضار والفواكه)

  ProductModel({
    required this.id,
    required this.name,
    required this.restaurantName,
    required this.price,
    required this.category,
    required this.available,
    required this.imageUrl,
    this.unit = 'حبة',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'restaurantName': restaurantName,
      'price': price,
      'category': category,
      'available': available,
      'imageUrl': imageUrl,
      'unit': unit,
    };
  }

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      restaurantName: map['restaurantName'] ?? '',
      price: (map['price'] ?? 0.0).toDouble(),
      category: map['category'] ?? 'المطاعم',
      available: map['available'] ?? true,
      imageUrl: map['imageUrl'] ?? '',
      unit: map['unit'] ?? 'حبة',
    );
  }
}