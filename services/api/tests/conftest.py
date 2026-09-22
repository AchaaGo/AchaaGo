import os
os.environ.setdefault("JWT_SECRET", "test-secret-that-is-at-least-thirty-two-characters")
os.environ.setdefault("DATABASE_URL", "sqlite+aiosqlite:////tmp/achaago-tests.db")
