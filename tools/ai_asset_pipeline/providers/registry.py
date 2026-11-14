from core.settings import Settings
from providers.base import (
    CAP_ALT_RIG,
    CAP_ANIMATE,
    CAP_GENERATE_MODEL,
    CAP_HUMANOID_RIG,
    CAP_RIG,
)
from providers.meshy import MeshyProvider
from providers.openai_images import OpenAIImageProvider
from providers.tripo import TripoProvider

THREE_D_PROVIDERS = ("meshy", "tripo")


def openai_from(settings: Settings) -> OpenAIImageProvider:
    return OpenAIImageProvider(settings.openai_key, settings.openai_model)


def meshy_from(settings: Settings) -> MeshyProvider:
    return MeshyProvider(settings.meshy_key, settings.meshy_model, settings.poll_timeout_sec, settings.poll_interval_sec)


def tripo_from(settings: Settings) -> TripoProvider:
    return TripoProvider(settings.tripo_key, settings.tripo_model, settings.poll_timeout_sec, settings.poll_interval_sec)


def threed_from(settings: Settings, name: str):
    """Return a ThreeDProvider adapter. meshy_text jobs still use Meshy."""
    key = (name or "").strip().lower()
    if key in {"meshy", "meshy_text"}:
        return meshy_from(settings)
    if key == "tripo":
        return tripo_from(settings)
    raise KeyError(f"Unknown 3D provider '{name}'. Expected meshy, meshy_text, or tripo.")


def provider_status(settings: Settings) -> dict:
    meshy = meshy_from(settings)
    tripo = tripo_from(settings)
    return {
        "procedural": {
            "configured": True,
            "role": "tileable textures and modular building meshes",
            "notes": "Local geometry and noise. This is not an image or mesh model.",
        },
        "openai": {
            "configured": bool(settings.openai_key),
            "role": "text-to-image concepts and texture albedo",
            "model": settings.openai_model,
            "docs": "https://developers.openai.com/api/docs/guides/image-generation",
        },
        "meshy": {
            "configured": bool(settings.meshy_key),
            "role": "image-to-3D, text-to-3D, humanoid rigging, animation library",
            "model": settings.meshy_model,
            "capabilities": sorted(meshy.capabilities),
            "docs": {
                "image_to_3d": "https://docs.meshy.ai/api/image-to-3d",
                "text_to_3d": "https://docs.meshy.ai/api/text-to-3d",
                "rigging": "https://docs.meshy.ai/api/rigging",
                "animation": "https://docs.meshy.ai/api/animation",
            },
        },
        "tripo": {
            "configured": bool(settings.tripo_key),
            "role": "image-to-3D and alternate (non-humanoid) animate_rig",
            "model": settings.tripo_model,
            "capabilities": sorted(tripo.capabilities),
            "docs": {
                "generation": "https://platform.tripo3d.ai/docs/generation",
                "animation": "https://platform.tripo3d.ai/docs/animation",
            },
            "notes": (
                "Use Tripo for creatures / alt anatomy. Humanoid survivors still prefer Meshy rigging. "
                "animate_rig needs the prior image_to_model task id, not only a local GLB."
            ),
        },
    }


def recommended_mesh_provider(profile: str) -> str:
    """Workshop profile → default mesh provider. Orchestrator can override per request."""
    key = (profile or "").strip().lower()
    if key in {"non_humanoid", "creature", "enemy_creature", "quadruped"}:
        return "tripo"
    return "meshy"


def capability_matrix() -> dict:
    return {
        "meshy": sorted({CAP_GENERATE_MODEL, CAP_RIG, CAP_HUMANOID_RIG, CAP_ANIMATE}),
        "tripo": sorted({CAP_GENERATE_MODEL, CAP_RIG, CAP_ALT_RIG}),
    }
