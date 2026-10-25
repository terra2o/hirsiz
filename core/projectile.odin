package core

import "core:fmt"

Point2D :: struct {
	x: int,
	y: int,
}

MAX_PROJECTILE_PATH :: 32
MAX_ACTIVE_PROJECTILES :: 8

Projectile_Kind :: enum u8 {
	None = 0,
	Bolt,
	Beam,
	Explosion,
	Bouncing_Bolt,
	Foxfire_Wisp,
}

Projectile :: struct {
	kind:             Projectile_Kind,
	spell:            Spell_Kind,
	glyph:            rune,
	color:            Color_RGB,
	start_pos:        Point2D,
	current_pos:      Point2D,
	target_pos:       Point2D,
	dir_x:            int,
	dir_y:            int,
	path:             [MAX_PROJECTILE_PATH]Point2D,
	path_len:         int,
	step_index:       int,
	damage:           int,
	piercing:         bool,
	aoe_radius:       int,
	bounces_left:     int,
	lifetime_steps:   int,
	source_label:     string,
	done:             bool,
}

// traces grid line coordinates between endpoints
trace_line :: proc(x0, y0, x1, y1: int, max_range: int = MAX_PROJECTILE_PATH) -> ([MAX_PROJECTILE_PATH]Point2D, int) {
	path: [MAX_PROJECTILE_PATH]Point2D
	count := 0

	dx := abs(x1 - x0)
	dy := abs(y1 - y0)
	sx := x0 < x1 ? 1 : -1
	sy := y0 < y1 ? 1 : -1
	err := dx - dy

	curr_x := x0
	curr_y := y0

	for {
		if count >= max_range || count >= len(path) do break
		path[count] = Point2D{curr_x, curr_y}
		count += 1

		if curr_x == x1 && curr_y == y1 do break

		e2 := 2 * err
		if e2 > -dy {
			err -= dy
			curr_x += sx
		}
		if e2 < dx {
			err += dx
			curr_y += sy
		}
	}

	return path, count
}

// checks line of fire clearance towards target
check_line_of_fire :: proc(
	d: ^Dungeon,
	x0, y0, x1, y1: int,
	max_range: int = MAX_PROJECTILE_PATH,
) -> (clear: bool, hit_point: Point2D, path: [MAX_PROJECTILE_PATH]Point2D, path_len: int) {
	path, path_len = trace_line(x0, y0, x1, y1, max_range)
	clear = true
	hit_point = Point2D{x1, y1}

	for i in 1 ..< path_len {
		pt := path[i]
		tile := dungeon_get_tile(d, pt.x, pt.y)
		if !tile.transparent {
			clear = false
			hit_point = pt
			path_len = i + 1
			return clear, hit_point, path, path_len
		}
	}
	return clear, hit_point, path, path_len
}

// spawns homing flame wisps adjacent to the caster
spawn_foxfire_wisps :: proc(state: ^Game_State, spell: Spell_Kind) -> bool {
	d := &state.dungeon
	def := SPELL_DEFS[spell]

	// find open adjacent tiles
	open_adj: [8]Point2D
	open_count := 0

	adj_offsets := [8][2]int{
		{-1, -1}, {0, -1}, {1, -1},
		{-1,  0},          {1,  0},
		{-1,  1}, {0,  1}, {1,  1},
	}

	for off in adj_offsets {
		nx := state.player_x + off[0]
		ny := state.player_y + off[1]
		if !dungeon_in_bounds(d, nx, ny) do continue
		tile := dungeon_get_tile(d, nx, ny)
		if tile.walkable && find_enemy_at(d, nx, ny) == nil {
			open_adj[open_count] = Point2D{nx, ny}
			open_count += 1
		}
	}

	if open_count == 0 {
		push_message(state, "The cramped space prevents the foxfires from manifesting!")
		return false
	}

	wisps_to_spawn := min(2, open_count)
	dmg := compute_spell_damage(state, spell)

	nearest := find_nearest_visible_enemy(state, 8)
	target_pos := nearest != nil ? Point2D{nearest.x, nearest.y} : Point2D{state.player_x, state.player_y}

	for i in 0 ..< wisps_to_spawn {
		if state.projectile_count >= MAX_ACTIVE_PROJECTILES do break

		idx := (i * (open_count - 1)) % open_count
		spawn_pt := open_adj[idx]

		p: Projectile
		p.kind = .Foxfire_Wisp
		p.spell = spell
		p.glyph = '*'
		p.color = Color_RGB{255, 140, 40}
		p.start_pos = spawn_pt
		p.current_pos = spawn_pt
		p.target_pos = target_pos
		p.damage = dmg
		p.piercing = false
		p.lifetime_steps = 14
		p.source_label = "Foxfire"
		p.done = false

		state.active_projectiles[state.projectile_count] = p
		state.projectile_count += 1
	}

	push_message(state, "You conjure two dancing wisps of burning flame!")
	return true
}

// creates a directed spell projectile
create_spell_projectile :: proc(
	state: ^Game_State,
	spell: Spell_Kind,
	target_x, target_y: int,
) -> (Projectile, bool) {
	proj: Projectile
	if spell == .None do return proj, false

	def := SPELL_DEFS[spell]
	proj.spell = spell
	proj.source_label = def.name
	proj.start_pos = Point2D{state.player_x, state.player_y}
	proj.current_pos = proj.start_pos
	proj.target_pos = Point2D{target_x, target_y}
	proj.damage = compute_spell_damage(state, spell)
	proj.piercing = def.pierce_defense
	proj.step_index = 0
	proj.done = false

	dx := target_x - state.player_x
	dy := target_y - state.player_y
	proj.dir_x = dx > 0 ? 1 : (dx < 0 ? -1 : 0)
	proj.dir_y = dy > 0 ? 1 : (dy < 0 ? -1 : 0)

	#partial switch spell {
	case .Magic_Dart:
		proj.kind = .Bolt
		proj.glyph = '*'
		proj.color = Color_RGB{220, 180, 255}

	case .Freeze:
		proj.kind = .Bolt
		proj.glyph = '*'
		proj.color = Color_RGB{120, 210, 255}

	case .Shock:
		proj.kind = .Bouncing_Bolt
		proj.glyph = '/'
		proj.color = Color_RGB{150, 240, 255}
		proj.bounces_left = 2

	case .Sandblast:
		proj.kind = .Bolt
		proj.glyph = '.'
		proj.color = Color_RGB{210, 180, 120}

	case .Venom_Bolt:
		proj.kind = .Bolt
		proj.glyph = '*'
		proj.color = Color_RGB{70, 230, 90}

	case .Vampiric_Drain:
		proj.kind = .Bolt
		proj.glyph = '*'
		proj.color = Color_RGB{180, 60, 220}

	case .Searing_Ray:
		proj.kind = .Beam
		proj.glyph = '-'
		proj.color = Color_RGB{255, 240, 120}

	case .Stone_Arrow:
		proj.kind = .Bolt
		proj.glyph = '^'
		proj.color = Color_RGB{160, 150, 140}

	case .Ice_Blast:
		proj.kind = .Explosion
		proj.glyph = '*'
		proj.color = Color_RGB{140, 220, 255}
		proj.aoe_radius = 1

	case .Fireball:
		proj.kind = .Explosion
		proj.glyph = '*'
		proj.color = Color_RGB{255, 100, 40}
		proj.aoe_radius = 1

	case .Chain_Lightning:
		proj.kind = .Bouncing_Bolt
		proj.glyph = '/'
		proj.color = Color_RGB{200, 240, 255}
		proj.bounces_left = 3

	case:
		proj.kind = .Bolt
		proj.glyph = '*'
		proj.color = Color_RGB{255, 255, 255}
	}

	max_r := min(def.range + 1, MAX_PROJECTILE_PATH)
	_, _, path, path_len := check_line_of_fire(&state.dungeon, state.player_x, state.player_y, target_x, target_y, max_r)
	proj.path = path
	proj.path_len = path_len

	return proj, true
}

// advances a single projectile along its path or homing trajectory
step_single_projectile :: proc(state: ^Game_State, proj: ^Projectile) -> bool {
	if proj.done do return true

	d := &state.dungeon

	// homing pathing for wisps
	if proj.kind == .Foxfire_Wisp {
		proj.lifetime_steps -= 1
		if proj.lifetime_steps <= 0 {
			push_message(state, "The foxfire dissipates into thin smoke.")
			proj.done = true
			return true
		}

		nearest := find_nearest_visible_enemy(state, 8)
		if nearest != nil {
			proj.target_pos = Point2D{nearest.x, nearest.y}
		}

		// check if already at target
		if proj.current_pos.x == proj.target_pos.x && proj.current_pos.y == proj.target_pos.y {
			hit_e := find_enemy_at(d, proj.current_pos.x, proj.current_pos.y)
			if hit_e != nil {
				damage_enemy_with_spell(state, hit_e, proj.damage, proj.piercing, proj.source_label)
			}
			proj.done = true
			return true
		}

		dx := proj.target_pos.x - proj.current_pos.x
		dy := proj.target_pos.y - proj.current_pos.y
		step_x := dx > 0 ? 1 : (dx < 0 ? -1 : 0)
		step_y := dy > 0 ? 1 : (dy < 0 ? -1 : 0)

		next_x := proj.current_pos.x + step_x
		next_y := proj.current_pos.y + step_y

		// navigate around corners if straight diagonal is blocked
		next_tile := dungeon_get_tile(d, next_x, next_y)
		if !next_tile.walkable {
			if step_x != 0 && dungeon_get_tile(d, proj.current_pos.x + step_x, proj.current_pos.y).walkable {
				next_x = proj.current_pos.x + step_x
				next_y = proj.current_pos.y
			} else if step_y != 0 && dungeon_get_tile(d, proj.current_pos.x, proj.current_pos.y + step_y).walkable {
				next_x = proj.current_pos.x
				next_y = proj.current_pos.y + step_y
			} else {
				push_message(state, "The foxfire fizzles out against the wall!")
				proj.done = true
				return true
			}
		}

		proj.current_pos = Point2D{next_x, next_y}

		hit_enemy := find_enemy_at(d, next_x, next_y)
		if hit_enemy != nil {
			damage_enemy_with_spell(state, hit_enemy, proj.damage, proj.piercing, proj.source_label)
			proj.done = true
			return true
		}

		return false
	}

	// linear projectile handling
	proj.step_index += 1
	if proj.step_index >= proj.path_len {
		proj.done = true
		if proj.aoe_radius > 0 {
			resolve_aoe_explosion(
				state,
				proj.current_pos.x,
				proj.current_pos.y,
				proj.aoe_radius,
				proj.damage,
				proj.piercing,
				proj.source_label,
			)
		}
		return true
	}

	next_pt := proj.path[proj.step_index]
	proj.current_pos = next_pt

	// check wall collision
	tile := dungeon_get_tile(d, next_pt.x, next_pt.y)
	if !tile.transparent {
		if proj.bounces_left > 0 && proj.kind == .Bouncing_Bolt {
			proj.bounces_left -= 1
			push_message(state, fmt.tprintf("The %s bounces off the wall!", proj.source_label))

			prev_pt := proj.path[max(0, proj.step_index - 1)]
			rx := prev_pt.x - (next_pt.x - prev_pt.x)
			ry := prev_pt.y - (next_pt.y - prev_pt.y)

			_, _, bounce_path, b_len := check_line_of_fire(d, prev_pt.x, prev_pt.y, rx, ry, 6)
			proj.path = bounce_path
			proj.path_len = b_len
			proj.step_index = 0
			return false
		}

		if proj.aoe_radius > 0 {
			prev_pt := proj.path[max(0, proj.step_index - 1)]
			resolve_aoe_explosion(
				state,
				prev_pt.x,
				prev_pt.y,
				proj.aoe_radius,
				proj.damage,
				proj.piercing,
				proj.source_label,
			)
		}
		proj.done = true
		return true
	}

	// check enemy collision
	hit_enemy := find_enemy_at(d, next_pt.x, next_pt.y)
	if hit_enemy != nil {
		if proj.aoe_radius > 0 {
			resolve_aoe_explosion(
				state,
				next_pt.x,
				next_pt.y,
				proj.aoe_radius,
				proj.damage,
				proj.piercing,
				proj.source_label,
			)
			proj.done = true
			return true
		}

		damage_enemy_with_spell(state, hit_enemy, proj.damage, proj.piercing, proj.source_label)

		if proj.spell == .Vampiric_Drain {
			healed := max(1, proj.damage / 2)
			state.player_hp = min(state.player_max_hp, state.player_hp + healed)
			push_message(state, fmt.tprintf("You drain %d HP from your foe!", healed))
		}

		// chain lightning arcs to a nearby visible enemy
		if proj.spell == .Chain_Lightning && proj.bounces_left > 0 {
			proj.bounces_left -= 1
			proj.damage = max(1, (proj.damage * 3) / 5)

			best_next: ^Enemy = nil
			best_dist := 999
			for &other in d.enemies {
				if !other.is_alive || &other == hit_enemy do continue
				odx := abs(other.x - next_pt.x)
				ody := abs(other.y - next_pt.y)
				dist := max(odx, ody)
				if dist <= 3 && dist < best_dist {
					vis_idx := other.y * d.width + other.x
					if vis_idx >= 0 && vis_idx < len(d.visible) && d.visible[vis_idx] {
						best_dist = dist
						best_next = &other
					}
				}
			}

			if best_next != nil {
				push_message(state, "The lightning arcs to another foe!")
				_, _, arc_path, arc_len := check_line_of_fire(d, next_pt.x, next_pt.y, best_next.x, best_next.y, 4)
				proj.path = arc_path
				proj.path_len = arc_len
				proj.step_index = 0
				return false
			}
		}

		if proj.kind != .Beam {
			proj.done = true
			return true
		}
	}

	return false
}

// checks if any non-wisp projectile is currently traveling across the grid
has_flying_projectiles :: proc(state: ^Game_State) -> bool {
	for i in 0 ..< state.projectile_count {
		p := &state.active_projectiles[i]
		if !p.done && p.kind != .Foxfire_Wisp do return true
	}
	return false
}

// advances in-flight projectiles by a single tile step (for visual flight animation)
// returns true when all flying projectiles have reached their destination
step_flying_projectiles :: proc(state: ^Game_State) -> bool {
	has_flying := false
	for i in 0 ..< state.projectile_count {
		p := &state.active_projectiles[i]
		if !p.done && p.kind != .Foxfire_Wisp {
			step_single_projectile(state, p)
			if !p.done do has_flying = true
		}
	}

	clean_finished_projectiles(state)
	return !has_flying
}

// compacts the active projectiles array removing completed ones
clean_finished_projectiles :: proc(state: ^Game_State) {
	new_count := 0
	for i in 0 ..< state.projectile_count {
		if !state.active_projectiles[i].done {
			state.active_projectiles[new_count] = state.active_projectiles[i]
			new_count += 1
		}
	}
	state.projectile_count = new_count
}

// advances all currently active projectiles
step_all_projectiles :: proc(state: ^Game_State) -> bool {
	if state.projectile_count == 0 do return true

	all_done := true
	for i in 0 ..< state.projectile_count {
		p := &state.active_projectiles[i]
		if !p.done {
			step_single_projectile(state, p)
			if !p.done do all_done = false
		}
	}

	clean_finished_projectiles(state)
	return all_done
}

// detonates an area-of-effect explosion around center position
resolve_aoe_explosion :: proc(
	state: ^Game_State,
	center_x, center_y: int,
	radius: int,
	damage: int,
	piercing: bool,
	source_label: string,
) {
	d := &state.dungeon
	push_message(state, fmt.tprintf("The %s explodes violently!", source_label))

	for dy in -radius ..= radius {
		for dx in -radius ..= radius {
			tx := center_x + dx
			ty := center_y + dy
			if !dungeon_in_bounds(d, tx, ty) do continue

			enemy := find_enemy_at(d, tx, ty)
			if enemy != nil && enemy.is_alive {
				damage_enemy_with_spell(state, enemy, damage, piercing, source_label)
			}

			if tx == state.player_x && ty == state.player_y {
				self_dmg := max(1, damage - state.player_defense / 2)
				state.player_hp -= self_dmg
				push_message(state, fmt.tprintf("You are caught in the blast for %d damage!", self_dmg))
			}
		}
	}
}
