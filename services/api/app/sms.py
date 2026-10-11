"""Request building for the configurable HTTP SMS provider.

Mongolian SMS gateways all differ in URL, auth and field names, and the
provider isn't chosen yet (AGENTS.md open question), so the request shape
comes from SMS_HTTP_* settings instead of code. Placeholders: {phone},
{message}, {sender}, {api_key}.

Standard library only, so the escaping rules are easy to test in isolation.
"""
import json
from urllib.parse import quote

PHONE_FORMATS = {"e164", "international", "local"}


def format_phone(phone: str, style: str) -> str:
    """Stored phones are E.164 (+976 and 8 digits); gateways want different shapes."""
    digits = phone.lstrip("+")
    if style == "e164":
        return "+" + digits
    if style == "international":
        return digits
    if style == "local":
        return digits[3:] if digits.startswith("976") else digits
    raise ValueError(f"Unknown phone format {style!r}")


def mask_phone(phone: str) -> str:
    """For logs: enough to tell messages apart, not enough to identify the customer."""
    return phone[:4] + "****" + phone[-4:] if len(phone) > 8 else "****"


def _substitute(text: str, values: dict) -> str:
    # Plain replacement, not str.format: templates may contain literal braces.
    for key, value in values.items():
        text = text.replace("{" + key + "}", str(value))
    return text


def fill_url(template: str, values: dict) -> str:
    """URL-encode every value, so a message with spaces, '&' or Cyrillic stays one parameter."""
    return _substitute(template, {key: quote(str(value), safe="") for key, value in values.items()})


def fill_json(template: str, values: dict):
    """Parse the JSON template first, then substitute inside its strings, so quotes
    or newlines in the message can never break the JSON."""
    def walk(node):
        if isinstance(node, str):
            return _substitute(node, values)
        if isinstance(node, list):
            return [walk(item) for item in node]
        if isinstance(node, dict):
            return {key: walk(item) for key, item in node.items()}
        return node
    return walk(json.loads(template))


def parse_json_object(value: str, name: str) -> dict:
    """Startup validation for the JSON-valued settings; empty means 'none'."""
    if not value:
        return {}
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError as error:
        raise ValueError(f"{name} is not valid JSON: {error.msg}") from None
    if not isinstance(parsed, dict):
        raise ValueError(f"{name} must be a JSON object")
    return parsed
