import 'service.dart';

/// The `breakdown` object returned by `calculate_price()` in
/// services/api/app/pricing.py.
class PriceBreakdown {
  const PriceBreakdown({
    required this.total,
    required this.serviceName,
    required this.baseFare,
    required this.distanceFare,
    required this.loaderFare,
    required this.nightSurcharge,
  });

  final int total;
  final String serviceName;
  final int baseFare;
  final int distanceFare;
  final int loaderFare;
  final int nightSurcharge;

  factory PriceBreakdown.fromJson(Map<String, dynamic> json) => PriceBreakdown(
        total: json['total'] as int,
        serviceName: json['service_name'] as String? ?? '',
        baseFare: json['base_fare'] as int? ?? 0,
        distanceFare: json['distance_fare'] as int? ?? 0,
        loaderFare: json['loader_fare'] as int? ?? 0,
        nightSurcharge: json['night_surcharge'] as int? ?? 0,
      );
}

class ServicePrice {
  const ServicePrice({required this.service, required this.breakdown});

  final ServiceOption service;
  final PriceBreakdown breakdown;

  factory ServicePrice.fromJson(Map<String, dynamic> json) => ServicePrice(
        service: ServiceOption.fromJson(json['service'] as Map<String, dynamic>),
        breakdown: PriceBreakdown.fromJson(json['breakdown'] as Map<String, dynamic>),
      );
}

/// POST /quotes response.
class Quote {
  const Quote({
    required this.distanceKm,
    required this.durationMinutes,
    required this.prices,
    required this.loaderRate,
    required this.approximate,
    required this.quoteToken,
  });

  final double distanceKm;
  final int durationMinutes;
  final List<ServicePrice> prices;
  final int loaderRate;
  final bool approximate;
  final String quoteToken;

  ServicePrice? priceFor(String serviceId) {
    for (final price in prices) {
      if (price.service.id == serviceId) return price;
    }
    return null;
  }

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
        distanceKm: (json['distance_km'] as num).toDouble(),
        durationMinutes: json['duration_minutes'] as int,
        prices: (json['prices'] as List)
            .map((row) => ServicePrice.fromJson(row as Map<String, dynamic>))
            .toList(),
        loaderRate: json['loader_rate'] as int? ?? 0,
        approximate: json['approximate'] as bool? ?? false,
        quoteToken: json['quote_token'] as String,
      );
}
