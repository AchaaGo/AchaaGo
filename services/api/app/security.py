import hashlib
import hmac
import secrets
from datetime import timedelta
import jwt
from fastapi import Depends, HTTPException, Request
from sqlalchemy import select
from .config import settings
from .db import get_db
from .models import User, RefreshSession, now


def digest(value: str):
    return hmac.new(settings.jwt_secret.encode(), value.encode(), hashlib.sha256).hexdigest()


def sign(payload: dict, seconds: int):
    return jwt.encode({**payload, "iat": now(), "exp": now() + timedelta(seconds=seconds),
                       "iss": "achaago", "aud": "achaago"}, settings.jwt_secret, algorithm="HS256")


def decode(token: str, kind="access"):
    try:
        claims = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"], issuer="achaago",
                            audience="achaago", options={"require": ["exp", "iat", "iss", "aud", "kind"]})
        if claims["kind"] != kind:
            raise ValueError("Wrong token type")
        return claims
    except (jwt.PyJWTError, ValueError):
        raise HTTPException(401, "SESSION_EXPIRED") from None


def user_json(user):
    return {"id": user.id, "phone": user.phone, "name": user.name, "role": user.role}


async def issue_tokens(db, user, response):
    access = sign({"sub": user.id, "kind": "access"}, 900)
    refresh = secrets.token_urlsafe(48)
    db.add(RefreshSession(id=digest(refresh), user_id=user.id, expires_at=now() + timedelta(days=30)))
    secure = settings.public_url.startswith("https://")
    response.set_cookie("ag_access", access, httponly=True, secure=secure, samesite="lax", max_age=900, path="/")
    response.set_cookie("ag_refresh", refresh, httponly=True, secure=secure, samesite="lax", max_age=2592000, path="/api/auth")
    return {"access_token": access, "refresh_token": refresh, "token_type": "bearer", "user": user_json(user)}


async def current_user(request: Request, db=Depends(get_db)):
    header = request.headers.get("authorization", "")
    token = header[7:] if header.startswith("Bearer ") else request.cookies.get("ag_access")
    if not token:
        raise HTTPException(401, "LOGIN_REQUIRED")
    claims = decode(token)
    user = await db.get(User, claims.get("sub", ""))
    if not user:
        raise HTTPException(401, "LOGIN_REQUIRED")
    return user


async def staff(user=Depends(current_user)):
    if user.role not in {"admin", "dispatcher"}:
        raise HTTPException(403, "STAFF_REQUIRED")
    return user


async def admin(user=Depends(staff)):
    if user.role != "admin":
        raise HTTPException(403, "ADMIN_REQUIRED")
    return user


async def find_user(db, phone):
    return (await db.execute(select(User).where(User.phone == phone))).scalar_one_or_none()
