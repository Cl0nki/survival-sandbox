import threading

from core.redact import redact
from core.settings import Settings
from core.store import AssetStore
from generators.orchestrator import execute_job


class Worker:
    def __init__(self, settings: Settings, store: AssetStore):
        self.settings = settings
        self.store = store
        self._wake = threading.Event()
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._loop, name="asset-pipeline", daemon=True)

    def start(self) -> None:
        self._thread.start()

    def wake(self) -> None:
        self._wake.set()

    def stop(self) -> None:
        self._stop.set()
        self._wake.set()

    def _loop(self) -> None:
        while not self._stop.is_set():
            job = self.store.next_waiting()
            if job is None:
                self._wake.wait(0.4)
                self._wake.clear()
                continue
            try:
                execute_job(self.settings, self.store, job)
            except Exception as exc:
                message = redact(str(exc))
                job["status"] = "failed"
                job.setdefault("errors", []).append(message)
                job["message"] = message
                self.store.save_job(job)
                self.store.append_log(f"job {job['job_id']} crashed: {message}")
