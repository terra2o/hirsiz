package main

import "../core"
import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

// button with hover and click state
draw_button :: proc(bounds: rl.Rectangle, text: cstring, is_active: bool, font_size: i32) -> bool {
	mouse_pos := rl.GetMousePosition()
	is_hovered := rl.CheckCollisionPointRec(mouse_pos, bounds)
	clicked := false

	bg_col := rl.Color{32, 34, 46, 255}
	border_col := rl.Color{70, 72, 90, 255}
	text_col := rl.Color{180, 185, 200, 255}

	if !is_active {
		bg_col = rl.Color{22, 22, 30, 255}
		border_col = rl.Color{45, 45, 55, 255}
		text_col = rl.Color{90, 90, 105, 255}
	} else if is_hovered {
		bg_col = rl.Color{48, 52, 72, 255}
		border_col = rl.GOLD
		text_col = rl.WHITE
		if rl.IsMouseButtonPressed(.LEFT) {
			clicked = true
		}
	}

	rl.DrawRectangleRec(bounds, bg_col)
	rl.DrawRectangleLinesEx(bounds, 1, border_col)

	tw := measure_text(text, font_size)
	draw_text(
		text,
		i32(bounds.x + (bounds.width - f32(tw)) / 2),
		i32(bounds.y + (bounds.height - f32(font_size)) / 2),
		font_size,
		text_col,
	)

	return clicked
}

draw_inventory_panel :: proc(
	rect: rl.Rectangle,
	state: ^core.Game_State,
	sel: ^Selected_Slot,
) -> Inventory_Action {
	action: Inventory_Action = .None

	// panel background & border
	rl.DrawRectangleRec(rect, rl.Color{16, 16, 24, 255})
	rl.DrawRectangleLinesEx(rect, 1.0, rl.Color{65, 65, 80, 255})

	pad_x := rect.x + math.clamp(rect.width * 0.04, 6.0, 14.0)
	panel_inner_w := rect.width - 2.0 * math.clamp(rect.width * 0.04, 6.0, 14.0)

	mouse_pos := rl.GetMousePosition()

	// dynamic allocation of vertical budget:
	// 2 section titles + divider + 2 rows equipment + 4 rows backpack + inspector info + buttons
	header_font := math.clamp(i32(rect.height * 0.034), 10, 20)
	header_h := f32(header_font + 6)
	divider_h: f32 = math.clamp(rect.height * 0.02, 4.0, 10.0)
	info_h := math.clamp(rect.height * 0.10, 24.0, 56.0)
	btn_h := math.clamp(rect.height * 0.07, 18.0, 40.0)
	slot_gap: f32 = math.clamp(rect.height * 0.01, 2.0, 6.0)

	// total non-grid vertical space
	fixed_vertical := header_h * 2.0 + divider_h + info_h + btn_h + slot_gap * 8.0
	avail_grid_h := rect.height - fixed_vertical
	if avail_grid_h < 40.0 {
		avail_grid_h = 40.0
	}

	// 6 total rows of slots: 2 for equipment, 4 for backpack
	max_slot_by_height := (avail_grid_h - slot_gap * 4.0) / 6.0
	max_slot_by_width := (panel_inner_w - slot_gap * 3.0) / 4.0
	slot_size := math.min(max_slot_by_width, max_slot_by_height)
	if slot_size < 10.0 {
		slot_size = 10.0
	}

	// center slot grids horizontally inside panel_inner_w
	grid_w := 4.0 * slot_size + 3.0 * slot_gap
	grid_offset_x := pad_x + (panel_inner_w - grid_w) / 2.0

	cur_y := rect.y + math.clamp(rect.height * 0.02, 4.0, 10.0)

	// equipment section title
	draw_text_bold("EQUIPMENT", i32(pad_x), i32(cur_y), header_font, rl.Color{170, 175, 190, 255})
	cur_y += header_h

	// equipment grid: 2 rows of 4 slots
	eq_cols := 4
	eq_rows := 2
	for row in 0 ..< eq_rows {
		for col in 0 ..< eq_cols {
			idx := row * eq_cols + col
			slot := core.Equipment_Slot(idx)
			slot_item := state.player_inventory.equipment[slot]
			placeholder := EQUIPMENT_SLOT_GLYPHS[slot]

			slot_rect := rl.Rectangle {
				x      = grid_offset_x + f32(col) * (slot_size + slot_gap),
				y      = cur_y + f32(row) * (slot_size + slot_gap),
				width  = slot_size,
				height = slot_size,
			}

			is_hovered := rl.CheckCollisionPointRec(mouse_pos, slot_rect)
			is_selected := (sel.kind == .Equip && sel.index == idx)

			if is_hovered && rl.IsMouseButtonPressed(.LEFT) {
				sel.kind = .Equip
				sel.index = idx
				is_selected = true
			}

			draw_slot_visual(slot_rect, slot_item, placeholder, is_hovered, is_selected)
		}
	}

	cur_y += f32(eq_rows) * (slot_size + slot_gap) + divider_h * 0.4

	// divider line
	rl.DrawLine(
		i32(pad_x),
		i32(cur_y),
		i32(pad_x + panel_inner_w),
		i32(cur_y),
		rl.Color{50, 50, 65, 255},
	)
	cur_y += divider_h * 0.6

	// backpack section title
	draw_text_bold("BACKPACK", i32(pad_x), i32(cur_y), header_font, rl.Color{170, 175, 190, 255})
	cur_y += header_h

	// backpack grid: 4 columns x 4 rows = 16 items
	inv_cols := 4
	inv_rows := 4
	for row in 0 ..< inv_rows {
		for col in 0 ..< inv_cols {
			idx := row * inv_cols + col
			item := state.player_inventory.items[idx]

			slot_rect := rl.Rectangle {
				x      = grid_offset_x + f32(col) * (slot_size + slot_gap),
				y      = cur_y + f32(row) * (slot_size + slot_gap),
				width  = slot_size,
				height = slot_size,
			}

			is_hovered := rl.CheckCollisionPointRec(mouse_pos, slot_rect)
			is_selected := (sel.kind == .Backpack && sel.index == idx)

			if is_hovered && rl.IsMouseButtonPressed(.LEFT) {
				sel.kind = .Backpack
				sel.index = idx
				is_selected = true
			}

			draw_slot_visual(slot_rect, item, ' ', is_hovered, is_selected)
		}
	}

	cur_y += f32(inv_rows) * (slot_size + slot_gap) + slot_gap

	// inspector info for currently selected slot
	selected_item: core.Item_Kind = .None
	selected_label := ""
	if sel.kind == .Equip && sel.index >= 0 && sel.index < int(core.EQUIPMENT_SLOT_COUNT) {
		slot := core.Equipment_Slot(sel.index)
		selected_item = state.player_inventory.equipment[slot]
		selected_label = core.EQUIPMENT_SLOT_NAMES[slot]
	} else if sel.kind == .Backpack && sel.index >= 0 && sel.index < core.MAX_INVENTORY_ITEMS {
		selected_item = state.player_inventory.items[sel.index]
		selected_label = fmt.tprintf("Slot %d", sel.index + 1)
	}

	info_rect := rl.Rectangle{pad_x, cur_y, panel_inner_w, info_h}
	rl.DrawRectangleRec(info_rect, rl.Color{22, 22, 30, 255})
	rl.DrawRectangleLinesEx(info_rect, 1, rl.Color{50, 52, 65, 255})

	info_font_main := math.clamp(i32(info_h * 0.44), 10, 22)
	info_font_sub := math.clamp(i32(info_h * 0.36), 9, 18)

	if selected_item != .None {
		def := core.ITEM_DEFS[selected_item]
		item_name_cstr := strings.clone_to_cstring(def.name, context.temp_allocator)
		draw_text_bold(item_name_cstr, i32(pad_x + 8), i32(cur_y + info_h * 0.1), info_font_main, rl.GOLD)

		desc := ""
		if def.category == .Equipment {
			desc = fmt.tprintf("+%dA +%dD +%dHP", def.attack_bonus, def.defense_bonus, def.hp_bonus)
		} else if def.category == .Consumable {
			desc = fmt.tprintf("Restores %d HP", def.heal_amount)
		}
		desc_cstr := strings.clone_to_cstring(desc, context.temp_allocator)
		draw_text(desc_cstr, i32(pad_x + 8), i32(cur_y + info_h * 0.54), info_font_sub, rl.Color{160, 165, 180, 255})
	} else {
		placeholder_text := fmt.tprintf("%s: Empty", selected_label)
		placeholder_cstr := strings.clone_to_cstring(placeholder_text, context.temp_allocator)
		draw_text(placeholder_cstr, i32(pad_x + 8), i32(cur_y + (info_h - f32(info_font_main)) / 2), info_font_main, rl.Color{110, 110, 125, 255})
	}

	cur_y += info_h + slot_gap

	// action buttons
	btn_gap: f32 = slot_gap
	btn_w := (panel_inner_w - btn_gap) / 2.0
	btn_font := math.clamp(i32(btn_h * 0.54), 9, 20)

	can_use := (sel.kind == .Backpack && selected_item != .None)
	can_unequip := (sel.kind == .Equip && selected_item != .None)

	btn1_rect := rl.Rectangle{pad_x, cur_y, btn_w, btn_h}
	btn2_rect := rl.Rectangle{pad_x + btn_w + btn_gap, cur_y, btn_w, btn_h}

	if draw_button(btn1_rect, "Use / Equip", can_use, btn_font) {
		action = .Use_Or_Equip
	}

	if draw_button(btn2_rect, "Unequip", can_unequip, btn_font) {
		action = .Unequip
	}

	return action
}
