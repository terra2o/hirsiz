package main

import "../core"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

draw_event_log_box :: proc(rect: rl.Rectangle, state: ^core.Game_State) {
	rl.DrawRectangleRec(rect, rl.Color{14, 14, 20, 245})
	rl.DrawRectangleLinesEx(rect, 1.0, rl.Color{55, 55, 70, 255})

	count := state.message_count
	if count == 0 {
		return
	}

	// reserve 8px total vertical padding and 3px gap per line so 3 lines always fit
	usable_h := rect.height - 8.0
	font_size := math.clamp(i32((usable_h / 3.0) - 3.0), 11, 22)
	line_h := f32(font_size + 3)

	pad_top := max(4.0, (rect.height - 3.0 * line_h) / 2.0)

	lines_to_show := min(count, 3)
	start_y := rect.y + pad_top

	for i in 0 ..< lines_to_show {
		msg_idx := count - lines_to_show + i
		msg := state.message_history[msg_idx]
		msg_cstr := strings.clone_to_cstring(msg, context.temp_allocator)

		col: rl.Color
		if i == lines_to_show - 1 {
			col = rl.RAYWHITE
		} else if i == lines_to_show - 2 {
			col = rl.Color{170, 175, 190, 220}
		} else {
			col = rl.Color{120, 125, 140, 160}
		}

		draw_text(msg_cstr, i32(rect.x + 10), i32(start_y + f32(i) * line_h), font_size, col)
	}
}
