import secrets
from fastapi import HTTPException
from redis.asyncio import Redis
from .config import settings
from .security import digest

redis = Redis.from_url(settings.redis_url, decode_responses=True)

RATE_SCRIPT = """
local value = redis.call('INCR', KEYS[1])
if value == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
return value
"""
VERIFY_SCRIPT = """
local value = redis.call('HGET', KEYS[1], 'hash')
if not value then return 'expired' end
local attempts = redis.call('HINCRBY', KEYS[1], 'attempts', 1)
if value == ARGV[1] then
  redis.call('DEL', KEYS[1]); return 'ok'
end
if attempts >= 5 then redis.call('DEL', KEYS[1]) end
return 'invalid'
"""


async def limit(key, maximum, seconds):
    count = await redis.eval(RATE_SCRIPT, 1, "rate:" + key, seconds)
    if count > maximum:
        raise HTTPException(429, "RATE_LIMITED", headers={"Retry-After": str(seconds)})


async def request_otp(phone, ip):
    await limit("otp-ip:" + digest(ip), 15, 600)
    await limit("otp-phone:" + digest(phone), 3, 600)
    if not await redis.set("otp-cooldown:" + digest(phone), "1", nx=True, ex=60):
        raise HTTPException(429, "OTP_WAIT", headers={"Retry-After": "60"})
    code = f"{secrets.randbelow(10000):04d}"
    key = "otp:" + digest(phone)
    async with redis.pipeline(transaction=True) as pipe:
        pipe.hset(key, mapping={"hash": digest(phone + ":" + code), "attempts": "0"})
        pipe.expire(key, 300)
        await pipe.execute()
    return code


async def verify_otp(phone, code, ip):
    await limit("verify-ip:" + digest(ip), 60, 600)
    result = await redis.eval(VERIFY_SCRIPT, 1, "otp:" + digest(phone), digest(phone + ":" + code))
    if result != "ok":
        raise HTTPException(400, "OTP_EXPIRED" if result == "expired" else "OTP_INVALID")
