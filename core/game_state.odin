package core

import "core:fmt"

Game_State :: struct {
	player_x:           int,
	player_y:           int,
	player_hp:          int,
	player_max_hp:      int,
	player_attack:      int,
	player_defense:     int,
	player_last_attack: int, // player last attacked / got attacked
	depth:              int, // current dungeon floor level (starts at 1)
	turn_count:         int,
	is_running:         bool,
	status_message:     string,
	dungeon:            Dungeon,
	floors:             map[int]Dungeon,
}

init_game :: proc(seed: u64 = 0) -> Game_State {
	floors := make(map[int]Dungeon)

	depth := 1
	cfg := default_dungeon_config(seed != 0 ? seed + u64(depth) : 0, depth)
	dung := generate_dungeon(cfg)
	floors[depth] = dung

	spawn_x := dung.stairs_up_pos.x
	spawn_y := dung.stairs_up_pos.y

	if spawn_x == 0 && spawn_y == 0 && len(dung.rooms) > 0 {
		spawn_x = dung.rooms[0].center_x
		spawn_y = dung.rooms[0].center_y
	}

	compute_fov(&dung, spawn_x, spawn_y)
	floors[depth] = dung

	return Game_State {
		player_x = spawn_x,
		player_y = spawn_y,
		player_hp = 20,
		player_max_hp = 20,
		player_attack = 5,
		player_defense = 1,
		player_last_attack = 0,
		depth = depth,
		turn_count = 0,
		is_running = true,
		status_message = "Welcome to hirsiz! Press < or > to use stairs.",
		dungeon = dung,
		floors = floors,
	}
}

destroy_game :: proc(state: ^Game_State) {
	for depth, &dung in state.floors {
		destroy_dungeon(&dung)
	}
	delete(state.floors)
}

find_enemy_at :: proc(d: ^Dungeon, x, y: int) -> ^Enemy {
	for &enemy in d.enemies {
		if enemy.is_alive && enemy.x == x && enemy.y == y {
			return &enemy
		}
	}
	return nil
}

is_tile_blocked :: proc(state: ^Game_State, x, y: int) -> bool {
	tile := dungeon_get_tile(&state.dungeon, x, y)
	if !tile.walkable do return true
	if x == state.player_x && y == state.player_y do return true
	if find_enemy_at(&state.dungeon, x, y) != nil do return true
	return false
}

player_attack :: proc(state: ^Game_State, enemy: ^Enemy) {
	def := ENEMY_DEFS[enemy.kind]
	damage := state.player_attack - def.defense
	if damage < 1 do damage = 1

	enemy.hp -= damage
	if enemy.hp <= 0 {
		enemy.is_alive = false
		state.status_message = fmt.tprintf(
			"You attack %s for %d damage and kill it!",
			def.name,
			damage,
		)
	} else {
		state.status_message = fmt.tprintf(
			"You attack %s for %d damage. (HP: %d/%d)",
			def.name,
			damage,
			enemy.hp,
			enemy.max_hp,
		)
	}
}

step_enemy_turns :: proc(state: ^Game_State) {
	d := &state.dungeon
	for &enemy in d.enemies {
		if !enemy.is_alive do continue

		def := ENEMY_DEFS[enemy.kind]
		dx := state.player_x - enemy.x
		dy := state.player_y - enemy.y
		dist_sq := dx * dx + dy * dy

		// if adjacent to player, attack
		if abs(dx) <= 1 && abs(dy) <= 1 {
			damage := def.attack - state.player_defense
			if damage < 1 do damage = 1
			state.player_hp -= damage
			state.player_last_attack = 0
			if state.player_hp <= 0 {
				state.player_hp = 0
				state.status_message = fmt.tprintf(
					"%s attacks you for %d damage. You died!",
					def.name,
					damage,
				)
				state.is_running = false
				return
			} else {
				state.status_message = fmt.tprintf(
					"%s attacks you for %d damage!",
					def.name,
					damage,
				)
			}
			continue
		}

		// check if enemy can see or is near player
		max_dist := def.fov_range
		if dist_sq <= max_dist * max_dist {
			// step towards player
			step_x := 0
			step_y := 0
			if dx > 0 do step_x = 1
			else if dx < 0 do step_x = -1

			if dy > 0 do step_y = 1
			else if dy < 0 do step_y = -1

			// try preferred axis first
			if abs(dx) >= abs(dy) {
				if step_x != 0 && !is_tile_blocked(state, enemy.x + step_x, enemy.y) {
					enemy.x += step_x
				} else if step_y != 0 && !is_tile_blocked(state, enemy.x, enemy.y + step_y) {
					enemy.y += step_y
				}
			} else {
				if step_y != 0 && !is_tile_blocked(state, enemy.x, enemy.y + step_y) {
					enemy.y += step_y
				} else if step_x != 0 && !is_tile_blocked(state, enemy.x + step_x, enemy.y) {
					enemy.x += step_x
				}
			}
		}
	}
}

player_regen :: proc(state: ^Game_State) {
	if state.player_hp < state.player_max_hp {
		state.player_hp += 1
	}
}

check_regen :: proc(state: ^Game_State) {
	if state.player_last_attack >= 10 {
		player_regen(state)
	}
}

step_turn :: proc(state: ^Game_State, dx: int, dy: int) {
	new_x := state.player_x + dx
	new_y := state.player_y + dy

	state.player_last_attack += 1

	// 1. check for bump attack on enemy
	target_enemy := find_enemy_at(&state.dungeon, new_x, new_y)
	if target_enemy != nil {
		player_attack(state, target_enemy)
		state.player_last_attack = 0
		state.turn_count += 1
		step_enemy_turns(state)
		state.floors[state.depth] = state.dungeon
		return
	}

	target_tile := dungeon_get_tile(&state.dungeon, new_x, new_y)

	// 2. if moving into a closed door, open it (bump to open)
	if target_tile.type == .Door_Closed {
		dungeon_set_tile(&state.dungeon, new_x, new_y, .Door_Open)
		compute_fov(&state.dungeon, state.player_x, state.player_y)
		state.turn_count += 1
		state.status_message = "You open the door."
		step_enemy_turns(state)
		state.floors[state.depth] = state.dungeon
		return
	}

	// 3. move if walkable
	if target_tile.walkable {
		state.player_x = new_x
		state.player_y = new_y
		compute_fov(&state.dungeon, state.player_x, state.player_y)
		state.turn_count += 1

		#partial switch target_tile.type {
		case .Stairs_Down:
			state.status_message = "There is a staircase leading down here (press > or . to descend)."
		case .Stairs_Up:
			state.status_message = "There is a staircase leading up here (press < or , to ascend)."
		case:
			state.status_message = ""
		}

		check_regen(state)
		step_enemy_turns(state)
		state.floors[state.depth] = state.dungeon
	}
}

// descend stairs to the next level down
go_down_stairs :: proc(state: ^Game_State) -> bool {
	current_tile := dungeon_get_tile(&state.dungeon, state.player_x, state.player_y)
	if current_tile.type != .Stairs_Down {
		state.status_message = "You can't go down here. (Find a > staircase)"
		return false
	}

	// save current floor modifications
	state.floors[state.depth] = state.dungeon

	target_depth := state.depth + 1
	if !(target_depth in state.floors) {
		cfg := default_dungeon_config(u64(target_depth * 1000 + 42), target_depth)
		state.floors[target_depth] = generate_dungeon(cfg)
	}

	state.depth = target_depth
	state.dungeon = state.floors[target_depth]

	// player arrives at the stairs leading up on the new floor
	state.player_x = state.dungeon.stairs_up_pos.x
	state.player_y = state.dungeon.stairs_up_pos.y

	compute_fov(&state.dungeon, state.player_x, state.player_y)
	state.floors[state.depth] = state.dungeon

	state.turn_count += 1
	state.status_message = "You descend deeper into the dungeon."
	return true
}

// ascend stairs to the previous level up
go_up_stairs :: proc(state: ^Game_State) -> bool {
	current_tile := dungeon_get_tile(&state.dungeon, state.player_x, state.player_y)
	if current_tile.type != .Stairs_Up {
		state.status_message = "You can't go up here. (Find a < staircase)"
		return false
	}

	if state.depth <= 1 {
		state.status_message = "You are already at the dungeon entrance! You cannot leave yet."
		return false
	}

	// save current floor modifications
	state.floors[state.depth] = state.dungeon

	target_depth := state.depth - 1
	state.depth = target_depth
	state.dungeon = state.floors[target_depth]

	// player arrives at the stairs leading down on the higher floor
	state.player_x = state.dungeon.stairs_down_pos.x
	state.player_y = state.dungeon.stairs_down_pos.y

	compute_fov(&state.dungeon, state.player_x, state.player_y)
	state.floors[state.depth] = state.dungeon

	state.turn_count += 1
	state.status_message = "You climb back up the stairs."
	return true
}
