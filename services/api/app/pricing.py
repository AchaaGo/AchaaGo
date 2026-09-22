from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP
from zoneinfo import ZoneInfo


def calculate_price(service, pricing, distance_km: float, loaders: int, at: datetime):
    if distance_km < 0 or not 0 <= loaders <= 4:
        raise ValueError("Invalid pricing input")
    hour = at.astimezone(ZoneInfo("Asia/Ulaanbaatar")).hour
    start, end = pricing.night_start, pricing.night_end
    night = (hour >= start or hour < end) if start > end else start <= hour < end
    distance_cost = Decimal(str(distance_km)) * service.per_km_rate
    loader_cost = loaders * pricing.loader_rate
    subtotal = Decimal(service.base_fare + loader_cost) + distance_cost
    surcharge = subtotal * Decimal(pricing.night_surcharge_pct if night else 0) / 100
    total = int(((subtotal + surcharge) / 500).quantize(Decimal("1"), rounding=ROUND_HALF_UP) * 500)
    return {"base_fare": service.base_fare, "per_km_rate": service.per_km_rate,
            "distance_km": distance_km, "distance_fare": int(distance_cost.quantize(Decimal("1"), rounding=ROUND_HALF_UP)),
            "loader_rate": pricing.loader_rate, "loaders": loaders, "loader_fare": loader_cost,
            "night_surcharge_pct": pricing.night_surcharge_pct if night else 0,
            "night_surcharge": int(surcharge.quantize(Decimal("1"), rounding=ROUND_HALF_UP)),
            "total": total, "currency": "MNT", "service_name": service.name_mn}


TRANSITIONS = {
    "pending": {"assigned", "cancelled", "no_driver_found"},
    "assigned": {"driver_arriving", "arrived", "cancelled"},
    "driver_arriving": {"arrived", "cancelled"},
    "arrived": {"picked_up", "cancelled"},
    "picked_up": {"delivered"},
    "delivered": {"completed"},
    "completed": set(), "cancelled": set(), "no_driver_found": set(),
}
TERMINAL = {"completed", "cancelled", "no_driver_found"}
ACTIVE = set(TRANSITIONS) - TERMINAL


def valid_transition(current, next_status):
    return next_status in TRANSITIONS.get(current, set())
