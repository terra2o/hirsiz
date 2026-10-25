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

	init_fonts()
	defer unload_fonts()

	tile_size :: 32

	menu := init_menu_state()
	state: core.Game_State
	game_active := false

	defer {
		if game_active {
			if state.player_hp > 0 {
				core.auto_save_game(&state)
			} else {
				core.delete_save_file()
			}
			core.destroy_game(&state)
		}
	}

	camera := init_camera(0, 0)

	hold_timer: f32 = 0
	first_delay :: 0.3
	repeat_delay :: 0.05

	held_dx: int
	held_dy: int

	waiting_cast_confirm := false

	selected_slot := Selected_Slot {
		kind  = .Backpack,
		index = 0,
	}

	main_loop: for !rl.WindowShouldClose() {
		free_all(context.temp_allocator)
		poll_frame_keys()

		screen_w := rl.GetScreenWidth()
		screen_h := rl.GetScreenHeight()

		if menu.screen != .Playing {
			rl.BeginDrawing()
			rl.ClearBackground(rl.Color{10, 10, 15, 255})
			act := update_and_draw_menu(&menu, screen_w, screen_h)
			rl.EndDrawing()

			#partial switch act {
			case .Start_New_Game:
				if game_active {
					core.destroy_game(&state)
					game_active = false
				}
				state = core.init_game(menu.char_cfg.seed, menu.char_cfg)
				game_active = true
				core.auto_save_game(&state)
				camera = init_camera(f32(state.player_x * tile_size), f32(state.player_y * tile_size))
				held_dx = 0
				held_dy = 0
				hold_timer = 0
				menu.screen = .Playing

			case .Continue_Saved_Game:
				if !game_active {
					save_data, load_ok, clean_session := core.load_game()
					if load_ok {
						state = core.restore_game_from_save(&save_data)
						game_active = true
						if !clean_session {
							core.push_message(&state, "Resumed after abnormal exit (crash/force quit detected).")
						} else {
							core.push_message(&state, "Welcome back to the dungeon!")
						}
						camera = init_camera(f32(state.player_x * tile_size), f32(state.player_y * tile_size))
					}
				}
				if game_active {
					held_dx = 0
					held_dy = 0
					hold_timer = 0
					menu.screen = .Playing
				}

			case .Quit_App:
				break main_loop
			}
			continue
		}

		layout := compute_ui_layout(screen_w, screen_h)

		shift_held := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)

		// return to main menu with Escape (including caps-tap via poll_frame_keys), Backspace, or 'm'
		if is_key_pressed(.ESCAPE) || is_key_pressed(.BACKSPACE) || is_key_pressed(.M) {
			if waiting_cast_confirm {
				waiting_cast_confirm = false
				core.push_message(&state, "Cancelled spell.")
				for rl.GetCharPressed() != 0 {}
				continue
			}
			if state.player_hp > 0 {
				core.auto_save_game(&state)
			}
			refresh_menu_save_preview(&menu)
			menu.main_cursor = menu.has_save ? 1 : 0
			menu.screen = .Main_Menu
			for rl.GetCharPressed() != 0 {}
			continue
		}

		// open dungeon manual with '?'
		if shift_held && is_key_pressed(.SLASH) {
			menu.return_screen = .Playing
			menu.screen = .Controls_Help
			for rl.GetCharPressed() != 0 {}
			continue
		}

		for rl.GetCharPressed() != 0 {}

		// check for player death
		if !state.is_running || state.player_hp <= 0 {
			menu.last_morgue = core.record_morgue_entry(&state)
			core.delete_save_file()
			core.destroy_game(&state)
			game_active = false
			refresh_menu_save_preview(&menu)
			menu.screen = .Game_Over
			continue
		}

		// step active in-flight projectiles across real-time frames
		if core.has_flying_projectiles(&state) {
			state.projectile_timer += rl.GetFrameTime()
			if state.projectile_timer >= 0.032 {
				state.projectile_timer = 0
				all_finished := core.step_flying_projectiles(&state)
				if all_finished {
					core.step_enemy_turns(&state)
					state.floors[state.depth] = state.dungeon
				}
			}
		} else if state.is_targeting {
			res := handle_targeting_input(&state)
			#partial switch res {
			case .Fired_Projectile, .Executed_Melee:
				if state.player_hp > 0 {
					core.auto_save_game(&state)
				}
			case .Cancelled, .None:
			}
		} else {
			// cycle spells with '[' / ']'
			if state.spell_count > 0 {
				if is_key_pressed(.LEFT_BRACKET) {
					state.selected_spell = (state.selected_spell - 1 + state.spell_count) % state.spell_count
					sp := state.known_spells[state.selected_spell]
					core.push_message(&state, fmt.tprintf("Selected spell: %s.", core.SPELL_DEFS[sp].name))
				} else if is_key_pressed(.RIGHT_BRACKET) {
					state.selected_spell = (state.selected_spell + 1) % state.spell_count
					sp := state.known_spells[state.selected_spell]
					core.push_message(&state, fmt.tprintf("Selected spell: %s.", core.SPELL_DEFS[sp].name))
				}
			}

			// manual targeting / attack with 'f'
			if is_key_pressed(.F) {
				waiting_cast_confirm = false
				start_targeting(&state)
			}

			// show spell to cast with 'z' (or confirm with Enter / .)
			if is_key_pressed(.Z) {
				if state.spell_count == 0 {
					core.push_message(&state, "You don't know any spells!")
				} else {
					if state.selected_spell >= state.spell_count {
						state.selected_spell = 0
					}
					sp_kind := state.known_spells[state.selected_spell]
					sp_def := core.SPELL_DEFS[sp_kind]
					cost_unit := state.player_species == .Djinni ? "HP" : "MP"
					core.push_message(
						&state,
						fmt.tprintf("Casting: %s (%d %s). Confirm with [Enter/.], or [Esc] to cancel.", sp_def.name, sp_def.mp_cost, cost_unit),
					)
					waiting_cast_confirm = true
				}
			} else if waiting_cast_confirm {
				if is_key_pressed(.ENTER) || is_key_pressed(.SPACE) || is_key_pressed(.PERIOD) {
					waiting_cast_confirm = false
					start_targeting(&state)
				} else if is_key_pressed(.ESCAPE) || is_key_pressed(.BACKSPACE) {
					waiting_cast_confirm = false
					core.push_message(&state, "Cancelled spell.")
				}
			}

			// directional movement (arrows & vi keys)
			dx, dy: int
			if is_key_pressed(.UP) || is_key_pressed(.K) {
				waiting_cast_confirm = false
				dy = -1; held_dx = 0; held_dy = -1
			} else if is_key_pressed(.DOWN) || is_key_pressed(.J) {
				waiting_cast_confirm = false
				dy = 1; held_dx = 0; held_dy = 1
			} else if is_key_pressed(.LEFT) || is_key_pressed(.H) {
				waiting_cast_confirm = false
				dx = -1; held_dx = -1; held_dy = 0
			} else if is_key_pressed(.RIGHT) || is_key_pressed(.L) {
				waiting_cast_confirm = false
				dx = 1; held_dx = 1; held_dy = 0
			}

			// stair interaction:
			// go down: '>' (Shift+PERIOD) or KEY_PAGE_DOWN
			// go up:   '<' (Shift+COMMA)  or KEY_PAGE_UP
			if (shift_held && is_key_pressed(.PERIOD)) || is_key_pressed(.PAGE_DOWN) {
				if core.go_down_stairs(&state) {
					core.auto_save_game(&state)
				}
			} else if (shift_held && is_key_pressed(.COMMA)) || is_key_pressed(.PAGE_UP) {
				if core.go_up_stairs(&state) {
					core.auto_save_game(&state)
				}
			}

			// keyboard shortcuts for equipment slots unequip (keys 1-8)
			for key_idx in 0 ..< int(core.EQUIPMENT_SLOT_COUNT) {
				key := rl.KeyboardKey(int(rl.KeyboardKey.ONE) + key_idx)
				if is_key_pressed(key) {
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

			if (dx != 0 || dy != 0) && state.is_running {
				prev_turns := state.turn_count
				core.step_turn(&state, dx, dy)
				if state.player_hp > 0 && state.turn_count != prev_turns && state.turn_count % 10 == 0 {
					core.auto_save_game(&state)
				}
			}
		}

		// check for player death
		if !state.is_running || state.player_hp <= 0 {
			menu.last_morgue = core.record_morgue_entry(&state)
			core.delete_save_file()
			core.destroy_game(&state)
			game_active = false
			refresh_menu_save_preview(&menu)
			menu.screen = .Game_Over
			continue
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
					glyph_size :: 26
					tw := measure_text_bold(cstring(&glyph_str[0]), glyph_size)
					draw_text_bold(
						cstring(&glyph_str[0]),
						i32(rect.x) + (tile_size - tw) / 2,
						i32(rect.y) + (tile_size - glyph_size) / 2,
						glyph_size,
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
			enemy_font_size :: 26
			tw := measure_text_bold(cstring(&glyph_str[0]), enemy_font_size)
			draw_text_bold(
				cstring(&glyph_str[0]),
				ex + (tile_size - tw) / 2,
				ey + (tile_size - enemy_font_size) / 2,
				enemy_font_size,
				rl.WHITE,
			)

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
		player_font_size :: 28
		player_tw := measure_text_bold("@", player_font_size)
		draw_text_bold(
			"@",
			px + (tile_size - player_tw) / 2,
			py + (tile_size - player_font_size) / 2,
			player_font_size,
			rl.WHITE,
		)

		// draw targeting overlay reticle and line of fire
		if state.is_targeting {
			draw_targeting_overlay(&state, tile_size)
		}

		// draw active projectile in flight
		if state.projectile_count > 0 {
			draw_active_projectiles(&state, tile_size)
		}

		rl.EndMode2D()
		rl.EndScissorMode()

		// draw top event log box
		draw_event_log_box(layout.event_box, &state)

		// draw right pane: stats (top)
		stats_act := draw_stats_panel(layout.stats_panel, &state)
		#partial switch stats_act {
		case .Cast_Spell:
			if state.spell_count > 0 && core.cast_spell(&state, state.selected_spell) {
				if state.player_hp > 0 {
					core.auto_save_game(&state)
				}
			}
		case .Open_Menu:
			if state.player_hp > 0 {
				core.auto_save_game(&state)
			}
			refresh_menu_save_preview(&menu)
			menu.main_cursor = menu.has_save ? 1 : 0
			menu.screen = .Main_Menu
		case .Open_Help:
			menu.return_screen = .Playing
			menu.screen = .Controls_Help
		}

		// draw right pane: inventory grid (bottom)
		inv_act := draw_inventory_panel(layout.inventory_panel, &state, &selected_slot)

		#partial switch inv_act {
		case .Use_Or_Equip:
			if selected_slot.kind == .Backpack {
				item_k := state.player_inventory.items[selected_slot.index]
				if state.player_species == .Felid && item_k != .None {
					item_d := core.ITEM_DEFS[item_k]
					if item_d.category == .Equipment && item_d.slot != .Ring && item_d.slot != .Amulet {
						core.push_message(&state, "As a Felid, your paws cannot wield weapons or wear armor!")
						rl.EndDrawing()
						continue
					}
				}
				success, msg := core.use_inventory_item(
					&state.player_inventory,
					selected_slot.index,
					&state.player_hp,
					state.player_max_hp,
					&state.player_mp,
					state.player_max_mp,
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
