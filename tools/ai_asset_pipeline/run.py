import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from core.settings import Settings
from core.store import AssetStore
from dashboard.server import serve
from generators.orchestrator import execute_job, normalize_request
from providers.registry import provider_status


def main() -> None:
    parser = argparse.ArgumentParser(description="Survival Sandbox AI asset pipeline")
    commands = parser.add_subparsers(dest="command", required=True)
    serve_parser = commands.add_parser("serve", help="Open the local dashboard")
    serve_parser.add_argument("--host")
    serve_parser.add_argument("--port", type=int)
    generate = commands.add_parser("generate", help="Run one job in the foreground")
    generate.add_argument("--kind", required=True)
    generate.add_argument("--category", required=True)
    generate.add_argument("--name", required=True)
    generate.add_argument("--prompt", default="")
    generate.add_argument("--provider", default="")
    generate.add_argument("--mesh-provider", default="")
    generate.add_argument("--resolution", type=int)
    generate.add_argument("--variations", type=int, default=1)
    generate.add_argument("--polycount", type=int)
    generate.add_argument("--seed", type=int)
    commands.add_parser("doctor", help="Show configuration without secrets")
    args = parser.parse_args()
    settings = Settings()
    if args.command == "serve":
        if args.host:
            settings.host = args.host
        if args.port:
            settings.port = args.port
        serve(settings)
        return
    if args.command == "doctor":
        print(f"Project: {settings.project_root}")
        print(f"Library: {settings.library_dir}")
        print(f"Blender: {settings.blender_bin or 'not configured'}")
        print(f"Godot: {settings.godot_bin or 'not configured'}")
        print(f"Style reference: {'present' if settings.style_reference().is_file() else 'missing'}")
        for name, info in provider_status(settings).items():
            print(f"{name}: {'configured' if info['configured'] else 'not configured'} ({info['role']})")
        return
    payload = {
        "kind": args.kind,
        "category": args.category,
        "name": args.name,
        "prompt": args.prompt,
        "provider": args.provider,
        "mesh_provider": args.mesh_provider,
        "variations": args.variations,
    }
    if args.resolution:
        payload["resolution"] = args.resolution
    if args.polycount:
        payload["polycount"] = args.polycount
    if args.seed is not None:
        payload["seed"] = args.seed
    request = normalize_request(settings, payload)
    store = AssetStore(settings.library_dir)
    job = store.create_job(request)
    execute_job(settings, store, job)
    print(job["status"])
    print(job.get("message", ""))
    for asset_id in job.get("asset_ids", []):
        asset = store.get_asset(asset_id)
        print(f"{asset['asset_name']} {asset['processing_status']} {asset['asset_id']}")
    if job["status"] == "failed":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
