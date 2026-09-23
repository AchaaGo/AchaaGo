from types import SimpleNamespace
import pytest
from fastapi import HTTPException
from app.config import settings
from app.models import Driver, OrderEvent, Outbox, Payment, User, Vehicle
from app.orders import change_status
from app.pricing import ACTIVE, TERMINAL, TRANSITIONS, valid_transition

# Every allowed move in the order lifecycle (AGENTS.md section 8). Anything not listed must be rejected.
ALLOWED = {
    ("pending", "assigned"), ("pending", "cancelled"), ("pending", "no_driver_found"),
    ("assigned", "driver_arriving"), ("assigned", "arrived"), ("assigned", "cancelled"),
    ("driver_arriving", "arrived"), ("driver_arriving", "cancelled"),
    ("arrived", "picked_up"), ("arrived", "cancelled"),
    ("picked_up", "delivered"),
    ("delivered", "completed"),
}
STATUSES = set(TRANSITIONS)


def test_every_status_pair_matches_the_documented_lifecycle():
    allowed = {(current, target) for current in STATUSES for target in STATUSES if valid_transition(current, target)}
    assert allowed == ALLOWED


def test_full_delivery_path_is_allowed_step_by_step():
    path = ["pending", "assigned", "driver_arriving", "arrived", "picked_up", "delivered", "completed"]
    for current, target in zip(path, path[1:]):
        assert valid_transition(current, target), f"{current} -> {target}"


@pytest.mark.parametrize("status", ["picked_up", "delivered", "completed", "cancelled", "no_driver_found"])
def test_cannot_cancel_once_goods_are_loaded_or_the_order_is_over(status):
    assert not valid_transition(status, "cancelled")


@pytest.mark.parametrize("status", sorted(TERMINAL))
def test_terminal_statuses_are_final(status):
    assert not any(valid_transition(status, target) for target in STATUSES)


def test_active_and_terminal_cover_every_status_exactly_once():
    assert ACTIVE | TERMINAL == STATUSES
    assert not ACTIVE & TERMINAL


def test_unknown_statuses_are_rejected():
    assert not valid_transition("teleported", "assigned")
    assert not valid_transition("pending", "teleported")


class FakeDb:
    """Just enough of an AsyncSession for change_status: get, scalar and add."""

    def __init__(self, payment_status="pending", fcm_token=None):
        self.added = []
        self.payment = SimpleNamespace(status=payment_status) if payment_status else None
        self.vehicle = SimpleNamespace(plate_number="1234УБА")
        self.rows = {
            (User, "cust-1"): SimpleNamespace(id="cust-1", phone="+97699112233"),
            (User, "drv-user-1"): SimpleNamespace(id="drv-user-1", name="Бат"),
            (Driver, "drv-1"): SimpleNamespace(id="drv-1", user_id="drv-user-1", fcm_token=fcm_token),
        }

    def add(self, obj):
        self.added.append(obj)

    async def get(self, model, key):
        return self.rows[(model, key)]

    async def scalar(self, statement):
        entity = statement.column_descriptions[0]["entity"]
        return {Payment: self.payment, Vehicle: self.vehicle}[entity]

    def events(self):
        return [(row.status, row.actor, row.reason) for row in self.added if isinstance(row, OrderEvent)]

    def outbox(self, kind):
        return [row.payload for row in self.added if isinstance(row, Outbox) and row.kind == kind]


def make_order(status):
    return SimpleNamespace(id="ord-1", status=status, updated_at=None, customer_id="cust-1",
                           driver_id="drv-1", tracking_token="tok-1")


async def test_invalid_transition_is_rejected_and_nothing_is_written():
    db, order = FakeDb(), make_order("pending")
    with pytest.raises(HTTPException) as error:
        await change_status(db, order, "delivered", "drv-user-1")
    assert (error.value.status_code, error.value.detail) == (409, "INVALID_STATUS_TRANSITION")
    assert order.status == "pending"
    assert db.added == []


async def test_valid_transition_records_an_audit_event_and_a_live_update():
    db, order = FakeDb(), make_order("arrived")
    await change_status(db, order, "picked_up", "drv-user-1")
    assert order.status == "picked_up"
    assert order.updated_at is not None
    assert db.events() == [("picked_up", "drv-user-1", None)]
    assert db.outbox("event") == [{"order_id": "ord-1", "type": "status", "status": "picked_up"}]
    assert db.outbox("sms") == []


@pytest.mark.parametrize("payment_status", ["pending", None])
async def test_completing_requires_a_paid_payment(payment_status):
    db, order = FakeDb(payment_status=payment_status), make_order("delivered")
    with pytest.raises(HTTPException) as error:
        await change_status(db, order, "completed", "drv-user-1")
    assert (error.value.status_code, error.value.detail) == (409, "PAYMENT_REQUIRED")
    assert order.status == "delivered"
    assert db.added == []


async def test_delivery_completes_the_order_when_already_paid():
    db, order = FakeDb(payment_status="paid"), make_order("picked_up")
    await change_status(db, order, "delivered", "drv-user-1")
    assert order.status == "completed"
    assert [status for status, _, _ in db.events()] == ["delivered", "completed"]


async def test_delivery_waits_for_payment_when_unpaid():
    db, order = FakeDb(payment_status="pending"), make_order("picked_up")
    await change_status(db, order, "delivered", "drv-user-1")
    assert order.status == "delivered"
    assert [status for status, _, _ in db.events()] == ["delivered"]


async def test_assignment_texts_the_customer_and_notifies_the_driver():
    db, order = FakeDb(fcm_token="fcm-1"), make_order("pending")
    await change_status(db, order, "assigned", "dispatcher-1")
    assert db.outbox("sms") == [{
        "phone": "+97699112233",
        "message": "Жолооч Бат, 1234УБА. " + settings.public_url + "/t/tok-1",
    }]
    assert db.outbox("push") == [{"token": "fcm-1", "order_id": "ord-1"}]


async def test_assignment_skips_the_push_when_the_driver_has_no_device_token():
    db, order = FakeDb(fcm_token=None), make_order("pending")
    await change_status(db, order, "assigned", "dispatcher-1")
    assert len(db.outbox("sms")) == 1
    assert db.outbox("push") == []


async def test_arrival_texts_the_customer():
    db, order = FakeDb(), make_order("driver_arriving")
    await change_status(db, order, "arrived", "drv-user-1")
    assert db.outbox("sms") == [{"phone": "+97699112233", "message": "Жолооч ирлээ. " + settings.public_url + "/t/tok-1"}]
    assert db.outbox("push") == []


async def test_cancellation_keeps_the_reason_and_sends_no_sms():
    db, order = FakeDb(), make_order("assigned")
    await change_status(db, order, "cancelled", "cust-1", "Буруу хаяг")
    assert order.status == "cancelled"
    assert db.events() == [("cancelled", "cust-1", "Буруу хаяг")]
    assert db.outbox("sms") == []
    assert db.outbox("push") == []
