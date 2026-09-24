from datetime import timedelta
from types import SimpleNamespace
import pytest
from fastapi import HTTPException
from app.models import Driver, Order, now
from app.orders import assign, driver_for_user, get_order
from app import orders as orders_module
from app import main as main_module
from app.schemas import CancelInput, StatusInput

# --- driver_for_user: only an authenticated, registered driver can act as one ---


class FakeDriverLookupDb:
    def __init__(self, driver):
        self.driver = driver

    async def scalar(self, statement):
        return self.driver


async def test_driver_for_user_rejects_a_user_with_no_driver_record():
    with pytest.raises(HTTPException) as error:
        await driver_for_user(FakeDriverLookupDb(None), SimpleNamespace(id="user-1"))
    assert (error.value.status_code, error.value.detail) == (403, "DRIVER_NOT_APPROVED")


async def test_driver_for_user_rejects_an_unapproved_driver_by_default():
    driver = SimpleNamespace(id="drv-1", status="pending")
    with pytest.raises(HTTPException) as error:
        await driver_for_user(FakeDriverLookupDb(driver), SimpleNamespace(id="user-1"))
    assert (error.value.status_code, error.value.detail) == (403, "DRIVER_NOT_APPROVED")


async def test_driver_for_user_allows_an_unapproved_driver_when_approval_not_required():
    # Used by /driver/me and /driver/offline, which a pending driver must still be able to call.
    driver = SimpleNamespace(id="drv-1", status="pending")
    result = await driver_for_user(FakeDriverLookupDb(driver), SimpleNamespace(id="user-1"), approved=False)
    assert result is driver


async def test_driver_for_user_allows_an_approved_driver():
    driver = SimpleNamespace(id="drv-1", status="approved")
    result = await driver_for_user(FakeDriverLookupDb(driver), SimpleNamespace(id="user-1"))
    assert result is driver


# --- get_order: staff see everything, customers see their own, drivers see only their own assignment ---


class FakeGetOrderDb:
    def __init__(self, order, driver=None):
        self.order = order
        self.driver = driver

    async def get(self, model, key):
        return self.order

    async def scalar(self, statement):
        return self.driver


async def test_get_order_404s_when_the_order_does_not_exist():
    with pytest.raises(HTTPException) as error:
        await get_order(FakeGetOrderDb(None), "missing", SimpleNamespace(id="u1", role="customer"))
    assert (error.value.status_code, error.value.detail) == (404, "ORDER_NOT_FOUND")


async def test_get_order_allows_staff_regardless_of_ownership():
    order = SimpleNamespace(id="o1", customer_id="cust-1", driver_id=None)
    result = await get_order(FakeGetOrderDb(order), "o1", SimpleNamespace(id="dispatcher-1", role="dispatcher"))
    assert result is order


async def test_get_order_allows_the_owning_customer():
    order = SimpleNamespace(id="o1", customer_id="cust-1", driver_id=None)
    result = await get_order(FakeGetOrderDb(order), "o1", SimpleNamespace(id="cust-1", role="customer"))
    assert result is order


async def test_get_order_hides_another_customers_order_as_not_found():
    # 404, not 403: existence of another customer's order is never confirmed.
    order = SimpleNamespace(id="o1", customer_id="cust-1", driver_id=None)
    with pytest.raises(HTTPException) as error:
        await get_order(FakeGetOrderDb(order, driver=None), "o1", SimpleNamespace(id="cust-2", role="customer"))
    assert (error.value.status_code, error.value.detail) == (404, "ORDER_NOT_FOUND")


async def test_get_order_allows_the_assigned_driver():
    order = SimpleNamespace(id="o1", customer_id="cust-1", driver_id="drv-mine")
    driver = SimpleNamespace(id="drv-mine")
    result = await get_order(FakeGetOrderDb(order, driver=driver), "o1", SimpleNamespace(id="driver-user-1", role="customer"))
    assert result is order


async def test_get_order_hides_an_order_assigned_to_a_different_driver():
    order = SimpleNamespace(id="o1", customer_id="cust-1", driver_id="drv-other")
    driver = SimpleNamespace(id="drv-mine")
    with pytest.raises(HTTPException) as error:
        await get_order(FakeGetOrderDb(order, driver=driver), "o1", SimpleNamespace(id="driver-user-1", role="customer"))
    assert error.value.status_code == 404


# --- assign(): every pre-check that keeps dispatch safe under concurrency ---


def make_order(status="pending"):
    return SimpleNamespace(id="ord-1", status=status, driver_id=None)


def make_driver(status="approved", is_online=True, last_seen=None):
    return SimpleNamespace(id="drv-1", status=status, is_online=is_online, last_seen=last_seen if last_seen is not None else now())


class FakeAssignDb:
    """Fakes exactly the queries assign() issues: two get_locked() calls (patched
    separately below), then always the vehicle lookup, then always the driver-busy
    check, in that fixed order — so responses are matched by call order rather
    than introspecting the statement, which is simpler and just as exact here."""

    def __init__(self, vehicle, busy_order_id=None):
        self.vehicle = vehicle
        self.busy_order_id = busy_order_id
        self.committed = False
        self.scalar_calls = 0

    async def scalar(self, statement):
        self.scalar_calls += 1
        return self.vehicle if self.scalar_calls == 1 else self.busy_order_id

    async def commit(self):
        self.committed = True


@pytest.fixture
def locked_rows(monkeypatch):
    """Stands in for get_locked(db, Model, key): assign() calls it once for the
    order and once for the driver, and their pre-checks read straight off the
    row it returns, so tests only need to seed this dict."""
    store = {}

    async def fake_get_locked(db, model, key):
        return store.get((model, key))
    monkeypatch.setattr(orders_module, "get_locked", fake_get_locked)
    return store


@pytest.fixture
def fake_change_status(monkeypatch):
    calls = []

    async def fake(db, order, target, actor, reason=None):
        calls.append((order.id, target, actor, reason))
        order.status = target
    monkeypatch.setattr(orders_module, "change_status", fake)
    return calls


async def test_assign_happy_path_sets_the_driver_and_transitions_the_order(locked_rows, fake_change_status):
    order, driver = make_order(), make_driver()
    locked_rows[(Order, "ord-1")] = order
    locked_rows[(Driver, "drv-1")] = driver
    db = FakeAssignDb(vehicle=SimpleNamespace(service_id="svc-porter"))
    order.service_id = "svc-porter"

    result = await assign(db, "ord-1", "drv-1", "dispatcher-1")

    assert result.driver_id == "drv-1"
    assert fake_change_status == [("ord-1", "assigned", "dispatcher-1", None)]
    assert db.committed


async def test_assign_rejects_an_order_that_is_no_longer_pending(locked_rows, fake_change_status):
    # The exact race this guards against: a second dispatcher assigning an
    # order the first dispatcher already assigned a moment earlier. On
    # Postgres, get_locked's SELECT ... FOR UPDATE serializes concurrent
    # calls so the loser observes this post-commit state; this test locks in
    # the pre-check's behavior once that already-updated row is read.
    order = make_order(status="assigned")
    locked_rows[(Order, "ord-1")] = order
    locked_rows[(Driver, "drv-1")] = make_driver()
    db = FakeAssignDb(vehicle=SimpleNamespace(service_id="svc-porter"))
    order.service_id = "svc-porter"

    with pytest.raises(HTTPException) as error:
        await assign(db, "ord-1", "drv-1", "dispatcher-1")
    assert (error.value.status_code, error.value.detail) == (409, "ORDER_ALREADY_ASSIGNED")
    assert fake_change_status == []


async def test_assign_rejects_a_missing_order(locked_rows):
    with pytest.raises(HTTPException) as error:
        await assign(FakeAssignDb(vehicle=None), "missing", "drv-1", "dispatcher-1")
    assert (error.value.status_code, error.value.detail) == (404, "ORDER_NOT_FOUND")


async def test_assign_rejects_an_unapproved_driver(locked_rows):
    locked_rows[(Order, "ord-1")] = make_order()
    locked_rows[(Driver, "drv-1")] = make_driver(status="pending")
    with pytest.raises(HTTPException) as error:
        await assign(FakeAssignDb(vehicle=None), "ord-1", "drv-1", "dispatcher-1")
    assert (error.value.status_code, error.value.detail) == (409, "DRIVER_UNAVAILABLE")


async def test_assign_rejects_an_offline_driver(locked_rows):
    locked_rows[(Order, "ord-1")] = make_order()
    locked_rows[(Driver, "drv-1")] = make_driver(is_online=False)
    with pytest.raises(HTTPException) as error:
        await assign(FakeAssignDb(vehicle=None), "ord-1", "drv-1", "dispatcher-1")
    assert (error.value.status_code, error.value.detail) == (409, "DRIVER_UNAVAILABLE")


async def test_assign_rejects_a_driver_with_no_recent_location(locked_rows):
    locked_rows[(Order, "ord-1")] = make_order()
    locked_rows[(Driver, "drv-1")] = make_driver(last_seen=now() - timedelta(seconds=200))
    with pytest.raises(HTTPException) as error:
        await assign(FakeAssignDb(vehicle=None), "ord-1", "drv-1", "dispatcher-1")
    assert (error.value.status_code, error.value.detail) == (409, "DRIVER_UNAVAILABLE")


async def test_assign_rejects_a_driver_who_never_sent_a_location(locked_rows):
    locked_rows[(Order, "ord-1")] = make_order()
    locked_rows[(Driver, "drv-1")] = make_driver(last_seen=None)
    with pytest.raises(HTTPException) as error:
        await assign(FakeAssignDb(vehicle=None), "ord-1", "drv-1", "dispatcher-1")
    assert (error.value.status_code, error.value.detail) == (409, "DRIVER_UNAVAILABLE")


async def test_assign_rejects_a_vehicle_service_mismatch(locked_rows):
    order = make_order()
    order.service_id = "svc-porter"
    locked_rows[(Order, "ord-1")] = order
    locked_rows[(Driver, "drv-1")] = make_driver()
    db = FakeAssignDb(vehicle=SimpleNamespace(service_id="svc-amjirgaa"))
    with pytest.raises(HTTPException) as error:
        await assign(db, "ord-1", "drv-1", "dispatcher-1")
    assert (error.value.status_code, error.value.detail) == (409, "VEHICLE_MISMATCH")


async def test_assign_rejects_a_driver_with_no_vehicle(locked_rows):
    order = make_order()
    order.service_id = "svc-porter"
    locked_rows[(Order, "ord-1")] = order
    locked_rows[(Driver, "drv-1")] = make_driver()
    with pytest.raises(HTTPException) as error:
        await assign(FakeAssignDb(vehicle=None), "ord-1", "drv-1", "dispatcher-1")
    assert (error.value.status_code, error.value.detail) == (409, "VEHICLE_MISMATCH")


async def test_assign_rejects_a_driver_already_on_another_active_order(locked_rows, fake_change_status):
    # The other half of the double-booking guard: get_locked() locks the
    # DRIVER row too, so a concurrent assign() targeting the same driver on a
    # different order serializes here and observes this already-busy state.
    order = make_order()
    order.service_id = "svc-porter"
    locked_rows[(Order, "ord-1")] = order
    locked_rows[(Driver, "drv-1")] = make_driver()
    db = FakeAssignDb(vehicle=SimpleNamespace(service_id="svc-porter"), busy_order_id="ord-other")
    with pytest.raises(HTTPException) as error:
        await assign(db, "ord-1", "drv-1", "dispatcher-1")
    assert (error.value.status_code, error.value.detail) == (409, "DRIVER_BUSY")
    assert fake_change_status == []


# --- driver_status endpoint: authorization, invalid transitions, and driver-initiated cancellation ---


class FakeDb:
    async def commit(self):
        pass


def patch_driver_status(monkeypatch, driver, order, reason_reached=None):
    async def fake_driver_for_user(db, user):
        return driver

    async def fake_get_order(db, order_id, user, locked=False):
        return order

    async def fake_change_status(db, order, target, actor, reason=None):
        if reason_reached is not None:
            reason_reached.append((target, actor, reason))
        order.status = target

    async def fake_order_json(db, order):
        return {"id": order.id, "status": order.status}
    monkeypatch.setattr(main_module, "driver_for_user", fake_driver_for_user)
    monkeypatch.setattr(main_module, "get_order", fake_get_order)
    monkeypatch.setattr(main_module, "change_status", fake_change_status)
    monkeypatch.setattr(main_module, "order_json", fake_order_json)


async def test_driver_status_rejects_an_order_that_is_not_this_drivers(monkeypatch):
    driver = SimpleNamespace(id="drv-mine")
    order = SimpleNamespace(id="o1", driver_id="drv-other", status="assigned")
    patch_driver_status(monkeypatch, driver, order)
    with pytest.raises(HTTPException) as error:
        await main_module.driver_status("o1", StatusInput(status="arrived"), SimpleNamespace(id="u1"), FakeDb())
    assert (error.value.status_code, error.value.detail) == (403, "FORBIDDEN")


async def test_driver_status_rejects_a_status_drivers_may_not_set(monkeypatch):
    # "no_driver_found" is a valid StatusInput value (the schema allows it for
    # the dispatch-timeout worker) but is not one a driver may set themselves.
    driver = SimpleNamespace(id="drv-1")
    order = SimpleNamespace(id="o1", driver_id="drv-1", status="pending")
    patch_driver_status(monkeypatch, driver, order)
    with pytest.raises(HTTPException) as error:
        await main_module.driver_status("o1", StatusInput(status="no_driver_found"), SimpleNamespace(id="u1"), FakeDb())
    assert (error.value.status_code, error.value.detail) == (403, "FORBIDDEN")


async def test_driver_status_requires_a_reason_to_cancel(monkeypatch):
    driver = SimpleNamespace(id="drv-1")
    order = SimpleNamespace(id="o1", driver_id="drv-1", status="assigned")
    patch_driver_status(monkeypatch, driver, order)
    with pytest.raises(HTTPException) as error:
        await main_module.driver_status("o1", StatusInput(status="cancelled"), SimpleNamespace(id="u1"), FakeDb())
    assert (error.value.status_code, error.value.detail) == (422, "REASON_REQUIRED")


async def test_driver_status_allows_cancellation_with_a_reason(monkeypatch):
    driver = SimpleNamespace(id="drv-1")
    order = SimpleNamespace(id="o1", driver_id="drv-1", status="assigned")
    calls = []
    patch_driver_status(monkeypatch, driver, order, reason_reached=calls)
    result = await main_module.driver_status("o1", StatusInput(status="cancelled", reason="Машин эвдэрсэн"),
                                             SimpleNamespace(id="driver-user-1"), FakeDb())
    assert calls == [("cancelled", "driver-user-1", "Машин эвдэрсэн")]
    assert result["status"] == "cancelled"


async def test_driver_status_allows_the_normal_progress_statuses_without_a_reason(monkeypatch):
    driver = SimpleNamespace(id="drv-1")
    order = SimpleNamespace(id="o1", driver_id="drv-1", status="driver_arriving")
    calls = []
    patch_driver_status(monkeypatch, driver, order, reason_reached=calls)
    result = await main_module.driver_status("o1", StatusInput(status="arrived"), SimpleNamespace(id="driver-user-1"), FakeDb())
    assert calls == [("arrived", "driver-user-1", None)]
    assert result["status"] == "arrived"


# --- customer cancel(): ownership, cancellable-status window, and the paid-order refund gate ---


class FakeCancelDb:
    def __init__(self, order, payment=None):
        self.order = order
        self.payment = payment
        self.committed = False

    async def get(self, model, key):
        return self.order

    async def scalar(self, statement):
        return self.payment

    async def commit(self):
        self.committed = True


def patch_cancel(monkeypatch, cancelled=None):
    async def fake_get_order(db, order_id, user, locked=False):
        return db.order

    async def fake_change_status(db, order, target, actor, reason=None):
        if cancelled is not None:
            cancelled.append((target, actor, reason))
        order.status = target

    async def fake_order_json(db, order):
        return {"id": order.id, "status": order.status}
    monkeypatch.setattr(main_module, "get_order", fake_get_order)
    monkeypatch.setattr(main_module, "change_status", fake_change_status)
    monkeypatch.setattr(main_module, "order_json", fake_order_json)


async def test_cancel_rejects_a_non_owning_customer(monkeypatch):
    order = SimpleNamespace(id="o1", customer_id="cust-1", status="pending")
    patch_cancel(monkeypatch)
    db = FakeCancelDb(order)
    with pytest.raises(HTTPException) as error:
        await main_module.cancel("o1", CancelInput(reason="Хэрэггүй боллоо"), SimpleNamespace(id="cust-2"), db)
    assert (error.value.status_code, error.value.detail) == (403, "FORBIDDEN")


async def test_cancel_rejects_an_order_past_the_cancellable_window(monkeypatch):
    order = SimpleNamespace(id="o1", customer_id="cust-1", status="picked_up")
    patch_cancel(monkeypatch)
    db = FakeCancelDb(order)
    with pytest.raises(HTTPException) as error:
        await main_module.cancel("o1", CancelInput(reason="Хэрэггүй боллоо"), SimpleNamespace(id="cust-1"), db)
    assert (error.value.status_code, error.value.detail) == (409, "CANCELLATION_UNAVAILABLE")


async def test_cancel_rejects_an_already_paid_order_pending_dispatcher_refund(monkeypatch):
    order = SimpleNamespace(id="o1", customer_id="cust-1", status="assigned")
    payment = SimpleNamespace(status="paid")
    patch_cancel(monkeypatch)
    db = FakeCancelDb(order, payment=payment)
    with pytest.raises(HTTPException) as error:
        await main_module.cancel("o1", CancelInput(reason="Хэрэггүй боллоо"), SimpleNamespace(id="cust-1"), db)
    assert (error.value.status_code, error.value.detail) == (409, "REFUND_REQUIRES_DISPATCHER")


async def test_cancel_succeeds_for_the_owning_customer_in_an_unpaid_cancellable_state(monkeypatch):
    order = SimpleNamespace(id="o1", customer_id="cust-1", status="pending")
    calls = []
    patch_cancel(monkeypatch, cancelled=calls)
    db = FakeCancelDb(order, payment=SimpleNamespace(status="pending"))
    result = await main_module.cancel("o1", CancelInput(reason="Хаяг буруу"), SimpleNamespace(id="cust-1"), db)
    assert calls == [("cancelled", "cust-1", "Хаяг буруу")]
    assert result["status"] == "cancelled"
    assert db.committed
