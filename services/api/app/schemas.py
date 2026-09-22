from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, field_validator


class Input(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class Phone(Input):
    phone: str = Field(pattern=r"^\+976[0-9]{8}$")


class OTPVerify(Phone):
    code: str = Field(pattern=r"^[0-9]{4}$")


class RefreshInput(Input):
    refresh_token: str | None = None


class Location(Input):
    lat: float = Field(ge=47.0, le=49.0, allow_inf_nan=False)
    lng: float = Field(ge=105.0, le=108.0, allow_inf_nan=False)
    address: str = Field(min_length=2, max_length=300)


class QuoteInput(Input):
    pickup: Location
    dropoff: Location
    loaders: int = Field(default=0, ge=0, le=4)


class OrderInput(QuoteInput):
    service_id: str
    payment_method: Literal["cash", "qpay"]
    expected_total: int = Field(ge=0)
    quote_token: str


class PhoneOrder(OrderInput):
    customer_phone: str = Field(pattern=r"^\+976[0-9]{8}$")


class CancelInput(Input):
    reason: str = Field(min_length=2, max_length=300)


class AssignInput(Input):
    driver_id: str


class InvoiceInput(Input):
    order_id: str


class StatusInput(Input):
    status: Literal["driver_arriving", "arrived", "picked_up", "delivered", "completed", "cancelled", "no_driver_found"]
    reason: str | None = Field(default=None, max_length=300)


class RatingInput(Input):
    rating: int = Field(ge=1, le=5)


class ServiceInput(Input):
    code: str = Field(pattern=r"^[a-z][a-z0-9_-]{1,29}$")
    name_mn: str = Field(min_length=2, max_length=80)
    description_mn: str = Field(min_length=1, max_length=200)
    icon: Literal["truck", "package"] = "truck"
    base_fare: int = Field(ge=0, le=10000000)
    per_km_rate: int = Field(ge=0, le=1000000)
    is_active: bool = True
    sort_order: int = Field(default=0, ge=0, le=1000)


class PricingInput(Input):
    loader_rate: int = Field(ge=0, le=1000000)
    floor_rate: int = Field(ge=0, le=1000000)
    night_surcharge_pct: int = Field(ge=0, le=200)
    night_start: int = Field(ge=0, le=23)
    night_end: int = Field(ge=0, le=23)


class DriverRegistration(Input):
    name: str = Field(min_length=2, max_length=100)
    license_info: str = Field(min_length=3, max_length=100)
    service_id: str
    plate_number: str = Field(min_length=4, max_length=20)
    model: str = Field(min_length=2, max_length=100)
    capacity_kg: int = Field(ge=50, le=30000)

    @field_validator("plate_number")
    @classmethod
    def normalize_plate(cls, value):
        return " ".join(value.upper().split())


class DriverApproval(Input):
    status: Literal["approved", "suspended", "pending"]


class DriverLocation(Input):
    lat: float = Field(ge=47, le=49, allow_inf_nan=False)
    lng: float = Field(ge=105, le=108, allow_inf_nan=False)


class PushToken(Input):
    token: str = Field(min_length=20, max_length=2048)
