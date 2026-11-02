import json
import mimetypes
import re
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

from core.errors import PipelineError
from core.redact import redact
from core.settings import Settings
from core.store import AssetStore
from generators.orchestrator import approve_asset, discard_asset, normalize_request, preview_prompt, reject_asset, reprocess_mesh
from generators.style_image import (
    accept_style_candidate,
    add_style_screenshots,
    discard_style_candidate,
    generate_style_candidate,
    listed_screenshots,
    remove_style_screenshot,
    screenshot_file,
)
from godot.descriptions import load_descriptions, save_item_copy, save_surface_copy
from godot.item_index import load_items
from godot.surface_index import load_grounds, load_surfaces
from jobqueue.worker import Worker
from providers.registry import openai_from, provider_status

STATIC = Path(__file__).resolve().parent / "static"


class App:
    def __init__(self, settings: Settings | None = None):
        self.settings = settings or Settings()
        self.store = AssetStore(self.settings.library_dir)
        (self.settings.library_dir / "uploads").mkdir(parents=True, exist_ok=True)
        self.worker = Worker(self.settings, self.store)
        self.worker.start()

    def bootstrap(self) -> dict:
        style = self.settings.style()
        return {
            "providers": provider_status(self.settings),
            "style": {
                "name": style.get("name"),
                "summary": style.get("summary"),
                "palette": style.get("palette"),
                "use_palette": style.get("use_palette", True),
                "avoid": style.get("avoid"),
                "image_prompt": style.get("image_prompt", ""),
                "image_screenshots": listed_screenshots(self.settings),
                "reference_present": self.settings.style_reference().is_file(),
                "candidate_present": self.settings.style_candidate().is_file(),
                "reference_path": "assets/style_reference/style_reference.png",
            },
            "catalog": self.settings.catalog(),
            "defaults": {
                "resolution": self.settings.defaults["resolution"],
                "allowed_resolutions": self.settings.defaults["allowed_resolutions"],
                "variations": self.settings.defaults["variations"],
                "max_variations": self.settings.defaults["max_variations"],
                "polycount": self.settings.defaults["polycount"],
                "character_polycount": self.settings.defaults["character_polycount"],
            },
            "blender": {"configured": bool(self.settings.blender_bin), "path": self.settings.blender_bin},
            "godot": {"configured": bool(self.settings.godot_bin), "path": self.settings.godot_bin},
            "grid": self.settings.grid(),
        }


def make_handler(app: App):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *args) -> None:
            app.store.append_log(redact(fmt % args))

        def _send(self, status: int, payload, content_type: str = "application/json") -> None:
            if not isinstance(payload, (bytes, bytearray)):
                payload = json.dumps(payload).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)

        def _error(self, status: int, message: str) -> None:
            self._send(status, {"error": redact(message)})

        def _read_json(self) -> dict:
            length = int(self.headers.get("Content-Length", "0"))
            if length > 2_000_000:
                raise PipelineError("Request body is too large.")
            raw = self.rfile.read(length) if length else b"{}"
            if not raw:
                return {}
            return json.loads(raw.decode("utf-8"))

        def do_GET(self) -> None:
            parsed = urlparse(self.path)
            path = unquote(parsed.path)
            try:
                if path in {"/", "/index.html"}:
                    self._file(STATIC / "index.html")
                elif path == "/app.js":
                    self._file(STATIC / "app.js")
                elif path == "/app.css":
                    self._file(STATIC / "app.css")
                elif path == "/api/bootstrap":
                    self._send(200, app.bootstrap())
                elif path == "/api/jobs":
                    self._send(200, {"jobs": app.store.list_jobs()})
                elif path == "/api/assets":
                    self._send(200, {"assets": app.store.list_assets()})
                elif path == "/api/items":
                    copy = load_descriptions(app.settings)
                    self._send(200, {"items": load_items(app.settings.project_root, copy)})
                elif path == "/api/surfaces":
                    copy = load_descriptions(app.settings)
                    root = app.settings.project_root
                    surfaces = load_surfaces(root, copy) + load_grounds(root, copy)
                    self._send(200, {"surfaces": surfaces})
                elif path == "/style-reference.png":
                    self._style_image()
                elif path == "/style-candidate.png":
                    self._style_candidate()
                elif path.startswith("/style-screenshots/"):
                    self._style_screenshot(path)
                elif path.startswith("/item-art/"):
                    self._item_art(path)
                elif path.startswith("/texture-art/"):
                    self._texture_art(path)
                elif path.startswith("/api/jobs/"):
                    self._send(200, app.store.get_job(path.split("/")[-1]))
                elif path.startswith("/api/assets/"):
                    self._send(200, app.store.get_asset(path.split("/")[-1]))
                elif path.startswith("/media/"):
                    self._media(path)
                else:
                    self._error(404, "Not found.")
            except KeyError:
                self._error(404, "Record not found.")
            except PipelineError as exc:
                self._error(400, str(exc))

        def do_POST(self) -> None:
            parsed = urlparse(self.path)
            path = unquote(parsed.path)
            try:
                if path == "/api/style":
                    self._send(200, self._save_style(self._read_json()))
                    return
                if path == "/api/style/reference":
                    self._send(200, self._save_style_image())
                    return
                if path == "/api/style/generate":
                    self._send(200, generate_style_candidate(app.settings, self._read_json().get("prompt"), openai_from(app.settings)))
                    return
                if path == "/api/style/screenshots":
                    self._send(200, self._add_style_screenshots())
                    return
                if path == "/api/style/screenshots/delete":
                    self._send(200, remove_style_screenshot(app.settings, self._read_json().get("name")))
                    return
                if path == "/api/style/candidate/accept":
                    self._send(200, accept_style_candidate(app.settings))
                    return
                if path == "/api/style/candidate/discard":
                    self._send(200, discard_style_candidate(app.settings))
                    return
                if path == "/api/copy":
                    self._send(200, self._save_copy(self._read_json()))
                    return
                if path == "/api/prompt-preview":
                    self._send(200, preview_prompt(app.settings, self._read_json()))
                    return
                if path == "/api/jobs":
                    payload = self._read_json()
                    request = normalize_request(app.settings, payload)
                    job = app.store.create_job(request)
                    app.worker.wake()
                    self._send(202, job)
                    return
                if path == "/api/upload":
                    self._send(201, self._upload())
                    return
                parts = path.strip("/").split("/")
                if len(parts) == 4 and parts[0] == "api" and parts[1] == "jobs" and parts[3] == "retry":
                    previous = app.store.get_job(parts[2])
                    if previous["status"] not in {"failed", "ready_for_review"}:
                        raise PipelineError("Retry is available after a job finishes or fails.")
                    job = app.store.create_job(previous["request"])
                    job["attempt"] = int(previous.get("attempt", 1)) + 1
                    job["retried_from"] = previous["job_id"]
                    app.store.save_job(job)
                    app.worker.wake()
                    self._send(202, job)
                    return
                if len(parts) == 4 and parts[0] == "api" and parts[1] == "assets":
                    body = self._read_json()
                    if parts[3] == "approve":
                        asset = approve_asset(
                            app.settings,
                            app.store,
                            parts[2],
                            bool(body.get("acknowledge_limitations")),
                            bool(body.get("force")),
                            bool(body.get("confirm_overwrite_approved")),
                        )
                        self._send(200, asset)
                        return
                    if parts[3] == "reject":
                        self._send(200, reject_asset(app.store, parts[2], str(body.get("reason") or "")))
                        return
                    if parts[3] == "delete":
                        self._send(200, discard_asset(app.store, parts[2]))
                        return
                if len(parts) == 4 and parts[0] == "api" and parts[1] == "assets" and parts[3] == "reprocess":
                    payload = self._upload()
                    asset = reprocess_mesh(app.settings, app.store, parts[2], Path(payload["path"]))
                    self._send(200, asset)
                    return
                self._error(404, "Not found.")
            except KeyError:
                self._error(404, "Record not found.")
            except PipelineError as exc:
                self._error(400, str(exc))
            except json.JSONDecodeError:
                self._error(400, "The request body is not JSON.")

        def _file(self, path: Path) -> None:
            if not path.is_file():
                self._error(404, "Missing dashboard file.")
                return
            content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
            self._send(200, path.read_bytes(), content_type)

        def _media(self, path: str) -> None:
            parts = path.strip("/").split("/")
            if len(parts) != 4 or parts[1].startswith("."):
                raise PipelineError("Invalid media path.")
            _media, asset_id, kind, filename = parts
            if kind not in {"original", "processed", "preview"} or "/" in filename or ".." in filename:
                raise PipelineError("Invalid media path.")
            root = (app.store.assets_dir / asset_id / kind).resolve()
            target = (root / filename).resolve()
            if root not in target.parents or not target.is_file():
                self._error(404, "Media not found.")
                return
            content_type = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
            self._send(200, target.read_bytes(), content_type)

        def _style_image(self) -> None:
            self._png(app.settings.style_reference(), "No style image yet.")

        def _style_candidate(self) -> None:
            self._png(app.settings.style_candidate(), "No generated style image yet.")

        def _style_screenshot(self, path: str) -> None:
            target = screenshot_file(app.settings, Path(path.strip("/")).name)
            self._png(target, "Screenshot not found.")

        def _add_style_screenshots(self) -> dict:
            blobs = []
            for part in self._parts():
                if part["name"] not in {"file", "screenshots"} or not part["filename"]:
                    continue
                suffix = Path(part["filename"]).suffix.lower()
                if suffix not in {".png", ".jpg", ".jpeg", ".webp"}:
                    raise PipelineError("Screenshots must be PNG, JPEG, or WEBP.")
                if part["data"]:
                    blobs.append(part["data"])
            return add_style_screenshots(app.settings, blobs)

        def _parts(self) -> list[dict]:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 80 * 1024 * 1024:
                raise PipelineError("Upload must be a file under 80 MB.")
            content_type = self.headers.get("Content-Type", "")
            if "boundary=" not in content_type:
                raise PipelineError("Upload must be multipart form data.")
            boundary = content_type.split("boundary=", 1)[1].split(";", 1)[0].strip().strip('"')
            body = self.rfile.read(length)
            marker = ("--" + boundary).encode("utf-8")
            parts = []
            for part in body.split(marker)[1:]:
                if part.startswith(b"--"):
                    break
                header, _, content = part.partition(b"\r\n\r\n")
                if not header:
                    continue
                header_text = header.decode("utf-8", errors="replace")
                name = header_text.split('name="', 1)[1].split('"', 1)[0] if 'name="' in header_text else ""
                filename = header_text.split('filename="', 1)[1].split('"', 1)[0] if 'filename="' in header_text else ""
                data = content[:-2] if content.endswith(b"\r\n") else content
                parts.append({"name": name, "filename": filename, "data": data})
            return parts

        def _png(self, target: Path, missing: str) -> None:
            if not target.is_file():
                self._error(404, missing)
                return
            self._send(200, target.read_bytes(), "image/png")

        def _save_copy(self, body: dict) -> dict:
            kind = str(body.get("kind") or "")
            record_id = str(body.get("id") or "")
            description = body.get("description")
            image = body.get("image_description")
            if not isinstance(description, str) or not isinstance(image, str):
                raise PipelineError("Descriptions must be text.")
            if kind == "item":
                return {"item": save_item_copy(app.settings, record_id, description, image)}
            if kind == "surface":
                return {"surface": save_surface_copy(app.settings, record_id, description, image)}
            raise PipelineError("Copy kind must be item or surface.")

        def _save_style(self, body: dict) -> dict:
            style = app.settings.style()
            if "summary" in body:
                summary = " ".join(str(body.get("summary") or "").split())
                if not summary:
                    raise PipelineError("The style text cannot be empty.")
                style["summary"] = summary[:4000]
            if "use_palette" in body:
                style["use_palette"] = bool(body.get("use_palette"))
            if "avoid" in body:
                lines = []
                for line in str(body.get("avoid") or "").splitlines():
                    item = " ".join(line.split()).strip(" -")
                    if item:
                        lines.append(item[:200])
                style["avoid"] = lines[:40]
            app.settings.style_path.write_text(json.dumps(style, indent=2) + "\n", encoding="utf-8")
            return {
                "summary": style.get("summary", ""),
                "use_palette": style.get("use_palette", True),
                "avoid": style.get("avoid", []),
            }

        def _save_style_image(self) -> dict:
            from PIL import Image

            uploaded = self._upload()
            source = Path(uploaded["path"])
            if source.suffix.lower() not in {".png", ".jpg", ".jpeg", ".webp"}:
                raise PipelineError("The style image must be a PNG, JPEG, or WEBP.")
            destination = app.settings.style_reference()
            destination.parent.mkdir(parents=True, exist_ok=True)
            with Image.open(source) as image:
                image.load()
                converted = image.convert("RGBA")
                temporary = destination.with_suffix(".tmp.png")
                converted.save(temporary, format="PNG")
            temporary.replace(destination)
            return {"ok": True, "path": "assets/style_reference/style_reference.png"}

        def _item_art(self, path: str) -> None:
            name = Path(path.strip("/").split("/")[-1]).name
            if not re.fullmatch(r"[a-z0-9_]+\.(png|webp|jpe?g)", name):
                raise PipelineError("Invalid item art name.")
            root = (app.settings.project_root / "assets" / "icons").resolve()
            target = (root / name).resolve()
            if root not in target.parents or not target.is_file():
                self._error(404, "No art file for that item.")
                return
            content_type = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
            self._send(200, target.read_bytes(), content_type)

        def _texture_art(self, path: str) -> None:
            parts = path.strip("/").split("/")
            if len(parts) != 3 or parts[2] != "albedo.png" or not re.fullmatch(r"[a-z0-9_]+", parts[1]):
                raise PipelineError("Invalid texture art path.")
            root = (app.settings.project_root / "assets" / "textures").resolve()
            target = (root / parts[1] / "albedo.png").resolve()
            if root not in target.parents or not target.is_file():
                self._error(404, "No albedo for that surface.")
                return
            self._send(200, target.read_bytes(), "image/png")

        def _upload(self) -> dict:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 80 * 1024 * 1024:
                raise PipelineError("Upload must be a file under 80 MB.")
            content_type = self.headers.get("Content-Type", "")
            if "boundary=" not in content_type:
                raise PipelineError("Upload must be multipart form data.")
            boundary = content_type.split("boundary=", 1)[1].split(";", 1)[0].strip().strip('"')
            body = self.rfile.read(length)
            marker = ("--" + boundary).encode("utf-8")
            filename = "upload.bin"
            data = b""
            for part in body.split(marker)[1:]:
                if part.startswith(b"--"):
                    break
                header, _, content = part.partition(b"\r\n\r\n")
                if b'name="file"' not in header:
                    continue
                header_text = header.decode("utf-8", errors="replace")
                if 'filename="' in header_text:
                    filename = header_text.split('filename="', 1)[1].split('"', 1)[0]
                data = content[:-2] if content.endswith(b"\r\n") else content
                break
            if not data:
                raise PipelineError("The upload did not include a file.")
            suffix = Path(filename).suffix.lower()
            if suffix not in {".png", ".jpg", ".jpeg", ".webp", ".glb"}:
                raise PipelineError("Upload a PNG, JPEG, WEBP, or GLB file.")
            destination = app.settings.library_dir / "uploads" / f"{uuid.uuid4().hex}{suffix}"
            destination.write_bytes(data)
            return {"path": str(destination), "filename": Path(filename).name}

    return Handler


def serve(settings: Settings | None = None) -> None:
    app = App(settings)
    server = ThreadingHTTPServer((app.settings.host, app.settings.port), make_handler(app))
    print(f"Asset pipeline dashboard: http://{app.settings.host}:{app.settings.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()
