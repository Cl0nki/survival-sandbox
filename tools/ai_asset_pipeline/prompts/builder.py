def _palette_text(style: dict) -> str:
    parts = [f"{name.replace('_', ' ')} {value}" for name, value in style.get("palette", {}).items()]
    return ", ".join(parts)


def negative_prompt(style: dict, preset: dict | None = None) -> str:
    avoid = list(style.get("avoid", []))
    extra = (preset or {}).get("negative") or []
    for item in extra:
        if item not in avoid:
            avoid.append(item)
    return ", ".join(avoid)


_TILE_SKIP = ("silhouette", "proportion", "geometry", "isometric")
_TILE_DIRECTION = "Hand-painted tileable surface. Orthographic flat material filling the frame. No object, no silhouette, no prop."


def _material_tile(kind: str, preset: dict) -> bool:
    return kind == "texture" and not preset.get("suffix")


def _direction(style: dict, preset: dict, kind: str) -> tuple[str, str]:
    requirements = list(style.get("requirements", []))
    if not _material_tile(kind, preset):
        return style.get("summary", ""), "; ".join(requirements)
    kept = [item for item in requirements if not any(word in item.lower() for word in _TILE_SKIP)]
    return style.get("texture_direction") or _TILE_DIRECTION, "; ".join(kept)


def build_prompts(style: dict, preset: dict, user_text: str, kind: str, customization: dict | None = None, style_reference_present: bool = False) -> dict:
    subject = preset.get("prompt", preset.get("label", "game asset"))
    user = " ".join((user_text or "").split())
    custom_bits = []
    for key, value in (customization or {}).items():
        if value and value != "none":
            custom_bits.append(f"{key.replace('_', ' ')}: {value}")
    custom = ", ".join(custom_bits)
    suffix_key = {
        "texture": "texture_suffix",
        "character": "character_suffix",
        "building": "building_suffix",
    }.get(kind, "prop_suffix")
    suffix = preset.get("suffix") or style.get(suffix_key, "")
    reference = ""
    negative = negative_prompt(style, preset)
    direction, requirements = _direction(style, preset, kind)
    tile = _material_tile(kind, preset)
    use_palette = style.get("use_palette", True) and bool(style.get("palette"))
    if style_reference_present:
        reference = "Match the project's style reference image."
        if use_palette:
            reference += " Stylized shapes, muted military colors, and painted material breakup."
    full = " ".join(
        part
        for part in (
            subject + ".",
            user + "." if user else "",
            custom + "." if custom else "",
            f"Art direction: {direction}",
            f"Palette: {_palette_text(style)}." if use_palette else "",
            f"Requirements: {requirements}.",
            suffix,
            reference,
            f"Avoid: {negative}.",
        )
        if part
    )
    full = " ".join(full.split())
    compact = " ".join(
        part
        for part in (
            subject,
            user,
            custom,
            "stylized low-poly hand-painted tactical survival game asset",
            "palette dark slate, blue gray, olive, sand, rust, concrete" if use_palette else "",
            "flat tileable surface, no object, no silhouette" if tile else "strong silhouette, clean real-time geometry",
            "no photorealism, no anime, no cartoon outline",
        )
        if part
    )
    sent = compact if len(compact) <= 800 else compact[:797].rsplit(" ", 1)[0]
    return {
        "prompt": full,
        "negative_prompt": negative,
        "provider_prompt": full,
        "compact_prompt": sent,
        "prompt_truncated": sent != compact,
    }
