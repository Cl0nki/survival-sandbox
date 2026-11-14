import json
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def new_id() -> str:
    return uuid.uuid4().hex[:12]


class AssetStore:
    """JSON metadata for jobs and assets. Approved production files are not replaced here."""

    def __init__(self, library_dir: Path):
        self.root = Path(library_dir)
        self.jobs_dir = self.root / "jobs"
        self.assets_dir = self.root / "assets"
        self.logs_dir = self.root / "logs"
        self.tasks_dir = self.root / "generation_tasks"
        self.costs_dir = self.root / "costs"
        for folder in (self.jobs_dir, self.assets_dir, self.logs_dir, self.tasks_dir, self.costs_dir):
            folder.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()

    def asset_dir(self, asset_id: str) -> Path:
        path = self.assets_dir / asset_id
        for name in ("original", "processed", "preview", "versions"):
            (path / name).mkdir(parents=True, exist_ok=True)
        return path

    def log_path(self) -> Path:
        return self.logs_dir / "pipeline.log"

    def append_log(self, message: str) -> None:
        line = f"{utc_now()} {message}\n"
        with self._lock:
            with self.log_path().open("a", encoding="utf-8") as handle:
                handle.write(line)

    def create_job(self, payload: dict) -> dict:
        job = {
            "job_id": new_id(),
            "created_at": utc_now(),
            "updated_at": utc_now(),
            "status": "waiting",
            "attempt": 1,
            "request": payload,
            "asset_ids": [],
            "errors": [],
            "message": "Waiting to start.",
        }
        self.save_job(job)
        return job

    def save_job(self, job: dict) -> None:
        job["updated_at"] = utc_now()
        path = self.jobs_dir / f"{job['job_id']}.json"
        text = json.dumps(job, indent=2)
        with self._lock:
            path.write_text(text, encoding="utf-8")

    def get_job(self, job_id: str) -> dict:
        path = self.jobs_dir / f"{job_id}.json"
        if not path.is_file():
            raise KeyError(job_id)
        return json.loads(path.read_text(encoding="utf-8"))

    def list_jobs(self) -> list[dict]:
        jobs = []
        for path in self.jobs_dir.glob("*.json"):
            jobs.append(json.loads(path.read_text(encoding="utf-8")))
        jobs.sort(key=lambda item: item.get("created_at", ""), reverse=True)
        return jobs

    def next_waiting(self) -> dict | None:
        with self._lock:
            waiting = []
            for path in self.jobs_dir.glob("*.json"):
                job = json.loads(path.read_text(encoding="utf-8"))
                if job.get("status") == "waiting":
                    waiting.append(job)
            if not waiting:
                return None
            waiting.sort(key=lambda item: item.get("created_at", ""))
            job = waiting[0]
            job["status"] = "generating"
            job["message"] = "Generation started."
            job["updated_at"] = utc_now()
            (self.jobs_dir / f"{job['job_id']}.json").write_text(json.dumps(job, indent=2), encoding="utf-8")
            return job

    def create_asset(self, fields: dict) -> dict:
        asset_id = fields.get("asset_id") or new_id()
        folder = self.asset_dir(asset_id)
        asset = {
            "asset_id": asset_id,
            "asset_name": fields["asset_name"],
            "category": fields["category"],
            "kind": fields["kind"],
            "workshop_category": fields.get("workshop_category") or (fields.get("generation_parameters") or {}).get("workshop_category") or "",
            "tags": list(fields.get("tags") or []),
            "created_at": utc_now(),
            "provider": fields.get("provider", ""),
            "model": fields.get("model", ""),
            "prompt": fields.get("prompt", ""),
            "negative_prompt": fields.get("negative_prompt", ""),
            "seed": fields.get("seed"),
            "seed_supported": bool(fields.get("seed_supported", False)),
            "generation_parameters": fields.get("generation_parameters", {}),
            "original_files": [],
            "processed_files": [],
            "polygon_count": None,
            "dimensions": None,
            "texture_resolution": fields.get("texture_resolution"),
            "processing_status": fields.get("processing_status", "waiting"),
            "approval_status": "pending",
            "version": 1,
            "history": [],
            "validation": None,
            "errors": [],
            "warnings": [],
            "job_id": fields.get("job_id", ""),
            "production_files": [],
            "manual_steps": [],
            "maps_origin": {},
            "modular": fields.get("modular"),
        }
        asset["history"].append(_snapshot(asset, "created"))
        self.save_asset(asset)
        (folder / "log.txt").write_text("", encoding="utf-8")
        return asset

    def save_asset(self, asset: dict) -> None:
        folder = self.asset_dir(asset["asset_id"])
        text = json.dumps(asset, indent=2)
        with self._lock:
            (folder / "metadata.json").write_text(text, encoding="utf-8")

    def get_asset(self, asset_id: str) -> dict:
        path = self.assets_dir / asset_id / "metadata.json"
        if not path.is_file():
            raise KeyError(asset_id)
        return json.loads(path.read_text(encoding="utf-8"))

    def list_assets(self) -> list[dict]:
        assets = []
        for path in self.assets_dir.glob("*/metadata.json"):
            assets.append(json.loads(path.read_text(encoding="utf-8")))
        assets.sort(key=lambda item: item.get("created_at", ""), reverse=True)
        return assets

    def asset_log(self, asset_id: str, message: str) -> None:
        folder = self.asset_dir(asset_id)
        with self._lock:
            with (folder / "log.txt").open("a", encoding="utf-8") as handle:
                handle.write(f"{utc_now()} {message}\n")

    def create_generation_task(self, fields: dict) -> dict:
        task = {
            "task_id": fields.get("task_id") or new_id(),
            "created_at": utc_now(),
            "updated_at": utc_now(),
            "completed_at": None,
            "job_id": fields.get("job_id", ""),
            "asset_id": fields.get("asset_id", ""),
            "provider": fields.get("provider", ""),
            "operation": fields.get("operation", ""),
            "provider_task_id": fields.get("provider_task_id", ""),
            "status": fields.get("status", "pending"),
            "input": fields.get("input") or {},
            "output": fields.get("output") or {},
            "error": fields.get("error", ""),
            "consumed_credits": fields.get("consumed_credits"),
            "attempt": int(fields.get("attempt") or 1),
            "history": [{"at": utc_now(), "status": fields.get("status", "pending"), "event": "created"}],
        }
        self.save_generation_task(task)
        return task

    def save_generation_task(self, task: dict) -> None:
        task["updated_at"] = utc_now()
        path = self.tasks_dir / f"{task['task_id']}.json"
        text = json.dumps(task, indent=2)
        with self._lock:
            path.write_text(text, encoding="utf-8")

    def update_generation_task(self, task_id: str, **fields) -> dict:
        task = self.get_generation_task(task_id)
        for key, value in fields.items():
            if key in {"history"}:
                continue
            task[key] = value
        status = fields.get("status")
        if status:
            task.setdefault("history", []).append({"at": utc_now(), "status": status, "event": "status"})
            if status in {"succeeded", "failed", "canceled", "ready_for_review", "approved", "rejected"}:
                task["completed_at"] = task.get("completed_at") or utc_now()
        self.save_generation_task(task)
        return task

    def get_generation_task(self, task_id: str) -> dict:
        path = self.tasks_dir / f"{task_id}.json"
        if not path.is_file():
            raise KeyError(task_id)
        return json.loads(path.read_text(encoding="utf-8"))

    def list_generation_tasks(self, asset_id: str | None = None, job_id: str | None = None) -> list[dict]:
        tasks = []
        for path in self.tasks_dir.glob("*.json"):
            task = json.loads(path.read_text(encoding="utf-8"))
            if asset_id and task.get("asset_id") != asset_id:
                continue
            if job_id and task.get("job_id") != job_id:
                continue
            tasks.append(task)
        tasks.sort(key=lambda item: item.get("created_at", ""), reverse=True)
        return tasks

    def create_cost_record(self, fields: dict) -> dict:
        record = {
            "cost_id": fields.get("cost_id") or new_id(),
            "created_at": utc_now(),
            "provider": fields.get("provider", ""),
            "operation": fields.get("operation", ""),
            "asset_id": fields.get("asset_id", ""),
            "job_id": fields.get("job_id", ""),
            "generation_task_id": fields.get("generation_task_id", ""),
            "provider_task_id": fields.get("provider_task_id", ""),
            "category": fields.get("category", ""),
            "credits": fields.get("credits"),
            "estimated_usd": fields.get("estimated_usd"),
            "actual_usd": fields.get("actual_usd"),
            "currency": fields.get("currency", "USD"),
            "known": bool(fields.get("known", False)),
            "approved": bool(fields.get("approved", False)),
            "notes": fields.get("notes", ""),
        }
        path = self.costs_dir / f"{record['cost_id']}.json"
        with self._lock:
            path.write_text(json.dumps(record, indent=2), encoding="utf-8")
        return record

    def list_cost_records(self, asset_id: str | None = None) -> list[dict]:
        records = []
        for path in self.costs_dir.glob("*.json"):
            record = json.loads(path.read_text(encoding="utf-8"))
            if asset_id and record.get("asset_id") != asset_id:
                continue
            records.append(record)
        records.sort(key=lambda item: item.get("created_at", ""), reverse=True)
        return records


def _snapshot(asset: dict, event: str) -> dict:
    return {
        "event": event,
        "at": utc_now(),
        "version": asset.get("version", 1),
        "provider": asset.get("provider", ""),
        "model": asset.get("model", ""),
        "prompt": asset.get("prompt", ""),
        "negative_prompt": asset.get("negative_prompt", ""),
        "seed": asset.get("seed"),
        "processing_status": asset.get("processing_status"),
        "approval_status": asset.get("approval_status"),
        "original_files": list(asset.get("original_files", [])),
        "processed_files": list(asset.get("processed_files", [])),
    }
