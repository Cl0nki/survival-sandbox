import base64
import time
from pathlib import Path

from core.errors import ConfigError, ProviderError
from providers.base import (
    CAP_ANIMATE,
    CAP_GENERATE_MODEL,
    CAP_HUMANOID_RIG,
    CAP_RIG,
    credits_from_task,
    task_result,
)
from providers.http_client import download, request, request_json

BASE = "https://api.meshy.ai"
IMAGE_TO_3D = f"{BASE}/openapi/v1/image-to-3d"
TEXT_TO_3D = f"{BASE}/openapi/v2/text-to-3d"
RIGGING = f"{BASE}/openapi/v1/rigging"
ANIMATIONS = f"{BASE}/openapi/v1/animations"
BALANCE = f"{BASE}/openapi/v1/balance"
TERMINAL = {"SUCCEEDED", "FAILED", "CANCELED"}

OPERATION_URLS = {
    "image_to_3d": IMAGE_TO_3D,
    "text_to_3d": TEXT_TO_3D,
    "rigging": RIGGING,
    "animation": ANIMATIONS,
}


def normalize_texture_resolution(value) -> str:
    """Meshy currently accepts 2k / 4k / 8k only."""
    text = str(value or "2k").strip().lower()
    aliases = {
        "1024": "2k",
        "1k": "2k",
        "2048": "2k",
        "2k": "2k",
        "4096": "4k",
        "4k": "4k",
        "8192": "8k",
        "8k": "8k",
    }
    if text not in aliases:
        raise ProviderError("Meshy texture_resolution must be one of 2k, 4k, or 8k.")
    return aliases[text]


def image_to_3d_payload(image_png: bytes, polycount: int, texture_resolution: str, character: bool, ai_model: str, auto_size: bool = False) -> dict:
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
        "texture_resolution": normalize_texture_resolution(texture_resolution),
    }
    if character:
        payload["pose_mode"] = "a-pose"
    elif auto_size:
        # Meshy estimates a real-world height from the picture and scales the mesh to it.
        payload["auto_size"] = True
        payload["origin_at"] = "bottom"
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


def animation_payload(rig_task_id: str, action_id=None, action_ids=None, motion_task_id=None) -> dict:
    payload = {"rig_task_id": str(rig_task_id)}
    chosen = [value for value in (action_id, action_ids, motion_task_id) if value not in (None, "", [])]
    if len(chosen) != 1:
        raise ProviderError("Meshy animation needs exactly one of action_id, action_ids, or motion_task_id.")
    if action_ids is not None:
        ids = [int(item) for item in action_ids]
        if not ids or len(ids) > 10 or len(ids) != len(set(ids)):
            raise ProviderError("Meshy action_ids must be 1–10 unique integers.")
        payload["action_ids"] = ids
    elif action_id is not None:
        payload["action_id"] = int(action_id)
    else:
        payload["motion_task_id"] = str(motion_task_id)
    return payload


class MeshyProvider:
    name = "meshy"
    capabilities = frozenset({CAP_GENERATE_MODEL, CAP_RIG, CAP_HUMANOID_RIG, CAP_ANIMATE})

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

    def _operation_url(self, operation: str) -> str:
        url = OPERATION_URLS.get(operation)
        if not url:
            raise ProviderError(f"Unknown Meshy operation '{operation}'. Known: {', '.join(sorted(OPERATION_URLS))}")
        return url

    def generate_model(self, input_data: dict, progress=None) -> dict:
        image_path = str(input_data.get("image_path") or "").strip()
        prompt = str(input_data.get("prompt") or "").strip()
        polycount = int(input_data.get("polycount") or 8000)
        character = bool(input_data.get("character"))
        texture_resolution = str(input_data.get("texture_resolution") or "2k")
        if image_path:
            legacy = self.image_to_3d(Path(image_path), polycount, texture_resolution, character, progress)
            task = legacy["task"]
            return task_result(
                provider=self.name,
                operation="image_to_3d",
                provider_task_id=task.get("id", ""),
                status=task.get("status", "SUCCEEDED"),
                model=legacy["model"],
                parameters=legacy["parameters"],
                task=task,
                consumed_credits=credits_from_task(task),
            )
        if not prompt:
            raise ProviderError("Meshy generate_model needs image_path or prompt.")
        legacy = self.text_to_3d(prompt, polycount, character, progress)
        task = legacy["task"]
        return task_result(
            provider=self.name,
            operation="text_to_3d",
            provider_task_id=task.get("id", ""),
            status=task.get("status", "SUCCEEDED"),
            model=legacy["model"],
            parameters=legacy["parameters"],
            task=task,
            consumed_credits=credits_from_task(task),
        )

    def generate_texture(self, input_data: dict, progress=None) -> dict:
        raise ProviderError(
            "Meshy texturing is bundled in image-to-3D / text-to-3D refine (should_texture / enable_pbr). "
            "A separate remesh/texture pass is not wired yet."
        )

    def rig_model(self, input_data: dict, progress=None) -> dict:
        glb_path = Path(str(input_data.get("glb_path") or ""))
        height = float(input_data.get("height_meters") or 1.8)
        if not glb_path.is_file():
            raise ProviderError("Meshy rig_model needs a local glb_path.")
        legacy = self.rig(glb_path, height, progress)
        task = legacy["task"]
        return task_result(
            provider=self.name,
            operation="rigging",
            provider_task_id=task.get("id", ""),
            status=task.get("status", "SUCCEEDED"),
            model=legacy["model"],
            parameters=legacy["parameters"],
            task=task,
            consumed_credits=credits_from_task(task),
        )

    def animate_model(self, input_data: dict, progress=None) -> dict:
        rig_task_id = str(input_data.get("rig_task_id") or "").strip()
        if not rig_task_id:
            raise ProviderError("Meshy animate_model needs rig_task_id from a succeeded rigging task.")
        payload = animation_payload(
            rig_task_id,
            action_id=input_data.get("action_id"),
            action_ids=input_data.get("action_ids"),
            motion_task_id=input_data.get("motion_task_id"),
        )
        task_id = self._create(ANIMATIONS, payload)
        task = self._poll(f"{ANIMATIONS}/{task_id}", progress)
        return task_result(
            provider=self.name,
            operation="animation",
            provider_task_id=task.get("id", task_id),
            status=task.get("status", "SUCCEEDED"),
            model="meshy-animation",
            parameters=payload,
            task=task,
            consumed_credits=credits_from_task(task),
        )

    def get_task_status(self, operation: str, task_id: str) -> dict:
        url = f"{self._operation_url(operation)}/{task_id}"
        task = request("GET", url, self._headers(), timeout=60).json()
        return {
            "provider": self.name,
            "operation": operation,
            "provider_task_id": task_id,
            "status": task.get("status", ""),
            "progress": task.get("progress"),
            "consumed_credits": credits_from_task(task),
            "task": task,
        }

    def download_result(self, operation: str, task_id: str, folder: Path) -> dict:
        status = self.get_task_status(operation, task_id)
        task = status["task"]
        if task.get("status") != "SUCCEEDED":
            raise ProviderError(f"Meshy task {task_id} is {task.get('status')}, not SUCCEEDED.")
        folder = Path(folder)
        folder.mkdir(parents=True, exist_ok=True)
        written = []
        if operation in {"image_to_3d", "text_to_3d"}:
            url = glb_url(task)
            target = folder / "model.glb"
            target.write_bytes(download(url))
            written.append(str(target))
            urls = task.get("model_urls") or {}
            written.extend(download_named({k: v for k, v in urls.items() if k != "glb"}, folder))
            thumb = task.get("thumbnail_url")
            if thumb:
                preview = folder / "thumbnail.png"
                preview.write_bytes(download(thumb))
                written.append(str(preview))
        elif operation == "rigging":
            result = task.get("result") or {}
            for key, name in (
                ("rigged_character_glb_url", "rigged.glb"),
                ("walking_glb_url", "walking.glb"),
                ("running_glb_url", "running.glb"),
            ):
                url = result.get(key) or (result.get("basic_animations") or {}).get(key)
                if url:
                    target = folder / name
                    target.write_bytes(download(url))
                    written.append(str(target))
        elif operation == "animation":
            result = task.get("result") or {}
            for key, name in (
                ("animation_glb_url", "animation.glb"),
                ("animation_fbx_url", "animation.fbx"),
            ):
                url = result.get(key)
                if url:
                    target = folder / name
                    target.write_bytes(download(url))
                    written.append(str(target))
        else:
            raise ProviderError(f"No Meshy download handler for operation '{operation}'.")
        if not written:
            raise ProviderError(f"Meshy task {task_id} succeeded without downloadable files.")
        return {"files": written, "task": task, "consumed_credits": credits_from_task(task)}

    def get_balance(self) -> dict:
        payload = request("GET", BALANCE, self._headers(), timeout=60).json()
        return {"provider": self.name, "balance": payload}

    def list_animation_library(self, page_size: int = 50) -> dict:
        url = f"{ANIMATIONS}/library?page_size={int(page_size)}"
        payload = request("GET", url, self._headers(), timeout=60).json()
        return payload

    def image_to_3d(self, image_path: Path, polycount: int, texture_resolution: str, character: bool, progress=None, auto_size: bool = False) -> dict:
        png = Path(image_path).read_bytes()
        if len(png) > 20 * 1024 * 1024:
            raise ProviderError("Concept image is over Meshy's 20 MB image limit.")
        payload = image_to_3d_payload(png, polycount, texture_resolution, character, self.ai_model, auto_size=auto_size)
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
