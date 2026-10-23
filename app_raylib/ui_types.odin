package main

import rl "vendor:raylib"

UI_Layout :: struct {
	screen_w:             i32,
	screen_h:             i32,
	scale:                f32,
	right_panel:          rl.Rectangle,
	event_box:            rl.Rectangle,
	game_view:            rl.Rectangle,
	stats_panel:          rl.Rectangle,
	inventory_panel:      rl.Rectangle,
	inventory_equip_grid: rl.Rectangle,
	inventory_item_grid:  rl.Rectangle,
	inventory_action_bar: rl.Rectangle,
}

Slot_Kind :: enum {
	None,
	Equip,
	Backpack,
}

Selected_Slot :: struct {
	kind:  Slot_Kind,
	index: int,
}

Inventory_Action :: enum {
	None,
	Use_Or_Equip,
	Unequip,
	Drop,
}
