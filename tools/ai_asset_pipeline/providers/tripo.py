import json
import time
import uuid
from pathlib import Path

from core.errors import ConfigError, ProviderError
from providers.base import (
    CAP_ALT_RIG,
    CAP_GENERATE_MODEL,
    CAP_RIG,
    credits_from_task,
    task_result,
)
from providers.http_client import download, request, request_json

BASE = "https://api.tripo3d.ai/v2/openapi"
UPLOAD = f"{BASE}/upload/sts"
TASK = f"{BASE}/task"
ONGOING = {"queued", "running"}
SUCCESS = {"success"}
FAILED = {"failed", "banned", "expired", "cancelled", "canceled"}


def image_to_model_payload(file_token: str, file_type: str, model_version: str, polycount: int, seed: int | None) -> dict:
    payload = {
        "type": "image_to_model",
        "model_version": model_version,
        "file": {"type": file_type, "file_token": file_token},
        "face_limit": int(polycount),
        "texture": True,
        "pbr": True,
    }
    if seed is not None:
        payload["model_seed"] = int(seed)
        payload["texture_seed"] = int(seed)
    return payload


def animate_rig_payload(
    original_model_task_id: str,
    *,
    out_format: str = "glb",
    model_version: str | None = None,
    rig_type: str = "biped",
    spec: str = "tripo",
) -> dict:
    payload = {
        "type": "animate_rig",
        "original_model_task_id": str(original_model_task_id),
        "out_format": out_format if out_format in {"glb", "fbx"} else "glb",
        "rig_type": str(rig_type or "biped"),
        "spec": str(spec or "tripo"),
    }
    if model_version:
        payload["model_version"] = model_version
    return payload


def animate_retarget_payload(original_model_task_id: str, animation: str, out_format: str = "glb") -> dict:
    return {
        "type": "animate_retarget",
        "original_model_task_id": str(original_model_task_id),
        "animation": str(animation),
        "out_format": out_format if out_format in {"glb", "fbx"} else "glb",
    }


class TripoProvider:
    name = "tripo"
    capabilities = frozenset({CAP_GENERATE_MODEL, CAP_RIG, CAP_ALT_RIG})

    def __init__(self, api_key: str, model_version: str, timeout_sec: int, interval_sec: float):
        self.api_key = api_key
        self.model_version = model_version
        self.timeout_sec = timeout_sec
        self.interval_sec = interval_sec

    def require_key(self) -> None:
        if not self.api_key:
            raise ConfigError(
                "TRIPO_API_KEY is not set. Create a key in the Tripo developer console "
                "and add it to tools/ai_asset_pipeline/.env. The key is only sent to api.tripo3d.ai."
            )

    def _headers(self, content_type: str | None = None) -> dict:
        self.require_key()
        headers = {"Authorization": f"Bearer {self.api_key}"}
        if content_type:
            headers["Content-Type"] = content_type
        return headers

    def upload_image(self, image_path: Path) -> str:
        data = Path(image_path).read_bytes()
        if len(data) > 20 * 1024 * 1024:
            raise ProviderError("Concept image is over Tripo's 20 MB upload limit.")
        suffix = Path(image_path).suffix.lower().lstrip(".") or "png"
        if suffix == "jpg":
            suffix = "jpeg"
        boundary = f"----pipeline{uuid.uuid4().hex}"
        filename = f"concept.{suffix}"
        mime = "image/png" if suffix == "png" else "image/jpeg"
        head = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
            f"Content-Type: {mime}\r\n\r\n"
        ).encode("utf-8")
        body = head + data + f"\r\n--{boundary}--\r\n".encode("utf-8")
        response = request(
            "POST",
            UPLOAD,
            self._headers(f"multipart/form-data; boundary={boundary}"),
            body,
            timeout=120,
        )
        payload = response.json()
        if payload.get("code") not in (0, None):
            raise ProviderError(f"Tripo upload failed: {payload.get('message') or payload.get('code')}")
        token = (payload.get("data") or {}).get("image_token")
        if not token:
            raise ProviderError("Tripo upload did not return image_token.")
        return token

    def generate_model(self, input_data: dict, progress=None) -> dict:
        image_path = str(input_data.get("image_path") or "").strip()
        if not image_path:
            raise ProviderError("Tripo generate_model currently needs image_path (image_to_model).")
        seed = input_data.get("seed")
        polycount = int(input_data.get("polycount") or 8000)
        legacy = self.image_to_3d(Path(image_path), polycount, seed, progress)
        task = legacy["task"]
        return task_result(
            provider=self.name,
            operation="image_to_model",
            provider_task_id=task.get("task_id", ""),
            status=task.get("status", "success"),
            model=legacy["model"],
            parameters=legacy["parameters"],
            task=task,
            consumed_credits=credits_from_task(task),
        )

    def generate_texture(self, input_data: dict, progress=None) -> dict:
        raise ProviderError(
            "Tripo texturing is bundled in image_to_model (texture/pbr). "
            "A separate texture task is not wired in this phase."
        )

    def rig_model(self, input_data: dict, progress=None) -> dict:
        original_task_id = str(input_data.get("original_model_task_id") or input_data.get("provider_task_id") or "").strip()
        if not original_task_id:
            raise ProviderError(
                "Tripo rig_model needs original_model_task_id from a prior image_to_model task. "
                "It does not accept an arbitrary local GLB upload for animate_rig."
            )
        payload = animate_rig_payload(
            original_task_id,
            out_format=str(input_data.get("out_format") or "glb"),
            model_version=str(input_data.get("model_version") or "") or None,
            rig_type=str(input_data.get("rig_type") or "biped"),
            spec=str(input_data.get("spec") or "tripo"),
        )
        response = request_json("POST", TASK, self._headers(), payload, timeout=120)
        created = response.json()
        if created.get("code") not in (0, None):
            raise ProviderError(f"Tripo animate_rig create failed: {json.dumps(created)[:500]}")
        task_id = (created.get("data") or {}).get("task_id")
        if not task_id:
            raise ProviderError("Tripo animate_rig did not return task_id.")
        task = self._poll(task_id, progress)
        return task_result(
            provider=self.name,
            operation="animate_rig",
            provider_task_id=task.get("task_id", task_id),
            status=task.get("status", "success"),
            model=payload.get("model_version") or "tripo-animate_rig",
            parameters=payload,
            task=task,
            consumed_credits=credits_from_task(task),
        )

    def animate_model(self, input_data: dict, progress=None) -> dict:
        original_task_id = str(input_data.get("original_model_task_id") or input_data.get("provider_task_id") or "").strip()
        animation = str(input_data.get("animation") or "").strip()
        if not original_task_id or not animation:
            raise ProviderError("Tripo animate_model needs original_model_task_id and animation preset name.")
        payload = animate_retarget_payload(
            original_task_id,
            animation,
            out_format=str(input_data.get("out_format") or "glb"),
        )
        response = request_json("POST", TASK, self._headers(), payload, timeout=120)
        created = response.json()
        if created.get("code") not in (0, None):
            raise ProviderError(f"Tripo animate_retarget create failed: {json.dumps(created)[:500]}")
        task_id = (created.get("data") or {}).get("task_id")
        if not task_id:
            raise ProviderError("Tripo animate_retarget did not return task_id.")
        task = self._poll(task_id, progress)
        return task_result(
            provider=self.name,
            operation="animate_retarget",
            provider_task_id=task.get("task_id", task_id),
            status=task.get("status", "success"),
            model="tripo-animate_retarget",
            parameters=payload,
            task=task,
            consumed_credits=credits_from_task(task),
        )

    def get_task_status(self, operation: str, task_id: str) -> dict:
        response = request("GET", f"{TASK}/{task_id}", self._headers(), timeout=60)
        body = response.json()
        data = body.get("data") or body
        return {
            "provider": self.name,
            "operation": operation,
            "provider_task_id": task_id,
            "status": data.get("status", ""),
            "progress": data.get("progress"),
            "consumed_credits": credits_from_task(data),
            "task": data,
        }

    def download_result(self, operation: str, task_id: str, folder: Path) -> dict:
        status = self.get_task_status(operation, task_id)
        task = status["task"]
        if task.get("status") not in SUCCESS:
            raise ProviderError(f"Tripo task {task_id} is {task.get('status')}, not success.")
        folder = Path(folder)
        folder.mkdir(parents=True, exist_ok=True)
        written = []
        target = folder / "model.glb"
        target.write_bytes(download(model_url(task)))
        written.append(str(target))
        preview_url = rendered_image_url(task)
        if preview_url:
            preview = folder / "thumbnail.png"
            preview.write_bytes(download(preview_url))
            written.append(str(preview))
        return {"files": written, "task": task, "consumed_credits": credits_from_task(task)}

    def image_to_3d(self, image_path: Path, polycount: int, seed: int | None, progress=None) -> dict:
        token = self.upload_image(image_path)
        suffix = Path(image_path).suffix.lower().lstrip(".") or "png"
        if suffix == "jpeg":
            suffix = "jpg"
        payload = image_to_model_payload(
            token,
            suffix if suffix in {"png", "jpg", "webp"} else "png",
            self.model_version,
            polycount,
            seed,
        )
        response = request_json("POST", TASK, self._headers(), payload, timeout=120)
        created = response.json()
        if created.get("code") not in (0, None):
            raise ProviderError(f"Tripo task create failed: {json.dumps(created)[:500]}")
        task_id = (created.get("data") or {}).get("task_id")
        if not task_id:
            raise ProviderError("Tripo did not return task_id.")
        task = self._poll(task_id, progress)
        return {"task": task, "model": self.model_version, "parameters": payload}

    def _poll(self, task_id: str, progress) -> dict:
        deadline = time.monotonic() + self.timeout_sec
        while True:
            response = request("GET", f"{TASK}/{task_id}", self._headers(), timeout=60)
            body = response.json()
            data = body.get("data") or body
            status = data.get("status", "")
            if progress:
                progress(f"Tripo {status} {data.get('progress', 0)}%")
            if status in SUCCESS:
                return data
            if status in FAILED:
                raise ProviderError(f"Tripo task {task_id} {status}.")
            if status not in ONGOING and status not in {"", "unknown"}:
                raise ProviderError(f"Tripo task {task_id} returned unrecognized status {status}.")
            if time.monotonic() > deadline:
                raise ProviderError(f"Tripo task {task_id} did not finish within {self.timeout_sec}s.")
            time.sleep(self.interval_sec)


def model_url(task: dict) -> str:
    output = task.get("output") or {}
    for key in ("pbr_model", "model", "model_url", "base_model"):
        value = output.get(key)
        if isinstance(value, str) and value.startswith("http"):
            return value
    raise ProviderError("Tripo task succeeded without a model URL. Output keys: " + ", ".join(output.keys()))


def rendered_image_url(task: dict) -> str:
    output = task.get("output") or {}
    for key in ("rendered_image", "rendered_image_url"):
        value = output.get(key)
        if isinstance(value, str) and value.startswith("http"):
            return value
    return ""


def download_url(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(download(url))
