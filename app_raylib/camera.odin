package main

import rl "vendor:raylib"

init_camera :: proc(target_x, target_y: f32) -> rl.Camera2D {
	camera: rl.Camera2D
	camera.target = {target_x, target_y}
	camera.offset = {1280.0 / 2.0, 720.0 / 2.0}
	camera.rotation = 0.0
	camera.zoom = 1.0
	return camera
}
