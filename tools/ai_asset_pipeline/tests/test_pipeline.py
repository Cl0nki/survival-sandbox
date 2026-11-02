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
from providers.meshy import image_to_3d_payload, text_preview_payload, text_refine_payload
from providers.openai_images import OpenAIImageProvider, generation_payload
from providers.tripo import image_to_model_payload


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
        prompts = build_prompts(style, {"prompt": "military backpack"}, "scuffed canvas", "prop")
        self.assertIn("#354451", prompts["prompt"])
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
        self.assertTrue(image["enable_pbr"])
        self.assertNotIn("pose_mode", image)
        character = image_to_3d_payload(b"\x89PNG\r\n", 12000, "1024", True, "latest")
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
        self.assertIn("#354451", asset["prompt"])
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
        self.assertTrue(hatchet["needs_art"])
        self.assertFalse(hatchet["has_art"])
        self.assertIn("medical", {item["category"] for item in items})
        deployables = [item for item in items if item["category"] == "deployable"]
        self.assertGreaterEqual(len(deployables), 30)
        self.assertTrue(any(item["id"].startswith("door_") for item in deployables))

    def test_texture_gallery_reads_building_colors(self):
        surfaces = load_surfaces(PROJECT)
        by_id = {item["id"]: item for item in surfaces}
        self.assertEqual(len(surfaces), 24)
        wood = by_id["wall_wood"]
        self.assertEqual(wood["display_name"], "Wood Wall")
        self.assertEqual(wood["category"], "wall")
        self.assertAlmostEqual(wood["swatch"][0], 0.78)
        self.assertAlmostEqual(wood["swatch"][1], 0.60)
        self.assertEqual(wood["pipeline_category"], "wood")
        self.assertAlmostEqual(by_id["post_scrap"]["swatch"][0], 0.36)
        self.assertAlmostEqual(by_id["floor_concrete"]["swatch"][0], 0.72)
        self.assertEqual(by_id["floor_concrete"]["pipeline_category"], "concrete_floor")
        self.assertTrue(by_id["wall_concrete"]["has_art"])
        self.assertTrue(by_id["floor_concrete"]["has_art"])
        self.assertTrue(by_id["wall_wood"]["needs_art"])
        self.assertNotIn("flat color", by_id["wall_wood"]["description"].lower())
        self.assertEqual(by_id["wall_wood"]["image_description"], "")

    def test_ground_textures_are_listed_with_the_building_surfaces(self):
        grounds = {item["id"]: item for item in load_grounds(PROJECT)}
        self.assertEqual(set(grounds), {
            "ground_grass",
            "ground_dirt",
            "ground_rock",
            "ground_meadow",
            "ground_sand",
            "ground_clay",
            "ground_gravel",
            "ground_water",
            "ground_gas",
            "ground_oil",
        })
        self.assertEqual(grounds["ground_grass"]["pipeline_category"], "grass")
        self.assertEqual(grounds["ground_rock"]["pipeline_category"], "rock")
        self.assertEqual(grounds["ground_meadow"]["pipeline_category"], "meadow")
        self.assertEqual(grounds["ground_oil"]["pipeline_category"], "oil")
        self.assertEqual(grounds["ground_water"]["category"], "ground")
        self.assertTrue(grounds["ground_rock"]["needs_art"])
        self.assertTrue(grounds["ground_meadow"]["needs_art"])

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

    def test_existing_game_files_are_unchanged_by_the_pipeline_package(self):
        project = (PROJECT / "project.godot").read_text(encoding="utf-8")
        self.assertIn('renderer/rendering_method="forward_plus"', project)
        self.assertIn('config/features=PackedStringArray("4.7", "Forward Plus")', project)
        geometry = (PROJECT / "scripts" / "building" / "building_geometry.gd").read_text(encoding="utf-8")
        self.assertIn("class_name BuildingGeometry", geometry)
        player = (PROJECT / "scenes" / "player" / "player.tscn").read_text(encoding="utf-8")
        self.assertIn("CapsuleMesh", player)


if __name__ == "__main__":
    unittest.main()
