import json
import os
import shutil
from pathlib import Path

PIPELINE_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = PIPELINE_ROOT.parents[1]


def load_dotenv(path: Path | None = None) -> None:
    env_path = path or (PIPELINE_ROOT / ".env")
    if not env_path.is_file():
        return
    for raw in env_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def _read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _existing_file(path_text: str) -> str:
    if not path_text:
        return ""
    candidate = Path(path_text)
    return str(candidate) if candidate.is_file() else ""


def _detect_godot() -> str:
    override = os.environ.get("GODOT_BIN", "").strip()
    found = _existing_file(override)
    if found:
        return found
    local = os.environ.get("LOCALAPPDATA", "")
    if not local:
        return ""
    package = Path(local) / "Microsoft" / "WinGet" / "Packages" / "GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe"
    if not package.is_dir():
        return ""
    matches = sorted(package.glob("Godot_v*_win64.exe"))
    return str(matches[-1]) if matches else ""


def _detect_blender() -> str:
    override = os.environ.get("BLENDER_BIN", "").strip()
    found = _existing_file(override)
    if found:
        return found
    which = shutil.which("blender")
    if which:
        return which
    program_files = os.environ.get("ProgramFiles", r"C:\Program Files")
    root = Path(program_files) / "Blender Foundation"
    if root.is_dir():
        matches = sorted(root.glob("Blender */blender.exe"))
        if matches:
            return str(matches[-1])
    return ""


class Settings:
    def __init__(self, library_dir: Path | None = None, project_root: Path | None = None):
        load_dotenv()
        self.pipeline_root = PIPELINE_ROOT
        self.project_root = project_root or PROJECT_ROOT
        self.defaults = _read_json(PIPELINE_ROOT / "config" / "defaults.json")
        self.style_path = PIPELINE_ROOT / "config" / "style.json"
        self.descriptions_path = PIPELINE_ROOT / "config" / "descriptions.json"
        self.grid_path = PIPELINE_ROOT / "config" / "building_grid.json"
        self.catalog_path = PIPELINE_ROOT / "presets" / "catalog.json"
        library = os.environ.get("PIPELINE_LIBRARY_DIR", "").strip()
        if library_dir is not None:
            self.library_dir = library_dir
        elif library:
            self.library_dir = Path(library)
        else:
            self.library_dir = PIPELINE_ROOT / "library"
        self.host = os.environ.get("PIPELINE_HOST", self.defaults["host"])
        self.port = int(os.environ.get("PIPELINE_PORT", self.defaults["port"]))
        self.poll_timeout_sec = int(os.environ.get("PIPELINE_POLL_TIMEOUT_SEC", self.defaults["poll_timeout_sec"]))
        self.poll_interval_sec = float(self.defaults["poll_interval_sec"])
        self.godot_bin = _detect_godot()
        self.blender_bin = _detect_blender()
        self.openai_key = os.environ.get("OPENAI_API_KEY", "").strip()
        self.meshy_key = os.environ.get("MESHY_API_KEY", "").strip()
        self.tripo_key = os.environ.get("TRIPO_API_KEY", "").strip()
        self.openai_model = os.environ.get("OPENAI_IMAGE_MODEL", self.defaults["openai_image_model"]).strip()
        self.meshy_model = os.environ.get("MESHY_AI_MODEL", self.defaults["meshy_ai_model"]).strip()
        self.tripo_model = os.environ.get("TRIPO_MODEL_VERSION", self.defaults["tripo_model_version"]).strip()

    def style(self) -> dict:
        return _read_json(self.style_path)

    def grid(self) -> dict:
        return _read_json(self.grid_path)

    def catalog(self) -> dict:
        return _read_json(self.catalog_path)

    def style_reference(self) -> Path:
        return self.project_root / "assets" / "style_reference" / "style_reference.png"

    def style_candidate(self) -> Path:
        return self.project_root / "assets" / "style_reference" / "style_candidate.png"
