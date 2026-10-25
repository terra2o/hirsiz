package main

import "../core"
import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

// per-frame key queue to catch sub-frame synthetic taps (e.g. caps-lock tap -> esc)
frame_keys: [16]rl.KeyboardKey
frame_key_count: int

poll_frame_keys :: proc() {
	frame_key_count = 0
	for {
		k := rl.GetKeyPressed()
		if k == .KEY_NULL do break
		if frame_key_count < len(frame_keys) {
			frame_keys[frame_key_count] = k
			frame_key_count += 1
		}
	}
}

is_key_pressed :: proc(key: rl.KeyboardKey) -> bool {
	if rl.IsKeyPressed(key) do return true
	for i in 0 ..< frame_key_count {
		if frame_keys[i] == key do return true
	}
	return false
}

is_back_pressed :: proc() -> bool {
	return is_key_pressed(.ESCAPE) || is_key_pressed(.BACKSPACE) || rl.IsMouseButtonPressed(.RIGHT)
}

App_Screen :: enum {
	Main_Menu,
	Char_Select_Species,
	Char_Select_Background,
	Seed_Input,
	High_Scores,
	Controls_Help,
	Playing,
	Game_Over,
}

Menu_Action :: enum {
	None,
	Start_New_Game,
	Continue_Saved_Game,
	Quit_App,
}

Menu_State :: struct {
	screen:         App_Screen,
	return_screen:  App_Screen,
	char_cfg:       core.Character_Config,
	editing_name:   bool,
	main_cursor:    int,
	species_cursor: core.Species,
	bg_cursor:      core.Background,
	seed_buf:       [20]u8,
	seed_len:       int,
	custom_seed_on: bool,
	has_save:       bool,
	saved_preview:  core.Save_Data,
	last_morgue:    core.Morgue_Entry,
	morgue_file:    core.Morgue_File,
}

init_menu_state :: proc() -> Menu_State {
	m: Menu_State
	m.screen = .Main_Menu
	m.return_screen = .Main_Menu
	m.char_cfg = core.default_character_config()
	core.set_character_name(&m.char_cfg, core.pick_random_name())
	m.species_cursor = .Minotaur
	m.bg_cursor = .Berserker
	refresh_menu_save_preview(&m)
	if m.has_save {
		m.main_cursor = 1 // highlight Continue Saved Game when a save exists
	}
	return m
}

refresh_menu_save_preview :: proc(m: ^Menu_State) {
	m.saved_preview, m.has_save = core.peek_save_game()
	m.morgue_file = core.load_morgue()
}

species_hotkey_rune :: proc(sp: core.Species) -> rune {
	idx := int(sp)
	if idx < 26 {
		return rune('a' + idx)
	}
	return rune('A' + (idx - 26))
}

bg_hotkey_rune :: proc(bg: core.Background) -> rune {
	return rune('a' + int(bg))
}

centered_terminal_rect :: proc(screen_w, screen_h: i32) -> rl.Rectangle {
	w := math.clamp(f32(screen_w) * 0.90, 620.0, 1020.0)
	h := math.clamp(f32(screen_h) * 0.90, 350.0, 680.0)
	return rl.Rectangle {
		x = (f32(screen_w) - w) / 2.0,
		y = (f32(screen_h) - h) / 2.0,
		width = w,
		height = h,
	}
}

draw_terminal_frame :: proc(term: rl.Rectangle, header_title: cstring) {
	rl.DrawRectangleRec(term, rl.Color{14, 14, 21, 255})
	rl.DrawRectangleLinesEx(term, 2.0, rl.Color{85, 78, 60, 255})
	inner := rl.Rectangle{term.x + 4, term.y + 4, term.width - 8, term.height - 8}
	rl.DrawRectangleLinesEx(inner, 1.0, rl.Color{45, 45, 62, 255})

	if len(header_title) > 0 {
		f_size := math.clamp(i32(term.height * 0.032), 14, 22)
		tw := measure_text_bold(header_title, f_size)
		badge_w := f32(tw + 24)
		badge_x := term.x + (term.width - badge_w) / 2.0
		rl.DrawRectangle(
			i32(badge_x),
			i32(term.y),
			i32(badge_w),
			f_size + 6,
			rl.Color{14, 14, 21, 255},
		)
		draw_text_bold(header_title, i32(badge_x + 12), i32(term.y + 2), f_size, rl.GOLD)
	}
}

handle_name_typing :: proc(m: ^Menu_State) {
	for {
		ch := rl.GetCharPressed()
		if ch == 0 do break
		if (ch >= 'a' && ch <= 'z') ||
		   (ch >= 'A' && ch <= 'Z') ||
		   (ch >= '0' && ch <= '9') ||
		   ch == '_' ||
		   ch == '-' {
			if int(m.char_cfg.name_len) < core.MAX_NAME_LEN - 1 {
				m.char_cfg.name[m.char_cfg.name_len] = u8(ch)
				m.char_cfg.name_len += 1
			}
		}
	}
	if is_key_pressed(.BACKSPACE) && m.char_cfg.name_len > 0 {
		m.char_cfg.name_len -= 1
		m.char_cfg.name[m.char_cfg.name_len] = 0
	}
	if is_key_pressed(.TAB) {
		core.set_character_name(&m.char_cfg, core.pick_random_name())
	}
	if is_key_pressed(.ENTER) || is_key_pressed(.ESCAPE) {
		if m.char_cfg.name_len == 0 {
			core.set_character_name(&m.char_cfg, "Adventurer")
		}
		m.editing_name = false
	}
}

update_and_draw_menu :: proc(m: ^Menu_State, screen_w, screen_h: i32) -> Menu_Action {
	#partial switch m.screen {
	case .Main_Menu:
		return draw_main_menu_screen(m, screen_w, screen_h)
	case .Char_Select_Species:
		return draw_species_select_screen(m, screen_w, screen_h)
	case .Char_Select_Background:
		return draw_background_select_screen(m, screen_w, screen_h)
	case .Seed_Input:
		return draw_seed_input_screen(m, screen_w, screen_h)
	case .High_Scores:
		draw_high_scores_screen(m, screen_w, screen_h)
	case .Controls_Help:
		draw_controls_help_screen(m, screen_w, screen_h)
	case .Game_Over:
		draw_game_over_screen(m, screen_w, screen_h)
	}
	return .None
}

draw_main_menu_screen :: proc(m: ^Menu_State, screen_w, screen_h: i32) -> Menu_Action {
	action: Menu_Action = .None
	term := centered_terminal_rect(screen_w, screen_h)
	draw_terminal_frame(term, " H I R S I Z  -  DUNGEON CRAWL ")

	pad_x := term.x + math.clamp(term.width * 0.06, 24.0, 56.0)
	inner_w := term.width - 2.0 * (pad_x - term.x)
	cur_y := term.y + math.clamp(term.height * 0.05, 22.0, 38.0)

	font_banner := math.clamp(i32(term.height * 0.032), 13, 22)
	font_main := math.clamp(i32(term.height * 0.033), 13, 22)
	font_sub := math.clamp(i32(term.height * 0.025), 11, 17)

	// ascii banner
	banner_lines := [?]cstring {
		" _     _           _      ",
		"| |__ (_)_ __ ___ (_)____ ",
		"| '_ \\| | '__/ __|| |_  / ",
		"| | | | | |  \\__ \\| |/ /  ",
		"|_| |_|_|_|  |___/|_/___| ",
	}
	for line in banner_lines {
		lw := measure_text_bold(line, font_banner)
		draw_text_bold(
			line,
			i32(term.x + (term.width - f32(lw)) / 2),
			i32(cur_y),
			font_banner,
			rl.GOLD,
		)
		cur_y += f32(font_banner) + 1
	}

	cur_y += 6
	welcome_cstr: cstring = "Welcome to hirsiz! Select your character and delve into the dungeon."
	ww := measure_text(welcome_cstr, font_sub)
	draw_text(
		welcome_cstr,
		i32(term.x + (term.width - f32(ww)) / 2),
		i32(cur_y),
		font_sub,
		rl.Color{170, 175, 195, 255},
	)
	cur_y += f32(font_sub) * 1.6

	// character name prompt bar
	name_box_h := f32(font_main) * 1.75
	name_box := rl.Rectangle{pad_x, cur_y, inner_w, name_box_h}
	mouse_pos := rl.GetMousePosition()
	name_hovered := rl.CheckCollisionPointRec(mouse_pos, name_box)

	if name_hovered && rl.IsMouseButtonPressed(.LEFT) {
		m.editing_name = true
	}

	rl.DrawRectangleRec(
		name_box,
		m.editing_name ? rl.Color{32, 30, 48, 255} : rl.Color{20, 20, 30, 255},
	)
	rl.DrawRectangleLinesEx(
		name_box,
		1.0,
		m.editing_name ? rl.GOLD : (name_hovered ? rl.Color{120, 130, 165, 255} : rl.Color{55, 58, 75, 255}),
	)

	p_name := core.character_name_str(&m.char_cfg.name, m.char_cfg.name_len)
	name_prompt :=
		m.editing_name ? fmt.tprintf("Enter your name: %s_   (Press Enter to confirm, Tab for random)", p_name) : fmt.tprintf("Character Name:  %s   ([n] Edit Name   [Tab] Random Name)", p_name)
	name_cstr := strings.clone_to_cstring(name_prompt, context.temp_allocator)
	draw_text_bold(
		name_cstr,
		i32(pad_x + 12),
		i32(cur_y + (name_box_h - f32(font_main)) / 2),
		font_main,
		m.editing_name ? rl.GOLD : rl.RAYWHITE,
	)
	cur_y += name_box_h + f32(font_sub) * 0.8

	// saved game summary box (if present)
	save_box_h := f32(font_main) * 2.2
	save_box := rl.Rectangle{pad_x, cur_y, inner_w, save_box_h}
	rl.DrawRectangleRec(
		save_box,
		m.has_save ? rl.Color{20, 32, 28, 255} : rl.Color{18, 18, 25, 255},
	)
	rl.DrawRectangleLinesEx(
		save_box,
		1.0,
		m.has_save ? rl.Color{75, 145, 100, 255} : rl.Color{45, 45, 58, 255},
	)

	if m.has_save {
		sp := core.Species(min(int(m.saved_preview.player.species), core.SPECIES_COUNT - 1))
		bg := core.Background(
			min(int(m.saved_preview.player.background), core.BACKGROUND_COUNT - 1),
		)
		s_name := core.character_name_str(
			&m.saved_preview.player.name,
			m.saved_preview.player.name_len,
		)
		line1 := fmt.tprintf(
			"Active Save: %s the %s %s (%s%s)",
			s_name,
			core.SPECIES_DEFS[sp].name,
			core.BACKGROUND_DEFS[bg].name,
			core.SPECIES_DEFS[sp].abbrev,
			core.BACKGROUND_DEFS[bg].abbrev,
		)
		line2 := fmt.tprintf(
			"Place: D:%d   Turn: %d   HP: %d/%d   MP: %d/%d   Str:%d Int:%d Dex:%d   Gold: %d",
			m.saved_preview.player.dungeon_depth,
			m.saved_preview.header.turn_count,
			m.saved_preview.player.hp,
			m.saved_preview.player.max_hp,
			m.saved_preview.player.mp,
			m.saved_preview.player.max_mp,
			m.saved_preview.player.str,
			m.saved_preview.player.intel,
			m.saved_preview.player.dex,
			m.saved_preview.player.gold,
		)
		l1_cstr := strings.clone_to_cstring(line1, context.temp_allocator)
		l2_cstr := strings.clone_to_cstring(line2, context.temp_allocator)
		draw_text_bold(
			l1_cstr,
			i32(pad_x + 12),
			i32(cur_y + 6),
			font_sub,
			rl.Color{130, 235, 160, 255},
		)
		draw_text(
			l2_cstr,
			i32(pad_x + 12),
			i32(cur_y + 8 + f32(font_sub)),
			font_sub,
			rl.Color{185, 205, 190, 255},
		)
	} else {
		draw_text(
			"No active saved game found on disk.",
			i32(pad_x + 12),
			i32(cur_y + (save_box_h - f32(font_sub)) / 2),
			font_sub,
			rl.Color{105, 105, 125, 255},
		)
	}
	cur_y += save_box_h + f32(font_sub) * 0.9

	// menu options
	Menu_Item :: struct {
		key_char: u8,
		label:    string,
		enabled:  bool,
	}
	items := [6]Menu_Item {
		{'a', "New Dungeon Crawl  -  Choose Species & Background", true},
		{'b', "Continue Saved Game", m.has_save},
		{'c', "Seeded Crawl       -  Play a Specific Dungeon Seed", true},
		{'d', "High Scores & Morgue (Past Characters)", true},
		{'e', "Dungeon Manual & Keybindings (?)", true},
		{'q', "Quit to Desktop", true},
	}

	row_h := math.clamp((term.y + term.height - cur_y - f32(font_sub) * 2.5) / 6.3, 24.0, 40.0)
	for item, idx in items {
		row_rect := rl.Rectangle{pad_x, cur_y + f32(idx) * (row_h + 3), inner_w, row_h}
		hovered := rl.CheckCollisionPointRec(mouse_pos, row_rect)
		if hovered && !m.editing_name {
			m.main_cursor = idx
		}
		is_sel := (!m.editing_name && m.main_cursor == idx)

		bg_col := rl.Color{20, 20, 30, 255}
		border_col := rl.Color{45, 48, 62, 255}
		txt_col := rl.Color{210, 215, 230, 255}

		if !item.enabled {
			bg_col = rl.Color{16, 16, 22, 255}
			txt_col = rl.Color{85, 85, 100, 255}
		} else if is_sel {
			bg_col = rl.Color{42, 46, 68, 255}
			border_col = rl.GOLD
			txt_col = rl.WHITE
		}

		rl.DrawRectangleRec(row_rect, bg_col)
		rl.DrawRectangleLinesEx(row_rect, 1.0, border_col)

		row_str := fmt.tprintf(" [%c]  %s", item.key_char, item.label)
		row_cstr := strings.clone_to_cstring(row_str, context.temp_allocator)
		draw_text_bold(
			row_cstr,
			i32(pad_x + 8),
			i32(row_rect.y + (row_h - f32(font_main)) / 2),
			font_main,
			is_sel && item.enabled ? rl.GOLD : txt_col,
		)

		if hovered && rl.IsMouseButtonPressed(.LEFT) && item.enabled {
			m.editing_name = false
			m.main_cursor = idx
			return trigger_main_menu_index(m, idx)
		}
	}

	// footer hint
	footer_y := term.y + term.height - f32(font_sub) - 10
	footer_cstr: cstring = "[a-e / Enter] Select   [Up/Down] Navigate   [n] Edit Name   [Tab] Random Name   [q] Quit"
	fw := measure_text(footer_cstr, font_sub)
	draw_text(
		footer_cstr,
		i32(term.x + (term.width - f32(fw)) / 2),
		i32(footer_y),
		font_sub,
		rl.Color{130, 135, 155, 255},
	)

	if m.editing_name {
		handle_name_typing(m)
		return .None
	}

	// keyboard navigation when not editing name
	if is_key_pressed(.UP) || is_key_pressed(.K) {
		m.main_cursor = (m.main_cursor - 1 + len(items)) % len(items)
	} else if is_key_pressed(.DOWN) || is_key_pressed(.J) {
		m.main_cursor = (m.main_cursor + 1) % len(items)
	} else if is_key_pressed(.TAB) {
		core.set_character_name(&m.char_cfg, core.pick_random_name())
	} else if is_key_pressed(.N) {
		m.editing_name = true
	} else if is_key_pressed(.ENTER) || is_key_pressed(.SPACE) {
		if items[m.main_cursor].enabled {
			return trigger_main_menu_index(m, m.main_cursor)
		}
	} else if is_key_pressed(.A) {
		return trigger_main_menu_index(m, 0)
	} else if is_key_pressed(.B) && m.has_save {
		return trigger_main_menu_index(m, 1)
	} else if is_key_pressed(.C) {
		return trigger_main_menu_index(m, 2)
	} else if is_key_pressed(.D) {
		return trigger_main_menu_index(m, 3)
	} else if is_key_pressed(.E) ||
	   ((rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)) && is_key_pressed(.SLASH)) {
		return trigger_main_menu_index(m, 4)
	} else if is_key_pressed(.Q) {
		return .Quit_App
	}

	// drain char queue so stray keys don't carry into name editing
	for rl.GetCharPressed() != 0 {}

	return action
}

trigger_main_menu_index :: proc(m: ^Menu_State, idx: int) -> Menu_Action {
	switch idx {
	case 0:
		m.custom_seed_on = false
		m.char_cfg.seed = 0
		m.screen = .Char_Select_Species
	case 1:
		if m.has_save {
			return .Continue_Saved_Game
		}
	case 2:
		m.custom_seed_on = true
		m.seed_len = 0
		m.seed_buf = {}
		m.screen = .Seed_Input
	case 3:
		m.morgue_file = core.load_morgue()
		m.screen = .High_Scores
	case 4:
		m.return_screen = .Main_Menu
		m.screen = .Controls_Help
	case 5:
		return .Quit_App
	}
	return .None
}

draw_species_select_screen :: proc(m: ^Menu_State, screen_w, screen_h: i32) -> Menu_Action {
	term := centered_terminal_rect(screen_w, screen_h)
	draw_terminal_frame(term, " CHARACTER CREATION  —  SELECT SPECIES ")

	pad_x := term.x + math.clamp(term.width * 0.035, 16.0, 32.0)
	inner_w := term.width - 2.0 * (pad_x - term.x)
	cur_y := term.y + math.clamp(term.height * 0.045, 22.0, 34.0)

	font_hdr := math.clamp(i32(term.height * 0.029), 12, 20)
	font_item := math.clamp(i32(term.height * 0.026), 11, 18)
	font_small := math.clamp(i32(term.height * 0.023), 10, 16)

	p_name := core.character_name_str(&m.char_cfg.name, m.char_cfg.name_len)
	seed_tag := m.custom_seed_on ? fmt.tprintf(" [Seed: %d]", m.char_cfg.seed) : ""
	prompt := fmt.tprintf("Welcome, %s! Please select your species:%s", p_name, seed_tag)
	prompt_cstr := strings.clone_to_cstring(prompt, context.temp_allocator)
	draw_text_bold(prompt_cstr, i32(pad_x), i32(cur_y), font_hdr, rl.RAYWHITE)
	cur_y += f32(font_hdr) * 1.45

	// 3 columns: Simple, Intermediate, Advanced
	col_gap: f32 = 12.0
	col_w := (inner_w - col_gap * 2.0) / 3.0
	inspector_h := math.clamp(term.height * 0.25, 110.0, 165.0)
	grid_avail_h := term.height - (cur_y - term.y) - inspector_h - f32(font_small) * 2.2
	row_h := math.clamp(grid_avail_h / 11.5, 18.0, 30.0)

	mouse_pos := rl.GetMousePosition()
	cats := [3]core.Species_Category{.Simple, .Intermediate, .Advanced}

	for cat, col_idx in cats {
		col_x := pad_x + f32(col_idx) * (col_w + col_gap)
		cat_title := core.SPECIES_CATEGORY_NAMES[cat]
		cat_cstr := strings.clone_to_cstring(cat_title, context.temp_allocator)
		draw_text_bold(cat_cstr, i32(col_x + 4), i32(cur_y), font_item, rl.GOLD)
		rl.DrawLine(
			i32(col_x),
			i32(cur_y + f32(font_item) + 2),
			i32(col_x + col_w),
			i32(cur_y + f32(font_item) + 2),
			rl.Color{65, 65, 85, 255},
		)

		row_y := cur_y + f32(font_item) + 6
		for sp in core.Species {
			def := core.SPECIES_DEFS[sp]
			if def.category != cat do continue

			r := rl.Rectangle{col_x, row_y, col_w, row_h}
			hovered := rl.CheckCollisionPointRec(mouse_pos, r)
			if hovered {
				m.species_cursor = sp
			}
			is_sel := (m.species_cursor == sp)

			if is_sel {
				rl.DrawRectangleRec(r, rl.Color{44, 48, 72, 255})
				rl.DrawRectangleLinesEx(r, 1.0, rl.GOLD)
			} else if hovered {
				rl.DrawRectangleRec(r, rl.Color{28, 30, 44, 255})
			}

			hk := species_hotkey_rune(sp)
			label := fmt.tprintf(" %c - %-15s (%s)", hk, def.name, def.abbrev)
			label_cstr := strings.clone_to_cstring(label, context.temp_allocator)
			draw_text(
				label_cstr,
				i32(col_x + 2),
				i32(row_y + (row_h - f32(font_item)) / 2),
				font_item,
				is_sel ? rl.GOLD : rl.Color{210, 215, 230, 255},
			)

			if hovered && rl.IsMouseButtonPressed(.LEFT) {
				m.char_cfg.species = sp
				m.screen = .Char_Select_Background
				for rl.GetCharPressed() != 0 {}
				return .None
			}
			row_y += row_h + 2
		}
	}

	// inspector box at bottom
	insp_y := term.y + term.height - inspector_h - f32(font_small) - 16
	insp_rect := rl.Rectangle{pad_x, insp_y, inner_w, inspector_h}
	rl.DrawRectangleRec(insp_rect, rl.Color{20, 20, 30, 255})
	rl.DrawRectangleLinesEx(insp_rect, 1.0, rl.Color{75, 78, 100, 255})

	sp_def := core.SPECIES_DEFS[m.species_cursor]
	hdr_line := fmt.tprintf(
		"%s (%s)  —  [%s Species]   |   Base Str: %d   Int: %d   Dex: %d   |   HP Mod: %+d%%   MP Mod: %+d",
		sp_def.name,
		sp_def.abbrev,
		core.SPECIES_CATEGORY_NAMES[sp_def.category],
		sp_def.base_str,
		sp_def.base_int,
		sp_def.base_dex,
		sp_def.hp_mod_pct,
		sp_def.mp_mod,
	)
	trait_line := fmt.tprintf("Innate Trait: %s", sp_def.trait_desc)

	hdr_cstr := strings.clone_to_cstring(hdr_line, context.temp_allocator)
	trait_cstr := strings.clone_to_cstring(trait_line, context.temp_allocator)
	desc_cstr := strings.clone_to_cstring(sp_def.desc, context.temp_allocator)

	iy := insp_y + 10
	draw_text_bold(hdr_cstr, i32(pad_x + 12), i32(iy), font_item, rl.GOLD)
	iy += f32(font_item) * 1.45
	draw_text_bold(trait_cstr, i32(pad_x + 12), i32(iy), font_small, rl.Color{135, 220, 165, 255})
	iy += f32(font_small) * 1.45
	draw_text(desc_cstr, i32(pad_x + 12), i32(iy), font_small, rl.Color{185, 190, 210, 255})

	// footer
	footer_y := term.y + term.height - f32(font_small) - 8
	footer_cstr: cstring = "[a-z / A] Pick Species   [Arrows + Enter] Select   [Tab] Random   [Backspace / Esc] Back"
	fw := measure_text(footer_cstr, font_small)
	draw_text(
		footer_cstr,
		i32(term.x + (term.width - f32(fw)) / 2),
		i32(footer_y),
		font_small,
		rl.Color{130, 135, 155, 255},
	)

	if is_back_pressed() {
		m.screen = .Main_Menu
		for rl.GetCharPressed() != 0 {}
		return .None
	}

	// keyboard handling: check character queue for exact a-z / A hotkeys
	for {
		ch := rl.GetCharPressed()
		if ch == 0 do break
		if ch >= 'a' && ch <= 'z' {
			idx := int(ch - 'a')
			if idx >= 0 && idx < core.SPECIES_COUNT {
				m.species_cursor = core.Species(idx)
				m.char_cfg.species = m.species_cursor
				m.screen = .Char_Select_Background
				return .None
			}
		} else if ch == 'A' {
			m.species_cursor = .Felid
			m.char_cfg.species = .Felid
			m.screen = .Char_Select_Background
			return .None
		}
	}

	if is_key_pressed(.UP) {
		m.species_cursor = core.Species(
			(int(m.species_cursor) - 1 + core.SPECIES_COUNT) % core.SPECIES_COUNT,
		)
	} else if is_key_pressed(.DOWN) {
		m.species_cursor = core.Species((int(m.species_cursor) + 1) % core.SPECIES_COUNT)
	} else if is_key_pressed(.LEFT) {
		m.species_cursor = core.Species(
			(int(m.species_cursor) - 9 + core.SPECIES_COUNT) % core.SPECIES_COUNT,
		)
	} else if is_key_pressed(.RIGHT) {
		m.species_cursor = core.Species((int(m.species_cursor) + 9) % core.SPECIES_COUNT)
	} else if is_key_pressed(.TAB) {
		rand_sp := core.Species(int(core.generate_random_seed() % u64(core.SPECIES_COUNT)))
		m.species_cursor = rand_sp
	} else if is_key_pressed(.ENTER) || is_key_pressed(.SPACE) {
		m.char_cfg.species = m.species_cursor
		m.screen = .Char_Select_Background
	}

	return .None
}

draw_background_select_screen :: proc(m: ^Menu_State, screen_w, screen_h: i32) -> Menu_Action {
	term := centered_terminal_rect(screen_w, screen_h)
	draw_terminal_frame(term, " CHARACTER CREATION  -  SELECT BACKGROUND ")

	pad_x := term.x + math.clamp(term.width * 0.035, 16.0, 32.0)
	inner_w := term.width - 2.0 * (pad_x - term.x)
	cur_y := term.y + math.clamp(term.height * 0.045, 22.0, 34.0)

	font_hdr := math.clamp(i32(term.height * 0.029), 12, 20)
	font_item := math.clamp(i32(term.height * 0.025), 11, 17)
	font_small := math.clamp(i32(term.height * 0.022), 10, 15)

	p_name := core.character_name_str(&m.char_cfg.name, m.char_cfg.name_len)
	sp_def := core.SPECIES_DEFS[m.char_cfg.species]
	prompt := fmt.tprintf(
		"You are %s the %s (%s). Please select your background:",
		p_name,
		sp_def.name,
		sp_def.abbrev,
	)
	prompt_cstr := strings.clone_to_cstring(prompt, context.temp_allocator)
	draw_text_bold(prompt_cstr, i32(pad_x), i32(cur_y), font_hdr, rl.RAYWHITE)
	cur_y += f32(font_hdr) * 1.4

	col_gap: f32 = 12.0
	col_w := (inner_w - col_gap * 2.0) / 3.0
	inspector_h := math.clamp(term.height * 0.27, 120.0, 175.0)
	grid_avail_h := term.height - (cur_y - term.y) - inspector_h - f32(font_small) * 2.2
	row_h := math.clamp(grid_avail_h / 12.0, 17.0, 28.0)

	mouse_pos := rl.GetMousePosition()

	col0_cats := [?]core.Background_Category{.Warrior, .Zealot}
	col1_cats := [?]core.Background_Category{.Warrior_Mage, .Adventurer}
	col2_cats := [?]core.Background_Category{.Mage}
	groups := [3][]core.Background_Category{col0_cats[:], col1_cats[:], col2_cats[:]}

	for grp_cats, col_idx in groups {
		col_x := pad_x + f32(col_idx) * (col_w + col_gap)
		row_y := cur_y

		for cat in grp_cats {
			cat_title := core.BACKGROUND_CATEGORY_NAMES[cat]
			cat_cstr := strings.clone_to_cstring(cat_title, context.temp_allocator)
			draw_text_bold(cat_cstr, i32(col_x + 4), i32(row_y), font_item, rl.GOLD)
			rl.DrawLine(
				i32(col_x),
				i32(row_y + f32(font_item) + 2),
				i32(col_x + col_w),
				i32(row_y + f32(font_item) + 2),
				rl.Color{65, 65, 85, 255},
			)
			row_y += f32(font_item) + 5

			for bg in core.Background {
				def := core.BACKGROUND_DEFS[bg]
				if def.category != cat do continue

				r := rl.Rectangle{col_x, row_y, col_w, row_h}
				hovered := rl.CheckCollisionPointRec(mouse_pos, r)
				if hovered {
					m.bg_cursor = bg
				}
				is_sel := (m.bg_cursor == bg)

				if is_sel {
					rl.DrawRectangleRec(r, rl.Color{44, 48, 72, 255})
					rl.DrawRectangleLinesEx(r, 1.0, rl.GOLD)
				} else if hovered {
					rl.DrawRectangleRec(r, rl.Color{28, 30, 44, 255})
				}

				hk := bg_hotkey_rune(bg)
				label := fmt.tprintf(" %c - %-18s (%s)", hk, def.name, def.abbrev)
				label_cstr := strings.clone_to_cstring(label, context.temp_allocator)
				draw_text(
					label_cstr,
					i32(col_x + 2),
					i32(row_y + (row_h - f32(font_item)) / 2),
					font_item,
					is_sel ? rl.GOLD : rl.Color{210, 215, 230, 255},
				)

				if hovered && rl.IsMouseButtonPressed(.LEFT) {
					m.char_cfg.background = bg
					for rl.GetCharPressed() != 0 {}
					return .Start_New_Game
				}
				row_y += row_h + 2
			}
			row_y += 6
		}
	}

	// inspector box at bottom showing combined Species + Background preview
	insp_y := term.y + term.height - inspector_h - f32(font_small) - 16
	insp_rect := rl.Rectangle{pad_x, insp_y, inner_w, inspector_h}
	rl.DrawRectangleRec(insp_rect, rl.Color{20, 20, 30, 255})
	rl.DrawRectangleLinesEx(insp_rect, 1.0, rl.Color{75, 78, 100, 255})

	bg_def := core.BACKGROUND_DEFS[m.bg_cursor]
	tot_str, tot_int, tot_dex, tot_hp, tot_mp := core.compute_starting_stats(
		m.char_cfg.species,
		m.bg_cursor,
	)
	mp_str := m.char_cfg.species == .Djinni ? "Essence (HP)" : fmt.tprintf("%d", tot_mp)

	hdr_line := fmt.tprintf(
		"%s the %s %s (%s%s)   |   HP: %d   MP: %s   |   Str: %d (%+d)   Int: %d (%+d)   Dex: %d (%+d)",
		p_name,
		sp_def.name,
		bg_def.name,
		sp_def.abbrev,
		bg_def.abbrev,
		tot_hp,
		mp_str,
		tot_str,
		bg_def.str_mod,
		tot_int,
		bg_def.int_mod,
		tot_dex,
		bg_def.dex_mod,
	)

	// format starting spells list
	spell_names := ""
	for sp_k in bg_def.spells {
		if sp_k != .None {
			if len(spell_names) > 0 {
				spell_names = fmt.tprintf("%s, %s", spell_names, core.SPELL_DEFS[sp_k].name)
			} else {
				spell_names = core.SPELL_DEFS[sp_k].name
			}
		}
	}
	if len(spell_names) == 0 {
		spell_names = "None (Pure Martial)"
	}

	// format starting gear list
	gear_names := ""
	for eq_k in bg_def.starting_eq {
		if eq_k != .None {
			if len(gear_names) > 0 {
				gear_names = fmt.tprintf("%s, %s", gear_names, core.ITEM_DEFS[eq_k].name)
			} else {
				gear_names = core.ITEM_DEFS[eq_k].name
			}
		}
	}
	for bag_k in bg_def.starting_bag {
		if bag_k != .None {
			if len(gear_names) > 0 {
				gear_names = fmt.tprintf("%s, %s", gear_names, core.ITEM_DEFS[bag_k].name)
			} else {
				gear_names = core.ITEM_DEFS[bag_k].name
			}
		}
	}

	kit_line := fmt.tprintf("Starting Gear: %s   |   Starting Spells: %s", gear_names, spell_names)

	hdr_cstr := strings.clone_to_cstring(hdr_line, context.temp_allocator)
	kit_cstr := strings.clone_to_cstring(kit_line, context.temp_allocator)
	desc_cstr := strings.clone_to_cstring(bg_def.desc, context.temp_allocator)

	iy := insp_y + 10
	draw_text_bold(hdr_cstr, i32(pad_x + 12), i32(iy), font_item, rl.GOLD)
	iy += f32(font_item) * 1.45
	draw_text_bold(kit_cstr, i32(pad_x + 12), i32(iy), font_small, rl.Color{165, 200, 255, 255})
	iy += f32(font_small) * 1.45
	draw_text(desc_cstr, i32(pad_x + 12), i32(iy), font_small, rl.Color{185, 190, 210, 255})

	// footer
	footer_y := term.y + term.height - f32(font_small) - 8
	footer_cstr: cstring = "[a-z] Pick Background & Begin Crawl   [Arrows + Enter] Confirm   [Tab] Random   [Backspace / Esc] Back"
	fw := measure_text(footer_cstr, font_small)
	draw_text(
		footer_cstr,
		i32(term.x + (term.width - f32(fw)) / 2),
		i32(footer_y),
		font_small,
		rl.Color{130, 135, 155, 255},
	)

	if is_back_pressed() {
		m.screen = .Char_Select_Species
		for rl.GetCharPressed() != 0 {}
		return .None
	}

	for {
		ch := rl.GetCharPressed()
		if ch == 0 do break
		if ch >= 'a' && ch <= 'z' {
			idx := int(ch - 'a')
			if idx >= 0 && idx < core.BACKGROUND_COUNT {
				m.bg_cursor = core.Background(idx)
				m.char_cfg.background = m.bg_cursor
				return .Start_New_Game
			}
		}
	}

	if is_key_pressed(.UP) {
		m.bg_cursor = core.Background(
			(int(m.bg_cursor) - 1 + core.BACKGROUND_COUNT) % core.BACKGROUND_COUNT,
		)
	} else if is_key_pressed(.DOWN) {
		m.bg_cursor = core.Background((int(m.bg_cursor) + 1) % core.BACKGROUND_COUNT)
	} else if is_key_pressed(.LEFT) {
		m.bg_cursor = core.Background(
			(int(m.bg_cursor) - 9 + core.BACKGROUND_COUNT) % core.BACKGROUND_COUNT,
		)
	} else if is_key_pressed(.RIGHT) {
		m.bg_cursor = core.Background((int(m.bg_cursor) + 9) % core.BACKGROUND_COUNT)
	} else if is_key_pressed(.TAB) {
		rand_bg := core.Background(int(core.generate_random_seed() % u64(core.BACKGROUND_COUNT)))
		m.bg_cursor = rand_bg
	} else if is_key_pressed(.ENTER) || is_key_pressed(.SPACE) {
		m.char_cfg.background = m.bg_cursor
		return .Start_New_Game
	}

	return .None
}

draw_seed_input_screen :: proc(m: ^Menu_State, screen_w, screen_h: i32) -> Menu_Action {
	term := centered_terminal_rect(screen_w, screen_h)
	draw_terminal_frame(term, " SEEDED CRAWL  -  CUSTOM DUNGEON SEED ")

	pad_x := term.x + math.clamp(term.width * 0.08, 32.0, 72.0)
	inner_w := term.width - 2.0 * (pad_x - term.x)
	cur_y := term.y + term.height * 0.22

	font_hdr := math.clamp(i32(term.height * 0.036), 14, 24)
	font_sub := math.clamp(i32(term.height * 0.028), 12, 18)

	draw_text_bold(
		"Enter a numeric seed for deterministic dungeon generation:",
		i32(pad_x),
		i32(cur_y),
		font_hdr,
		rl.RAYWHITE,
	)
	cur_y += f32(font_hdr) * 1.8

	box_h := f32(font_hdr) * 2.0
	box := rl.Rectangle{pad_x, cur_y, inner_w, box_h}
	rl.DrawRectangleRec(box, rl.Color{24, 24, 36, 255})
	rl.DrawRectangleLinesEx(box, 1.5, rl.GOLD)

	seed_str := m.seed_len > 0 ? string(m.seed_buf[:m.seed_len]) : ""
	disp := fmt.tprintf("Seed: %s_", seed_str)
	disp_cstr := strings.clone_to_cstring(disp, context.temp_allocator)
	draw_text_bold(
		disp_cstr,
		i32(pad_x + 14),
		i32(cur_y + (box_h - f32(font_hdr)) / 2),
		font_hdr,
		rl.GOLD,
	)
	cur_y += box_h + f32(font_sub) * 1.4

	draw_text(
		"Tip: [Tab] Roll random seed   [Enter] Confirm & pick Species   [q / Esc] Cancel",
		i32(pad_x),
		i32(cur_y),
		font_sub,
		rl.Color{165, 175, 195, 255},
	)

	for {
		ch := rl.GetCharPressed()
		if ch == 0 do break
		if ch == 'q' || ch == 'Q' {
			m.custom_seed_on = false
			m.screen = .Main_Menu
			return .None
		}
		if ch >= '0' && ch <= '9' && m.seed_len < 18 {
			m.seed_buf[m.seed_len] = u8(ch)
			m.seed_len += 1
		}
	}

	if is_key_pressed(.BACKSPACE) && m.seed_len > 0 {
		m.seed_len -= 1
		m.seed_buf[m.seed_len] = 0
	} else if is_key_pressed(.TAB) {
		rnd := core.generate_random_seed() % 1000000000
		s := fmt.tprintf("%d", rnd)
		m.seed_len = min(len(s), 18)
		for i in 0 ..< m.seed_len {
			m.seed_buf[i] = s[i]
		}
	} else if is_key_pressed(.ENTER) {
		parsed: u64 = 0
		for i in 0 ..< m.seed_len {
			parsed = parsed * 10 + u64(m.seed_buf[i] - '0')
		}
		if parsed == 0 {
			parsed = core.generate_random_seed()
		}
		m.char_cfg.seed = parsed
		m.custom_seed_on = true
		m.screen = .Char_Select_Species
	} else if is_key_pressed(.ESCAPE) || rl.IsMouseButtonPressed(.RIGHT) {
		m.custom_seed_on = false
		m.screen = .Main_Menu
	}

	return .None
}

draw_high_scores_screen :: proc(m: ^Menu_State, screen_w, screen_h: i32) {
	term := centered_terminal_rect(screen_w, screen_h)
	draw_terminal_frame(term, " HIGH SCORES & MORGUE  —  FALLEN ADVENTURERS ")

	pad_x := term.x + math.clamp(term.width * 0.05, 20.0, 44.0)
	cur_y := term.y + math.clamp(term.height * 0.06, 28.0, 42.0)

	font_hdr := math.clamp(i32(term.height * 0.030), 13, 20)
	font_row := math.clamp(i32(term.height * 0.025), 11, 17)

	draw_text_bold("Top Dungeon Crawl Chronicles:", i32(pad_x), i32(cur_y), font_hdr, rl.GOLD)
	cur_y += f32(font_hdr) * 1.5

	if m.morgue_file.count == 0 {
		draw_text(
			"No fallen characters recorded in the morgue yet. Venture forth into the dungeon!",
			i32(pad_x),
			i32(cur_y + 20),
			font_row,
			rl.Color{150, 155, 175, 255},
		)
	} else {
		max_show := min(int(m.morgue_file.count), 16)
		for i in 0 ..< max_show {
			entry := &m.morgue_file.entries[i]
			line := core.format_morgue_line(i + 1, entry)
			line_cstr := strings.clone_to_cstring(line, context.temp_allocator)
			col :=
				i == 0 ? rl.GOLD : (i < 3 ? rl.Color{225, 230, 245, 255} : rl.Color{175, 180, 200, 255})
			draw_text(line_cstr, i32(pad_x), i32(cur_y), font_row, col)
			cur_y += f32(font_row) * 1.4
		}
	}

	footer_y := term.y + term.height - f32(font_row) - 12
	footer_cstr: cstring = "Press [Enter], [Space], [Backspace], [q], or [Esc] to return to the Main Menu"
	fw := measure_text(footer_cstr, font_row)
	draw_text(
		footer_cstr,
		i32(term.x + (term.width - f32(fw)) / 2),
		i32(footer_y),
		font_row,
		rl.Color{130, 135, 155, 255},
	)

	if is_back_pressed() ||
	   is_key_pressed(.ENTER) ||
	   is_key_pressed(.SPACE) ||
	   is_key_pressed(.Q) ||
	   rl.IsMouseButtonPressed(.LEFT) {
		m.screen = .Main_Menu
	}
	for rl.GetCharPressed() != 0 {}
}

draw_controls_help_screen :: proc(m: ^Menu_State, screen_w, screen_h: i32) {
	term := centered_terminal_rect(screen_w, screen_h)
	draw_terminal_frame(term, " DUNGEON MANUAL & KEYBINDINGS ")

	pad_x := term.x + math.clamp(term.width * 0.06, 24.0, 48.0)
	cur_y := term.y + math.clamp(term.height * 0.06, 28.0, 42.0)

	font_hdr := math.clamp(i32(term.height * 0.030), 13, 20)
	font_row := math.clamp(i32(term.height * 0.025), 11, 17)

	lines := [?]struct {
		header: bool,
		text:   cstring,
	} {
		{true, "MOVEMENT & EXPLORATION"},
		{
			false,
			"  Arrow Keys / h j k l     Move North, South, East, West (bump into enemies to attack)",
		},
		{false, "  > or PageDown            Descend downstairs (>) to the next dungeon floor"},
		{false, "  < or PageUp              Ascend upstairs (<) to the previous dungeon floor"},
		{true, "MAGIC & COMBAT TARGETING"},
		{false, "  f                        Target mode: start aiming from player position"},
		{false, "  z                        Show currently queued spell to cast"},
		{false, "  Tab (in target mode)     Cycle target between visible monsters"},
		{false, "  [ and ]                  Cycle active spell slot"},
		{false, "  Intelligence (Int)       Increases maximum MP and scales spell damage"},
		{
			false,
			"  Djinni (Dj) Trait        Djinni characters channel spells directly from HP instead of MP",
		},
		{true, "INVENTORY & EQUIPMENT"},
		{false, "  , or g                   Pick up item on the floor"},
		{false, "  Left-Click Slot          Inspect equipment or backpack slot"},
		{
			false,
			"  Use/Equip Button         Quaff selected Health/Magic Potion or equip weapon/armor",
		},
		{false, "  Drop Button              Drop selected backpack item onto the floor"},
		{false, "  Keys 1 - 8               Quickly unequip worn item from Equipment Slots 1..8"},
		{true, "SAVING & SYSTEM"},
		{false, "  Esc / Backspace / m      Save current progress and return to the Main Menu"},
		{false, "  ?                        Open this Dungeon Manual screen"},
	}

	for l in lines {
		if l.header {
			cur_y += 6
			draw_text_bold(l.text, i32(pad_x), i32(cur_y), font_hdr, rl.GOLD)
			cur_y += f32(font_hdr) * 1.35
		} else {
			draw_text(l.text, i32(pad_x), i32(cur_y), font_row, rl.Color{205, 210, 225, 255})
			cur_y += f32(font_row) * 1.35
		}
	}

	footer_y := term.y + term.height - f32(font_row) - 12
	footer_cstr: cstring = "Press [Enter], [Space], [Backspace], [q], or [Esc] to return"
	fw := measure_text(footer_cstr, font_row)
	draw_text(
		footer_cstr,
		i32(term.x + (term.width - f32(fw)) / 2),
		i32(footer_y),
		font_row,
		rl.Color{130, 135, 155, 255},
	)

	if is_back_pressed() ||
	   is_key_pressed(.ENTER) ||
	   is_key_pressed(.SPACE) ||
	   is_key_pressed(.Q) ||
	   rl.IsMouseButtonPressed(.LEFT) {
		m.screen = m.return_screen
	}
	for rl.GetCharPressed() != 0 {}
}

draw_game_over_screen :: proc(m: ^Menu_State, screen_w, screen_h: i32) {
	term := centered_terminal_rect(screen_w, screen_h)
	draw_terminal_frame(term, " YOU HAVE DIED  -  MORGUE CHRONICLE ")

	pad_x := term.x + math.clamp(term.width * 0.08, 32.0, 64.0)
	cur_y := term.y + term.height * 0.16

	font_title := math.clamp(i32(term.height * 0.045), 18, 32)
	font_row := math.clamp(i32(term.height * 0.030), 13, 20)

	draw_text_bold(
		"Rest in Peace, Explorer of the Dungeon",
		i32(pad_x),
		i32(cur_y),
		font_title,
		rl.Color{235, 75, 75, 255},
	)
	cur_y += f32(font_title) * 1.8

	e := &m.last_morgue
	p_name := core.character_name_str(&e.name, e.name_len)
	sp := core.Species(min(int(e.species), core.SPECIES_COUNT - 1))
	bg := core.Background(min(int(e.background), core.BACKGROUND_COUNT - 1))
	k_len := min(int(e.killer_len), core.MAX_KILLER_LEN)
	killer := k_len > 0 ? string(e.killer[:k_len]) : "unknown monster"

	summary_lines := [5]string {
		fmt.tprintf(
			"Character:    %s the %s %s (%s%s)",
			p_name,
			core.SPECIES_DEFS[sp].name,
			core.BACKGROUND_DEFS[bg].name,
			core.SPECIES_DEFS[sp].abbrev,
			core.BACKGROUND_DEFS[bg].abbrev,
		),
		fmt.tprintf("Fate:         Slain by %s on Dungeon Level D:%d", killer, e.depth),
		fmt.tprintf("Turns Taken:  %d turns", e.turns),
		fmt.tprintf("Gold Found:   %d gold pieces", e.gold),
		fmt.tprintf("Final Score:  %d points   (Dungeon Seed: %d)", e.score, e.seed),
	}

	for s in summary_lines {
		cstr := strings.clone_to_cstring(s, context.temp_allocator)
		draw_text_bold(cstr, i32(pad_x), i32(cur_y), font_row, rl.RAYWHITE)
		cur_y += f32(font_row) * 1.65
	}

	footer_y := term.y + term.height - f32(font_row) - 16
	footer_cstr: cstring = "Press [Enter], [Space], [Backspace], or [Esc] to return to the Main Menu"
	fw := measure_text(footer_cstr, font_row)
	draw_text_bold(
		footer_cstr,
		i32(term.x + (term.width - f32(fw)) / 2),
		i32(footer_y),
		font_row,
		rl.GOLD,
	)

	if is_back_pressed() ||
	   is_key_pressed(.ENTER) ||
	   is_key_pressed(.SPACE) ||
	   rl.IsMouseButtonPressed(.LEFT) {
		refresh_menu_save_preview(m)
		m.main_cursor = 0
		m.screen = .Main_Menu
	}
	for rl.GetCharPressed() != 0 {}
}
