package core

Game_State :: struct {
	player_x:   int,
	player_y:   int,
	turn_count: int,
	is_running: bool,
}

init_game :: proc() -> Game_State {
	return Game_State{
		player_x   = 10,
		player_y   = 10,
		turn_count = 0,
		is_running = true,
	}
}

step_turn :: proc(state: ^Game_State, dx: int, dy: int) {
	state.player_x += dx
	state.player_y += dy
	state.turn_count += 1
}
