from core.settings import Settings
from providers.meshy import MeshyProvider
from providers.openai_images import OpenAIImageProvider
from providers.tripo import TripoProvider


def openai_from(settings: Settings) -> OpenAIImageProvider:
    return OpenAIImageProvider(settings.openai_key, settings.openai_model)


def meshy_from(settings: Settings) -> MeshyProvider:
    return MeshyProvider(settings.meshy_key, settings.meshy_model, settings.poll_timeout_sec, settings.poll_interval_sec)


def tripo_from(settings: Settings) -> TripoProvider:
    return TripoProvider(settings.tripo_key, settings.tripo_model, settings.poll_timeout_sec, settings.poll_interval_sec)


def provider_status(settings: Settings) -> dict:
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
            "role": "image-to-3D, text-to-3D, and humanoid rigging",
            "model": settings.meshy_model,
            "docs": "https://docs.meshy.ai/api/image-to-3d",
        },
        "tripo": {
            "configured": bool(settings.tripo_key),
            "role": "image-to-3D",
            "model": settings.tripo_model,
            "docs": "https://platform.tripo3d.ai/docs/generation",
            "notes": "Tripo rigging is not called. Character rigs use Meshy when that key is set, otherwise the Blender fallback.",
        },
    }
