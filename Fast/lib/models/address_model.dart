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

  bool get hasCoordinates {
    final lat = latitude;
    final lng = longitude;
    if (lat == null || lng == null) return false;
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'area': area,
        'details': details,
        'latitude': latitude,
        'longitude': longitude,
        'instructions': instructions,
      };

  static double? _parseCoordinate(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) {
      final val = raw.toDouble();
      return val.isFinite ? val : null;
    }
    final parsed = double.tryParse(raw.toString().trim());
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }

  factory AddressModel.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString().trim();
    final resolvedId = (rawId != null && rawId.isNotEmpty)
        ? rawId
        : DateTime.now().microsecondsSinceEpoch.toString();

    return AddressModel(
      id: resolvedId,
      title: json['title']?.toString().trim().isNotEmpty == true
          ? json['title'].toString().trim()
          : 'العنوان الرئيسي',
      area: json['area']?.toString() ?? '',
      details: json['details']?.toString() ?? '',
      latitude: _parseCoordinate(json['latitude']),
      longitude: _parseCoordinate(json['longitude']),
      instructions: json['instructions']?.toString() ?? '',
    );
  }

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
