# Milestone 4 — inventory, pickups, and crates

Item definitions are resources. Inventories and crates are changed only by the authoritative server. A client sends a request. The server checks the player, the distance, the item, and the slots, then applies the whole change once.

## Launch

Double-click `tools\launcher.vbs`, or:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\Admin\Documents\VSC\survival-sandbox\tools\start_multiplayer.ps1"
```

Headless check:

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Users\Admin\Documents\VSC\survival-sandbox" --script res://tests/milestone4_inventory.gd
```

Success prints `MILESTONE4_INVENTORY_OK`.

## Items

Each definition is a `ItemDefinition` resource in `resources/items/`. The catalog loads Scrap Metal, Cloth, Medical Supplies, Ammunition, Canned Food, and Debug Weapon. Everyone starts with one Debug Weapon in the hotbar. It fires with the selected hotbar slot and does not use ammunition. A slot stores an item id and a quantity. An empty slot is id `""` and quantity 0.

Players have 12 slots. The supply crate has 8. Stacks stop at the definition's maximum. Weight is stored on the definition and shown in the panel. It does not limit capacity yet.

## World loot

The south yard has a scrap pile (8), a cloth pile, a canned-food pile, and a crate at `(-12, 12)` holding 2 medical supplies and 20 ammunition. Two more scrap piles of 12 sit at the north `(0, -8)` and the east `(6, -4)`. Press F within 2.5 m. Tab opens the inventory in the center of the screen. With a crate open, the inventory and the crate sit side by side in the center, and walking is disabled until the crate is closed. The inventory behaves like Minecraft's. The bottom row is a 9-slot hotbar, with 27 storage slots above it. A crate has 27 slots. Left click picks up or places a stack. Right click picks up half or places one. Shift-click moves a stack between the hotbar, the storage, and an open crate. Double-click gathers matching stacks onto the cursor. Dragging a held stack across slots spreads it. Press 1-9 to select the hotbar, or hover a slot and press 1-9 to swap. G drops one item. Ctrl+G drops the stack. Q stays lean, so drop is G rather than Minecraft's Q. There is no crafting grid, armor bar, or off-hand.

The panel shows the last snapshot the server confirmed.

## Manual check

1. Start the server and two clients.
2. Walk to the scrap pile in the south-east yard and press F. Tab shows Scrap Metal. The pile disappears.
3. Have the other client press F on the same spot. Nothing is added.
4. Walk to the wooden crate and press F. Move one medical supply into the inventory, then move it back.
5. Fill the inventory and try another pile. The pile stays in the world.

## Limits

There is no crafting, armor, durability, hunger, trading, death bags, or saving. The debug weapon is the only equipped item, and only while its hotbar slot is selected. Ammunition is not consumed. World pickup positions are sent to every client. Crate contents and a player's inventory are not. A modified client can still read the fixed test loot in `scripts/items/loot_layout.gd`. Operations are applied one at a time on the server thread, with a lock so a nested request is rejected.
