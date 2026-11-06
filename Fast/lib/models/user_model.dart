class UserModel {
  final String uid;
  final String phone;
  final String name;
  final String address;
  final double? latitude;
  final double? longitude;

  UserModel({
    required this.uid,
    required this.phone,
    this.name = 'عميل تعز إكسبرس',
    this.address = 'تعز - شارع جمال',
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'phone': phone,
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      phone: map['phone'] ?? '',
      name: map['name'] ?? 'عميل تعز إكسبرس',
      address: map['address'] ?? 'تعز - شارع جمال',
      latitude: map['latitude'],
      longitude: map['longitude'],
    );
  }
}