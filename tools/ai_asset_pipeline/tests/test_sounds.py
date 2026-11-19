import io
import json
import shutil
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
import wave
import zipfile
from http.server import ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from core.errors import PipelineError
from core.settings import Settings
from dashboard.server import App, make_handler
from godot import sound_bank


def wav_bytes(seconds: float = 0.1, rate: int = 8000) -> bytes:
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(b"\x00\x00" * int(rate * seconds))
    return buffer.getvalue()


class SoundBankTests(unittest.TestCase):
    def setUp(self):
        self.temp = Path(tempfile.mkdtemp(prefix="sound-bank-"))
        self.settings = Settings(library_dir=self.temp / "library", project_root=self.temp / "project")
        self.config = self.settings.sounds()
        self.root = self.settings.project_root
        self.inbox = self.settings.sounds_inbox()

    def tearDown(self):
        shutil.rmtree(self.temp, ignore_errors=True)

    def manifest(self) -> dict:
        return json.loads((self.root / self.config["manifest"]).read_text(encoding="utf-8"))

    def test_config_covers_the_four_things_the_game_asks_for(self):
        ids = {event["id"] for event in self.config["events"]}
        self.assertTrue({"footstep", "shot", "hurt", "craft_start", "craft_done"} <= ids)
        surfaces = {"grass", "forest", "dirt", "gravel", "sand", "rock", "asphalt"}
        self.assertTrue({f"footstep_{name}" for name in surfaces} <= ids)
        self.assertTrue({"shot_far", "bullet_impact", "bullet_hit"} <= ids)
        self.assertTrue({"hog_grunt", "hog_alert", "hog_charge", "hog_hurt", "hog_die"} <= ids)
        self.assertEqual(len(ids), len(self.config["events"]), "duplicate event id")
        for event in self.config["events"]:
            self.assertLessEqual(event["pitch_min"], event["pitch_max"])
            self.assertTrue(event["keywords"])

    def test_names_are_cleaned_and_other_formats_refused(self):
        self.assertEqual(sound_bank.clean_name("Heavy Boots (Gravel) 19.WAV", self.config), "heavy_boots_gravel_19.wav")
        with self.assertRaises(PipelineError):
            sound_bank.clean_name("notes.txt", self.config)
        with self.assertRaises(PipelineError):
            sound_bank.clean_name("song.flac", self.config)

    def test_auto_sort_suggestions(self):
        suggest = lambda name: sound_bank.suggest_event(name, self.config)
        self.assertEqual(suggest("footsteps_gravel_03.wav"), "footstep_gravel")
        self.assertEqual(suggest("footstep_leaves_02.ogg"), "footstep_forest")
        self.assertEqual(suggest("steps_on_concrete.wav"), "footstep_asphalt")
        self.assertEqual(suggest("walk_sand_1.wav"), "footstep_sand")
        self.assertEqual(suggest("footsteps_01.wav"), "footstep")
        self.assertEqual(suggest("distant_gunshot_echo.wav"), "shot_far")
        self.assertEqual(suggest("bullet_impact_wall.ogg"), "bullet_impact")
        self.assertEqual(suggest("bullet_hit_flesh.ogg"), "bullet_hit")
        self.assertEqual(suggest("boar_charge_roar.ogg"), "hog_charge")
        self.assertEqual(suggest("pig_death.mp3"), "hog_die")
        self.assertEqual(suggest("pig_grunt.mp3"), "hog_grunt")
        self.assertEqual(suggest("pistol_shot_02.ogg"), "shot")
        self.assertEqual(suggest("male_hurt_grunt.mp3"), "hurt")
        self.assertEqual(suggest("anvil_hammer_wood.wav"), "craft_start")
        self.assertEqual(suggest("ding_complete.wav"), "craft_done")
        self.assertEqual(suggest("ambience_wind.wav"), "")

    def test_assigning_a_sound_writes_the_manifest_the_game_reads(self):
        outcome = sound_bank.inbox_add_upload(self.inbox, self.config, "Gravel Step.wav", wav_bytes())
        self.assertEqual(outcome["added"], ["gravel_step.wav"])
        sound_bank.assign(self.root, self.inbox, self.config, "gravel_step.wav", "footstep")
        self.assertFalse((self.inbox / "gravel_step.wav").exists())
        self.assertTrue((self.root / "assets/audio/sfx/footstep/gravel_step.wav").is_file())
        events = self.manifest()["events"]
        self.assertEqual(events["footstep"]["files"], ["res://assets/audio/sfx/footstep/gravel_step.wav"])
        self.assertEqual(events["shot"]["files"], [])
        self.assertTrue(events["footstep"]["positional"])
        for key in sound_bank.TUNE_KEYS:
            self.assertIn(key, events["footstep"])

    def test_same_name_twice_keeps_both(self):
        for _ in range(2):
            sound_bank.inbox_add_upload(self.inbox, self.config, "hit.wav", wav_bytes())
        names = [row["name"] for row in sound_bank.inbox_list(self.inbox, self.config)]
        self.assertEqual(names, ["hit.wav", "hit_2.wav"])

    def test_tuning_is_clamped_and_survives_new_files(self):
        sound_bank.tune(self.root, self.config, "shot", {"volume_db": -999, "pitch_min": 1.4, "pitch_max": 0.8, "cooldown": 99})
        row = self.manifest()["events"]["shot"]
        self.assertEqual(row["volume_db"], -40.0)
        self.assertEqual((row["pitch_min"], row["pitch_max"]), (0.8, 1.4))
        self.assertEqual(row["cooldown"], 5.0)
        sound_bank.inbox_add_upload(self.inbox, self.config, "bang.wav", wav_bytes())
        sound_bank.assign(self.root, self.inbox, self.config, "bang.wav", "shot")
        self.assertEqual(self.manifest()["events"]["shot"]["volume_db"], -40.0)
        sound_bank.reset_tuning(self.root, self.config, "shot")
        self.assertEqual(self.manifest()["events"]["shot"]["volume_db"], 0.0)
        with self.assertRaises(PipelineError):
            sound_bank.tune(self.root, self.config, "shot", {"volume_db": "loud"})

    def test_removing_a_sound_updates_the_manifest(self):
        sound_bank.inbox_add_upload(self.inbox, self.config, "ouch.wav", wav_bytes())
        sound_bank.assign(self.root, self.inbox, self.config, "ouch.wav", "hurt")
        (self.root / "assets/audio/sfx/hurt/ouch.wav.import").write_text("stub", encoding="utf-8")
        sound_bank.remove(self.root, self.config, "hurt", "ouch.wav")
        self.assertFalse((self.root / "assets/audio/sfx/hurt/ouch.wav").exists())
        self.assertFalse((self.root / "assets/audio/sfx/hurt/ouch.wav.import").exists())
        self.assertEqual(self.manifest()["events"]["hurt"]["files"], [])

    def test_a_file_dropped_in_by_hand_is_picked_up(self):
        folder = self.root / "assets/audio/sfx/craft_done"
        folder.mkdir(parents=True)
        (folder / "ding.ogg").write_bytes(b"OggS")
        (folder / "ding.ogg.import").write_text("stub", encoding="utf-8")
        snapshot = sound_bank.snapshot(self.root, self.inbox, self.config, "")
        row = next(item for item in snapshot["events"] if item["id"] == "craft_done")
        self.assertEqual([item["name"] for item in row["files"]], ["ding.ogg"])
        self.assertTrue(row["files"][0]["imported"])
        self.assertEqual(snapshot["covered"], 1)
        sound_bank.write_manifest(self.root, self.config)
        self.assertEqual(self.manifest()["events"]["craft_done"]["files"], ["res://assets/audio/sfx/craft_done/ding.ogg"])

    def test_names_cannot_escape_their_folders(self):
        for bad in ("../x.wav", "..\\x.wav", "a/b.wav", "", "UPPER.wav"):
            with self.assertRaises(PipelineError):
                sound_bank.inbox_file(self.inbox, bad)
            with self.assertRaises(PipelineError):
                sound_bank.bank_file(self.root, self.config, "hurt", bad)
        with self.assertRaises(PipelineError):
            sound_bank.bank_file(self.root, self.config, "../..", "x.wav")

    def test_zip_pack_keeps_folder_hints_and_skips_everything_else(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("Pack/Footsteps/gravel_01.wav", wav_bytes())
            archive.writestr("Pack/Footsteps/footsteps_snow.wav", wav_bytes())
            archive.writestr("Pack/readme.txt", "hello")
            archive.writestr("../escape/evil.wav", wav_bytes())
        outcome = sound_bank.inbox_add_upload(self.inbox, self.config, "pack.zip", buffer.getvalue())
        names = sorted(outcome["added"])
        self.assertIn("footsteps_gravel_01.wav", names)
        self.assertIn("footsteps_snow.wav", names)
        self.assertEqual(len(names), 3)
        self.assertFalse(any((self.temp / "escape").glob("*")))
        suggested = {row["name"]: row["suggest"] for row in sound_bank.inbox_list(self.inbox, self.config)}
        self.assertEqual(suggested["footsteps_gravel_01.wav"], "footstep_gravel")

    def test_a_bad_zip_is_reported(self):
        with self.assertRaises(PipelineError):
            sound_bank.inbox_add_upload(self.inbox, self.config, "broken.zip", b"not a zip")

    def test_folder_scan_filters_and_respects_the_limit(self):
        source = self.temp / "downloads"
        (source / "Footsteps").mkdir(parents=True)
        (source / "Guns").mkdir()
        for index in range(5):
            (source / "Footsteps" / f"step_{index}.wav").write_bytes(wav_bytes())
        (source / "Guns" / "pistol.wav").write_bytes(wav_bytes())
        (source / "Guns" / "cover.png").write_bytes(b"png")
        found = sound_bank.inbox_scan(self.inbox, self.config, str(source), "footsteps", 3)
        self.assertEqual(found["matched"], 5)
        self.assertEqual(len(found["added"]), 3)
        all_audio = sound_bank.inbox_scan(self.inbox, self.config, str(source), "", 100)
        self.assertEqual(all_audio["matched"], 6)
        with self.assertRaises(PipelineError):
            sound_bank.inbox_scan(self.inbox, self.config, str(self.temp / "missing"), "", 10)

    def test_oversized_files_are_skipped_not_copied(self):
        source = self.temp / "big"
        source.mkdir()
        (source / "huge.wav").write_bytes(b"\x00" * (int(self.config["max_file_bytes"]) + 1))
        (source / "small.wav").write_bytes(wav_bytes())
        found = sound_bank.inbox_scan(self.inbox, self.config, str(source), "", 10)
        self.assertEqual(found["skipped_large"], 1)
        self.assertEqual(found["added"], ["small.wav"])

    def test_import_needs_godot(self):
        with self.assertRaises(PipelineError):
            sound_bank.import_in_godot("", self.root)


class SoundsApiTests(unittest.TestCase):
    def setUp(self):
        self.temp = Path(tempfile.mkdtemp(prefix="sound-api-"))
        self.settings = Settings(library_dir=self.temp / "library", project_root=self.temp / "project")
        self.settings.godot_bin = ""
        self.app = App(self.settings)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.app))
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        shutil.rmtree(self.temp, ignore_errors=True)

    def get(self, path: str):
        with urllib.request.urlopen(self.base + path, timeout=5) as response:
            return response.status, response.headers.get("Content-Type", ""), response.read()

    def post_json(self, path: str, body: dict) -> dict:
        request = urllib.request.Request(
            self.base + path, data=json.dumps(body).encode("utf-8"), headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            return json.loads(response.read().decode("utf-8"))

    def upload(self, filename: str, data: bytes) -> dict:
        boundary = "----soundtest"
        body = (
            f'--{boundary}\r\nContent-Disposition: form-data; name="files"; filename="{filename}"\r\n'
            "Content-Type: application/octet-stream\r\n\r\n"
        ).encode("utf-8") + data + f"\r\n--{boundary}--\r\n".encode("utf-8")
        request = urllib.request.Request(
            self.base + "/api/sounds/upload", data=body, headers={"Content-Type": f"multipart/form-data; boundary={boundary}"}
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            return json.loads(response.read().decode("utf-8"))

    def test_page_assets_and_nav_links_are_served(self):
        for path, kind in (("/sounds", "text/html"), ("/sounds.js", "javascript"), ("/sounds.css", "text/css")):
            status, content_type, body = self.get(path)
            self.assertEqual(status, 200, path)
            self.assertIn(kind, content_type, path)
            self.assertTrue(body, path)

    def test_all_tools_share_one_design_and_top_bar(self):
        for path, kind in (("/shared.css", "text/css"), ("/shared.js", "javascript")):
            status, content_type, body = self.get(path)
            self.assertEqual(status, 200, path)
            self.assertIn(kind, content_type, path)
            self.assertTrue(body, path)
        bar = self.get("/shared.js")[2]
        for target in (b'"/"', b'"/codex"', b'"/sounds"'):
            self.assertIn(target, bar)
        for page, own_css in (("/", b"/app.css"), ("/codex", b"/codex.css"), ("/sounds", b"/codex.css")):
            html = self.get(page)[2]
            self.assertIn(b'href="/shared.css"', html, page)
            self.assertIn(b'src="/shared.js"', html, page)
            # Shared tokens must load first so page styles can override them.
            self.assertLess(html.index(b"/shared.css"), html.index(own_css), page)
        for sheet in ("/app.css", "/codex.css", "/sounds.css"):
            self.assertNotIn(b":root", self.get(sheet)[2], sheet)

    def test_upload_assign_play_tune_remove(self):
        listing = json.loads(self.get("/api/sounds")[2])
        self.assertEqual((listing["covered"], listing["total"]), (0, len(listing["events"])))
        self.assertGreaterEqual(listing["total"], 20)
        self.assertTrue(listing["sources"])

        after_upload = self.upload("boot_gravel_step.wav", wav_bytes())
        self.assertEqual([row["name"] for row in after_upload["inbox"]], ["boot_gravel_step.wav"])
        self.assertEqual(after_upload["inbox"][0]["suggest"], "footstep_gravel")

        assigned = self.post_json("/api/sounds/assign", {"name": "boot_gravel_step.wav", "event": "footstep"})
        self.assertEqual(assigned["inbox"], [])
        self.assertEqual(assigned["covered"], 1)

        status, content_type, body = self.get("/sound-file/bank/footstep/boot_gravel_step.wav")
        self.assertEqual((status, content_type), (200, "audio/wav"))
        self.assertEqual(body[:4], b"RIFF")

        tuned = self.post_json("/api/sounds/tune", {"event": "footstep", "volume_db": -12})
        footstep = next(row for row in tuned["events"] if row["id"] == "footstep")
        self.assertEqual(footstep["tuning"]["volume_db"], -12.0)

        removed = self.post_json("/api/sounds/remove", {"event": "footstep", "name": "boot_gravel_step.wav"})
        self.assertEqual(removed["covered"], 0)
        manifest = json.loads((self.settings.project_root / "resources/audio/sounds.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["events"]["footstep"]["files"], [])

    def test_errors_come_back_as_json_not_a_crash(self):
        for path, body in (
            ("/api/sounds/assign", {"name": "nope.wav", "event": "footstep"}),
            ("/api/sounds/assign", {"name": "../x.wav", "event": "footstep"}),
            ("/api/sounds/tune", {"event": "not_an_event"}),
            ("/api/sounds/import", {}),
            ("/api/sounds/scan", {"path": ""}),
            ("/api/sounds/whatever", {}),
        ):
            with self.assertRaises(urllib.error.HTTPError) as caught:
                self.post_json(path, body)
            self.assertEqual(caught.exception.code, 400, path)
            self.assertIn("error", json.loads(caught.exception.read().decode("utf-8")))
        with self.assertRaises(urllib.error.HTTPError) as caught:
            self.get("/sound-file/bank/footstep/../../../.env")
        self.assertIn(caught.exception.code, {400, 404})


if __name__ == "__main__":
    unittest.main()
