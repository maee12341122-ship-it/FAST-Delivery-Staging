class AddressModel {
  final String id;
  final String title;
  final String area;
  final String details;
  final double? latitude;
  final double? longitude;
  final String instructions;

  const AddressModel({
    required this.id,
    required this.title,
    required this.area,
    required this.details,
    this.latitude,
    this.longitude,
    this.instructions = '',
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'area': area,
        'details': details,
        'latitude': latitude,
        'longitude': longitude,
        'instructions': instructions,
      };

  factory AddressModel.fromJson(Map<String, dynamic> json) => AddressModel(
        id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: json['title'] as String? ?? 'العنوان الرئيسي',
        area: json['area'] as String? ?? '',
        details: json['details'] as String? ?? '',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        instructions: json['instructions'] as String? ?? '',
      );

  AddressModel copyWith({
    String? title,
    String? area,
    String? details,
    double? latitude,
    double? longitude,
    String? instructions,
  }) {
    return AddressModel(
      id: id,
      title: title ?? this.title,
      area: area ?? this.area,
      details: details ?? this.details,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      instructions: instructions ?? this.instructions,
    );
  }
}
