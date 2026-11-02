"""Local inventory icons.

These are painted on this machine from the item category and swatch. They are
not an image-model picture and are labeled procedural by the caller.
"""

from PIL import Image, ImageDraw, ImageFilter


def _channel(value: float) -> int:
    number = float(value)
    if number <= 1:
        number *= 255
    return max(0, min(255, int(round(number))))


def _rgb(swatch: list | None) -> tuple[int, int, int]:
    if not swatch or len(swatch) < 3:
        return (137, 146, 157)
    return (_channel(swatch[0]), _channel(swatch[1]), _channel(swatch[2]))


def _mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _at(size: int, unit: float, offset: int = 0) -> int:
    return int(round(unit * size)) + offset


def _rect(draw: ImageDraw.ImageDraw, color, size: int, ox: int, oy: int, x: float, y: float, w: float, h: float) -> None:
    draw.rectangle([_at(size, x, ox), _at(size, y, oy), _at(size, x + w, ox), _at(size, y + h, oy)], fill=color)


def _round(draw: ImageDraw.ImageDraw, color, size: int, ox: int, oy: int, x: float, y: float, w: float, h: float) -> None:
    radius = max(1, int(size * 0.02))
    draw.rounded_rectangle(
        [_at(size, x, ox), _at(size, y, oy), _at(size, x + w, ox), _at(size, y + h, oy)],
        radius=radius,
        fill=color,
    )


def _paint_weapon(draw, color, size, ox, oy):
    _round(draw, color, size, ox, oy, 0.16, 0.36, 0.62, 0.14)
    _rect(draw, color, size, ox, oy, 0.70, 0.39, 0.18, 0.08)
    draw.polygon(
        [
            (_at(size, 0.34, ox), _at(size, 0.48, oy)),
            (_at(size, 0.52, ox), _at(size, 0.48, oy)),
            (_at(size, 0.46, ox), _at(size, 0.82, oy)),
            (_at(size, 0.26, ox), _at(size, 0.82, oy)),
        ],
        fill=color,
    )


def _paint_tool(draw, color, size, ox, oy):
    draw.polygon(
        [
            (_at(size, 0.16, ox), _at(size, 0.34, oy)),
            (_at(size, 0.62, ox), _at(size, 0.22, oy)),
            (_at(size, 0.74, ox), _at(size, 0.34, oy)),
            (_at(size, 0.30, ox), _at(size, 0.48, oy)),
        ],
        fill=color,
    )
    _rect(draw, color, size, ox, oy, 0.46, 0.40, 0.08, 0.42)


def _paint_ammo(draw, color, size, ox, oy):
    for index, y in enumerate((0.28, 0.44, 0.60)):
        _round(draw, color, size, ox, oy, 0.22, y, 0.50, 0.10)
        _rect(draw, color, size, ox, oy, 0.68, y + 0.02, 0.10, 0.06)


def _paint_food(draw, color, size, ox, oy):
    draw.ellipse([_at(size, 0.24, ox), _at(size, 0.24, oy), _at(size, 0.76, ox), _at(size, 0.76, oy)], fill=color)


def _paint_medical(draw, color, size, ox, oy):
    _round(draw, color, size, ox, oy, 0.40, 0.18, 0.20, 0.64)
    _round(draw, color, size, ox, oy, 0.18, 0.40, 0.64, 0.20)


def _paint_harvest(draw, color, size, ox, oy):
    _rect(draw, color, size, ox, oy, 0.46, 0.48, 0.08, 0.30)
    draw.polygon(
        [
            (_at(size, 0.50, ox), _at(size, 0.16, oy)),
            (_at(size, 0.78, ox), _at(size, 0.52, oy)),
            (_at(size, 0.22, ox), _at(size, 0.52, oy)),
        ],
        fill=color,
    )


def _paint_refined(draw, color, size, ox, oy):
    draw.polygon(
        [
            (_at(size, 0.22, ox), _at(size, 0.38, oy)),
            (_at(size, 0.78, ox), _at(size, 0.30, oy)),
            (_at(size, 0.84, ox), _at(size, 0.58, oy)),
            (_at(size, 0.28, ox), _at(size, 0.68, oy)),
        ],
        fill=color,
    )


def _paint_component(draw, color, size, ox, oy):
    for x in (0.22, 0.54):
        for y in (0.22, 0.54):
            _round(draw, color, size, ox, oy, x, y, 0.22, 0.22)


def _paint_explosive(draw, color, size, ox, oy):
    draw.ellipse([_at(size, 0.28, ox), _at(size, 0.34, oy), _at(size, 0.72, ox), _at(size, 0.80, oy)], fill=color)
    _rect(draw, color, size, ox, oy, 0.46, 0.16, 0.08, 0.20)


def _paint_container(draw, color, size, ox, oy):
    _round(draw, color, size, ox, oy, 0.20, 0.36, 0.60, 0.40)
    _round(draw, color, size, ox, oy, 0.20, 0.28, 0.60, 0.12)


def _paint_deployable(draw, color, size, ox, oy):
    _rect(draw, color, size, ox, oy, 0.28, 0.16, 0.08, 0.68)
    _rect(draw, color, size, ox, oy, 0.64, 0.16, 0.08, 0.68)
    _rect(draw, color, size, ox, oy, 0.28, 0.16, 0.44, 0.08)
    _round(draw, color, size, ox, oy, 0.38, 0.28, 0.24, 0.52)


def _paint_material(draw, color, size, ox, oy):
    _round(draw, color, size, ox, oy, 0.22, 0.30, 0.56, 0.14)
    _round(draw, color, size, ox, oy, 0.22, 0.50, 0.56, 0.14)


def _paint_default(draw, color, size, ox, oy):
    _round(draw, color, size, ox, oy, 0.26, 0.26, 0.48, 0.48)


_PAINTERS = {
    "weapon": _paint_weapon,
    "tool": _paint_tool,
    "ammo": _paint_ammo,
    "food": _paint_food,
    "medical": _paint_medical,
    "harvest": _paint_harvest,
    "refined": _paint_refined,
    "component": _paint_component,
    "explosive": _paint_explosive,
    "container": _paint_container,
    "deployable": _paint_deployable,
    "material": _paint_material,
}


def procedural_icon(size: int, category: str, swatch: list | None, seed: int) -> Image.Image:
    if size < 8:
        raise ValueError("icon size must be at least 8")
    color = _rgb(swatch)
    ink = _mix(color, (255, 255, 255), 0.42)
    shade = _mix(color, (20, 24, 28), 0.55)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    painter = _PAINTERS.get(category, _paint_default)
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    painter(ImageDraw.Draw(shadow), (*shade, 255), size, max(1, size // 80), max(2, size // 48))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=max(0.4, size / 220)))
    mark = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    painter(ImageDraw.Draw(mark), (*ink, 255), size, 0, 0)
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(mark)
    return canvas
