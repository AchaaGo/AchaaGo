import pytest
from fastapi import HTTPException
from fakeredis.aioredis import FakeRedis
from app import cache


@pytest.mark.asyncio
async def test_otp_is_one_time_and_attempt_limited(monkeypatch):
    fake = FakeRedis(decode_responses=True)
    monkeypatch.setattr(cache, "redis", fake)
    monkeypatch.setattr(cache.secrets, "randbelow", lambda _: 1234)
    code = await cache.request_otp("+97699112233", "127.0.0.1")
    assert code == "1234"
    with pytest.raises(HTTPException) as wrong:
        await cache.verify_otp("+97699112233", "0000", "127.0.0.1")
    assert wrong.value.detail == "OTP_INVALID"
    await cache.verify_otp("+97699112233", "1234", "127.0.0.1")
    with pytest.raises(HTTPException) as reused:
        await cache.verify_otp("+97699112233", "1234", "127.0.0.1")
    assert reused.value.detail == "OTP_EXPIRED"
    await fake.aclose()
