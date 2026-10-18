package core

Game_State :: struct {
	player_x:       int,
	player_y:       int,
	depth:          int, // current dungeon floor level (starts at 1)
	turn_count:     int,
	is_running:     bool,
	status_message: string,
	dungeon:        Dungeon,
	floors:         map[int]Dungeon,
}

init_game :: proc(seed: u64 = 0) -> Game_State {
	floors := make(map[int]Dungeon)

	depth := 1
	cfg := default_dungeon_config(seed != 0 ? seed + u64(depth) : 0)
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

step_turn :: proc(state: ^Game_State, dx: int, dy: int) {
	new_x := state.player_x + dx
	new_y := state.player_y + dy

	target_tile := dungeon_get_tile(&state.dungeon, new_x, new_y)

	// if moving into a closed door, open it (bump to open)
	if target_tile.type == .Door_Closed {
		dungeon_set_tile(&state.dungeon, new_x, new_y, .Door_Open)
		compute_fov(&state.dungeon, state.player_x, state.player_y)
		state.floors[state.depth] = state.dungeon
		state.turn_count += 1
		state.status_message = "You open the door."
		return
	}

	// move if walkable
	if target_tile.walkable {
		state.player_x = new_x
		state.player_y = new_y
		compute_fov(&state.dungeon, state.player_x, state.player_y)
		state.floors[state.depth] = state.dungeon
		state.turn_count += 1

		#partial switch target_tile.type {
		case .Stairs_Down:
			state.status_message = "There is a staircase leading down here (press > or . to descend)."
		case .Stairs_Up:
			state.status_message = "There is a staircase leading up here (press < or , to ascend)."
		case:
			state.status_message = ""
		}
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
		cfg := default_dungeon_config(u64(target_depth * 1000 + 42))
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
