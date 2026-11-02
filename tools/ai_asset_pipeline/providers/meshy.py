import base64
import time
from pathlib import Path

from core.errors import ConfigError, ProviderError
from providers.http_client import download, request, request_json

BASE = "https://api.meshy.ai"
IMAGE_TO_3D = f"{BASE}/openapi/v1/image-to-3d"
TEXT_TO_3D = f"{BASE}/openapi/v2/text-to-3d"
RIGGING = f"{BASE}/openapi/v1/rigging"
TERMINAL = {"SUCCEEDED", "FAILED", "CANCELED"}


def image_to_3d_payload(image_png: bytes, polycount: int, texture_resolution: str, character: bool, ai_model: str) -> dict:
    encoded = base64.b64encode(image_png).decode("ascii")
    payload = {
        "image_url": f"data:image/png;base64,{encoded}",
        "ai_model": ai_model,
        "enable_pbr": True,
        "should_remesh": True,
        "should_texture": True,
        "save_pre_remeshed_model": True,
        "target_polycount": int(polycount),
        "target_formats": ["glb"],
        "texture_resolution": str(texture_resolution),
    }
    if character:
        payload["pose_mode"] = "a-pose"
    return payload


def text_preview_payload(prompt: str, polycount: int, character: bool, ai_model: str) -> dict:
    payload = {
        "mode": "preview",
        "prompt": prompt[:800],
        "ai_model": ai_model,
        "should_remesh": True,
        "target_polycount": int(polycount),
        "target_formats": ["glb"],
    }
    if character:
        payload["pose_mode"] = "a-pose"
    return payload


def text_refine_payload(preview_task_id: str) -> dict:
    return {
        "mode": "refine",
        "preview_task_id": preview_task_id,
        "enable_pbr": True,
        "target_formats": ["glb"],
    }


def rigging_payload(model_png_or_glb: bytes, height_meters: float) -> dict:
    encoded = base64.b64encode(model_png_or_glb).decode("ascii")
    return {
        "model_url": f"data:model/gltf-binary;base64,{encoded}",
        "height_meters": float(height_meters),
    }


class MeshyProvider:
    name = "meshy"

    def __init__(self, api_key: str, ai_model: str, timeout_sec: int, interval_sec: float):
        self.api_key = api_key
        self.ai_model = ai_model
        self.timeout_sec = timeout_sec
        self.interval_sec = interval_sec

    def require_key(self) -> None:
        if not self.api_key:
            raise ConfigError(
                "MESHY_API_KEY is not set. Create a key in the Meshy developer console "
                "and add it to tools/ai_asset_pipeline/.env. The key is only sent to api.meshy.ai."
            )

    def _headers(self) -> dict:
        self.require_key()
        return {"Authorization": f"Bearer {self.api_key}"}

    def _poll(self, url: str, progress) -> dict:
        deadline = time.monotonic() + self.timeout_sec
        while True:
            response = request("GET", url, self._headers(), timeout=60)
            task = response.json()
            status = task.get("status", "")
            if progress:
                progress(f"Meshy {status} {task.get('progress', 0)}%")
            if status in TERMINAL:
                if status != "SUCCEEDED":
                    message = (task.get("task_error") or {}).get("message") or status
                    raise ProviderError(f"Meshy task {task.get('id', '')} {status}: {message}")
                return task
            if time.monotonic() > deadline:
                raise ProviderError(f"Meshy task {task.get('id', '')} did not finish within {self.timeout_sec}s.")
            delay = response.retry_after() or self.interval_sec
            time.sleep(max(1.0, min(delay, 30.0)))

    def _create(self, url: str, payload: dict) -> str:
        # The logged payload must not include the data URI.
        response = request_json("POST", url, self._headers(), payload, timeout=120)
        task_id = response.json().get("result")
        if not task_id:
            raise ProviderError("Meshy did not return a task id.")
        return task_id

    def image_to_3d(self, image_path: Path, polycount: int, texture_resolution: str, character: bool, progress=None) -> dict:
        png = Path(image_path).read_bytes()
        if len(png) > 20 * 1024 * 1024:
            raise ProviderError("Concept image is over Meshy's 20 MB image limit.")
        payload = image_to_3d_payload(png, polycount, texture_resolution, character, self.ai_model)
        task_id = self._create(IMAGE_TO_3D, payload)
        task = self._poll(f"{IMAGE_TO_3D}/{task_id}", progress)
        return {"task": task, "model": self.ai_model, "parameters": _public_parameters(payload)}

    def text_to_3d(self, prompt: str, polycount: int, character: bool, progress=None) -> dict:
        preview_body = text_preview_payload(prompt, polycount, character, self.ai_model)
        preview_id = self._create(TEXT_TO_3D, preview_body)
        self._poll(f"{TEXT_TO_3D}/{preview_id}", progress)
        refine_body = text_refine_payload(preview_id)
        refine_id = self._create(TEXT_TO_3D, refine_body)
        task = self._poll(f"{TEXT_TO_3D}/{refine_id}", progress)
        return {
            "task": task,
            "model": self.ai_model,
            "parameters": {"preview": preview_body, "refine": refine_body, "preview_task_id": preview_id},
        }

    def rig(self, glb_path: Path, height_meters: float, progress=None) -> dict:
        data = Path(glb_path).read_bytes()
        if len(data) > 100 * 1024 * 1024:
            raise ProviderError("GLB is over Meshy's 100 MB data-URI rigging limit. Rig it in Blender instead.")
        payload = rigging_payload(data, height_meters)
        task_id = self._create(RIGGING, payload)
        task = self._poll(f"{RIGGING}/{task_id}", progress)
        return {"task": task, "model": "meshy-rigging", "parameters": {"height_meters": height_meters}}


def glb_url(task: dict) -> str:
    urls = task.get("model_urls") or {}
    if urls.get("glb"):
        return urls["glb"]
    result = task.get("result") or {}
    if isinstance(result, dict) and result.get("rigged_character_glb_url"):
        return result["rigged_character_glb_url"]
    raise ProviderError("Meshy task succeeded without a GLB URL.")


def download_named(urls: dict, folder: Path) -> list[str]:
    folder.mkdir(parents=True, exist_ok=True)
    written = []
    for name, url in urls.items():
        if not url or not isinstance(url, str) or not url.startswith("http"):
            continue
        target = folder / f"{name}.glb" if "glb" in name or name == "glb" else folder / f"{name}.png"
        if name in {"glb", "pre_remeshed_glb"} or name.endswith("glb_url"):
            target = folder / f"{name.replace('_url', '')}.glb"
        target.write_bytes(download(url))
        written.append(str(target))
    return written


def _public_parameters(payload: dict) -> dict:
    hidden = {"image_url", "model_url"}
    return {key: value for key, value in payload.items() if key not in hidden}
