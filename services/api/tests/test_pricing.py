from datetime import datetime, timezone
from types import SimpleNamespace
from app.pricing import calculate_price, valid_transition


def test_price_rounding_and_breakdown():
    service = SimpleNamespace(base_fare=30000, per_km_rate=2000, name_mn="Портер")
    pricing = SimpleNamespace(loader_rate=25000, night_surcharge_pct=20, night_start=22, night_end=7)
    result = calculate_price(service, pricing, 8, 1, datetime(2026, 9, 21, 4, tzinfo=timezone.utc))
    assert result["distance_fare"] == 16000
    assert result["loader_fare"] == 25000
    assert result["night_surcharge"] == 0
    assert result["total"] == 71000


def test_night_price_and_status_transitions():
    service = SimpleNamespace(base_fare=10000, per_km_rate=1500, name_mn="Амжиргаа")
    pricing = SimpleNamespace(loader_rate=25000, night_surcharge_pct=20, night_start=22, night_end=7)
    result = calculate_price(service, pricing, 3.1, 0, datetime(2026, 9, 21, 15, tzinfo=timezone.utc))
    assert result["night_surcharge_pct"] == 20
    assert result["total"] == 17500
    assert valid_transition("pending", "assigned")
    assert not valid_transition("pending", "delivered")
    assert valid_transition("picked_up", "delivered")
