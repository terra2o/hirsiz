package main

import "../core"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

Targeting_Result :: enum {
	None,
	Fired_Projectile,
	Executed_Melee,
	Cancelled,
}

// enters targeting mode, positioning reticle at player position
start_targeting :: proc(state: ^core.Game_State) {
	state.is_targeting = true
	state.target_x = state.player_x
	state.target_y = state.player_y
	core.push_message(
		state,
		"Targeting: select direction or target. [Enter/f/z] Fire, [Tab] Next, [Esc] Cancel.",
	)
}

// cycles through all visible alive enemies
cycle_next_target :: proc(state: ^core.Game_State) {
	d := &state.dungeon
	first_idx := -1
	next_idx := -1
	found_current := false

	for &enemy, idx in d.enemies {
		if !enemy.is_alive do continue
		vis_idx := enemy.y * d.width + enemy.x
		if !d.visible[vis_idx] do continue

		if first_idx == -1 {
			first_idx = idx
		}

		if found_current && next_idx == -1 {
			next_idx = idx
			break
		}

		if enemy.x == state.target_x && enemy.y == state.target_y {
			found_current = true
		}
	}

	target_idx := next_idx != -1 ? next_idx : first_idx
	if target_idx != -1 {
		state.target_x = d.enemies[target_idx].x
		state.target_y = d.enemies[target_idx].y
	}
}

// handles keyboard controls when targeting reticle is active
handle_targeting_input :: proc(state: ^core.Game_State) -> Targeting_Result {
	if !state.is_targeting do return .None

	// cancel targeting
	if is_key_pressed(.ESCAPE) || is_key_pressed(.BACKSPACE) {
		state.is_targeting = false
		core.push_message(state, "Cancelled targeting.")
		return .Cancelled
	}

	// cycle visible enemies
	if is_key_pressed(.TAB) {
		cycle_next_target(state)
		return .None
	}

	// move reticle with directional arrows / vi keys
	dx, dy: int
	if is_key_pressed(.UP) || is_key_pressed(.K) {
		dy = -1
	} else if is_key_pressed(.DOWN) || is_key_pressed(.J) {
		dy = 1
	} else if is_key_pressed(.LEFT) || is_key_pressed(.H) {
		dx = -1
	} else if is_key_pressed(.RIGHT) || is_key_pressed(.L) {
		dx = 1
	}

	if dx != 0 || dy != 0 {
		nx := state.target_x + dx
		ny := state.target_y + dy
		if core.dungeon_in_bounds(&state.dungeon, nx, ny) {
			state.target_x = nx
			state.target_y = ny
		}
		return .None
	}

	// confirm target and execute attack or spell
	if is_key_pressed(.ENTER) ||
	   is_key_pressed(.SPACE) ||
	   is_key_pressed(.F) ||
	   is_key_pressed(.Z) {
		tx := state.target_x
		ty := state.target_y

		// check if target is an adjacent enemy for melee attack
		ad_dx := abs(tx - state.player_x)
		ad_dy := abs(ty - state.player_y)
		is_adjacent := (ad_dx <= 1 && ad_dy <= 1) && !(ad_dx == 0 && ad_dy == 0)

		target_enemy := core.find_enemy_at(&state.dungeon, tx, ty)

		if is_adjacent && target_enemy != nil {
			// execute direct melee weapon attack
			state.is_targeting = false
			core.player_attack(state, target_enemy)
			state.player_last_attack = 0
			state.turn_count += 1
			core.step_all_projectiles(state)
			core.step_enemy_turns(state)
			state.floors[state.depth] = state.dungeon
			return .Executed_Melee
		}

		// otherwise attempt to cast currently selected spell
		if state.spell_count > 0 {
			state.is_targeting = false
			if core.cast_spell_at(state, state.selected_spell, tx, ty) {
				return .Fired_Projectile
			} else {
				return .None
			}
		}

		if is_adjacent {
			core.push_message(state, "No target there to attack!")
		} else {
			core.push_message(state, "Target is out of melee range and no spell is selected!")
		}
		state.is_targeting = false
		return .Cancelled
	}

	return .None
}

// draws the targeting ray and reticle box in the dungeon view
draw_targeting_overlay :: proc(state: ^core.Game_State, tile_size: i32) {
	if !state.is_targeting do return

	d := &state.dungeon
	clear, _, path, path_len := core.check_line_of_fire(
		d,
		state.player_x,
		state.player_y,
		state.target_x,
		state.target_y,
	)

	// draw line of fire tiles
	for i in 1 ..< path_len {
		pt := path[i]
		rx := f32(pt.x * int(tile_size))
		ry := f32(pt.y * int(tile_size))
		line_col := clear ? rl.Color{60, 220, 100, 70} : rl.Color{230, 80, 60, 80}
		rl.DrawRectangleRec(
			rl.Rectangle{rx + 4, ry + 4, f32(tile_size - 8), f32(tile_size - 8)},
			line_col,
		)
	}

	// draw targeting reticle around (target_x, target_y)
	tx := i32(state.target_x) * tile_size
	ty := i32(state.target_y) * tile_size
	reticle_col := clear ? rl.Color{80, 240, 120, 255} : rl.Color{240, 80, 80, 255}

	rl.DrawRectangleLinesEx(
		rl.Rectangle{f32(tx), f32(ty), f32(tile_size), f32(tile_size)},
		2.0,
		reticle_col,
	)

	// hover description text
	hover_enemy := core.find_enemy_at(d, state.target_x, state.target_y)
	if hover_enemy != nil {
		def := core.ENEMY_DEFS[hover_enemy.kind]
		info := fmt.tprintf("%s (%d/%d HP)", def.name, hover_enemy.hp, hover_enemy.max_hp)
		info_cstr := strings.clone_to_cstring(info, context.temp_allocator)
		draw_text(info_cstr, tx, ty - 14, 12, rl.WHITE)
	}
}

// draws all active projectiles in flight
draw_active_projectiles :: proc(state: ^core.Game_State, tile_size: i32) {
	for i in 0 ..< state.projectile_count {
		proj := &state.active_projectiles[i]
		if proj.done do continue

		col := rl.Color{proj.color.r, proj.color.g, proj.color.b, 255}

		// render beam path for beam weapons
		if proj.kind == .Beam && proj.step_index > 0 {
			beam_col := rl.Color{proj.color.r, proj.color.g, proj.color.b, 160}
			for s in 1 ..= proj.step_index {
				if s >= proj.path_len do break
				pt := proj.path[s]
				bx := f32(pt.x * int(tile_size))
				by := f32(pt.y * int(tile_size))
				rl.DrawRectangleRec(
					rl.Rectangle{bx + 6, by + 6, f32(tile_size - 12), f32(tile_size - 12)},
					beam_col,
				)
			}
		}

		px := i32(proj.current_pos.x) * tile_size
		py := i32(proj.current_pos.y) * tile_size

		radius := proj.kind == .Foxfire_Wisp ? f32(tile_size / 4) : f32(tile_size / 3)
		// glow halo
		halo_col := rl.Color{proj.color.r, proj.color.g, proj.color.b, 80}
		rl.DrawCircle(px + tile_size / 2, py + tile_size / 2, radius * 1.5, halo_col)
		rl.DrawCircle(px + tile_size / 2, py + tile_size / 2, radius, col)

		glyph_str: [2]u8 = {u8(proj.glyph), 0}
		font_size :: 20
		tw := measure_text_bold(cstring(&glyph_str[0]), font_size)
		draw_text_bold(
			cstring(&glyph_str[0]),
			px + (tile_size - tw) / 2,
			py + (tile_size - font_size) / 2,
			font_size,
			rl.WHITE,
		)
	}
}
