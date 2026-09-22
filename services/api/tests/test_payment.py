from decimal import Decimal
import pytest
from app.providers import PaymentProvider


class FakeQPay(PaymentProvider):
    def __init__(self, rows): self.rows = rows
    async def invoice(self, order, callback_url): return {"invoice_id": "inv-1"}
    async def paid(self, invoice_id, amount):
        confirmed = sum((Decimal(str(row["amount"])) for row in self.rows if row["status"] == "PAID"), Decimal(0))
        return invoice_id == "inv-1" and confirmed == Decimal(amount)


@pytest.mark.asyncio
async def test_qpay_confirmation_requires_exact_server_amount():
    assert await FakeQPay([{"status":"PAID","amount":46000}]).paid("inv-1", 46000)
    assert not await FakeQPay([{"status":"PAID","amount":45000}]).paid("inv-1", 46000)
    assert not await FakeQPay([{"status":"PENDING","amount":46000}]).paid("inv-1", 46000)
