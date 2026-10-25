package main

import "../core"
import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

Stats_Panel_Action :: enum {
	None,
	Cast_Spell,
	Open_Menu,
	Open_Help,
}

draw_stats_panel :: proc(rect: rl.Rectangle, state: ^core.Game_State) -> Stats_Panel_Action {
	panel_action: Stats_Panel_Action = .None

	// panel background & border
	rl.DrawRectangleRec(rect, rl.Color{18, 18, 26, 255})
	rl.DrawRectangleLinesEx(rect, 1.0, rl.Color{65, 65, 80, 255})

	pad_x := rect.x + math.clamp(rect.width * 0.045, 8.0, 14.0)
	inner_w := rect.width - 2.0 * math.clamp(rect.width * 0.045, 8.0, 14.0)

	line_step := rect.height / 10.2
	cur_y := rect.y + line_step * 0.28

	font_title := math.clamp(i32(line_step * 0.72), 11, 22)
	font_stat := math.clamp(i32(line_step * 0.68), 10, 20)
	font_small := math.clamp(i32(line_step * 0.60), 9, 18)

	// character name & species/background header
	p_name := core.character_name_str(&state.player_name, state.player_name_len)
	sp_def := core.SPECIES_DEFS[state.player_species]
	bg_def := core.BACKGROUND_DEFS[state.player_background]
	title_str := fmt.tprintf("%s (%s%s)", p_name, sp_def.abbrev, bg_def.abbrev)
	title_cstr := strings.clone_to_cstring(title_str, context.temp_allocator)
	draw_text_bold(title_cstr, i32(pad_x), i32(cur_y), font_title, rl.GOLD)

	sub_str := fmt.tprintf("%s %s", sp_def.name, bg_def.name)
	sub_cstr := strings.clone_to_cstring(sub_str, context.temp_allocator)
	cur_y += line_step * 0.80
	draw_text(sub_cstr, i32(pad_x), i32(cur_y), font_small, rl.Color{175, 185, 210, 255})
	cur_y += line_step * 0.88

	// hp bar
	hp_ratio: f32 = 0
	if state.player_max_hp > 0 {
		hp_ratio = clamp(f32(state.player_hp) / f32(state.player_max_hp), 0, 1)
	}

	bar_h := math.clamp(line_step * 0.82, 12.0, 26.0)
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
	bar_font := math.clamp(i32(bar_h * 0.72), 10, 20)
	th := measure_text_bold(hp_text, bar_font)
	draw_text_bold(
		hp_text,
		i32(pad_x + (inner_w - f32(th)) / 2),
		i32(cur_y + (bar_h - f32(bar_font)) / 2),
		bar_font,
		rl.WHITE,
	)
	cur_y += line_step * 1.02

	// mp bar (or djinni essence bar)
	mp_bg := rl.Rectangle{pad_x, cur_y, inner_w, bar_h}
	rl.DrawRectangleRec(mp_bg, rl.Color{18, 24, 48, 255})
	if state.player_species == .Djinni {
		rl.DrawRectangleRec(rl.Rectangle{pad_x, cur_y, inner_w * hp_ratio, bar_h}, rl.Color{170, 90, 210, 255})
		rl.DrawRectangleLinesEx(mp_bg, 1, rl.Color{80, 80, 105, 255})
		dj_text: cstring = "MP: Essence (Uses HP)"
		djw := measure_text_bold(dj_text, bar_font)
		draw_text_bold(
			dj_text,
			i32(pad_x + (inner_w - f32(djw)) / 2),
			i32(cur_y + (bar_h - f32(bar_font)) / 2),
			bar_font,
			rl.WHITE,
		)
	} else {
		mp_ratio: f32 = 0
		if state.player_max_mp > 0 {
			mp_ratio = clamp(f32(state.player_mp) / f32(state.player_max_mp), 0, 1)
		}
		rl.DrawRectangleRec(rl.Rectangle{pad_x, cur_y, inner_w * mp_ratio, bar_h}, rl.Color{55, 115, 225, 255})
		rl.DrawRectangleLinesEx(mp_bg, 1, rl.Color{80, 80, 105, 255})
		mp_text := rl.TextFormat("MP %d/%d", state.player_mp, state.player_max_mp)
		mpw := measure_text_bold(mp_text, bar_font)
		draw_text_bold(
			mp_text,
			i32(pad_x + (inner_w - f32(mpw)) / 2),
			i32(cur_y + (bar_h - f32(bar_font)) / 2),
			bar_font,
			rl.WHITE,
		)
	}
	cur_y += line_step * 1.08

	// attributes line: Str / Int / Dex
	attr_line := rl.TextFormat("Str: %-2d  Int: %-2d  Dex: %-2d", state.player_str, state.player_int, state.player_dex)
	draw_text_bold(attr_line, i32(pad_x), i32(cur_y), font_stat, rl.Color{220, 225, 240, 255})
	cur_y += line_step * 0.92

	// combat stats line: Att / Def (+ Berserk status)
	if state.berserk_turns > 0 {
		att_line := rl.TextFormat("Att: %-2d  Def: %-2d [BERSERK %d]", state.player_attack, state.player_defense, state.berserk_turns)
		draw_text_bold(att_line, i32(pad_x), i32(cur_y), font_stat, rl.Color{255, 105, 95, 255})
	} else {
		att_line := rl.TextFormat("Att: %-2d  Def: %-2d", state.player_attack, state.player_defense)
		draw_text(att_line, i32(pad_x), i32(cur_y), font_stat, rl.RAYWHITE)
	}
	cur_y += line_step * 0.95

	// active spell selector / cast button
	spell_rect := rl.Rectangle{pad_x, cur_y, inner_w, bar_h * 1.05}
	if state.spell_count > 0 {
		if state.selected_spell >= state.spell_count {
			state.selected_spell = 0
		}
		sp_kind := state.known_spells[state.selected_spell]
		sp_d := core.SPELL_DEFS[sp_kind]
		cost_unit := state.player_species == .Djinni ? "HP" : "MP"
		sp_label := fmt.tprintf(
			"[z] %s (%d%s) [%d/%d]",
			sp_d.name,
			sp_d.mp_cost,
			cost_unit,
			state.selected_spell + 1,
			state.spell_count,
		)
		sp_cstr := strings.clone_to_cstring(sp_label, context.temp_allocator)

		mouse_pos := rl.GetMousePosition()
		hovered := rl.CheckCollisionPointRec(mouse_pos, spell_rect)
		bg_c := hovered ? rl.Color{42, 36, 68, 255} : rl.Color{28, 24, 46, 255}
		border_c := hovered ? rl.GOLD : rl.Color{95, 85, 145, 255}
		rl.DrawRectangleRec(spell_rect, bg_c)
		rl.DrawRectangleLinesEx(spell_rect, 1, border_c)

		draw_text_bold(
			sp_cstr,
			i32(pad_x + 6),
			i32(cur_y + (spell_rect.height - f32(font_small)) / 2),
			font_small,
			rl.Color{205, 185, 255, 255},
		)

		if hovered {
			if rl.IsMouseButtonPressed(.LEFT) {
				panel_action = .Cast_Spell
			} else if rl.IsMouseButtonPressed(.RIGHT) {
				state.selected_spell = (state.selected_spell + 1) % state.spell_count
			}
		}
	} else {
		rl.DrawRectangleRec(spell_rect, rl.Color{22, 22, 30, 255})
		rl.DrawRectangleLinesEx(spell_rect, 1, rl.Color{45, 45, 58, 255})
		draw_text(
			"Spells: None ([?] Help)",
			i32(pad_x + 6),
			i32(cur_y + (spell_rect.height - f32(font_small)) / 2),
			font_small,
			rl.Color{105, 105, 120, 255},
		)
	}
	cur_y += line_step * 1.18

	// divider
	rl.DrawLine(
		i32(pad_x),
		i32(cur_y),
		i32(pad_x + inner_w),
		i32(cur_y),
		rl.Color{50, 50, 65, 255},
	)
	cur_y += line_step * 0.22

	// dungeon progress & turns & gold
	d_line := rl.TextFormat("D:%-2d  Turns: %-4d  Gold: %d", state.depth, state.turn_count, state.player_gold)
	draw_text(d_line, i32(pad_x), i32(cur_y), font_small, rl.Color{230, 200, 70, 255})
	cur_y += line_step * 0.80

	// clickable menu & help buttons
	btn_gap: f32 = 6.0
	btn_w := (inner_w - btn_gap) / 2.0
	btn_h := math.clamp(line_step * 0.78, 16.0, 24.0)
	if draw_button(rl.Rectangle{pad_x, cur_y, btn_w, btn_h}, "[m / Bksp] Menu", true, font_small) {
		panel_action = .Open_Menu
	}
	if draw_button(rl.Rectangle{pad_x + btn_w + btn_gap, cur_y, btn_w, btn_h}, "[?] Manual", true, font_small) {
		panel_action = .Open_Help
	}

	return panel_action
}
