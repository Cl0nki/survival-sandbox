import os
import re

_BEARER = re.compile(r"(?i)(bearer\s+)[A-Za-z0-9\-._~+/]+=*")
_KEYISH = re.compile(r"\b(?:sk-[A-Za-z0-9]+|tsk_[A-Za-z0-9]+)\b")


def secret_values() -> list[str]:
    values = []
    for name in ("OPENAI_API_KEY", "MESHY_API_KEY", "TRIPO_API_KEY"):
        value = os.environ.get(name, "").strip()
        if len(value) >= 6:
            values.append(value)
    return values


def redact(text: str) -> str:
    if not text:
        return text
    cleaned = _BEARER.sub(r"\1[redacted]", text)
    cleaned = _KEYISH.sub("[redacted]", cleaned)
    for secret in secret_values():
        cleaned = cleaned.replace(secret, "[redacted]")
    return cleaned
