import base64
import uuid
from pathlib import Path

from core.errors import ConfigError, ProviderError
from providers.http_client import request, request_json

API_URL = "https://api.openai.com/v1/images/generations"
EDITS_URL = "https://api.openai.com/v1/images/edits"

# Sizes accepted by the documented Images API. Larger pipeline sizes are resized locally.
PROVIDER_SIZES = {
    512: "1024x1024",
    1024: "1024x1024",
    2048: "2048x2048",
    4096: "2048x2048",
}


def generation_payload(prompt: str, model: str, resolution: int, quality: str, transparent: bool = False) -> dict:
    size = PROVIDER_SIZES.get(resolution, "1024x1024")
    payload = {
        "model": model,
        "prompt": prompt[:32000],
        "size": size,
        "n": 1,
    }
    if model.startswith("gpt-image"):
        payload["quality"] = quality if quality in {"low", "medium", "high", "auto"} else "medium"
        payload["output_format"] = "png"
        if transparent:
            payload["background"] = "transparent"
    elif model in {"dall-e-2", "dall-e-3"}:
        payload["response_format"] = "b64_json"
        payload["size"] = "1024x1024"
    return payload


def edit_multipart(model: str, prompt: str, images: list[tuple[str, bytes]], resolution: int, quality: str, transparent: bool = False) -> tuple[str, bytes]:
    if not images:
        raise ProviderError("A reference image is required for an image edit.")
    if len(images) > 16:
        raise ProviderError("OpenAI accepts at most 16 reference images.")
    boundary = f"----pipeline{uuid.uuid4().hex}"
    chunks: list[bytes] = []

    def text(name: str, value: str) -> None:
        chunks.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode("utf-8")
        )

    def file(filename: str, data: bytes) -> None:
        safe = Path(filename).name.replace('"', "") or "reference.png"
        head = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="image[]"; filename="{safe}"\r\n'
            "Content-Type: image/png\r\n\r\n"
        ).encode("utf-8")
        chunks.append(head + data + b"\r\n")

    text("model", model)
    text("prompt", prompt[:32000])
    text("n", "1")
    text("size", PROVIDER_SIZES.get(resolution, "1024x1024"))
    if model.startswith("gpt-image"):
        text("quality", quality if quality in {"low", "medium", "high", "auto"} else "medium")
        text("output_format", "png")
        if transparent:
            text("background", "transparent")
    for filename, data in images:
        file(filename, data)
    chunks.append(f"--{boundary}--\r\n".encode("utf-8"))
    return f"multipart/form-data; boundary={boundary}", b"".join(chunks)


class OpenAIImageProvider:
    name = "openai"

    def __init__(self, api_key: str, model: str):
        self.api_key = api_key
        self.model = model

    def require_key(self) -> None:
        if not self.api_key:
            raise ConfigError(
                "OPENAI_API_KEY is not set. Add it to tools/ai_asset_pipeline/.env. "
                "Texture jobs can use the procedural provider without this key. "
                "Prop and character concept images need an image provider."
            )

    def generate_png(self, prompt: str, destination: Path, resolution: int, quality: str, transparent: bool = False) -> dict:
        self.require_key()
        payload = generation_payload(prompt, self.model, resolution, quality, transparent)
        response = request_json(
            "POST",
            API_URL,
            {"Authorization": f"Bearer {self.api_key}"},
            payload,
            timeout=180,
        )
        return self._write_png(response.json(), destination, {key: value for key, value in payload.items() if key != "prompt"}, resolution)

    def edit_png(self, prompt: str, images: list[tuple[str, bytes]], destination: Path, resolution: int, quality: str, transparent: bool = False) -> dict:
        self.require_key()
        content_type, body = edit_multipart(self.model, prompt, images, resolution, quality, transparent)
        response = request(
            "POST",
            EDITS_URL,
            {"Authorization": f"Bearer {self.api_key}", "Content-Type": content_type},
            body,
            timeout=180,
        )
        parameters = {"output_format": "png", "reference_images": len(images)}
        if transparent:
            parameters["background"] = "transparent"
        return self._write_png(response.json(), destination, parameters, resolution)

    def _write_png(self, data: dict, destination: Path, parameters: dict, resolution: int) -> dict:
        items = data.get("data") or []
        if not items:
            raise ProviderError("OpenAI image response did not contain an image.")
        item = items[0]
        if item.get("b64_json"):
            raw = base64.b64decode(item["b64_json"])
        elif item.get("url"):
            from providers.http_client import download

            raw = download(item["url"])
        else:
            raise ProviderError("OpenAI image response had neither b64_json nor url.")
        if not raw.startswith(b"\x89PNG"):
            raise ProviderError("OpenAI did not return a PNG.")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(raw)
        return {
            "model": self.model,
            "seed": None,
            "seed_supported": False,
            "parameters": parameters,
            "provider_resolution": parameters.get("size", PROVIDER_SIZES.get(resolution, "1024x1024")),
            "upscaled_from": 2048 if resolution == 4096 else None,
        }
