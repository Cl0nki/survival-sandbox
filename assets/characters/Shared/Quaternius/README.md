# Quaternius Universal Animation Library (Standard)

CC0 pack used as the **default Shared locomotion library** for pipeline humanoids.

## Files

| File | Role |
| --- | --- |
| `AnimationLibrary_Godot_Standard.glb` | UAL1 Standard source |
| `AnimationLibrary_Godot_Pro.glb` | UAL1 Pro (Unreal mannequin) — Idle/Walk + crouch 8-dir + pistol |
| `ual_locomotion.res` | **Use this** — Pro idle/walk/crouch/pistol + UAL2 strafe and harvest |
| `ual2/` | UAL2 directional walk / mining / chop GLBs (CC0) |
| `QuaterniusBoneMap.tres` | Standard DEF-* → humanoid |
| `QuaterniusProBoneMap.tres` | Pro Unreal bones → humanoid |
| `../GodotHumanoidBoneMap.tres` | Identity map for pipeline characters |

## Clip aliases (after Godot import)

| Logical | Animation |
| --- | --- |
| idle / walk | Pro `Idle` / `Walk` |
| walk_l / walk_r / walk_bwd | UAL2, imported as skeleton + BoneMap (same rest as Pro) |
| sprint | removed for now (Pro `Sprint` exists in the GLB if it comes back) |
| diagonals | no clips, blend space interpolates |
| crouch_* | Pro 8-dir (+ enter/exit) |
| pistol_* | Pro |
| mining / tree_chopping | UAL2 harvest only |

## Rebuild the `.res`

```bat
Godot_v4.7.2-stable_win64_console.exe --path . --headless --import
Godot_v4.7.2-stable_win64_console.exe --path . --headless -s res://tools/bake_shared_locomotion.gd
```

`meshy_walk_strafe/` is unused source.


The `pipeline_retarget` editor plugin keeps BoneMaps on the GLB / character imports.
