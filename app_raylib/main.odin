package main

import "../core"
import "core:fmt"
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
			core.push_message(&state, "Resumed after abnormal exit (crash/force quit detected).")
		} else {
			core.push_message(&state, "Game loaded.")
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

	selected_slot := Selected_Slot {
		kind  = .Backpack,
		index = 0,
	}

	for !rl.WindowShouldClose() && state.is_running {
		screen_w := rl.GetScreenWidth()
		screen_h := rl.GetScreenHeight()
		layout := compute_ui_layout(screen_w, screen_h)

		// consume queued keys to catch fast taps from remappers (e.g. caps tap -> esc)
		for {
			k := rl.GetKeyPressed()
			if k == .KEY_NULL do break
		}

		// directional movement (arrows & vi keys)
		dx, dy: int
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

		// keyboard shortcuts for equipment slots unequip (keys 1-8)
		for key_idx in 0 ..< int(core.EQUIPMENT_SLOT_COUNT) {
			key := rl.KeyboardKey(int(rl.KeyboardKey.ONE) + key_idx)
			if rl.IsKeyPressed(key) {
				slot := core.Equipment_Slot(key_idx)
				eq_item := state.player_inventory.equipment[slot]
				if eq_item != .None {
					if core.unequip_item(&state.player_inventory, slot) {
						core.recompute_player_stats(&state)
						core.push_message(
							&state,
							fmt.tprintf("Unequipped %s.", core.ITEM_DEFS[eq_item].name),
						)
						core.auto_save_game(&state)
					} else {
						core.push_message(&state, "Inventory is full! Cannot unequip.")
					}
				}
			}
		}

		// movement repeat logic
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

		// update camera target and center inside game viewport
		px := i32(state.player_x) * tile_size
		py := i32(state.player_y) * tile_size
		camera.target = {f32(px + tile_size / 2), f32(py + tile_size / 2)}
		camera.offset = {
			layout.game_view.x + layout.game_view.width / 2.0,
			layout.game_view.y + layout.game_view.height / 2.0,
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{12, 12, 18, 255})

		// clip dungeon rendering to game viewport
		rl.BeginScissorMode(
			i32(layout.game_view.x),
			i32(layout.game_view.y),
			i32(layout.game_view.width),
			i32(layout.game_view.height),
		)

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

				// overlay ascii glyph indicator on special tiles or walls
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
		rl.EndScissorMode()

		// draw top event log box
		draw_event_log_box(layout.event_box, &state)

		// draw right pane: stats (top)
		draw_stats_panel(layout.stats_panel, &state)

		// draw right pane: inventory grid (bottom)
		inv_act := draw_inventory_panel(layout.inventory_panel, &state, &selected_slot)

		#partial switch inv_act {
		case .Use_Or_Equip:
			if selected_slot.kind == .Backpack {
				success, msg := core.use_inventory_item(
					&state.player_inventory,
					selected_slot.index,
					&state.player_hp,
					state.player_max_hp,
				)
				if success {
					core.recompute_player_stats(&state)
					core.push_message(&state, msg)
					core.auto_save_game(&state)
				} else if len(msg) > 0 {
					core.push_message(&state, msg)
				}
			}
		case .Unequip:
			if selected_slot.kind == .Equip &&
			   selected_slot.index >= 0 &&
			   selected_slot.index < int(core.EQUIPMENT_SLOT_COUNT) {
				slot := core.Equipment_Slot(selected_slot.index)
				eq_item := state.player_inventory.equipment[slot]
				if eq_item != .None {
					if core.unequip_item(&state.player_inventory, slot) {
						core.recompute_player_stats(&state)
						core.push_message(
							&state,
							fmt.tprintf("Unequipped %s.", core.ITEM_DEFS[eq_item].name),
						)
						core.auto_save_game(&state)
					} else {
						core.push_message(&state, "Inventory is full! Cannot unequip.")
					}
				}
			}
		}

		rl.EndDrawing()
	}
}
