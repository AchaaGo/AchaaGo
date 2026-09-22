class AppUser {
  const AppUser({required this.id, required this.phone, this.name, required this.role});

  final String id;
  final String phone;
  final String? name;
  final String role;

  bool get isDriver => role == 'driver';

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        phone: json['phone'] as String,
        name: json['name'] as String?,
        role: json['role'] as String? ?? 'customer',
      );

  Map<String, dynamic> toJson() => {'id': id, 'phone': phone, 'name': name, 'role': role};
}
