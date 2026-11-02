import io
import json
import re
import uuid

from PIL import Image

from core.errors import PipelineError

SHOT_NAME = re.compile(r"shot-[0-9a-f]{16}\.png")
MAX_SHOTS = 16


def style_image_prompt(text: str) -> str:
    prompt = " ".join(str(text or "").split())
    if not prompt:
        raise PipelineError("Write a prompt for the style image.")
    return prompt[:4000]


def screenshots_dir(settings):
    return settings.style_reference().parent / "screenshots"


def screenshot_file(settings, name: str):
    if not SHOT_NAME.fullmatch(str(name or "")):
        raise PipelineError("Unknown screenshot.")
    root = screenshots_dir(settings).resolve()
    target = (root / name).resolve()
    if target.parent != root:
        raise PipelineError("Unknown screenshot.")
    return target


def listed_screenshots(settings) -> list[str]:
    names = []
    for name in settings.style().get("image_screenshots") or []:
        try:
            path = screenshot_file(settings, name)
        except PipelineError:
            continue
        if path.is_file():
            names.append(path.name)
    return names


def _write_style(settings, style: dict) -> None:
    settings.style_path.write_text(json.dumps(style, indent=2) + "\n", encoding="utf-8")


def add_style_screenshots(settings, blobs: list[bytes]) -> dict:
    if not blobs:
        raise PipelineError("Choose a screenshot to add.")
    current = listed_screenshots(settings)
    if len(current) + len(blobs) > MAX_SHOTS:
        raise PipelineError("The style prompt can include at most 16 screenshots.")
    folder = screenshots_dir(settings)
    folder.mkdir(parents=True, exist_ok=True)
    added = []
    try:
        for blob in blobs:
            if len(blob) > 15 * 1024 * 1024:
                raise PipelineError("Each screenshot must be under 15 MB.")
            try:
                with Image.open(io.BytesIO(blob)) as image:
                    image.load()
                    converted = image.convert("RGBA")
                    if max(converted.size) > 2048:
                        converted.thumbnail((2048, 2048), Image.Resampling.LANCZOS)
                    name = f"shot-{uuid.uuid4().hex[:16]}.png"
                    converted.save(folder / name, format="PNG")
            except PipelineError:
                raise
            except Exception:
                raise PipelineError("That file is not a PNG, JPEG, or WEBP image.") from None
            added.append(name)
    except PipelineError:
        for name in added:
            (folder / name).unlink(missing_ok=True)
        raise
    style = settings.style()
    style["image_screenshots"] = current + added
    _write_style(settings, style)
    return {"screenshots": style["image_screenshots"]}


def remove_style_screenshot(settings, name: str) -> dict:
    path = screenshot_file(settings, name)
    if path.is_file():
        path.unlink()
    style = settings.style()
    style["image_screenshots"] = [item for item in listed_screenshots(settings) if item != name]
    _write_style(settings, style)
    return {"screenshots": style["image_screenshots"]}


def generate_style_candidate(settings, prompt: str, provider) -> dict:
    prompt = style_image_prompt(prompt)
    destination = settings.style_candidate()
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(".tmp.png")
    shots = [(name, screenshot_file(settings, name).read_bytes()) for name in listed_screenshots(settings)]
    quality = str(settings.defaults.get("openai_quality") or "medium")
    try:
        if shots:
            result = provider.edit_png(prompt, shots, temporary, 1024, quality)
        else:
            result = provider.generate_png(prompt, temporary, 1024, quality, transparent=False)
        raw = temporary.read_bytes() if temporary.is_file() else b""
        if not raw.startswith(b"\x89PNG"):
            raise PipelineError("The style image was not a PNG.")
        temporary.replace(destination)
    finally:
        if temporary.exists():
            temporary.unlink()
    style = settings.style()
    style["image_prompt"] = prompt
    settings.style_path.write_text(json.dumps(style, indent=2) + "\n", encoding="utf-8")
    return {
        "ok": True,
        "prompt": prompt,
        "model": result.get("model", ""),
        "candidate_present": True,
        "screenshot_count": len(shots),
    }


def accept_style_candidate(settings) -> dict:
    candidate = settings.style_candidate()
    if not candidate.is_file():
        raise PipelineError("Generate a style image before using it.")
    destination = settings.style_reference()
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(".tmp.png")
    temporary.write_bytes(candidate.read_bytes())
    temporary.replace(destination)
    candidate.unlink()
    return {"ok": True, "reference_present": True, "candidate_present": False}


def discard_style_candidate(settings) -> dict:
    candidate = settings.style_candidate()
    if candidate.is_file():
        candidate.unlink()
    return {"ok": True, "candidate_present": False}
