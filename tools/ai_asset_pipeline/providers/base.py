"""Shared 3D provider types. Provider-specific HTTP stays in adapter modules."""

from __future__ import annotations

from pathlib import Path
from typing import Callable, Protocol, runtime_checkable

ProgressFn = Callable[[str], None] | None

# Capability flags returned by adapters and registry status.
CAP_GENERATE_MODEL = "generate_model"
CAP_GENERATE_TEXTURE = "generate_texture"
CAP_RIG = "rig_model"
CAP_ANIMATE = "animate_model"
CAP_HUMANOID_RIG = "humanoid_rig"
CAP_ALT_RIG = "alt_rig"


def task_result(
    *,
    provider: str,
    operation: str,
    provider_task_id: str,
    status: str,
    model: str,
    parameters: dict,
    task: dict,
    consumed_credits=None,
) -> dict:
    result = {
        "provider": provider,
        "operation": operation,
        "provider_task_id": str(provider_task_id or ""),
        "status": status,
        "model": model,
        "parameters": parameters or {},
        "task": task or {},
    }
    if consumed_credits is not None:
        result["consumed_credits"] = consumed_credits
    elif isinstance(task, dict) and "consumed_credits" in task:
        result["consumed_credits"] = task.get("consumed_credits")
    return result


def credits_from_task(task: dict | None):
    if not isinstance(task, dict):
        return None
    if "consumed_credits" in task:
        try:
            return int(task.get("consumed_credits") or 0)
        except (TypeError, ValueError):
            return None
    return None


@runtime_checkable
class ThreeDProvider(Protocol):
    """Common surface for mesh providers. Optional methods raise ProviderError when unsupported."""

    name: str
    capabilities: frozenset[str]

    def generate_model(self, input_data: dict, progress: ProgressFn = None) -> dict:
        """Create a textured (or untextured) mesh from image_path and/or prompt."""

    def get_task_status(self, operation: str, task_id: str) -> dict:
        """Poll a provider task. Returns {status, progress, task, consumed_credits?}."""

    def download_result(self, operation: str, task_id: str, folder: Path) -> dict:
        """Download durable local copies. Returns {files: [paths], task: dict}."""

    def generate_texture(self, input_data: dict, progress: ProgressFn = None) -> dict:
        ...

    def rig_model(self, input_data: dict, progress: ProgressFn = None) -> dict:
        ...

    def animate_model(self, input_data: dict, progress: ProgressFn = None) -> dict:
        ...
