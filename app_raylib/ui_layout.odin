package main

import "core:math"
import rl "vendor:raylib"

compute_ui_layout :: proc(screen_w, screen_h: i32) -> UI_Layout {
	layout: UI_Layout
	layout.screen_w = screen_w
	layout.screen_h = screen_h

	// baseline reference is 720p
	layout.scale = math.clamp(f32(screen_h) / 720.0, 0.45, 2.0)

	// right pane takes between 20% and 26% of screen width, clamped between 160 and 420 px
	target_right_w := f32(screen_w) * 0.24
	right_w := math.clamp(target_right_w, 180.0, 420.0)
	if right_w > f32(screen_w) * 0.45 {
		right_w = f32(screen_w) * 0.45
	}

	left_w := f32(screen_w) - right_w

	// top event box takes between 8% and 12% of screen height
	event_h := math.clamp(f32(screen_h) * 0.09, 36.0, 80.0)

	layout.event_box = rl.Rectangle {
		x      = 0,
		y      = 0,
		width  = left_w,
		height = event_h,
	}

	layout.game_view = rl.Rectangle {
		x      = 0,
		y      = event_h,
		width  = left_w,
		height = f32(screen_h) - event_h,
	}

	layout.right_panel = rl.Rectangle {
		x      = left_w,
		y      = 0,
		width  = right_w,
		height = f32(screen_h),
	}

	// stats panel takes top ~38% of right pane, leaving 62% for inventory
	stats_h := f32(screen_h) * 0.38
	stats_h = math.clamp(stats_h, 140.0, f32(screen_h) * 0.46)

	layout.stats_panel = rl.Rectangle {
		x      = left_w,
		y      = 0,
		width  = right_w,
		height = stats_h,
	}

	layout.inventory_panel = rl.Rectangle {
		x      = left_w,
		y      = stats_h,
		width  = right_w,
		height = f32(screen_h) - stats_h,
	}

	return layout
}
