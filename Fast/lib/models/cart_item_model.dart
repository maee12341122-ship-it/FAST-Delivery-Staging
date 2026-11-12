class CartItemModel {
  final String id;
  final String name;
  final double price;
  int quantity;
  final String restaurantId;
  final String imageUrl;
  double get lineTotal => price * quantity;

  CartItemModel({
    required this.id,
    required this.name,
    required this.price,
    this.quantity = 1,
    required this.restaurantId,
    required this.imageUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'quantity': quantity,
      'restaurantId': restaurantId,
      'imageUrl': imageUrl,
    };
  }

  factory CartItemModel.fromMap(Map<String, dynamic> map) {
    return CartItemModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      price: (map['price'] ?? 0.0).toDouble(),
      quantity: map['quantity'] ?? 1,
      restaurantId: map['restaurantId'] ?? '',
      imageUrl: map['imageUrl'] ?? '',
    );
  }
}