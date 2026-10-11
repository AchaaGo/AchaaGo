"""Error alerts: forward ERROR-level log records to the team's Telegram chat.

ALERT_PROVIDER=console (the default) leaves logging alone; telegram needs
TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID. Anything logged at ERROR or above
(unhandled request errors, failed Celery tasks, dropped outbox messages, a
stale background worker) becomes one message. The same problem alerts at
most once per cooldown, so a crash loop can't flood the chat.

Standard library only, and it never raises: a broken alert channel must not
take requests down with it.
"""
import json
import logging
import threading
import time
import traceback
import urllib.request

_installed = None


def format_alert(record: logging.LogRecord, label: str, limit: int = 3500) -> str:
    text = f"[{label}] {record.levelname} in {record.name}\n{record.getMessage()}"
    if record.exc_info:
        # The tail of the traceback is where the cause is; Telegram caps messages at 4096 chars.
        text += "\n\n" + "".join(traceback.format_exception(*record.exc_info))[-2000:]
    return text[:limit]


class AlertHandler(logging.Handler):
    def __init__(self, send, label: str, cooldown: float = 600, clock=time.monotonic, background: bool = True):
        super().__init__(level=logging.ERROR)
        self.send, self.label, self.cooldown, self.clock, self.background = send, label, cooldown, clock, background
        self._last_sent: dict = {}
        self._lock = threading.Lock()

    def should_send(self, record: logging.LogRecord) -> bool:
        if record.name == __name__:
            return False  # never alert about alerting
        # Key on the message template, not the formatted text: one bug with
        # changing ids in its message is still one alert per cooldown.
        key = (record.name, str(record.msg))
        now = self.clock()
        with self._lock:
            last = self._last_sent.get(key)
            if last is not None and now - last < self.cooldown:
                return False
            if len(self._last_sent) > 500:
                self._last_sent.clear()
            self._last_sent[key] = now
        return True

    def emit(self, record):
        try:
            if not self.should_send(record):
                return
            text = format_alert(record, self.label)
        except Exception:
            return
        if self.background:
            threading.Thread(target=self._deliver, args=(text,), daemon=True).start()
        else:
            self._deliver(text)

    def _deliver(self, text):
        try:
            self.send(text)
        except Exception as error:
            # Type only: urllib errors can carry the request URL, which contains the bot token.
            logging.getLogger(__name__).warning("Alert delivery failed (%s)", type(error).__name__)


def telegram_sender(bot_token: str, chat_id: str, timeout: float = 5):
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"

    def send(text: str):
        body = json.dumps({"chat_id": chat_id, "text": text, "disable_web_page_preview": True}).encode()
        request = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=timeout) as response:
            response.read()
    return send


def install(provider: str, bot_token: str = "", chat_id: str = "", label: str = "AchaaGo"):
    """Attach the alert handler to the root logger once per process."""
    global _installed
    if provider != "telegram":
        return None
    if _installed is None:
        _installed = AlertHandler(telegram_sender(bot_token, chat_id), label)
    root = logging.getLogger()
    if _installed not in root.handlers:  # Celery's worker resets root handlers; re-adding is safe.
        root.addHandler(_installed)
    return _installed
