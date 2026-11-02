"""Grid-aligned building pieces.

Dimensions come from config/building_grid.json, which copies the live BuildingConfig.
These meshes are not injected into the building solver.
"""

from processors.gltf_write import Mesh


def _span(grid: dict) -> float:
    return float(grid["cell_size"]) - float(grid["wall_thickness"])


def _materials() -> list[dict]:
    return [
        {"name": "concrete", "color": (0.537, 0.573, 0.616, 1.0), "metallic": 0.0, "roughness": 0.88},
        {"name": "painted_metal", "color": (0.349, 0.420, 0.239, 1.0), "metallic": 0.35, "roughness": 0.55},
        {"name": "rust_metal", "color": (0.714, 0.420, 0.286, 1.0), "metallic": 0.45, "roughness": 0.7},
        {"name": "wood", "color": (0.706, 0.627, 0.443, 1.0), "metallic": 0.0, "roughness": 0.78},
        {"name": "glass", "color": (0.325, 0.396, 0.459, 1.0), "metallic": 0.0, "roughness": 0.18},
        {"name": "dark_metal", "color": (0.208, 0.267, 0.318, 1.0), "metallic": 0.6, "roughness": 0.48},
    ]


def _box(name: str, size, center, material: int = 0, collision: bool = True) -> list[Mesh]:
    visual = Mesh(name, material)
    visual.add_box(size, center)
    meshes = [visual]
    if collision:
        collider = Mesh(f"{name}-colonly", material)
        collider.add_box(size, center)
        meshes.append(collider)
    return meshes


def concrete_wall(grid: dict) -> list[Mesh]:
    span = _span(grid)
    height = float(grid["floor_height"])
    thickness = float(grid["wall_thickness"])
    return _box("concrete_wall", (span, height, thickness), (0.0, height * 0.5, 0.0), 0)


def concrete_floor(grid: dict) -> list[Mesh]:
    cell = float(grid["cell_size"])
    thick = float(grid["slab_thickness"])
    return _box("concrete_floor", (cell, thick, cell), (0.0, thick * 0.5, 0.0), 0)


def post(grid: dict) -> list[Mesh]:
    thickness = float(grid["wall_thickness"])
    height = float(grid["floor_height"])
    return _box("post", (thickness, height, thickness), (0.0, height * 0.5, 0.0), 0)


def doorway(grid: dict) -> list[Mesh]:
    span = _span(grid)
    height = float(grid["floor_height"])
    thickness = float(grid["wall_thickness"])
    door = float(grid["door_height"])
    header_h = height - door
    return _box("doorway_header", (span, header_h, thickness), (0.0, door + header_h * 0.5, 0.0), 0)


def door_leaf(grid: dict) -> list[Mesh]:
    span = _span(grid)
    door = float(grid["door_height"])
    leaf_t = 0.04
    # Origin is the hinge at the left edge, on the ground.
    visual = Mesh("door_leaf", 3)
    visual.add_box((span, door, leaf_t), (span * 0.5, door * 0.5, 0.0))
    collider = Mesh("door_leaf-colonly", 3)
    collider.add_box((span, door, leaf_t), (span * 0.5, door * 0.5, 0.0))
    return [visual, collider]


def window(grid: dict) -> list[Mesh]:
    span = _span(grid)
    height = float(grid["floor_height"])
    thickness = float(grid["wall_thickness"])
    sill = float(grid["window_sill_height"])
    head = float(grid["window_head_height"])
    meshes = []
    meshes.extend(_box("window_sill", (span, sill, thickness), (0.0, sill * 0.5, 0.0), 0))
    head_h = height - head
    meshes.extend(_box("window_header", (span, head_h, thickness), (0.0, head + head_h * 0.5, 0.0), 0))
    glass_h = head - sill
    glass = Mesh("window_glass", 4)
    glass.add_box((span * 0.92, glass_h * 0.92, 0.02), (0.0, sill + glass_h * 0.5, 0.0))
    meshes.append(glass)
    return meshes


def stairs(grid: dict) -> list[Mesh]:
    cell = float(grid["cell_size"])
    wall_t = float(grid["wall_thickness"])
    rise = float(grid["floor_height"])
    cells = grid.get("stairs_cells", [1, 3])
    w = (cell - wall_t) * 0.5
    half_run = cell * float(cells[1]) * 0.5
    p0 = (-w, 0.0, half_run)
    p1 = (w, 0.0, half_run)
    p2 = (w, 0.0, -half_run)
    p3 = (-w, 0.0, -half_run)
    p4 = (w, rise, -half_run)
    p5 = (-w, rise, -half_run)
    visual = Mesh("stairs", 0)
    visual.add_quad(p0, p3, p2, p1, (0, -1, 0))
    visual.add_quad(p2, p3, p5, p4, (0, 0, -1))
    slope = (0.0, p0[2] - p3[2], p4[1])
    visual.add_quad(p0, p1, p4, p5, slope)
    visual.add_tri(p1, p2, p4, (1, 0, 0))
    visual.add_tri(p0, p5, p3, (-1, 0, 0))
    collider = Mesh("stairs-colonly", 0)
    collider.add_quad(p0, p3, p2, p1, (0, -1, 0))
    collider.add_quad(p2, p3, p5, p4, (0, 0, -1))
    collider.add_quad(p0, p1, p4, p5, slope)
    collider.add_tri(p1, p2, p4, (1, 0, 0))
    collider.add_tri(p0, p5, p3, (-1, 0, 0))
    return [visual, collider]


def metal_fence(grid: dict) -> list[Mesh]:
    cell = float(grid["cell_size"])
    visual = Mesh("metal_fence", 5)
    visual.add_box((0.06, 1.2, 0.06), (0.03, 0.6, 0.0))
    visual.add_box((cell - 0.06, 0.04, 0.03), (0.03 + (cell - 0.06) * 0.5, 1.05, 0.0))
    visual.add_box((cell - 0.06, 0.04, 0.03), (0.03 + (cell - 0.06) * 0.5, 0.62, 0.0))
    visual.add_box((cell - 0.06, 0.04, 0.03), (0.03 + (cell - 0.06) * 0.5, 0.22, 0.0))
    collider = Mesh("metal_fence-colonly", 5)
    collider.add_box((cell, 1.2, 0.06), (cell * 0.5, 0.6, 0.0))
    return [visual, collider]


def gate(grid: dict) -> list[Mesh]:
    cell = float(grid["cell_size"])
    height = 2.2
    visual = Mesh("gate", 5)
    visual.add_box((0.08, height, 0.08), (0.04, height * 0.5, 0.0))
    visual.add_box((0.08, height, 0.08), (cell - 0.04, height * 0.5, 0.0))
    visual.add_box((cell, 0.08, 0.06), (cell * 0.5, height - 0.04, 0.0))
    leaf_w = cell * 0.42
    visual.add_box((leaf_w, height - 0.2, 0.03), (0.12 + leaf_w * 0.5, (height - 0.2) * 0.5, 0.0))
    visual.add_box((leaf_w, height - 0.2, 0.03), (cell - 0.12 - leaf_w * 0.5, (height - 0.2) * 0.5, 0.0))
    collider = Mesh("gate-colonly", 5)
    collider.add_box((cell, height, 0.08), (cell * 0.5, height * 0.5, 0.0))
    return [visual, collider]


def roof(grid: dict) -> list[Mesh]:
    cell = float(grid["cell_size"])
    half = cell * 0.5
    rise = 0.45
    a = (-half, 0.0, -half)
    b = (half, 0.0, -half)
    c = (half, 0.0, half)
    d = (-half, 0.0, half)
    e = (-half, rise, 0.0)
    f = (half, rise, 0.0)
    visual = Mesh("roof", 2)
    visual.add_quad(a, b, f, e, (0, 1, -1))
    visual.add_quad(c, d, e, f, (0, 1, 1))
    visual.add_tri(d, a, e, (-1, 0, 0))
    visual.add_tri(b, c, f, (1, 0, 0))
    visual.add_quad(a, d, c, b, (0, -1, 0))
    collider = Mesh("roof-colonly", 2)
    collider.add_box((cell, rise, cell), (0.0, rise * 0.5, 0.0))
    return [visual, collider]


def barricade(grid: dict) -> list[Mesh]:
    cell = float(grid["cell_size"])
    visual = Mesh("barricade", 3)
    visual.add_box((cell, 0.18, 0.08), (0.0, 0.28, 0.0))
    visual.add_box((cell, 0.18, 0.08), (0.0, 0.62, 0.08))
    visual.add_box((0.12, 0.9, 0.12), (-cell * 0.42, 0.45, 0.0))
    visual.add_box((0.12, 0.9, 0.12), (cell * 0.42, 0.45, 0.0))
    collider = Mesh("barricade-colonly", 3)
    collider.add_box((cell, 0.9, 0.28), (0.0, 0.45, 0.04))
    return [visual, collider]


def crate(_grid: dict) -> list[Mesh]:
    visual = Mesh("crate", 3)
    visual.add_box((0.7, 0.42, 0.7), (0.0, 0.21, 0.0))
    visual.add_box((0.74, 0.06, 0.74), (0.0, 0.45, 0.0))
    collider = Mesh("crate-colonly", 3)
    collider.add_box((0.74, 0.48, 0.74), (0.0, 0.24, 0.0))
    return [visual, collider]


def shipping_container(_grid: dict) -> list[Mesh]:
    size = (6.0, 2.4, 2.4)
    center = (0.0, 1.2, 0.0)
    visual = Mesh("shipping_container", 1)
    visual.add_box(size, center)
    visual.add_box((0.06, 2.1, 2.2), (2.97, 1.15, 0.0))
    collider = Mesh("shipping_container-colonly", 1)
    collider.add_box(size, center)
    return [visual, collider]


def watchtower(grid: dict) -> list[Mesh]:
    cell = float(grid["cell_size"])
    post_w = float(grid["wall_thickness"])
    visual = Mesh("watchtower", 0)
    half = cell
    for x in (-half, half):
        for z in (-half, half):
            visual.add_box((post_w, 6.0, post_w), (x, 3.0, z))
    visual.add_box((cell * 2, 0.12, cell * 2), (0.0, 3.0, 0.0))
    visual.add_box((cell * 2, 0.08, 0.08), (0.0, 4.1, half))
    visual.add_box((cell * 2, 0.08, 0.08), (0.0, 4.1, -half))
    visual.add_box((0.08, 0.08, cell * 2), (half, 4.1, 0.0))
    visual.add_box((0.08, 0.08, cell * 2), (-half, 4.1, 0.0))
    visual.add_box((cell * 2.2, 0.12, cell * 2.2), (0.0, 5.9, 0.0))
    collider = Mesh("watchtower-colonly", 0)
    collider.add_box((cell * 2, 6.0, cell * 2), (0.0, 3.0, 0.0))
    return [visual, collider]


def _shell(name: str, grid: dict, material: int) -> list[Mesh]:
    cell = float(grid["cell_size"])
    height = float(grid["floor_height"])
    thick = float(grid["wall_thickness"])
    width = cell * 3
    depth = cell * 3
    visual = Mesh(name, material)
    visual.add_box((width, thick, depth), (0.0, thick * 0.5, 0.0))
    visual.add_box((width, thick, depth), (0.0, height, 0.0))
    visual.add_box((thick, height, depth), (-width * 0.5, height * 0.5, 0.0))
    visual.add_box((thick, height, depth), (width * 0.5, height * 0.5, 0.0))
    visual.add_box((width, height, thick), (0.0, height * 0.5, -depth * 0.5))
    door_w = 0.9
    side = (width - door_w) * 0.5
    visual.add_box((side, height, thick), (-(door_w + side) * 0.5, height * 0.5, depth * 0.5))
    visual.add_box((side, height, thick), ((door_w + side) * 0.5, height * 0.5, depth * 0.5))
    visual.add_box((door_w, height - 2.2, thick), (0.0, 2.2 + (height - 2.2) * 0.5, depth * 0.5))
    collider = Mesh(f"{name}-colonly", material)
    collider.add_box((width, height, depth), (0.0, height * 0.5, 0.0))
    return [visual, collider]


def industrial_shell(grid: dict) -> list[Mesh]:
    return _shell("industrial_shell", grid, 5)


def military_shell(grid: dict) -> list[Mesh]:
    return _shell("military_shell", grid, 1)


BUILDERS = {
    "concrete_wall": concrete_wall,
    "concrete_floor": concrete_floor,
    "post": post,
    "doorway": doorway,
    "door_leaf": door_leaf,
    "window": window,
    "stairs": stairs,
    "metal_fence": metal_fence,
    "gate": gate,
    "roof": roof,
    "barricade": barricade,
    "crate": crate,
    "shipping_container": shipping_container,
    "watchtower": watchtower,
    "industrial_shell": industrial_shell,
    "military_shell": military_shell,
}

PIECE_META = {
    "concrete_wall": {"pivot": "edge_midpoint_bottom", "local_x": "along the wall", "snap": "building edge"},
    "concrete_floor": {"pivot": "cell_center_bottom", "snap": "building cell"},
    "post": {"pivot": "vertex_bottom", "snap": "building corner"},
    "doorway": {"pivot": "edge_midpoint_bottom", "snap": "building edge", "opening_height_m": "door_height"},
    "door_leaf": {"pivot": "hinge_left_bottom", "snap": "door opening"},
    "window": {"pivot": "edge_midpoint_bottom", "snap": "building edge"},
    "stairs": {"pivot": "footprint_center_on_slab", "snap": "3 cells along local -Z climb"},
    "metal_fence": {"pivot": "left_post_bottom", "snap": "1 m along local +X"},
    "gate": {"pivot": "left_bottom", "snap": "1 m along local +X"},
    "roof": {"pivot": "cell_center_bottom", "snap": "one cell"},
    "barricade": {"pivot": "center_bottom", "snap": "1 m"},
    "crate": {"pivot": "center_bottom", "snap": "free"},
    "shipping_container": {"pivot": "center_bottom", "footprint_m": [6.0, 2.4]},
    "watchtower": {"pivot": "footprint_center_bottom", "footprint_m": [2.0, 2.0], "height_m": 6.0},
    "industrial_shell": {"pivot": "footprint_center_bottom", "footprint_m": [3.0, 3.0]},
    "military_shell": {"pivot": "footprint_center_bottom", "footprint_m": [3.0, 3.0]},
}


def build_piece(piece_id: str, grid: dict) -> tuple[list[Mesh], list[dict]]:
    if piece_id not in BUILDERS:
        raise KeyError(piece_id)
    return BUILDERS[piece_id](grid), _materials()


def kit_piece_ids() -> list[str]:
    return list(BUILDERS)
