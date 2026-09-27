package main

import "../core"
import rl "vendor:raylib"

main :: proc() {
	rl.InitWindow(1280, 720, "hirsiz")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	state := core.init_game()
	tile_size :: 32
	
	camera := init_camera(f32(state.player_x * tile_size), f32(state.player_y * tile_size))

	hold_timer: f32 = 0
	first_delay :: 0.3
	repeat_delay :: 0.05

	held_dx: int
	held_dy: int

	for !rl.WindowShouldClose() && state.is_running {
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
			core.step_turn(&state, dx, dy)
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		px := i32(state.player_x) * tile_size
		py := i32(state.player_y) * tile_size
		
		camera.target = {f32(px), f32(py)}

		rl.BeginMode2D(camera)
		rl.DrawRectangle(px, py, tile_size, tile_size, rl.RED)
		rl.EndMode2D()
		
		rl.EndDrawing()


	}
}
