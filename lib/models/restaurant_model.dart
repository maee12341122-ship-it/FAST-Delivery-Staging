class RestaurantModel {
  final String id;
  final String name;
  final String description;
  final String address;
  final String logoUrl;
  final String imageUrl;
  final int openingHour;
  final int closingHour;
  final int preparationMinutes;
  final bool isEnabled;

  const RestaurantModel({
    required this.id,
    required this.name,
    this.description = '',
    this.address = '',
    this.logoUrl = '',
    this.imageUrl = '',
    this.openingHour = 11,
    this.closingHour = 22,
    this.preparationMinutes = 30,
    this.isEnabled = true,
  });

  bool isOpenAt(DateTime time) {
    if (openingHour == closingHour) return true;
    if (openingHour < closingHour) return time.hour >= openingHour && time.hour < closingHour;
    return time.hour >= openingHour || time.hour < closingHour;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'address': address,
        'logoUrl': logoUrl,
        'imageUrl': imageUrl,
        'openingHour': openingHour,
        'closingHour': closingHour,
        'preparationMinutes': preparationMinutes,
        'isEnabled': isEnabled,
      };

  factory RestaurantModel.fromJson(Map<String, dynamic> json) => RestaurantModel(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        address: json['address'] as String? ?? '',
        logoUrl: json['logoUrl'] as String? ?? '',
        imageUrl: json['imageUrl'] as String? ?? '',
        openingHour: (json['openingHour'] as num?)?.toInt() ?? 11,
        closingHour: (json['closingHour'] as num?)?.toInt() ?? 22,
        preparationMinutes: (json['preparationMinutes'] as num?)?.toInt() ?? 30,
        isEnabled: json['isEnabled'] as bool? ?? true,
      );
}
