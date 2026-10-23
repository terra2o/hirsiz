package main

import "../core"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

draw_event_log_box :: proc(rect: rl.Rectangle, state: ^core.Game_State) {
	// background and border
	rl.DrawRectangleRec(rect, rl.Color{14, 14, 20, 245})
	rl.DrawRectangleLinesEx(rect, 1.0, rl.Color{55, 55, 70, 255})

	count := state.message_count
	if count == 0 {
		return
	}

	// dynamic font size and line height based on box height
	font_size := math.clamp(i32(rect.height * 0.26), 9, 16)
	line_h := f32(font_size + 4)
	pad_top := (rect.height - f32(3) * line_h) / 2.0
	if pad_top < 4.0 {
		pad_top = 4.0
	}

	// determine how many lines can fit
	max_lines := int(rect.height / line_h)
	if max_lines < 1 do max_lines = 1
	lines_to_show := min(count, min(max_lines, 3))
	start_y := rect.y + pad_top

	for i in 0 ..< lines_to_show {
		msg_idx := count - lines_to_show + i
		msg := state.message_history[msg_idx]
		msg_cstr := strings.clone_to_cstring(msg, context.temp_allocator)

		// fade older messages, latest is bright
		col: rl.Color
		if i == lines_to_show - 1 {
			col = rl.RAYWHITE
		} else if i == lines_to_show - 2 {
			col = rl.Color{170, 175, 190, 220}
		} else {
			col = rl.Color{120, 125, 140, 160}
		}

		rl.DrawText(msg_cstr, i32(rect.x + 10), i32(start_y + f32(i) * line_h), font_size, col)
	}
}
