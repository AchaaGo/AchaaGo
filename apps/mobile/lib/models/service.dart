/// GET /services, GET /admin/services — services/api/app/orders.py `service_json`.
class ServiceOption {
  const ServiceOption({
    required this.id,
    required this.code,
    required this.nameMn,
    required this.descriptionMn,
    required this.icon,
    required this.baseFare,
    required this.perKmRate,
    required this.isActive,
    required this.sortOrder,
  });

  final String id;
  final String code;
  final String nameMn;
  final String descriptionMn;
  final String icon;
  final int baseFare;
  final int perKmRate;
  final bool isActive;
  final int sortOrder;

  factory ServiceOption.fromJson(Map<String, dynamic> json) => ServiceOption(
        id: json['id'] as String,
        code: json['code'] as String,
        nameMn: json['name_mn'] as String,
        descriptionMn: json['description_mn'] as String,
        icon: json['icon'] as String? ?? 'truck',
        baseFare: json['base_fare'] as int,
        perKmRate: json['per_km_rate'] as int,
        isActive: json['is_active'] as bool? ?? true,
        sortOrder: json['sort_order'] as int? ?? 0,
      );
}
