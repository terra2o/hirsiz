package main

import "../core"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

tile_type_to_rl_color :: proc(type: core.Tile_Type) -> rl.Color {
	c := core.tile_color(type)
	return rl.Color{c.r, c.g, c.b, 255}
}

main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(1280, 720, "hirsiz")
	defer rl.CloseWindow()

	rl.SetWindowMinSize(640, 360)
	rl.SetTargetFPS(60)
	rl.SetExitKey(.KEY_NULL)

	state: core.Game_State
	save_data, load_ok, clean_session := core.load_game()
	if load_ok {
		state = core.restore_game_from_save(&save_data)
		if !clean_session {
			state.status_message = "Resumed after abnormal exit (crash/force quit detected)."
		} else {
			state.status_message = "Game loaded."
		}
	} else {
		state = core.init_game()
	}
	defer {
		if state.player_hp > 0 {
			core.auto_save_game(&state)
		} else {
			// remove save file when player dies
			core.delete_save_file()
		}
		core.destroy_game(&state)
	}

	tile_size :: 32

	camera := init_camera(f32(state.player_x * tile_size), f32(state.player_y * tile_size))

	hold_timer: f32 = 0
	first_delay :: 0.3
	repeat_delay :: 0.05

	held_dx: int
	held_dy: int

	show_inventory := false
	inv_selected := 0

	for !rl.WindowShouldClose() && state.is_running {
		escape_hit := rl.IsKeyPressed(.ESCAPE) || rl.IsKeyReleased(.ESCAPE)
		i_hit := rl.IsKeyPressed(.I)

		// consume queued keys to catch fast taps from remappers (e.g. caps tap -> esc)
		for {
			k := rl.GetKeyPressed()
			if k == .KEY_NULL do break
			if k == .ESCAPE do escape_hit = true
			if k == .I do i_hit = true
		}

		if i_hit {
			show_inventory = !show_inventory
		}

		if show_inventory {
			if escape_hit {
				show_inventory = false
			} else if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.K) {
				inv_selected = max(0, inv_selected - 1)
			} else if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.J) {
				inv_selected = min(core.MAX_INVENTORY_ITEMS - 1, inv_selected + 1)
			} else if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.E) {
				success, msg := core.use_inventory_item(
					&state.player_inventory,
					inv_selected,
					&state.player_hp,
					state.player_max_hp,
				)
				if success {
					core.recompute_player_stats(&state)
					state.status_message = msg
					core.auto_save_game(&state)
				} else if len(msg) > 0 {
					state.status_message = msg
				}
			} else if rl.IsKeyPressed(.U) {
			}

			for key_idx in 0 ..< int(core.EQUIPMENT_SLOT_COUNT) {
				key := rl.KeyboardKey(int(rl.KeyboardKey.ONE) + key_idx)
				if rl.IsKeyPressed(key) {
					slot := core.Equipment_Slot(key_idx)
					eq_item := state.player_inventory.equipment[slot]
					if eq_item != .None {
						if core.unequip_item(&state.player_inventory, slot) {
							core.recompute_player_stats(&state)
							state.status_message = fmt.tprintf(
								"Unequipped %s.",
								core.ITEM_DEFS[eq_item].name,
							)
							core.auto_save_game(&state)
						} else {
							state.status_message = "Inventory is full! Cannot unequip."
						}
					}
				}
			}
		} else {
			dx, dy: int

			// directional movement (Arrows & Vi keys)
			if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.K) {
				dy = -1; held_dx = 0; held_dy = -1
			} else if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.J) {
				dy = 1; held_dx = 0; held_dy = 1
			} else if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressed(.H) {
				dx = -1; held_dx = -1; held_dy = 0
			} else if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressed(.L) {
				dx = 1; held_dx = 1; held_dy = 0
			}

			// stair interaction:
			// go down: '>' (Shift+PERIOD) or PERIOD with shift or KEY_PAGE_DOWN
			// go up:   '<' (Shift+COMMA)  or COMMA with shift or KEY_PAGE_UP
			shift_held := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)

			if (shift_held && rl.IsKeyPressed(.PERIOD)) || rl.IsKeyPressed(.PAGE_DOWN) {
				if core.go_down_stairs(&state) {
					core.auto_save_game(&state)
				}
			} else if (shift_held && rl.IsKeyPressed(.COMMA)) || rl.IsKeyPressed(.PAGE_UP) {
				if core.go_up_stairs(&state) {
					core.auto_save_game(&state)
				}
			}

			if dx != 0 || dy != 0 {
				hold_timer = 0
			} else {
				is_still_held := false
				if held_dy == -1 && (rl.IsKeyDown(.UP) || rl.IsKeyDown(.K)) do is_still_held = true
				if held_dy == 1 && (rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.J)) do is_still_held = true
				if held_dx == -1 && (rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.H)) do is_still_held = true
				if held_dx == 1 && (rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.L)) do is_still_held = true

				if is_still_held {
					hold_timer += rl.GetFrameTime()
					if hold_timer >= first_delay {
						dx = held_dx
						dy = held_dy
						hold_timer -= repeat_delay
					}
				} else {
					held_dx = 0
					held_dy = 0
					hold_timer = 0
				}
			}

			if dx != 0 || dy != 0 {
				prev_turns := state.turn_count
				core.step_turn(&state, dx, dy)
				if state.turn_count != prev_turns && state.turn_count % 10 == 0 {
					core.auto_save_game(&state)
				}
			}
		}

		px := i32(state.player_x) * tile_size
		py := i32(state.player_y) * tile_size
		camera.target = {f32(px + tile_size / 2), f32(py + tile_size / 2)}
		camera.offset = {f32(rl.GetScreenWidth()) / 2.0, f32(rl.GetScreenHeight()) / 2.0}

		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{12, 12, 18, 255})

		rl.BeginMode2D(camera)

		d := &state.dungeon
		for y in 0 ..< d.height {
			for x in 0 ..< d.width {
				idx := y * d.width + x
				is_vis := d.visible[idx]
				is_exp := d.explored[idx]

				if !is_exp do continue

				tile := core.dungeon_get_tile(d, x, y)
				if tile.type == .Unused do continue

				rect := rl.Rectangle {
					x      = f32(x * tile_size),
					y      = f32(y * tile_size),
					width  = f32(tile_size),
					height = f32(tile_size),
				}

				base_col := tile_type_to_rl_color(tile.type)
				col: rl.Color
				if is_vis {
					col = base_col
				} else {
					col = rl.Color {
						u8(u32(base_col.r) * 35 / 100),
						u8(u32(base_col.g) * 35 / 100),
						u8(u32(base_col.b) * 45 / 100),
						255,
					}
				}
				rl.DrawRectangleRec(rect, col)

				// overlay ASCII glyph indicator on special tiles or walls
				glyph := core.tile_to_ascii(tile.type)
				if tile.type == .Door_Closed ||
				   tile.type == .Door_Open ||
				   tile.type == .Stairs_Up ||
				   tile.type == .Stairs_Down {
					glyph_str: [2]u8 = {u8(glyph), 0}
					glyph_col := is_vis ? rl.RAYWHITE : rl.Color{130, 130, 140, 255}
					rl.DrawText(
						cstring(&glyph_str[0]),
						i32(rect.x) + 10,
						i32(rect.y) + 6,
						20,
						glyph_col,
					)
				} else if tile.type == .Wall {
					line_col := is_vis ? rl.Color{45, 40, 50, 255} : rl.Color{20, 18, 25, 255}
					rl.DrawRectangleLines(i32(rect.x), i32(rect.y), tile_size, tile_size, line_col)
				} else if tile.type == .Floor {
					line_col := is_vis ? rl.Color{160, 140, 115, 60} : rl.Color{60, 50, 45, 40}
					rl.DrawRectangleLines(i32(rect.x), i32(rect.y), tile_size, tile_size, line_col)
				}
			}
		}

		for &enemy in d.enemies {
			if !enemy.is_alive do continue

			idx := enemy.y * d.width + enemy.x
			if !d.visible[idx] do continue

			def := core.ENEMY_DEFS[enemy.kind]
			ex := i32(enemy.x) * tile_size
			ey := i32(enemy.y) * tile_size

			enemy_col := rl.Color{def.color.r, def.color.g, def.color.b, 255}
			rl.DrawRectangle(ex + 2, ey + 2, tile_size - 4, tile_size - 4, enemy_col)

			glyph_str: [2]u8 = {u8(def.symbol), 0}
			rl.DrawText(cstring(&glyph_str[0]), ex + 10, ey + 4, 22, rl.WHITE)

			if enemy.hp < enemy.max_hp {
				bar_w := tile_size - 4
				hp_w := i32(f32(bar_w) * f32(enemy.hp) / f32(enemy.max_hp))
				rl.DrawRectangle(ex + 2, ey - 3, i32(bar_w), 3, rl.RED)
				if hp_w > 0 {
					rl.DrawRectangle(ex + 2, ey - 3, hp_w, 3, rl.GREEN)
				}
			}
		}

		rl.DrawRectangle(px, py, tile_size, tile_size, rl.Color{220, 60, 60, 255})
		rl.DrawText("@", px + 9, py + 4, 24, rl.WHITE)

		rl.EndMode2D()

		hud_text := rl.TextFormat(
			"HP: %d/%d | ATK: %d | DEF: %d | Depth: %d | Turn: %d",
			state.player_hp,
			state.player_max_hp,
			state.player_attack,
			state.player_defense,
			state.depth,
			state.turn_count,
		)
		rl.DrawRectangle(10, 10, 580, 70, rl.Color{0, 0, 0, 180})
		rl.DrawRectangleLines(10, 10, 580, 70, rl.Color{100, 100, 120, 200})
		rl.DrawText(hud_text, 20, 18, 20, rl.GOLD)

		if len(state.status_message) > 0 {
			msg_cstr := strings.clone_to_cstring(state.status_message, context.temp_allocator)
			rl.DrawText(msg_cstr, 20, 48, 18, rl.RAYWHITE)
		}

		if show_inventory {
			screen_w := rl.GetScreenWidth()
			screen_h := rl.GetScreenHeight()

			panel_w: i32 = 720
			panel_h: i32 = 520
			panel_x := (screen_w - panel_w) / 2
			panel_y := (screen_h - panel_h) / 2

			rl.DrawRectangle(0, 0, screen_w, screen_h, rl.Color{0, 0, 0, 150})

			rl.DrawRectangle(panel_x, panel_y, panel_w, panel_h, rl.Color{20, 20, 28, 245})
			rl.DrawRectangleLines(panel_x, panel_y, panel_w, panel_h, rl.Color{160, 150, 130, 255})

			rl.DrawText("INVENTORY & EQUIPMENT", panel_x + 20, panel_y + 16, 22, rl.GOLD)
			rl.DrawText("[ESC] Close", panel_x + panel_w - 120, panel_y + 18, 16, rl.LIGHTGRAY)

			rl.DrawText("Equipment:", panel_x + 25, panel_y + 55, 18, rl.RAYWHITE)

			eq_y := panel_y + 85
			for slot_idx in 0 ..< int(core.EQUIPMENT_SLOT_COUNT) {
				slot := core.Equipment_Slot(slot_idx)
				slot_name := core.EQUIPMENT_SLOT_NAMES[slot]
				eq_item := state.player_inventory.equipment[slot]

				slot_text: cstring
				col: rl.Color
				if eq_item != .None {
					item_def := core.ITEM_DEFS[eq_item]
					slot_text = rl.TextFormat(
						"[%d] %s: %s (+%dA / +%dD)",
						slot_idx + 1,
						strings.clone_to_cstring(slot_name, context.temp_allocator),
						strings.clone_to_cstring(item_def.name, context.temp_allocator),
						item_def.attack_bonus,
						item_def.defense_bonus,
					)
					col = rl.Color{140, 220, 150, 255}
				} else {
					slot_text = rl.TextFormat(
						"[%d] %s: (empty)",
						slot_idx + 1,
						strings.clone_to_cstring(slot_name, context.temp_allocator),
					)
					col = rl.Color{120, 120, 130, 255}
				}
				rl.DrawText(slot_text, panel_x + 30, eq_y, 16, col)
				eq_y += 28
			}

			rl.DrawLine(
				panel_x + 25,
				eq_y + 10,
				panel_x + 330,
				eq_y + 10,
				rl.Color{80, 80, 95, 255},
			)
			att_b, def_b, hp_b := core.inventory_stat_bonuses(&state.player_inventory)
			stats_text := rl.TextFormat("Bonus: +%d Atk | +%d Def | +%d HP", att_b, def_b, hp_b)
			rl.DrawText(stats_text, panel_x + 30, eq_y + 20, 16, rl.GOLD)

			rl.DrawLine(
				panel_x + 350,
				panel_y + 50,
				panel_x + 350,
				panel_y + panel_h - 20,
				rl.Color{80, 80, 95, 255},
			)

			rl.DrawText("Backpack:", panel_x + 370, panel_y + 55, 18, rl.RAYWHITE)

			item_y := panel_y + 85
			for i in 0 ..< core.MAX_INVENTORY_ITEMS {
				item := state.player_inventory.items[i]
				is_sel := (i == inv_selected)

				item_rect := rl.Rectangle {
					x      = f32(panel_x + 365),
					y      = f32(item_y - 2),
					width  = 330,
					height = 22,
				}

				if is_sel {
					rl.DrawRectangleRec(item_rect, rl.Color{60, 70, 90, 220})
					rl.DrawRectangleLinesEx(item_rect, 1, rl.GOLD)
				}

				if item != .None {
					def := core.ITEM_DEFS[item]
					item_name_cstr := strings.clone_to_cstring(def.name, context.temp_allocator)
					name_txt := rl.TextFormat("%2d. %s", i + 1, item_name_cstr)
					rl.DrawText(name_txt, panel_x + 370, item_y, 16, is_sel ? rl.GOLD : rl.WHITE)
				} else {
					name_txt := rl.TextFormat("%2d. ---", i + 1)
					rl.DrawText(name_txt, panel_x + 370, item_y, 16, rl.Color{100, 100, 110, 180})
				}

				item_y += 24
			}
		}

		rl.EndDrawing()
	}
}
