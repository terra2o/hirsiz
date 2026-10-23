package core

import "core:crypto"
import "core:fmt"

floor_seed :: proc(base_seed: u64, depth: int) -> u64 {
	z := base_seed ~ (u64(depth) * 0x9e3779b97f4a7c15)
	z = (z ~ (z >> 30)) * 0xbf58476d1ce4e5b9
	z = (z ~ (z >> 27)) * 0x94d049bb133111eb
	res := z ~ (z >> 31)
	if res == 0 do res = 1
	return res
}

generate_random_seed :: proc() -> u64 {
	buf: [8]u8
	crypto.rand_bytes(buf[:])
	token := (^u64)(&buf[0])^
	if token == 0 do token = 1337
	return token
}

Game_State :: struct {
	seed:               u64,
	player_x:           int,
	player_y:           int,
	player_hp:          int,
	player_max_hp:      int,
	player_base_max_hp: int,
	player_gold:        u32,
	player_base_attack: int,
	player_base_def:    int,
	player_attack:      int,
	player_defense:     int,
	player_last_attack: int,
	player_inventory:   Inventory,
	depth:              int,
	turn_count:         int,
	is_running:         bool,
	status_message:     string,
	message_history:    [8]string,
	message_count:      int,
	dungeon:            Dungeon,
	floors:             map[int]Dungeon,
}

push_message :: proc(state: ^Game_State, msg: string) {
	if len(msg) == 0 do return
	state.status_message = msg

	// shift messages if buffer is full
	if state.message_count < len(state.message_history) {
		state.message_history[state.message_count] = msg
		state.message_count += 1
	} else {
		for i in 0 ..< len(state.message_history) - 1 {
			state.message_history[i] = state.message_history[i + 1]
		}
		state.message_history[len(state.message_history) - 1] = msg
	}
}

recompute_player_stats :: proc(state: ^Game_State) {
	att_b, def_b, hp_b := inventory_stat_bonuses(&state.player_inventory)
	state.player_attack = state.player_base_attack + att_b
	state.player_defense = state.player_base_def + def_b

	old_max := state.player_max_hp
	state.player_max_hp = state.player_base_max_hp + hp_b
	if state.player_max_hp > old_max {
		state.player_hp += (state.player_max_hp - old_max)
	}
	if state.player_hp > state.player_max_hp {
		state.player_hp = state.player_max_hp
	}
}

get_enemy_stats :: proc(enemy: ^Enemy) -> (attack: int, defense: int) {
	def := ENEMY_DEFS[enemy.kind]
	att_b, def_b, _ := inventory_stat_bonuses(&enemy.inventory)
	return def.attack + att_b, def.defense + def_b
}

init_game :: proc(seed: u64 = 0) -> Game_State {
	actual_seed := seed
	if actual_seed == 0 {
		actual_seed = generate_random_seed()
	}

	floors := make(map[int]Dungeon)

	depth := 1
	cfg := default_dungeon_config(floor_seed(actual_seed, depth), depth)
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

	welcome_msg := "Welcome to hirsiz! Press < or > to use stairs."
	state := Game_State {
		seed               = actual_seed,
		player_x           = spawn_x,
		player_y           = spawn_y,
		player_hp          = 20,
		player_max_hp      = 20,
		player_base_max_hp = 20,
		player_gold        = 0,
		player_base_attack = 5,
		player_base_def    = 1,
		player_attack      = 5,
		player_defense     = 1,
		player_last_attack = 0,
		depth              = depth,
		turn_count         = 0,
		is_running         = true,
		status_message     = welcome_msg,
		dungeon            = dung,
		floors             = floors,
	}
	push_message(&state, welcome_msg)

	force_equip(&state.player_inventory, .Rusty_Dagger)
	force_equip(&state.player_inventory, .Cloth_Tunic)
	force_equip(&state.player_inventory, .Leather_Boots)
	inventory_add(&state.player_inventory, .Health_Potion)
	recompute_player_stats(&state)

	return state
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
	_, enemy_def := get_enemy_stats(enemy)
	damage := state.player_attack - enemy_def
	if damage < 1 do damage = 1

	enemy.hp -= damage
	if enemy.hp <= 0 {
		enemy.is_alive = false

		loot_item: Item_Kind = .None
		for slot in Equipment_Slot {
			if enemy.inventory.equipment[slot] != .None {
				loot_item = enemy.inventory.equipment[slot]
				break
			}
		}
		if loot_item == .None && enemy.inventory.item_count > 0 {
			for it in enemy.inventory.items {
				if it != .None {
					loot_item = it
					break
				}
			}
		}

		if loot_item != .None && inventory_add(&state.player_inventory, loot_item) {
			item_d := ITEM_DEFS[loot_item]
			push_message(
				state,
				fmt.tprintf("You kill %s! Found %s and took it.", def.name, item_d.name),
			)
		} else {
			push_message(
				state,
				fmt.tprintf("You attack %s for %d damage and kill it!", def.name, damage),
			)
		}
	} else {
		push_message(
			state,
			fmt.tprintf("You attack %s for %d damage. (HP: %d/%d)", def.name, damage, enemy.hp, enemy.max_hp),
		)
	}
}

step_enemy_turns :: proc(state: ^Game_State) {
	d := &state.dungeon
	for &enemy in d.enemies {
		if !enemy.is_alive do continue

		def := ENEMY_DEFS[enemy.kind]
		enemy_att, _ := get_enemy_stats(&enemy)
		dx := state.player_x - enemy.x
		dy := state.player_y - enemy.y
		dist_sq := dx * dx + dy * dy

		if abs(dx) <= 1 && abs(dy) <= 1 {
			damage := enemy_att - state.player_defense
			if damage < 1 do damage = 1
			state.player_hp -= damage
			state.player_last_attack = 0
			if state.player_hp <= 0 {
				state.player_hp = 0
				push_message(
					state,
					fmt.tprintf("%s attacks you for %d damage. You died!", def.name, damage),
				)
				state.is_running = false
				return
			} else {
				push_message(
					state,
					fmt.tprintf("%s attacks you for %d damage!", def.name, damage),
				)
			}
			continue
		}

		max_dist := def.fov_range
		if dist_sq <= max_dist * max_dist {
			step_x := 0
			step_y := 0
			if dx > 0 do step_x = 1
			else if dx < 0 do step_x = -1

			if dy > 0 do step_y = 1
			else if dy < 0 do step_y = -1

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

	if target_tile.type == .Door_Closed {
		dungeon_set_tile(&state.dungeon, new_x, new_y, .Door_Open)
		compute_fov(&state.dungeon, state.player_x, state.player_y)
		state.turn_count += 1
		push_message(state, "You open the door.")
		step_enemy_turns(state)
		state.floors[state.depth] = state.dungeon
		return
	}

	if target_tile.walkable {
		state.player_x = new_x
		state.player_y = new_y
		compute_fov(&state.dungeon, state.player_x, state.player_y)
		state.turn_count += 1

		#partial switch target_tile.type {
		case .Stairs_Down:
			push_message(state, "There is a staircase leading down here (press > or . to descend).")
		case .Stairs_Up:
			push_message(state, "There is a staircase leading up here (press < or , to ascend).")
		}

		check_regen(state)
		step_enemy_turns(state)
		state.floors[state.depth] = state.dungeon
	}
}

// descend stairs to next level
go_down_stairs :: proc(state: ^Game_State) -> bool {
	current_tile := dungeon_get_tile(&state.dungeon, state.player_x, state.player_y)
	if current_tile.type != .Stairs_Down {
		push_message(state, "You can't go down here. (Find a > staircase)")
		return false
	}

	state.floors[state.depth] = state.dungeon

	target_depth := state.depth + 1
	if !(target_depth in state.floors) {
		cfg := default_dungeon_config(floor_seed(state.seed, target_depth), target_depth)
		state.floors[target_depth] = generate_dungeon(cfg)
	}

	state.depth = target_depth
	state.dungeon = state.floors[target_depth]

	state.player_x = state.dungeon.stairs_up_pos.x
	state.player_y = state.dungeon.stairs_up_pos.y

	compute_fov(&state.dungeon, state.player_x, state.player_y)
	state.floors[state.depth] = state.dungeon

	state.turn_count += 1
	push_message(state, "You descend deeper into the dungeon.")
	return true
}

// ascend stairs to previous level
go_up_stairs :: proc(state: ^Game_State) -> bool {
	current_tile := dungeon_get_tile(&state.dungeon, state.player_x, state.player_y)
	if current_tile.type != .Stairs_Up {
		push_message(state, "You can't go up here. (Find a < staircase)")
		return false
	}

	if state.depth <= 1 {
		push_message(state, "You are already at the dungeon entrance! You cannot leave yet.")
		return false
	}

	state.floors[state.depth] = state.dungeon

	target_depth := state.depth - 1
	state.depth = target_depth
	state.dungeon = state.floors[target_depth]

	state.player_x = state.dungeon.stairs_down_pos.x
	state.player_y = state.dungeon.stairs_down_pos.y

	compute_fov(&state.dungeon, state.player_x, state.player_y)
	state.floors[state.depth] = state.dungeon

	state.turn_count += 1
	push_message(state, "You climb back up the stairs.")
	return true
}
