package main

import rl "vendor:raylib"

ui_font: rl.Font
ui_font_bold: rl.Font

init_fonts :: proc() {
	font_path: cstring = "assets/JetBrainsMono/JetBrainsMono-Regular.ttf"
	font_bold_path: cstring = "assets/JetBrainsMono/JetBrainsMono-Bold.ttf"
	if !rl.FileExists(font_path) {
		font_path = "../assets/JetBrainsMono/JetBrainsMono-Regular.ttf"
		font_bold_path = "../assets/JetBrainsMono/JetBrainsMono-Bold.ttf"
	}
	ui_font = rl.LoadFontEx(font_path, 64, nil, 0)
	ui_font_bold = rl.LoadFontEx(font_bold_path, 64, nil, 0)
	rl.SetTextureFilter(ui_font.texture, .BILINEAR)
	rl.SetTextureFilter(ui_font_bold.texture, .BILINEAR)
}

unload_fonts :: proc() {
	rl.UnloadFont(ui_font)
	rl.UnloadFont(ui_font_bold)
}

draw_text :: proc(text: cstring, x, y: i32, font_size: i32, color: rl.Color) {
	rl.DrawTextEx(ui_font, text, {f32(x), f32(y)}, f32(font_size), 0, color)
}

draw_text_bold :: proc(text: cstring, x, y: i32, font_size: i32, color: rl.Color) {
	rl.DrawTextEx(ui_font_bold, text, {f32(x), f32(y)}, f32(font_size), 0, color)
}

measure_text :: proc(text: cstring, font_size: i32) -> i32 {
	size := rl.MeasureTextEx(ui_font, text, f32(font_size), 0)
	return i32(size.x)
}

measure_text_bold :: proc(text: cstring, font_size: i32) -> i32 {
	size := rl.MeasureTextEx(ui_font_bold, text, f32(font_size), 0)
	return i32(size.x)
}
