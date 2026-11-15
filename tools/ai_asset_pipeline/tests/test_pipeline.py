import json
import shutil
import sys
import tempfile
import threading
import unittest
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT.parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from core.errors import ConfigError, PipelineError
from core.redact import redact
from core.settings import Settings
from core.store import AssetStore
from dashboard.server import App, make_handler
from generators.modular import build_piece
from generators.orchestrator import approve_asset, discard_asset, execute_job, preview_prompt
from godot.descriptions import load_descriptions, save_item_copy, save_surface_copy
from godot.item_index import load_items
from godot.surface_index import load_grounds, load_surfaces
from http.server import ThreadingHTTPServer
from processors.gltf_write import Mesh, read_glb_json, write_glb
from processors.maps import procedural_maps, seam_score
from processors.validate import inspect_glb, validate_mesh
from prompts.builder import build_prompts
from core.costs import estimate_operation, load_pricing
from core.workshop import infer_workshop_category, production_stats, resolve_category
from providers.base import CAP_ALT_RIG, CAP_ANIMATE, CAP_GENERATE_MODEL, CAP_HUMANOID_RIG, ThreeDProvider
from providers.meshy import MeshyProvider, animation_payload, image_to_3d_payload, text_preview_payload, text_refine_payload
from providers.openai_images import OpenAIImageProvider, generation_payload
from providers.registry import capability_matrix, recommended_mesh_provider, threed_from
from providers.tripo import animate_rig_payload, image_to_model_payload
from providers.tripo import TripoProvider


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = Path(tempfile.mkdtemp(prefix="asset-pipeline-"))
        self.settings = Settings(library_dir=self.temp / "library", project_root=self.temp / "project")
        self.settings.defaults["allowed_resolutions"] = [32, 64, 512, 1024, 2048, 4096]
        self.settings.blender_bin = ""
        self.store = AssetStore(self.settings.library_dir)

    def tearDown(self):
        shutil.rmtree(self.temp, ignore_errors=True)

    def test_style_prompt_uses_the_config_file(self):
        style = self.settings.style()
        prompts = build_prompts(style, {"prompt": "survival backpack"}, "scuffed canvas", "prop")
        self.assertIn(style["summary"].split(",")[0], prompts["prompt"])
        if style.get("use_palette", True):
            self.assertIn("#354451", prompts["prompt"])
        else:
            self.assertNotIn("#354451", prompts["prompt"])
        self.assertIn("photorealism", prompts["negative_prompt"])
        self.assertIn("scuffed canvas", prompts["prompt"])
        self.assertLessEqual(len(prompts["compact_prompt"]), 800)

    def test_procedural_texture_is_tileable_and_labeled(self):
        maps = procedural_maps(32, ["#89929D", "#354451"], seed=7, roughness=0.86, metallic=0.0)
        self.assertLess(seam_score(maps["albedo"]), 20)
        self.assertEqual(maps["normal"].size, (32, 32))
        self.assertEqual(maps["roughness"].getpixel((0, 0))[0], maps["roughness"].getpixel((0, 0))[1])

    def test_wall_matches_the_building_grid(self):
        meshes, materials = build_piece("concrete_wall", self.settings.grid())
        path = self.temp / "wall.glb"
        write_glb(path, meshes, materials)
        report = inspect_glb(path)
        self.assertGreater(report["triangles"], 0)
        self.assertTrue(report["has_uv"])
        self.assertTrue(report["has_collision_node"])
        bounds = report["bounds"]
        self.assertAlmostEqual(bounds[1][0] - bounds[0][0], 0.85, places=3)
        self.assertAlmostEqual(bounds[1][1] - bounds[0][1], 3.0, places=3)
        self.assertAlmostEqual(bounds[1][2] - bounds[0][2], 0.15, places=3)
        self.assertAlmostEqual(bounds[0][1], 0.0, places=3)

    def test_door_header_starts_at_the_game_door_height(self):
        meshes, materials = build_piece("doorway", self.settings.grid())
        path = self.temp / "door.glb"
        write_glb(path, meshes, materials)
        bounds = inspect_glb(path)["bounds"]
        self.assertAlmostEqual(bounds[0][1], 2.2, places=3)
        self.assertAlmostEqual(bounds[1][1], 3.0, places=3)

    def test_box_normals_face_outward(self):
        mesh = Mesh("box")
        mesh.add_box((1, 2, 0.5), (0, 1, 0))
        for index in range(0, len(mesh.indices), 3):
            a, b, c = (mesh.indices[index + offset] for offset in range(3))
            ax, ay, az = mesh.positions[a * 3 : a * 3 + 3]
            bx, by, bz = mesh.positions[b * 3 : b * 3 + 3]
            cx, cy, cz = mesh.positions[c * 3 : c * 3 + 3]
            nx = (by - ay) * (cz - az) - (bz - az) * (cy - ay)
            ny = (bz - az) * (cx - ax) - (bx - ax) * (cz - az)
            nz = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
            stored = mesh.normals[a * 3 : a * 3 + 3]
            self.assertGreater(nx * stored[0] + ny * stored[1] + nz * stored[2], 0)

    def test_provider_payloads_match_the_documented_fields(self):
        image = image_to_3d_payload(b"\x89PNG\r\n", 8000, "1024", False, "latest")
        self.assertTrue(image["image_url"].startswith("data:image/png;base64,"))
        self.assertEqual(image["target_formats"], ["glb"])
        self.assertEqual(image["texture_resolution"], "2k")
        self.assertTrue(image["enable_pbr"])
        self.assertNotIn("pose_mode", image)
        character = image_to_3d_payload(b"\x89PNG\r\n", 12000, "2k", True, "latest")
        self.assertEqual(character["pose_mode"], "a-pose")
        preview = text_preview_payload("a crate", 4000, False, "latest")
        self.assertEqual(preview["mode"], "preview")
        self.assertLessEqual(len(preview["prompt"]), 800)
        refine = text_refine_payload("task-id")
        self.assertEqual(refine["mode"], "refine")
        self.assertTrue(refine["enable_pbr"])
        tripo = image_to_model_payload("token", "png", "v2.5-20250123", 5000, 12)
        self.assertEqual(tripo["type"], "image_to_model")
        self.assertEqual(tripo["file"]["file_token"], "token")
        self.assertEqual(tripo["model_seed"], 12)
        rig = animate_rig_payload("prior-task", rig_type="quadruped")
        self.assertEqual(rig["type"], "animate_rig")
        self.assertEqual(rig["original_model_task_id"], "prior-task")
        self.assertEqual(rig["rig_type"], "quadruped")
        anim = animation_payload("rig-task", action_ids=[10, 25, 92])
        self.assertEqual(anim["rig_task_id"], "rig-task")
        self.assertEqual(anim["action_ids"], [10, 25, 92])
        with self.assertRaises(Exception):
            animation_payload("rig-task", action_id=1, action_ids=[1])
        openai = generation_payload("a wall", "gpt-image-2.5-flare", 4096, "medium")
        self.assertEqual(openai["size"], "2048x2048")
        self.assertNotIn("response_format", openai)
        self.assertNotIn("background", openai)
        icon = generation_payload("a pistol", "gpt-image-2.5-flare", 1024, "medium", transparent=True)
        self.assertEqual(icon["background"], "transparent")
        self.assertEqual(icon["output_format"], "png")
        from providers.openai_images import edit_multipart

        content_type, body = edit_multipart(
            "gpt-image-2.5-flare",
            "follow these screenshots",
            [("one.png", b"one"), ("two.png", b"two")],
            1024,
            "medium",
        )
        text = body.decode("utf-8")
        self.assertIn("multipart/form-data", content_type)
        self.assertEqual(text.count('name="image[]"'), 2)
        self.assertIn("follow these screenshots", text)
        self.assertIn("output_format", text)
        self.assertNotIn("input_fidelity", text)
        self.assertNotIn("background", text)
        _content_type, transparent = edit_multipart(
            "gpt-image-2.5-flare",
            "one pistol",
            [("one.png", b"one")],
            1024,
            "medium",
            transparent=True,
        )
        self.assertIn('name="background"\r\n\r\ntransparent', transparent.decode("utf-8"))
        with self.assertRaises(ConfigError):
            OpenAIImageProvider("", "gpt-image-2.5-flare").require_key()

    def test_secrets_are_redacted(self):
        self.assertNotIn("sk-testsecret", redact("failed sk-testsecret"))
        self.assertNotIn("abc123", redact("Bearer abc123"))

    def test_job_publishes_a_godot_scene_without_overwriting_approval(self):
        job = self.store.create_job(
            {
                "kind": "building",
                "category": "concrete_wall",
                "name": "yard_wall",
                "prompt": "stained",
                "resolution": 32,
                "variations": 1,
                "polycount": 2000,
            }
        )
        execute_job(self.settings, self.store, job)
        self.assertEqual(job["status"], "ready_for_review", job.get("errors"))
        asset = self.store.get_asset(job["asset_ids"][0])
        self.assertEqual(asset["provider"], "procedural")
        self.assertIn("modular concrete wall", asset["prompt"])
        self.assertIn("Art direction:", asset["prompt"])
        self.assertTrue(asset["validation"]["ok"], asset["validation"])
        self.assertIn("original/", asset["original_files"][0])
        approved = approve_asset(self.settings, self.store, asset["asset_id"], False, False, False)
        scene = self.settings.project_root / "assets" / "buildings" / "yard_wall.tscn"
        glb = self.settings.project_root / "assets" / "buildings" / "yard_wall.glb"
        self.assertIn("PackedScene", scene.read_text(encoding="utf-8"))
        self.assertEqual(read_glb_json(glb)["asset"]["version"], "2.0")
        self.assertEqual(approved["approval_status"], "approved")
        with self.assertRaises(PipelineError):
            approve_asset(self.settings, self.store, asset["asset_id"], False, True, False)

    def test_texture_job_and_material_resource(self):
        job = self.store.create_job(
            {
                "kind": "texture",
                "category": "concrete_wall",
                "name": "panel_concrete",
                "prompt": "form tie holes",
                "provider": "procedural",
                "resolution": 32,
                "seed": 3,
            }
        )
        execute_job(self.settings, self.store, job)
        self.assertEqual(job["status"], "ready_for_review", job.get("errors"))
        asset = self.store.get_asset(job["asset_ids"][0])
        self.assertEqual(asset["maps_origin"]["albedo"], "procedural")
        self.assertEqual(asset["maps_origin"]["normal"], "procedural")
        self.assertTrue(asset["seed_supported"])
        approve_asset(self.settings, self.store, asset["asset_id"], False, False, False)
        material = (self.settings.project_root / "assets" / "materials" / "panel_concrete.tres").read_text(encoding="utf-8")
        self.assertIn("StandardMaterial3D", material)
        self.assertIn("roughness_texture_channel = 0", material)
        self.assertIn("res://assets/textures/panel_concrete/albedo.png", material)
        self.assertTrue((self.settings.project_root / "assets" / "pipeline_meta" / ".gdignore").is_file())

    def test_unconfigured_image_provider_fails_without_a_fake_image(self):
        self.settings.openai_key = ""
        job = self.store.create_job(
            {
                "kind": "texture",
                "category": "brick",
                "name": "brick_wall",
                "provider": "openai",
                "resolution": 32,
            }
        )
        execute_job(self.settings, self.store, job)
        self.assertEqual(job["status"], "failed")
        self.assertIn("OPENAI_API_KEY", job["message"])
        self.assertEqual(list((self.store.asset_dir(job["asset_ids"][0]) / "processed").glob("*.png")), [])

    def test_item_icon_prompt_is_an_object_not_a_tile(self):
        preset = self.settings.catalog()["textures"]["item_icon"]
        prompts = build_prompts(self.settings.style(), preset, "Debug Weapon. A test pistol.", "texture", None, False)
        self.assertIn("one object", prompts["provider_prompt"].lower())
        self.assertIn("from the side", prompts["provider_prompt"].lower())
        self.assertNotIn("point to the right", prompts["provider_prompt"].lower())
        self.assertNotIn("pointing left", prompts["provider_prompt"].lower())
        self.assertIn("empty alpha", prompts["provider_prompt"].lower())
        self.assertIn("5 percent empty margin", prompts["provider_prompt"].lower())
        self.assertNotIn("checkerboard", prompts["provider_prompt"].lower())
        self.assertNotIn("Seamless tileable", prompts["provider_prompt"])
        plain = dict(self.settings.style())
        plain["use_palette"] = False
        open_colors = build_prompts(plain, preset, "Debug Weapon. A test pistol.", "texture", None, False)
        self.assertNotIn("Palette:", open_colors["provider_prompt"])
        self.assertNotIn("#354451", open_colors["provider_prompt"])
        self.assertNotIn("palette dark slate", open_colors["compact_prompt"])

    def test_style_image_prompt_is_sent_unchanged_and_kept_only_on_accept(self):
        from PIL import Image

        from generators.style_image import accept_style_candidate, generate_style_candidate, style_image_prompt

        self.settings.style_path = self.temp / "style.json"
        self.settings.style_path.write_text(json.dumps({"summary": "keep me", "use_palette": True}) + "\n", encoding="utf-8")

        class FakeProvider:
            def generate_png(self, prompt, destination, resolution, quality, transparent=False):
                self.prompt = prompt
                self.transparent = transparent
                self.resolution = resolution
                Image.new("RGB", (8, 8), (12, 34, 56)).save(destination, format="PNG")
                return {"model": "fake"}

        provider = FakeProvider()
        with self.assertRaises(PipelineError):
            style_image_prompt("   ")
        result = generate_style_candidate(self.settings, "A painted kit of olive cloth and rusted metal.", provider)
        self.assertEqual(provider.prompt, "A painted kit of olive cloth and rusted metal.")
        self.assertFalse(provider.transparent)
        self.assertEqual(provider.resolution, 1024)
        self.assertTrue(result["candidate_present"])
        self.assertFalse(self.settings.style_reference().is_file())
        saved = json.loads(self.settings.style_path.read_text(encoding="utf-8"))
        self.assertEqual(saved["summary"], "keep me")
        self.assertEqual(saved["image_prompt"], provider.prompt)
        accept_style_candidate(self.settings)
        with Image.open(self.settings.style_reference()) as image:
            self.assertEqual(image.getpixel((0, 0)), (12, 34, 56))
        self.assertFalse(self.settings.style_candidate().is_file())

    def test_style_screenshots_are_sent_with_the_prompt(self):
        from io import BytesIO

        from PIL import Image

        from generators.style_image import add_style_screenshots, generate_style_candidate, remove_style_screenshot

        self.settings.style_path = self.temp / "style.json"
        self.settings.style_path.write_text(json.dumps({"summary": "keep me"}) + "\n", encoding="utf-8")
        buffer = BytesIO()
        Image.new("RGB", (4, 4), (9, 8, 7)).save(buffer, format="PNG")
        with self.assertRaises(PipelineError):
            add_style_screenshots(self.settings, [buffer.getvalue(), b"not-an-image"])
        self.assertEqual(list((self.settings.style_reference().parent / "screenshots").glob("*.png")), [])
        saved = add_style_screenshots(self.settings, [buffer.getvalue()])
        self.assertEqual(len(saved["screenshots"]), 1)

        class FakeProvider:
            def generate_png(self, *args, **kwargs):
                raise AssertionError("text-only generation was used")

            def edit_png(self, prompt, images, destination, resolution, quality):
                self.prompt = prompt
                self.images = images
                self.quality = quality
                Image.new("RGB", (8, 8), (1, 2, 3)).save(destination, format="PNG")
                return {"model": "fake"}

        provider = FakeProvider()
        result = generate_style_candidate(self.settings, "Match the screenshots.", provider)
        self.assertEqual(result["screenshot_count"], 1)
        self.assertEqual(provider.prompt, "Match the screenshots.")
        self.assertEqual(provider.quality, "medium")
        self.assertEqual(len(provider.images), 1)
        self.assertTrue(provider.images[0][1].startswith(b"\x89PNG"))
        removed = remove_style_screenshot(self.settings, saved["screenshots"][0])
        self.assertEqual(removed["screenshots"], [])

    def test_prompt_override_is_sent_without_the_palette(self):
        from generators.orchestrator import _prompts, normalize_request

        request = normalize_request(self.settings, {
            "kind": "texture",
            "category": "item_icon",
            "name": "debugweapon",
            "provider": "openai",
            "prompt_override": "Side view of one pistol. No extra palette line.",
        })
        prompts = _prompts(self.settings, request)
        self.assertEqual(prompts["provider_prompt"], "Side view of one pistol. No extra palette line.")
        uploads = self.settings.library_dir / "uploads"
        uploads.mkdir(parents=True, exist_ok=True)
        reference = uploads / "pistol.png"
        reference.write_bytes(b"\x89PNG\r\n\x1a\n")
        with_image = normalize_request(self.settings, {
            "kind": "texture",
            "category": "item_icon",
            "name": "debugweapon",
            "provider": "openai",
            "reference_images": [str(reference)],
        })
        self.assertEqual(with_image["reference_images"], [str(reference.resolve())])
        with self.assertRaises(PipelineError):
            normalize_request(self.settings, {
                "kind": "texture",
                "category": "item_icon",
                "name": "debugweapon",
                "provider": "openai",
                "reference_images": [str(self.temp / "outside.png")],
            })

    def test_local_item_icon_is_painted_without_an_image_provider(self):
        from PIL import Image

        self.settings.openai_key = ""
        job = self.store.create_job(
            {
                "kind": "texture",
                "category": "item_icon",
                "name": "debugweapon",
                "provider": "procedural",
                "resolution": 64,
                "icon_category": "weapon",
                "swatch": [0.35, 0.38, 0.42],
                "prompt": "Debug Weapon",
            }
        )
        execute_job(self.settings, self.store, job)
        self.assertEqual(job["status"], "ready_for_review", job.get("errors"))
        asset = self.store.get_asset(job["asset_ids"][0])
        self.assertEqual(asset["model"], "procedural-item-icon")
        self.assertEqual(asset["maps_origin"]["albedo"], "procedural")
        self.assertEqual(asset["maps_origin"]["normal"], "derived_from_albedo")
        with Image.open(self.store.asset_dir(asset["asset_id"]) / "preview" / "icon.png") as image:
            self.assertEqual(image.size, (64, 64))
            corner = image.getpixel((2, 2))
            barrel = image.getpixel((48, 28))
        self.assertEqual(corner[3], 0)
        self.assertGreater(barrel[3], 0)
        self.assertNotEqual(corner, barrel)

    def test_character_without_a_provider_explains_the_rig_fallback(self):
        meshes, materials = build_piece("crate", self.settings.grid())
        path = self.temp / "unrigged.glb"
        write_glb(path, meshes, materials)
        report = validate_mesh(path, "character", False)
        self.assertFalse(report["ok"])
        self.assertTrue(any("skin" in error.lower() for error in report["errors"]))

    def test_dashboard_queues_a_job_without_blocking(self):
        app = App(self.settings)
        server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(app))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        port = server.server_address[1]
        try:
            body = json.dumps(
                {"kind": "building", "category": "barricade", "name": "road_block", "resolution": 32, "polycount": 1000}
            ).encode("utf-8")
            request = urllib.request.Request(
                f"http://127.0.0.1:{port}/api/jobs",
                data=body,
                headers={"Content-Type": "application/json"},
            )
            with urllib.request.urlopen(request, timeout=5) as response:
                self.assertEqual(response.status, 202)
                job = json.loads(response.read().decode("utf-8"))
            self.assertIn(job["status"], {"waiting", "generating", "processing", "ready_for_review"})
            for _ in range(50):
                with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/jobs/{job['job_id']}", timeout=5) as response:
                    current = json.loads(response.read().decode("utf-8"))
                if current["status"] in {"ready_for_review", "failed"}:
                    break
                threading.Event().wait(0.1)
            self.assertEqual(current["status"], "ready_for_review", current.get("errors"))
            bootstrap = json.loads(urllib.request.urlopen(f"http://127.0.0.1:{port}/api/bootstrap", timeout=5).read().decode("utf-8"))
            self.assertNotIn("OPENAI_API_KEY", json.dumps(bootstrap))
            self.assertNotIn("MESHY_API_KEY", json.dumps(bootstrap))
            self.assertNotIn("TRIPO_API_KEY", json.dumps(bootstrap))
        finally:
            server.shutdown()
            server.server_close()

    def test_item_gallery_reads_every_game_item(self):
        items = load_items(PROJECT)
        by_id = {item["id"]: item for item in items}
        self.assertGreaterEqual(len(items), 140)
        self.assertEqual(len(by_id), len(items))
        hatchet = by_id["hatchet_scrap"]
        self.assertEqual(hatchet["display_name"], "Scrap Hatchet")
        self.assertEqual(hatchet["category"], "tool")
        self.assertAlmostEqual(hatchet["swatch"][0], 0.62)
        self.assertIn("needs_art", hatchet)
        self.assertIn("has_art", hatchet)
        self.assertEqual(hatchet["needs_art"], not hatchet["has_art"])
        self.assertIn("medical", {item["category"] for item in items})
        deployables = [item for item in items if item["category"] == "deployable"]
        self.assertGreaterEqual(len(deployables), 30)
        self.assertTrue(any(item["id"].startswith("door_") for item in deployables))
        workbench = by_id["workbench"]
        self.assertEqual(workbench["footprint"], [2, 1])
        self.assertAlmostEqual(workbench["height"], 1.428)
        self.assertEqual(workbench["target_size"], [1.81, 1.428, 0.81])
        self.assertIn("needs_world_art", workbench)
        self.assertEqual(workbench["needs_world_art"], not workbench["has_world_art"])
        self.assertEqual(by_id["hatchet_scrap"]["target_size"], [0.38, 0.28, 0.38])

    def test_deployable_from_icon_job_normalizes_with_target_size(self):
        from generators.orchestrator import normalize_request, stage_item_icon

        folder = self.settings.library_dir / "uploads"
        folder.mkdir(parents=True, exist_ok=True)
        concept = folder / "bench.png"
        concept.write_bytes(b"\x89PNG\r\n\x1a\nfake")
        request = normalize_request(self.settings, {
            "workshop_category": "deployables",
            "category": "from_icon",
            "name": "workbench",
            "provider": "manual",
            "source_file": str(concept),
            "target_size": [1.81, 1.428, 0.81],
            "subject_override": "Workbench",
        })
        self.assertEqual(request["kind"], "deployable")
        self.assertEqual(request["category"], "from_icon")
        self.assertEqual(request["target_size"], [1.81, 1.428, 0.81])
        self.assertEqual(request["mesh_provider"], "meshy")
        icons = PROJECT / "assets" / "icons"
        sample = next(icons.glob("*.png"), None)
        if sample is not None:
            staged = stage_item_icon(Settings(library_dir=self.settings.library_dir, project_root=PROJECT), sample.stem)
            self.assertTrue(Path(staged["path"]).is_file())
            self.assertEqual(staged["item_id"], sample.stem)

    def test_world_props_are_gallery_rows_with_a_target_size(self):
        import importlib.util

        spec = importlib.util.spec_from_file_location("gen_world_props", PROJECT / "tools" / "gen_world_props.py")
        gen = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(gen)
        authored = {entry[0]: entry for entry in gen.PROPS}
        on_disk = {path.stem for path in (PROJECT / "resources" / "world_props").glob("*.tres")}
        self.assertEqual(on_disk, set(authored), "run python tools/gen_world_props.py")

        items = load_items(PROJECT)
        by_id = {item["id"]: item for item in items}
        props = {item["id"]: item for item in items if item["category"] == "world_prop"}
        self.assertEqual(set(props), set(authored))
        self.assertEqual(len(by_id), len(items), "a world prop id collides with an item id")
        for prop_id, entry in authored.items():
            row = props[prop_id]
            self.assertEqual(row["target_size"], [round(axis, 4) for axis in entry[4]])
            self.assertEqual(row["mount"], "world")
            self.assertEqual(row["height"], entry[4][1])
            self.assertEqual(row["display_name"], entry[1])
            self.assertEqual(row["prop_kind"], entry[2])
            self.assertEqual(row["deposit_id"], entry[3])
            self.assertEqual(row["needs_art"], not row["has_art"])
            self.assertEqual(row["needs_world_art"], not row["has_world_art"])
        self.assertEqual(props["tree_oak"]["target_size"], [2.99, 5.14, 2.99])
        self.assertEqual(props["broken_car"]["deposit_id"], "broken_car")

    def test_world_prop_ids_match_the_game_catalogs(self):
        import re

        text = (PROJECT / "scripts" / "world" / "world_prop_catalog.gd").read_text(encoding="utf-8")
        order = re.search(r"const ORDER: PackedStringArray = \[(.*?)\]", text, re.S).group(1)
        ordered = re.findall(r'"([a-z0-9_]+)"', order)
        on_disk = sorted(path.stem for path in (PROJECT / "resources" / "world_props").glob("*.tres"))
        self.assertEqual(sorted(ordered), on_disk)
        deployables = set(json.loads((ROOT / "config" / "deployable_dimensions.json").read_text(encoding="utf-8"))["items"])
        self.assertFalse(deployables & set(ordered), "a world prop id collides with a deployable id")
        resources = (PROJECT / "scripts" / "items" / "resource_catalog.gd").read_text(encoding="utf-8")
        for deposit_id in re.findall(r'^\t_add(?:_tree|_flora|_scavenge)?\(\s*"([a-z0-9_]+)"', resources, re.M):
            definition = (PROJECT / "resources" / "world_props").glob("*.tres")
            self.assertTrue(
                any(f'deposit_id = "{deposit_id}"' in path.read_text(encoding="utf-8") for path in definition),
                f"deposit {deposit_id} has no world prop",
            )

    def test_world_prop_from_icon_job_normalizes_with_target_size(self):
        from generators.orchestrator import normalize_request

        folder = self.settings.library_dir / "uploads"
        folder.mkdir(parents=True, exist_ok=True)
        concept = folder / "oak.png"
        concept.write_bytes(b"\x89PNG\r\n\x1a\nfake")
        request = normalize_request(self.settings, {
            "workshop_category": "resources",
            "category": "from_icon",
            "name": "tree_oak",
            "provider": "manual",
            "source_file": str(concept),
            "target_size": [2.99, 5.14, 2.99],
            "subject_override": "Oak Tree",
        })
        self.assertEqual(request["kind"], "resource")
        self.assertEqual(request["category"], "from_icon")
        self.assertEqual(request["godot_folder"], "resources")
        self.assertEqual(request["target_size"], [2.99, 5.14, 2.99])
        self.assertTrue(request["expect_collision"])
        self.assertEqual(request["icon_category"], "misc")
        icon_job = normalize_request(self.settings, {
            "kind": "texture",
            "category": "item_icon",
            "name": "tree_oak",
            "provider": "procedural",
            "resolution": 64,
            "icon_category": "world_prop",
            "swatch": [0.42, 0.28, 0.16],
            "prompt": "Oak Tree",
        })
        self.assertEqual(icon_job["icon_category"], "world_prop")

    def test_world_prop_icon_is_painted_without_an_image_provider(self):
        from processors.icons import procedural_icon

        image = procedural_icon(64, "world_prop", [0.52, 0.52, 0.50], 1)
        self.assertEqual(image.getpixel((2, 2))[3], 0)
        self.assertGreater(image.getpixel((26, 36))[3], 0)

    def test_world_prop_description_is_saved_in_its_own_file(self):
        from godot.descriptions import _item_file

        path = _item_file(PROJECT, "tree_oak")
        self.assertEqual(path.parent.name, "world_props")

    def test_texture_gallery_reads_building_colors(self):
        surfaces = load_surfaces(PROJECT)
        by_id = {item["id"]: item for item in surfaces}
        self.assertEqual(len(surfaces), 12)
        self.assertFalse(any(item["category"] in {"post", "stairs"} for item in surfaces))
        wood = by_id["wall_wood"]
        self.assertEqual(wood["display_name"], "Wood Wall")
        self.assertEqual(wood["category"], "wall")
        self.assertAlmostEqual(wood["swatch"][0], 0.78)
        self.assertAlmostEqual(wood["swatch"][1], 0.60)
        self.assertEqual(wood["pipeline_category"], "wood")
        self.assertNotIn("post_scrap", by_id)
        self.assertAlmostEqual(by_id["floor_concrete"]["swatch"][0], 0.72)
        self.assertEqual(by_id["floor_concrete"]["pipeline_category"], "concrete_floor")
        self.assertTrue(by_id["wall_concrete"]["has_art"])
        self.assertTrue(by_id["floor_concrete"]["has_art"])
        self.assertTrue(by_id["wall_wood"]["has_art"])
        self.assertNotIn("flat color", by_id["wall_wood"]["description"].lower())



    def test_ground_textures_are_listed_with_the_building_surfaces(self):
        from godot.surface_index import load_vegetation

        grounds = {item["id"]: item for item in load_grounds(PROJECT)}
        self.assertEqual(set(grounds), {
            "ground_grass",
            "ground_forest_oak",
            "ground_forest_birch",
            "ground_forest_spruce",
            "ground_dirt",
            "ground_rock",
            "ground_asphalt",
            "ground_meadow",
            "ground_sand",
            "ground_clay",
            "ground_gravel",
            "ground_water",
            "ground_gas",
            "ground_oil",
        })
        self.assertEqual(grounds["ground_grass"]["pipeline_category"], "grass")
        self.assertEqual(grounds["ground_forest_oak"]["pipeline_category"], "forest_oak")
        self.assertEqual(grounds["ground_forest_birch"]["pipeline_category"], "forest_birch")
        self.assertEqual(grounds["ground_forest_spruce"]["pipeline_category"], "forest_spruce")
        self.assertEqual(grounds["ground_forest_oak"]["material"], "Forest")
        self.assertEqual(grounds["ground_forest_oak"]["category"], "forest")
        self.assertEqual(grounds["ground_forest_birch"]["category"], "forest")
        self.assertEqual(grounds["ground_forest_spruce"]["category"], "forest")
        self.assertEqual(grounds["ground_rock"]["pipeline_category"], "rock")
        self.assertEqual(grounds["ground_asphalt"]["pipeline_category"], "asphalt")
        self.assertEqual(grounds["ground_meadow"]["pipeline_category"], "meadow")
        self.assertEqual(grounds["ground_oil"]["pipeline_category"], "oil")
        self.assertEqual(grounds["ground_water"]["category"], "ground")

        self.assertFalse(grounds["ground_asphalt"]["needs_art"])
        self.assertFalse(grounds["ground_dirt"]["needs_art"])
        plants = {item["id"]: item for item in load_vegetation(PROJECT)}
        self.assertEqual(set(plants), {
            "tree_oak",
            "tree_birch",
            "tree_spruce",
            "stone_boulder",
            "grass_tuft",
            "fern",
        })
        self.assertEqual(plants["tree_oak"]["asset_kind"], "prop")
        self.assertEqual(plants["fern"]["pipeline_category"], "fern")
        self.assertTrue(plants["grass_tuft"]["needs_art"])

    def test_subject_override_replaces_the_category_words(self):
        prompts = preview_prompt(
            self.settings,
            {
                "kind": "texture",
                "category": "concrete_wall",
                "name": "wall_concrete",
                "provider": "procedural",
                "subject_override": "wide painted concrete panels",
                "prompt": "",
            },
        )
        self.assertIn("wide painted concrete panels", prompts["prompt"])
        self.assertNotIn("form-tie", prompts["prompt"])
        self.assertIn("Seamless tileable", prompts["prompt"])
        plain = preview_prompt(
            self.settings,
            {
                "kind": "texture",
                "category": "concrete_wall",
                "name": "wall_concrete",
                "provider": "procedural",
            },
        )
        self.assertNotIn("strong readable silhouette", plain["prompt"].lower())
        self.assertNotIn("isometric-friendly", plain["prompt"].lower())
        self.assertNotIn("point to the right", plain["prompt"].lower())
        self.assertIn("no object", plain["prompt"].lower())
        self.assertIn("form-tie", plain["prompt"])

    def test_item_and_surface_copy_stay_separate(self):
        root = self.settings.project_root
        item = root / "resources" / "items" / "sample.tres"
        item.parent.mkdir(parents=True)
        item.write_text(
            '[gd_resource type="Resource" format=3]\n\n[resource]\nid = "sample"\ndisplay_name = "Sample"\ndescription = "Old text."\ncategory = "misc"\n',
            encoding="utf-8",
        )
        self.settings.descriptions_path = self.temp / "descriptions.json"
        saved = save_item_copy(self.settings, "sample", 'A "quoted" note.', "round tin, side view")
        text = item.read_text(encoding="utf-8")
        self.assertIn('description = "A \\"quoted\\" note."', text)
        self.assertIn('id = "sample"', text)
        self.assertEqual(saved["description"], 'A "quoted" note.')
        self.assertEqual(saved["image_description"], "round tin, side view")
        cleared = save_item_copy(self.settings, "sample", "A quoted note.", "")
        self.assertEqual(cleared["image_description"], "")
        stored = json.loads(self.settings.descriptions_path.read_text(encoding="utf-8"))
        self.assertNotIn("sample", stored["items"])

        self.settings.project_root = PROJECT
        surface = save_surface_copy(self.settings, "wall_wood", "Warm boards.", "wide painted plank")
        self.assertEqual(surface["description"], "Warm boards.")
        self.assertEqual(surface["image_description"], "wide painted plank")
        loaded = {item["id"]: item for item in load_surfaces(PROJECT, load_descriptions(self.settings))}
        self.assertEqual(loaded["wall_wood"]["image_description"], "wide painted plank")
        self.assertEqual(loaded["floor_wood"]["description"], "Wood floor surface.")
        reset = save_surface_copy(self.settings, "wall_wood", "", "")
        self.assertEqual(reset["description"], "Wood wall surface.")
        self.assertEqual(reset["image_description"], "")
        with self.assertRaises(PipelineError):
            save_surface_copy(self.settings, "not_a_surface", "no", "no")

    def test_discard_removes_an_unapproved_review_copy(self):
        job = self.store.create_job(
            {
                "kind": "texture",
                "category": "item_icon",
                "name": "debugweapon",
                "provider": "procedural",
                "resolution": 32,
                "icon_category": "weapon",
                "swatch": [0.35, 0.38, 0.42],
            }
        )
        execute_job(self.settings, self.store, job)
        asset_id = job["asset_ids"][0]
        folder = self.store.asset_dir(asset_id)
        self.assertTrue(folder.is_dir())
        discarded = discard_asset(self.store, asset_id)
        self.assertTrue(discarded["deleted"])
        self.assertFalse(folder.exists())
        with self.assertRaises(KeyError):
            self.store.get_asset(asset_id)

    def test_workshop_openai_concept_uses_style_prompt_builder(self):
        from generators.orchestrator import normalize_request, preview_prompt

        folder = self.settings.library_dir / "uploads"
        folder.mkdir(parents=True, exist_ok=True)
        request = normalize_request(self.settings, {
            "workshop_category": "characters",
            "category": "survivor",
            "name": "concept_survivor",
            "provider": "openai",
            "mesh_provider": "meshy",
            "prompt": "worn green jacket",
        })
        self.assertEqual(request["provider"], "openai")
        self.assertTrue(request["humanoid"])
        preview = preview_prompt(self.settings, request)
        style = self.settings.style()
        self.assertIn(style["summary"].split(",")[0], preview["prompt"])
        self.assertIn("worn green jacket", preview["prompt"])
        self.assertIn("A-pose", preview["prompt"])
        self.assertIn("photorealism", preview["prompt"].lower())

    def test_skeleton_normalize_maps_meshy_bones_to_godot(self):
        from processors.skeleton_normalize import load_skeleton_profile, plan_renames, normalize_glb_skeleton
        from processors.gltf_write import Mesh, write_glb, read_glb_json

        profile = load_skeleton_profile(ROOT / "config" / "humanoid_skeleton.json")
        plan = plan_renames(
            ["Hips", "Spine", "Spine01", "Spine02", "neck", "Head", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"],
            profile,
        )
        self.assertEqual(plan["renames"]["LeftArm"], "LeftUpperArm")
        self.assertEqual(plan["renames"]["neck"], "Neck")
        self.assertEqual(plan["missing_required"], [])
        path = self.temp / "plain.glb"
        mesh = Mesh("Body")
        mesh.add_tri((0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1))
        write_glb(path, [mesh], [{"name": "mat", "base_color": [0.5, 0.5, 0.5, 1.0]}])
        out = self.temp / "normalized.glb"
        result = normalize_glb_skeleton(path, out, profile)
        self.assertTrue(out.is_file())
        self.assertEqual(result["renamed_bones"], 0)
        self.assertEqual(read_glb_json(out)["asset"]["version"], "2.0")

    def test_character_template_scene_has_attachment_points(self):
        from godot.animation_library import load_meshy_actions
        from godot.character_template import write_character_scene

        glb = self.temp / "hero.glb"
        glb.write_bytes(b"glTF")
        scene = self.temp / "hero.tscn"
        actions = load_meshy_actions(ROOT / "config" / "meshy_actions.json")
        write_character_scene(
            scene,
            "hero",
            glb,
            self.temp,
            {},
            actions=actions,
            clip_names=["idle", "walk", "run"],
            equipment_slots={"helmet": {"attach_bone": "Head", "mesh_name": "Helmet"}},
        )
        text = scene.read_text(encoding="utf-8")
        self.assertIn('type="CharacterBody3D"', text)
        self.assertIn("AttachmentPoints", text)
        self.assertIn("PrimaryWeapon", text)
        self.assertIn("AnimationTree", text)
        self.assertIn("AnimationNodeBlendSpace1D", text)
        self.assertIn("active = true", text)
        self.assertIn("Equipment", text)
        self.assertIn("helmet", text)

    def test_phase5_shared_animation_library_index(self):
        from godot.animation_library import load_meshy_actions, clip_set, shared_clip_name, update_library_index

        actions = load_meshy_actions(ROOT / "config" / "meshy_actions.json")
        clips = clip_set(actions)
        self.assertIn("walk", clips)
        self.assertEqual(shared_clip_name("walk", clips["walk"]), "walk")
        self.assertEqual(clips["walk"]["from_rig_basic"], "walking_glb")
        index_path = self.temp / "library_index.json"
        payload = update_library_index(index_path, {"walk": {"path": "assets/characters/Shared/Animations/walk.glb", "source": "meshy"}})
        self.assertTrue(index_path.is_file())
        self.assertEqual(payload["clips"]["walk"]["source"], "meshy")

    def test_quaternius_shared_library_wires_character_scene(self):
        from godot.animation_library import load_shared_animation_library, resolve_shared_library
        from godot.character_template import write_character_scene

        cfg = load_shared_animation_library(ROOT / "config" / "shared_animation_library.json")
        self.assertEqual(cfg["provider"], "quaternius")
        self.assertEqual(cfg["clips"]["idle"], "Idle")
        shared_dir = self.temp / "assets" / "characters" / "Shared" / "Quaternius"
        shared_dir.mkdir(parents=True)
        (shared_dir / "ual_locomotion.res").write_bytes(b"GDRES")
        shared = resolve_shared_library(self.temp, cfg)
        self.assertIsNotNone(shared)
        glb = self.temp / "hero.glb"
        glb.write_bytes(b"glTF")
        scene = self.temp / "hero.tscn"
        write_character_scene(scene, "hero", glb, self.temp, {}, shared_library=shared)
        text = scene.read_text(encoding="utf-8")
        self.assertIn("ual_locomotion.res", text)
        self.assertIn("Idle", text)
        self.assertIn("Walk", text)
        self.assertIn("Walk_Bwd", text)
        self.assertIn("Walk_L", text)
        self.assertIn("Walk_R", text)
        self.assertIn("AnimationNodeBlendSpace2D", text)
        self.assertIn("active = true", text)

    def test_phase6_clothing_slot_matching(self):
        from processors.clothing import analyze_clothing_glb, clothing_export_plan, load_clothing_slots, match_slots
        from processors.gltf_write import Mesh, write_glb

        slots = load_clothing_slots(ROOT / "config" / "clothing_slots.json")
        matched = match_slots(["Body", "Helmet", "Backpack", "LooseProp"], slots)
        self.assertTrue(matched["slots"]["body"]["present"])
        self.assertTrue(matched["slots"]["helmet"]["present"])
        self.assertIn("LooseProp", matched["unmatched_meshes"])
        path = self.temp / "dressed.glb"
        body = Mesh("Body")
        body.add_tri((0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1))
        helmet = Mesh("Helmet")
        helmet.add_tri((0, 1, 0), (1, 1, 0), (0, 2, 0), (0, 1, 0))
        write_glb(path, [body, helmet], [{"name": "mat", "base_color": [0.5, 0.5, 0.5, 1.0]}])
        analysis = analyze_clothing_glb(path, slots)
        self.assertTrue(analysis["slots"]["body"]["present"] or analysis["slots"]["helmet"]["present"])
        plan = clothing_export_plan(analysis, self.temp / "clothing")
        self.assertTrue(any(item["slot"] in {"body", "helmet"} for item in plan))

    def test_phase7_cost_summary_and_budget_gate(self):
        from core.costs import check_budget, summarize_costs

        records = [
            {"provider": "meshy", "operation": "rigging", "category": "characters", "actual_usd": 1.5, "created_at": "2026-11-03T10:00:00Z"},
            {"provider": "tripo", "operation": "image_to_model", "category": "enemies", "estimated_usd": 0.2, "created_at": "2026-11-03T11:00:00Z"},
            {"provider": "openai", "operation": "image_generation", "category": "characters", "created_at": "2026-11-03T12:00:00Z"},
        ]
        summary = summarize_costs(records, {"currency": "USD", "monthly_usd": 50})
        self.assertAlmostEqual(summary["total_usd"], 1.7, places=4)
        self.assertEqual(summary["unknown_records"], 1)
        self.assertIn("meshy", summary["by_provider"])
        soft = check_budget({"monthly_usd": 1.0, "hard_limit": False}, records=records, estimated_usd=0.5)
        self.assertTrue(soft["ok"])
        self.assertTrue(soft["warnings"])
        hard = check_budget({"monthly_usd": 1.0, "hard_limit": True}, records=records, estimated_usd=0.5)
        self.assertTrue(hard["blocked"])
        self.assertFalse(hard["ok"])

    def test_phase8_optimization_profiles_resolve(self):
        from core.optimization import blender_job_fields, load_profiles, resolve_profile

        profiles = load_profiles(ROOT / "config" / "optimization_profiles.json")
        character = resolve_profile("character", profiles=profiles, defaults=self.settings.defaults)
        self.assertEqual(character["target_polycount"], 12000)
        self.assertFalse(character["add_collision"])
        self.assertTrue(character["preserve_skin"])
        deployable = resolve_profile("deployable", profiles=profiles, defaults=self.settings.defaults)
        self.assertTrue(deployable["add_collision"])
        fields = blender_job_fields(character)
        self.assertEqual(fields["optimization_profile"], "character")
        self.assertFalse(fields["add_collision"])

    def test_threed_provider_protocol_and_capabilities(self):
        meshy = MeshyProvider("", "latest", 10, 1)
        tripo = TripoProvider("", "v2.5-20250123", 10, 1)
        self.assertIsInstance(meshy, ThreeDProvider)
        self.assertIsInstance(tripo, ThreeDProvider)
        self.assertIn(CAP_GENERATE_MODEL, meshy.capabilities)
        self.assertIn(CAP_HUMANOID_RIG, meshy.capabilities)
        self.assertIn(CAP_ANIMATE, meshy.capabilities)
        self.assertIn(CAP_ALT_RIG, tripo.capabilities)
        self.assertEqual(recommended_mesh_provider("creature"), "tripo")
        self.assertEqual(recommended_mesh_provider("survivor"), "meshy")
        matrix = capability_matrix()
        self.assertIn(CAP_ANIMATE, matrix["meshy"])
        self.assertIn(CAP_ALT_RIG, matrix["tripo"])
        self.assertEqual(threed_from(self.settings, "meshy_text").name, "meshy")
        self.assertEqual(threed_from(self.settings, "tripo").name, "tripo")

    def test_workshop_static_profiles_normalize(self):
        from generators.orchestrator import normalize_request

        folder = self.settings.library_dir / "uploads"
        folder.mkdir(parents=True, exist_ok=True)
        concept = folder / "concept.png"
        concept.write_bytes(b"\x89PNG\r\n\x1a\nfake")
        deployable = normalize_request(self.settings, {
            "workshop_category": "deployables",
            "category": "turret",
            "name": "field_turret",
            "provider": "manual",
            "source_file": str(concept),
        })
        self.assertEqual(deployable["kind"], "deployable")
        self.assertEqual(deployable["godot_folder"], "deployables")
        self.assertTrue(deployable["expect_collision"])
        self.assertFalse(deployable["auto_rig"])
        resource = normalize_request(self.settings, {
            "workshop_category": "resources",
            "category": "scrap_pile",
            "name": "scrap_a",
            "mesh_provider": "meshy_text",
        })
        self.assertEqual(resource["kind"], "resource")
        creature = normalize_request(self.settings, {
            "workshop_category": "enemies",
            "category": "creature",
            "name": "mutant_dog",
            "provider": "manual",
            "source_file": str(concept),
        })
        self.assertFalse(creature["humanoid"])
        self.assertEqual(creature["mesh_provider"], "tripo")
        self.assertFalse(creature["auto_rig"])
        raider = normalize_request(self.settings, {
            "workshop_category": "enemies",
            "category": "humanoid_raider",
            "name": "raider_a",
            "provider": "manual",
            "source_file": str(concept),
        })
        self.assertTrue(raider["humanoid"])
        self.assertTrue(raider["auto_rig"])
        self.assertFalse(raider["auto_animate"])
        survivor = normalize_request(self.settings, {
            "workshop_category": "characters",
            "category": "survivor",
            "name": "survivor_a",
            "provider": "manual",
            "source_file": str(concept),
        })
        self.assertTrue(survivor["auto_rig"])
        self.assertFalse(survivor["auto_animate"])
        animated = normalize_request(self.settings, {
            "workshop_category": "characters",
            "category": "survivor",
            "name": "survivor_b",
            "provider": "manual",
            "source_file": str(concept),
            "auto_animate": True,
        })
        self.assertTrue(animated["auto_animate"])
        self.assertEqual(resolve_category(self.settings.workshop(), "decorations")["kind"], "decoration")

    def test_production_stats_count_approved_assets(self):
        asset = self.store.create_asset({
            "asset_name": "scrap_pile_demo",
            "category": "scrap_pile",
            "kind": "resource",
            "workshop_category": "resources",
            "generation_parameters": {"workshop_category": "resources", "godot_folder": "resources"},
        })
        asset["approval_status"] = "approved"
        asset["processing_status"] = "approved"
        self.store.save_asset(asset)
        pending = self.store.create_asset({
            "asset_name": "turret_review",
            "category": "turret",
            "kind": "deployable",
            "workshop_category": "deployables",
            "generation_parameters": {"workshop_category": "deployables"},
            "processing_status": "ready_for_review",
        })
        self.store.save_asset(pending)
        stats = production_stats(self.store, self.settings.project_root, self.settings.workshop())
        by_id = {row["id"]: row for row in stats["rows"]}
        self.assertEqual(by_id["resources"]["approved"], 1)
        self.assertEqual(by_id["deployables"]["pending_review"], 1)
        self.assertEqual(infer_workshop_category(asset), "resources")
        self.assertEqual(stats["totals"]["target"], 280)

    def test_generation_task_and_cost_records_persist(self):
        task = self.store.create_generation_task(
            {
                "job_id": "job1",
                "asset_id": "asset1",
                "provider": "meshy",
                "operation": "image_to_3d",
                "status": "generating",
                "input": {"polycount": 8000},
            }
        )
        self.store.update_generation_task(task["task_id"], status="succeeded", provider_task_id="prov-1", consumed_credits=30)
        loaded = self.store.get_generation_task(task["task_id"])
        self.assertEqual(loaded["provider_task_id"], "prov-1")
        self.assertEqual(loaded["status"], "succeeded")
        self.assertTrue(loaded["completed_at"])
        pricing = load_pricing()
        estimate = estimate_operation(pricing, "tripo", "image_to_model")
        self.assertTrue(estimate["known"])
        self.assertEqual(estimate["credits"], 20)
        self.assertAlmostEqual(estimate["estimated_usd"], 0.2)
        unknown = estimate_operation(pricing, "openai", "image_generation")
        self.assertFalse(unknown["known"])
        cost = self.store.create_cost_record(
            {
                "provider": "meshy",
                "operation": "image_to_3d",
                "asset_id": "asset1",
                "generation_task_id": task["task_id"],
                "credits": 30,
                "known": True,
            }
        )
        listed = self.store.list_cost_records(asset_id="asset1")
        self.assertEqual(listed[0]["cost_id"], cost["cost_id"])
        self.assertEqual(len(self.store.list_generation_tasks(asset_id="asset1")), 1)

    def test_existing_game_files_are_unchanged_by_the_pipeline_package(self):
        project = (PROJECT / "project.godot").read_text(encoding="utf-8")
        self.assertIn('renderer/rendering_method="forward_plus"', project)
        self.assertIn('config/features=PackedStringArray("4.7", "Forward Plus")', project)
        geometry = (PROJECT / "scripts" / "building" / "building_geometry.gd").read_text(encoding="utf-8")
        self.assertIn("class_name BuildingGeometry", geometry)
        player = (PROJECT / "scenes" / "player" / "player.tscn").read_text(encoding="utf-8")
        # The capsule body mesh was replaced by the Quaternius mannequin. The
        # collision capsule and the player script are what must stay.
        self.assertIn("CapsuleShape3D", player)
        self.assertIn("player_controller.gd", player)


if __name__ == "__main__":
    unittest.main()
