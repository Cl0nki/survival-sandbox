import json
import urllib.error
import urllib.request

from core.errors import ProviderError
from core.redact import redact


class HttpResponse:
    def __init__(self, status: int, headers, body: bytes):
        self.status = status
        self.headers = headers
        self.body = body

    def json(self) -> dict:
        if not self.body:
            return {}
        return json.loads(self.body.decode("utf-8"))

    def retry_after(self) -> float | None:
        value = self.headers.get("Retry-After") if self.headers else None
        if not value:
            return None
        try:
            return float(value)
        except ValueError:
            return None


def request(method: str, url: str, headers: dict | None = None, body: bytes | None = None, timeout: float = 120) -> HttpResponse:
    if not url.startswith("https://") and not url.startswith("http://"):
        raise ProviderError(f"Refusing non-HTTP URL scheme for {url.split(':', 1)[0]}")
    outgoing = dict(headers or {})
    req = urllib.request.Request(url, data=body, headers=outgoing, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return HttpResponse(response.status, response.headers, response.read())
    except urllib.error.HTTPError as exc:
        payload = exc.read()
        text = redact(payload.decode("utf-8", errors="replace")[:2000])
        raise ProviderError(f"{method} {url.split('?', 1)[0]} returned HTTP {exc.code}: {text}") from None
    except urllib.error.URLError as exc:
        raise ProviderError(f"{method} {url.split('?', 1)[0]} failed: {redact(str(exc.reason))}") from None


def request_json(method: str, url: str, headers: dict, payload: dict | None = None, timeout: float = 120) -> HttpResponse:
    body = None
    outgoing = dict(headers)
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        outgoing["Content-Type"] = "application/json"
    return request(method, url, outgoing, body, timeout)


def download(url: str, timeout: float = 180) -> bytes:
    response = request("GET", url, timeout=timeout)
    if response.status >= 400:
        raise ProviderError(f"Download failed with HTTP {response.status}")
    return response.body
