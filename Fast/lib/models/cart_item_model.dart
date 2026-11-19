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
    final rawId = map['id'] ?? map['product_id'];
    final rawName = map['name'] ?? map['product_name'];
    final rawPrice = map['price'] ?? map['unit_price'];
    final rawQty = map['quantity'];
    final rawRestaurantId = map['restaurantId'] ?? map['restaurant_id'];
    final rawImageUrl = map['imageUrl'] ?? map['image_url'];

    final parsedPrice = rawPrice is num
        ? rawPrice.toDouble()
        : (double.tryParse(rawPrice?.toString() ?? '0.0') ?? 0.0);

    final parsedQty = rawQty is int
        ? rawQty
        : (rawQty is num
            ? rawQty.toInt()
            : (int.tryParse(rawQty?.toString() ?? '1') ?? 1));

    return CartItemModel(
      id: rawId?.toString() ?? '',
      name: rawName?.toString() ?? '',
      price: parsedPrice,
      quantity: parsedQty > 0 ? parsedQty : 1,
      restaurantId: rawRestaurantId?.toString() ?? '',
      imageUrl: rawImageUrl?.toString() ?? '',
    );
  }
}
