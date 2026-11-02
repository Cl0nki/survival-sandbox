import json
import struct
from pathlib import Path


def _dot(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _normal(a, b, c) -> tuple[float, float, float]:
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    nx = uy * vz - uz * vy
    ny = uz * vx - ux * vz
    nz = ux * vy - uy * vx
    length = (nx * nx + ny * ny + nz * nz) ** 0.5
    if length < 1e-12:
        return (0.0, 1.0, 0.0)
    return (nx / length, ny / length, nz / length)


def _uv(point, normal) -> tuple[float, float]:
    ax, ay, az = abs(normal[0]), abs(normal[1]), abs(normal[2])
    if ay >= ax and ay >= az:
        return (point[0], point[2])
    if ax >= az:
        return (point[2], point[1])
    return (point[0], point[1])


class Mesh:
    def __init__(self, name: str, material: int = 0):
        self.name = name
        self.material = material
        self.positions: list[float] = []
        self.normals: list[float] = []
        self.uvs: list[float] = []
        self.indices: list[int] = []

    def add_tri(self, a, b, c, normal) -> None:
        geometric = _normal(a, b, c)
        if _dot(geometric, normal) < 0:
            b, c = c, b
            geometric = _normal(a, b, c)
        start = len(self.positions) // 3
        for point in (a, b, c):
            self.positions.extend(point)
            self.normals.extend(geometric)
            self.uvs.extend(_uv(point, geometric))
        self.indices.extend((start, start + 1, start + 2))

    def add_quad(self, a, b, c, d, normal) -> None:
        self.add_tri(a, b, c, normal)
        self.add_tri(a, c, d, normal)

    def add_box(self, size, center) -> None:
        hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        cx, cy, cz = center

        def point(x, y, z):
            return (cx + x, cy + y, cz + z)

        self.add_quad(
            point(-hx, hy, -hz), point(hx, hy, -hz), point(hx, hy, hz), point(-hx, hy, hz), (0, 1, 0)
        )
        self.add_quad(
            point(-hx, -hy, hz), point(hx, -hy, hz), point(hx, -hy, -hz), point(-hx, -hy, -hz), (0, -1, 0)
        )
        self.add_quad(
            point(hx, -hy, -hz), point(hx, hy, -hz), point(hx, hy, hz), point(hx, -hy, hz), (1, 0, 0)
        )
        self.add_quad(
            point(-hx, -hy, hz), point(-hx, hy, hz), point(-hx, hy, -hz), point(-hx, -hy, -hz), (-1, 0, 0)
        )
        self.add_quad(
            point(-hx, -hy, hz), point(hx, -hy, hz), point(hx, hy, hz), point(-hx, hy, hz), (0, 0, 1)
        )
        self.add_quad(
            point(hx, -hy, -hz), point(-hx, -hy, -hz), point(-hx, hy, -hz), point(hx, hy, -hz), (0, 0, -1)
        )

    @property
    def triangles(self) -> int:
        return len(self.indices) // 3


def _pad(data: bytes, fill: bytes) -> bytes:
    extra = (-len(data)) % 4
    return data + fill * extra


def write_glb(path: Path, meshes: list[Mesh], materials: list[dict]) -> None:
    if not meshes:
        raise ValueError("refusing to write a GLB with no meshes")
    blob = bytearray()
    buffer_views = []
    accessors = []
    mesh_defs = []
    nodes = []

    def push(values: list[float], component: int, count_div: int, target: int, vtype: str) -> int:
        raw = struct.pack("<" + "f" * len(values), *values)
        while len(blob) % 4:
            blob.append(0)
        offset = len(blob)
        blob.extend(raw)
        view_index = len(buffer_views)
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(raw), "target": target})
        count = len(values) // count_div
        accessor_index = len(accessors)
        minimum = None
        maximum = None
        if vtype == "VEC3":
            groups = [values[i : i + 3] for i in range(0, len(values), 3)]
            minimum = [min(item[axis] for item in groups) for axis in range(3)]
            maximum = [max(item[axis] for item in groups) for axis in range(3)]
        entry = {
            "bufferView": view_index,
            "componentType": component,
            "count": count,
            "type": vtype,
        }
        if minimum is not None:
            entry["min"] = minimum
            entry["max"] = maximum
        accessors.append(entry)
        return accessor_index

    for mesh in meshes:
        if mesh.triangles <= 0:
            raise ValueError(f"{mesh.name} has no triangles")
        position_index = push(mesh.positions, 5126, 3, 34962, "VEC3")
        normal_index = push(mesh.normals, 5126, 3, 34962, "VEC3")
        uv_index = push(mesh.uvs, 5126, 2, 34962, "VEC2")
        index_type = 5123 if max(mesh.indices) <= 65535 else 5125
        raw_index = struct.pack("<" + ("H" if index_type == 5123 else "I") * len(mesh.indices), *mesh.indices)
        while len(blob) % 4:
            blob.append(0)
        offset = len(blob)
        blob.extend(raw_index)
        view_index = len(buffer_views)
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(raw_index), "target": 34963})
        index_accessor = len(accessors)
        accessors.append(
            {"bufferView": view_index, "componentType": index_type, "count": len(mesh.indices), "type": "SCALAR"}
        )
        mesh_index = len(mesh_defs)
        mesh_defs.append(
            {
                "name": mesh.name,
                "primitives": [
                    {
                        "attributes": {"POSITION": position_index, "NORMAL": normal_index, "TEXCOORD_0": uv_index},
                        "indices": index_accessor,
                        "material": mesh.material,
                    }
                ],
            }
        )
        nodes.append({"name": mesh.name, "mesh": mesh_index})

    gltf_materials = []
    for material in materials:
        color = material.get("color", (0.7, 0.7, 0.7, 1.0))
        gltf_materials.append(
            {
                "name": material.get("name", "material"),
                "doubleSided": False,
                "pbrMetallicRoughness": {
                    "baseColorFactor": list(color),
                    "metallicFactor": float(material.get("metallic", 0.0)),
                    "roughnessFactor": float(material.get("roughness", 0.8)),
                },
            }
        )
    if not gltf_materials:
        gltf_materials.append(
            {
                "name": "default",
                "pbrMetallicRoughness": {"baseColorFactor": [0.7, 0.7, 0.7, 1.0], "metallicFactor": 0.0, "roughnessFactor": 0.8},
            }
        )

    document = {
        "asset": {"version": "2.0", "generator": "survival-sandbox-ai-pipeline"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": mesh_defs,
        "materials": gltf_materials,
        "buffers": [{"byteLength": len(blob)}],
        "bufferViews": buffer_views,
        "accessors": accessors,
    }
    json_chunk = _pad(json.dumps(document, separators=(",", ":")).encode("utf-8"), b" ")
    bin_chunk = _pad(bytes(blob), b"\x00")
    length = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    header = struct.pack("<III", 0x46546C67, 2, length)
    body = header
    body += struct.pack("<II", len(json_chunk), 0x4E4F534A)
    body += json_chunk
    body += struct.pack("<II", len(bin_chunk), 0x004E4942)
    body += bin_chunk
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(body)


def read_glb_json(path: Path) -> dict:
    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise ValueError(f"{path.name} is not a GLB file")
    _magic, version, length = struct.unpack_from("<III", data, 0)
    if version != 2 or length != len(data):
        raise ValueError(f"{path.name} has an unexpected GLB header")
    offset = 12
    document = None
    while offset + 8 <= len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8 : offset + 8 + chunk_length]
        if chunk_type == 0x4E4F534A:
            document = json.loads(chunk.decode("utf-8").rstrip())
        offset += 8 + chunk_length
    if document is None:
        raise ValueError(f"{path.name} has no JSON chunk")
    return document
