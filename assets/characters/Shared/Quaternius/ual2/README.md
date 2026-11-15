# Quaternius UAL2 clips

CC0 clips from [Universal Animation Library 2](https://quaternius.com/packs/universalanimationlibrary2.html) (via Drawcall Market).

| File | Alias in `ual_locomotion.res` | Import |
| --- | --- | --- |
| `quaternius-ual2-walk-l-loop.glb` | `Walk_L` | skeleton + `UAL2BoneMap.tres` |
| `quaternius-ual2-walk-r-loop.glb` | `Walk_R` | skeleton + `UAL2BoneMap.tres` |
| `quaternius-ual2-walk-bwd-loop.glb` | `Walk_Bwd` | skeleton + `UAL2BoneMap.tres` |
| `quaternius-ual2-mining-loop.glb` | `Mining` | skeleton import + BoneMap |
| `quaternius-ual2-tree-chopping-loop.glb` | `TreeChopping` | skeleton import + BoneMap |

## Why the walks work now

The GLBs have no `Skeleton3D`, only `Node3D` bones named `hips`, `leftUpperLeg`, and so on. Merging their tracks by name never matched the Pro rest. The walk `.import` files now set `nodes/import_as_skeleton_bones=true` and a BoneMap. Godot's rest fixer then puts them on the humanoid reference pose, the same one the Pro mannequin uses (rest difference 0.001 rad, hips at 0.917 m).

Use this flow for every new clip source: import as skeleton with Use Retarget Modifier, map the bones, then bake with `tools/bake_shared_locomotion.gd`.

## Diagonals

There are no diagonal walks. The stand blend space interpolates between `Walk`, `Walk_L`, `Walk_R`, and `Walk_Bwd`.

Re-download if needed:

```bat
npx drawcall market install walk-bwd-loop walk-l-loop walk-right-loop mining-loop-alternate-2 tree-chopping-loop-alternate-2
```

Then reimport and bake:

```bat
Godot_v4.7.2-stable_win64_console.exe --path . --headless --import
Godot_v4.7.2-stable_win64_console.exe --path . --headless -s res://tools/bake_shared_locomotion.gd
```

The BoneMap is `UAL2BoneMap.tres`. Re-download keeps the `.import` settings only if the `.import` files stay in the repo.
