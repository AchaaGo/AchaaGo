"""Create the project's development environment without printing credentials."""
import pathlib
import secrets
import sys

root = pathlib.Path(__file__).resolve().parents[1]
path = root / ".env"
if path.exists():
    raise SystemExit(".env already exists; leaving it unchanged")
public_url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8187"
text = (root / ".env.example").read_text()
text = text.replace("replace-with-a-random-password", secrets.token_hex(24))
text = text.replace("replace-with-at-least-32-random-characters", secrets.token_hex(48))
text = text.replace("http://localhost:8187", public_url)
with path.open("x", opener=lambda p, flags: __import__("os").open(p, flags, 0o600)) as output:
    output.write(text)
print("Created project-local .env with unique secrets (not displayed).")
