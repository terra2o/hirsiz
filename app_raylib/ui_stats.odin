package main

import "../core"
import "core:math"
import rl "vendor:raylib"

draw_stats_panel :: proc(rect: rl.Rectangle, state: ^core.Game_State) {
	// panel background & border
	rl.DrawRectangleRec(rect, rl.Color{18, 18, 26, 255})
	rl.DrawRectangleLinesEx(rect, 1.0, rl.Color{65, 65, 80, 255})

	pad_x := rect.x + math.clamp(rect.width * 0.05, 8.0, 16.0)
	inner_w := rect.width - 2.0 * math.clamp(rect.width * 0.05, 8.0, 16.0)

	// total vertical distribution: 8 logical units/lines
	// hp bar + hp text + attack + defense + gear bonus + divider + depth + turns/gold
	line_step := rect.height / 9.2
	cur_y := rect.y + line_step * 0.5

	font_stat := math.clamp(i32(line_step * 0.72), 8, 16)
	font_small := math.clamp(i32(line_step * 0.64), 7, 14)

	// hp bar
	hp_ratio: f32 = 0
	if state.player_max_hp > 0 {
		hp_ratio = f32(state.player_hp) / f32(state.player_max_hp)
	}
	if hp_ratio < 0 do hp_ratio = 0
	if hp_ratio > 1 do hp_ratio = 1

	bar_h := math.clamp(line_step * 0.85, 10.0, 22.0)
	bar_bg := rl.Rectangle{pad_x, cur_y, inner_w, bar_h}
	rl.DrawRectangleRec(bar_bg, rl.Color{45, 20, 20, 255})

	fill_w := inner_w * hp_ratio
	fill_col := rl.Color{60, 180, 75, 255}
	if hp_ratio < 0.25 {
		fill_col = rl.Color{220, 40, 40, 255}
	} else if hp_ratio < 0.55 {
		fill_col = rl.Color{220, 160, 40, 255}
	}
	rl.DrawRectangleRec(rl.Rectangle{pad_x, cur_y, fill_w, bar_h}, fill_col)
	rl.DrawRectangleLinesEx(bar_bg, 1, rl.Color{80, 80, 95, 255})

	hp_text := rl.TextFormat("HP %d/%d", state.player_hp, state.player_max_hp)
	hp_font_size := math.clamp(i32(bar_h * 0.7), 8, 14)
	th := rl.MeasureText(hp_text, hp_font_size)
	rl.DrawText(
		hp_text,
		i32(pad_x + (inner_w - f32(th)) / 2),
		i32(cur_y + (bar_h - f32(hp_font_size)) / 2),
		hp_font_size,
		rl.WHITE,
	)
	cur_y += line_step * 1.25

	// attack & defense
	stat_line_1 := rl.TextFormat("Attack:  %d", state.player_attack)
	rl.DrawText(stat_line_1, i32(pad_x), i32(cur_y), font_stat, rl.RAYWHITE)
	cur_y += line_step

	stat_line_2 := rl.TextFormat("Defense: %d", state.player_defense)
	rl.DrawText(stat_line_2, i32(pad_x), i32(cur_y), font_stat, rl.RAYWHITE)
	cur_y += line_step

	// equipment bonus summary
	att_b, def_b, hp_b := core.inventory_stat_bonuses(&state.player_inventory)
	bonus_text := rl.TextFormat("Gear: +%dA +%dD +%dHP", att_b, def_b, hp_b)
	rl.DrawText(bonus_text, i32(pad_x), i32(cur_y), font_small, rl.Color{130, 210, 150, 255})
	cur_y += line_step

	// divider
	divider_y := cur_y + line_step * 0.1
	rl.DrawLine(
		i32(pad_x),
		i32(divider_y),
		i32(pad_x + inner_w),
		i32(divider_y),
		rl.Color{50, 50, 65, 255},
	)
	cur_y += line_step * 0.4

	// dungeon progress & turns
	dungeon_info := rl.TextFormat("Depth: %d", state.depth)
	rl.DrawText(dungeon_info, i32(pad_x), i32(cur_y), font_small, rl.Color{160, 190, 230, 255})
	cur_y += line_step

	turns_info := rl.TextFormat("Turns: %d", state.turn_count)
	rl.DrawText(turns_info, i32(pad_x), i32(cur_y), font_small, rl.Color{150, 150, 165, 255})
	cur_y += line_step

	gold_info := rl.TextFormat("Gold:  %d", state.player_gold)
	rl.DrawText(gold_info, i32(pad_x), i32(cur_y), font_small, rl.Color{230, 200, 70, 255})
}
