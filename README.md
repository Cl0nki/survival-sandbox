# Survival Sandbox

Local playable prototype of a 3D top-down survival sandbox. This repository is **Milestone 1 only**: one player, one arena, no networking and no persistence.

Built for Godot **4.7.2 stable**.

## Play

Import `project.godot` in the Godot 4.7 project manager and press F5, or run:

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe" --path "C:\Users\Admin\Documents\VSC\survival-sandbox"
```

Open the editor with the same command plus `--editor`.

## Check

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Users\Admin\Documents\VSC\survival-sandbox" --script res://tests/milestone1_smoke.gd
```

A passing run prints `MILESTONE1_SMOKE_OK` and exits 0.

Controls, the manual checklist, and the decisions for this milestone are in [docs/milestone-1.md](docs/milestone-1.md).
