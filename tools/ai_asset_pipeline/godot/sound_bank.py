"""Sound bank: files under assets/audio/sfx/<event>/ plus the manifest the game reads.

The folders are the truth. The manifest (resources/audio/sounds.json) is rebuilt from them
on every change, and only the per-event tuning (volume, pitch, cooldown, range) is carried
over from the previous manifest. Dropping a file into a folder by hand works too: the next
snapshot or write picks it up.
"""

import io
import json
import os
import re
import shutil
import subprocess
import time
import wave
import zipfile
from pathlib import Path

from core.errors import PipelineError

TUNE_KEYS = ("volume_db", "pitch_min", "pitch_max", "cooldown", "max_distance")
NAME_OK = re.compile(r"^[a-z0-9_.-]+$")
STEM_BAD = re.compile(r"[^a-z0-9_-]+")
MAX_INBOX_FILES = 800
MAX_ZIP_BYTES = 600 * 1024 * 1024
MAX_WALK_FILES = 250_000


def extensions(config: dict) -> set[str]:
    return {str(item).lower() for item in config["extensions"]}


def event_of(config: dict, event_id: str) -> dict:
    for event in config["events"]:
        if event["id"] == event_id:
            return event
    raise PipelineError(f"Unknown sound event: {event_id}.")


def audio_root(project_root: Path, config: dict) -> Path:
    return project_root / config["audio_dir"]


def manifest_file(project_root: Path, config: dict) -> Path:
    return project_root / config["manifest"]


def clean_name(filename: str, config: dict) -> str:
    path = Path(filename)
    suffix = path.suffix.lower()
    if suffix not in extensions(config):
        raise PipelineError("Sounds must be WAV, OGG, or MP3 files.")
    stem = STEM_BAD.sub("_", path.stem.lower()).strip("._-") or "sound"
    return stem[:60] + suffix


def unique_name(folder: Path, name: str) -> str:
    if not (folder / name).exists():
        return name
    stem, suffix = Path(name).stem, Path(name).suffix
    counter = 2
    while (folder / f"{stem}_{counter}{suffix}").exists():
        counter += 1
    return f"{stem}_{counter}{suffix}"


def audio_seconds(path: Path) -> float | None:
    if path.suffix.lower() != ".wav":
        return None
    try:
        with wave.open(str(path), "rb") as handle:
            rate = handle.getframerate()
            return round(handle.getnframes() / rate, 2) if rate else None
    except (wave.Error, EOFError, OSError):
        return None


def suggest_event(name: str, config: dict) -> str:
    tokens = [token for token in re.split(r"[^a-z0-9]+", name.lower()) if token]
    best, best_score = "", 0
    for event in config["events"]:
        words = set(event["keywords"])
        score = sum(1 for token in tokens if token in words)
        if score > best_score:
            best, best_score = event["id"], score
    return best


def _number(values: dict, key: str, low: float, high: float, fallback: float) -> float:
    if key not in values:
        return fallback
    try:
        value = float(values[key])
    except (TypeError, ValueError) as exc:
        raise PipelineError(f"{key} must be a number.") from exc
    if value != value:
        raise PipelineError(f"{key} must be a number.")
    return round(min(max(value, low), high), 3)


def read_tuning(project_root: Path, config: dict) -> dict:
    saved: dict = {}
    path = manifest_file(project_root, config)
    if path.is_file():
        try:
            saved = (json.loads(path.read_text(encoding="utf-8")).get("events")) or {}
        except (json.JSONDecodeError, OSError):
            saved = {}
    tuning = {}
    for event in config["events"]:
        row = {key: event[key] for key in TUNE_KEYS}
        stored = saved.get(event["id"]) or {}
        for key in TUNE_KEYS:
            if isinstance(stored.get(key), (int, float)):
                row[key] = stored[key]
        tuning[event["id"]] = row
    return tuning


def _event_files(project_root: Path, config: dict, event_id: str) -> list[Path]:
    folder = audio_root(project_root, config) / event_id
    if not folder.is_dir():
        return []
    allowed = extensions(config)
    return sorted(path for path in folder.iterdir() if path.is_file() and path.suffix.lower() in allowed)


def write_manifest(project_root: Path, config: dict, tuning: dict | None = None) -> dict:
    tuning = tuning or read_tuning(project_root, config)
    events = {}
    for event in config["events"]:
        files = [
            f"res://{config['audio_dir']}/{event['id']}/{path.name}"
            for path in _event_files(project_root, config, event["id"])
        ]
        events[event["id"]] = {"files": files, "positional": bool(event["positional"]), **tuning[event["id"]]}
    manifest = {"version": 1, "events": events}
    target = manifest_file(project_root, config)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    temporary.replace(target)
    return manifest


def list_bank(project_root: Path, config: dict) -> list[dict]:
    tuning = read_tuning(project_root, config)
    rows = []
    for event in config["events"]:
        files = []
        for path in _event_files(project_root, config, event["id"]):
            files.append({
                "name": path.name,
                "bytes": path.stat().st_size,
                "seconds": audio_seconds(path),
                "imported": path.with_name(path.name + ".import").is_file(),
            })
        rows.append({
            "id": event["id"],
            "label": event["label"],
            "group": event["group"],
            "played": event["played"],
            "find": event["find"],
            "tuning": tuning[event["id"]],
            "defaults": {key: event[key] for key in TUNE_KEYS},
            "files": files,
        })
    return rows


def tune(project_root: Path, config: dict, event_id: str, values: dict) -> dict:
    event_of(config, event_id)
    tuning = read_tuning(project_root, config)
    row = dict(tuning[event_id])
    row["volume_db"] = _number(values, "volume_db", -40.0, 12.0, row["volume_db"])
    row["pitch_min"] = _number(values, "pitch_min", 0.5, 2.0, row["pitch_min"])
    row["pitch_max"] = _number(values, "pitch_max", 0.5, 2.0, row["pitch_max"])
    row["cooldown"] = _number(values, "cooldown", 0.0, 5.0, row["cooldown"])
    row["max_distance"] = _number(values, "max_distance", 5.0, 200.0, row["max_distance"])
    if row["pitch_max"] < row["pitch_min"]:
        row["pitch_min"], row["pitch_max"] = row["pitch_max"], row["pitch_min"]
    tuning[event_id] = row
    write_manifest(project_root, config, tuning)
    return row


def reset_tuning(project_root: Path, config: dict, event_id: str) -> dict:
    event = event_of(config, event_id)
    tuning = read_tuning(project_root, config)
    tuning[event_id] = {key: event[key] for key in TUNE_KEYS}
    write_manifest(project_root, config, tuning)
    return tuning[event_id]


def _checked_name(name: str) -> str:
    if not isinstance(name, str) or not NAME_OK.fullmatch(name):
        raise PipelineError("Invalid sound file name.")
    return name


def bank_file(project_root: Path, config: dict, event_id: str, name: str) -> Path:
    event_of(config, event_id)
    path = audio_root(project_root, config) / event_id / _checked_name(name)
    if not path.is_file():
        raise PipelineError("That sound is not in the bank.")
    return path


def inbox_file(inbox: Path, name: str) -> Path:
    path = inbox / _checked_name(name)
    if not path.is_file():
        raise PipelineError("That sound is not in the inbox.")
    return path


def remove(project_root: Path, config: dict, event_id: str, name: str) -> None:
    path = bank_file(project_root, config, event_id, name)
    path.unlink()
    path.with_name(path.name + ".import").unlink(missing_ok=True)
    write_manifest(project_root, config)


def inbox_list(inbox: Path, config: dict) -> list[dict]:
    if not inbox.is_dir():
        return []
    allowed = extensions(config)
    rows = []
    for path in sorted(inbox.iterdir()):
        if path.is_file() and path.suffix.lower() in allowed:
            rows.append({
                "name": path.name,
                "bytes": path.stat().st_size,
                "seconds": audio_seconds(path),
                "suggest": suggest_event(path.name, config),
            })
    return rows


def inbox_delete(inbox: Path, name: str) -> None:
    inbox_file(inbox, name).unlink()


def inbox_clear(inbox: Path) -> int:
    if not inbox.is_dir():
        return 0
    removed = 0
    for path in inbox.iterdir():
        if path.is_file():
            path.unlink()
            removed += 1
    return removed


def _flat_label(parts: list[str]) -> str:
    """Folder hints help the auto-sort: Footsteps/gravel_03.wav becomes footsteps_gravel_03.wav."""
    if len(parts) < 2:
        return parts[-1]
    parent = STEM_BAD.sub("_", parts[-2].lower()).strip("_")
    stem = Path(parts[-1]).stem
    low = stem.lower()
    if not parent or low.startswith(parent):
        return parts[-1]
    return f"{parent}_{parts[-1]}"


def _inbox_room(inbox: Path) -> int:
    existing = sum(1 for path in inbox.iterdir() if path.is_file()) if inbox.is_dir() else 0
    return max(MAX_INBOX_FILES - existing, 0)


def _save_to_inbox(inbox: Path, config: dict, filename: str, data: bytes) -> str:
    inbox.mkdir(parents=True, exist_ok=True)
    name = unique_name(inbox, clean_name(filename, config))
    (inbox / name).write_bytes(data)
    return name


def _from_zip(inbox: Path, config: dict, source, query: str, limit: int) -> dict:
    allowed = extensions(config)
    words = [word for word in query.lower().split() if word]
    try:
        archive = zipfile.ZipFile(source)
    except zipfile.BadZipFile as exc:
        raise PipelineError("That ZIP file could not be read.") from exc
    added, skipped_large, matched = [], 0, 0
    with archive:
        members = [
            member for member in archive.infolist()
            if not member.is_dir() and Path(member.filename).suffix.lower() in allowed
        ]
        if sum(member.file_size for member in members) > MAX_ZIP_BYTES:
            raise PipelineError("That ZIP holds too much audio. Unpack it and use Scan a folder with a filter.")
        for member in members:
            if words and not all(word in member.filename.lower() for word in words):
                continue
            matched += 1
            if len(added) >= limit:
                continue
            if member.file_size > int(config["max_file_bytes"]):
                skipped_large += 1
                continue
            parts = [part for part in Path(member.filename.replace("\\", "/")).parts if part not in ("", ".", "..", "/")]
            added.append(_save_to_inbox(inbox, config, _flat_label(parts), archive.read(member)))
    return {"added": added, "matched": matched, "skipped_large": skipped_large}


def inbox_add_upload(inbox: Path, config: dict, filename: str, data: bytes) -> dict:
    if _inbox_room(inbox) <= 0:
        raise PipelineError("The inbox is full. Add or clear some sounds first.")
    suffix = Path(filename).suffix.lower()
    if suffix == ".zip":
        return _from_zip(inbox, config, io.BytesIO(data), "", _inbox_room(inbox))
    if len(data) > int(config["max_file_bytes"]):
        raise PipelineError(f"{Path(filename).name} is over the {int(config['max_file_bytes']) // (1024 * 1024)} MB limit.")
    return {"added": [_save_to_inbox(inbox, config, filename, data)], "matched": 1, "skipped_large": 0}


def inbox_scan(inbox: Path, config: dict, location: str, query: str = "", limit=200) -> dict:
    location = (location or "").strip().strip('"')
    if not location:
        raise PipelineError("Enter a folder or ZIP path.")
    path = Path(os.path.expandvars(location)).expanduser()
    if not path.exists():
        raise PipelineError("That folder or ZIP does not exist.")
    if _inbox_room(inbox) <= 0:
        raise PipelineError("The inbox is full. Add or clear some sounds first.")
    try:
        limit = int(limit)
    except (TypeError, ValueError):
        limit = 200
    limit = max(1, min(limit, _inbox_room(inbox)))
    if path.is_file():
        suffix = path.suffix.lower()
        if suffix == ".zip":
            return _from_zip(inbox, config, path, query, limit)
        if suffix in extensions(config):
            return inbox_add_upload(inbox, config, path.name, path.read_bytes())
        raise PipelineError("Point at a folder, a ZIP, or a WAV, OGG, or MP3 file.")
    allowed = extensions(config)
    words = [word for word in query.lower().split() if word]
    added, matched, skipped_large, visited, truncated = [], 0, 0, 0, False
    for root, _dirs, files in os.walk(path):
        for filename in sorted(files):
            visited += 1
            if visited > MAX_WALK_FILES:
                truncated = True
                break
            if Path(filename).suffix.lower() not in allowed:
                continue
            full = Path(root) / filename
            relative = full.relative_to(path)
            if words and not all(word in relative.as_posix().lower() for word in words):
                continue
            matched += 1
            if len(added) >= limit:
                continue
            if full.stat().st_size > int(config["max_file_bytes"]):
                skipped_large += 1
                continue
            added.append(_save_to_inbox(inbox, config, _flat_label(list(relative.parts)), full.read_bytes()))
        if truncated:
            break
    return {"added": added, "matched": matched, "skipped_large": skipped_large, "truncated": truncated}


def assign(project_root: Path, inbox: Path, config: dict, name: str, event_id: str) -> dict:
    event_of(config, event_id)
    source = inbox_file(inbox, name)
    folder = audio_root(project_root, config) / event_id
    folder.mkdir(parents=True, exist_ok=True)
    final = unique_name(folder, source.name)
    shutil.move(str(source), str(folder / final))
    write_manifest(project_root, config)
    return {"event": event_id, "name": final}


def import_in_godot(godot_bin: str, project_root: Path, timeout: int = 240) -> dict:
    if not godot_bin:
        raise PipelineError("Godot was not found. Set GODOT_BIN in tools/ai_asset_pipeline/.env, or open the project in the editor once.")
    started = time.time()
    flags = 0x08000000 if os.name == "nt" else 0
    try:
        result = subprocess.run(
            [godot_bin, "--headless", "--path", str(project_root), "--import"],
            capture_output=True,
            text=True,
            errors="replace",
            timeout=timeout,
            creationflags=flags,
        )
    except subprocess.TimeoutExpired as exc:
        raise PipelineError("Godot did not finish importing in time. Close the editor and try again.") from exc
    tail = "\n".join((result.stdout or "").strip().splitlines()[-6:])
    return {"ok": result.returncode == 0, "seconds": round(time.time() - started, 1), "output": tail}


def snapshot(project_root: Path, inbox: Path, config: dict, godot_bin: str) -> dict:
    bank = list_bank(project_root, config)
    covered = sum(1 for row in bank if row["files"])
    pending = sum(1 for row in bank for item in row["files"] if not item["imported"])
    return {
        "events": bank,
        "inbox": inbox_list(inbox, config),
        "sources": config["sources"],
        "extensions": sorted(extensions(config)),
        "audio_dir": config["audio_dir"],
        "manifest": config["manifest"],
        "godot": bool(godot_bin),
        "covered": covered,
        "total": len(bank),
        "pending_import": pending,
    }
