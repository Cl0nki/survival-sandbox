import json
import subprocess
from pathlib import Path

from core.redact import redact
from core.settings import Settings

SCRIPT = Path(__file__).resolve().parent / "process_mesh.py"


def blender_available(settings: Settings) -> bool:
    return bool(settings.blender_bin) and Path(settings.blender_bin).is_file()


def process_with_blender(settings: Settings, source_glb: Path, output_glb: Path, target_polycount: int, lod_ratios: list[float], log) -> dict:
    if not blender_available(settings):
        return {
            "ok": False,
            "skipped": True,
            "message": "Blender was not found. Set BLENDER_BIN in tools/ai_asset_pipeline/.env. The original GLB was kept.",
        }
    result_path = output_glb.with_suffix(".blender.json")
    job = {
        "input": str(source_glb),
        "output": str(output_glb),
        "result": str(result_path),
        "target_polycount": int(target_polycount),
        "lod_ratios": lod_ratios,
        "recalc_normals": True,
    }
    job_path = output_glb.with_suffix(".blender-job.json")
    job_path.write_text(json.dumps(job, indent=2), encoding="utf-8")
    command = [settings.blender_bin, "--background", "--python", str(SCRIPT), "--", str(job_path)]
    log("Running Blender: " + " ".join(command[:4]))
    completed = subprocess.run(command, capture_output=True, text=True, timeout=900, check=False)
    tail = redact((completed.stdout or "")[-2000:] + "\n" + (completed.stderr or "")[-2000:])
    log(tail)
    if result_path.is_file():
        result = json.loads(result_path.read_text(encoding="utf-8"))
    else:
        result = {"ok": False, "error": f"Blender exited {completed.returncode} without a result file.", "log": tail}
    result["returncode"] = completed.returncode
    return result
