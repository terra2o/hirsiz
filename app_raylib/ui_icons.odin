package main

import "../core"
import "core:math"
import rl "vendor:raylib"

Icon_Mode :: enum {
	Ascii,
	Sprite,
}

Item_Visual :: struct {
	glyph:    rune,
	color:    rl.Color,
	bg_color: rl.Color,
}

// default ASCII visuals for each item kind
ITEM_VISUALS := [core.Item_Kind]Item_Visual {
	.None = {
		glyph = ' ',
		color = rl.BLANK,
		bg_color = rl.BLANK,
	},
	.Rusty_Dagger = {
		glyph = ')',
		color = rl.Color{180, 160, 140, 255},
		bg_color = rl.Color{50, 40, 35, 100},
	},
	.Iron_Shortsword = {
		glyph = ')',
		color = rl.Color{200, 210, 225, 255},
		bg_color = rl.Color{40, 50, 65, 100},
	},
	.Steel_Broadsword = {
		glyph = ')',
		color = rl.Color{230, 240, 255, 255},
		bg_color = rl.Color{45, 60, 80, 100},
	},
	.Battle_Axe = {
		glyph = 'P',
		color = rl.Color{220, 140, 110, 255},
		bg_color = rl.Color{65, 40, 35, 100},
	},
	.Hand_Axe = {
		glyph = ')',
		color = rl.Color{210, 155, 115, 255},
		bg_color = rl.Color{60, 42, 32, 100},
	},
	.Mace = {
		glyph = ')',
		color = rl.Color{195, 200, 210, 255},
		bg_color = rl.Color{45, 48, 58, 100},
	},
	.Spear = {
		glyph = '/',
		color = rl.Color{215, 190, 140, 255},
		bg_color = rl.Color{55, 48, 35, 100},
	},
	.Quarterstaff = {
		glyph = '\\',
		color = rl.Color{190, 145, 95, 255},
		bg_color = rl.Color{55, 40, 28, 100},
	},
	.Short_Bow = {
		glyph = '}',
		color = rl.Color{205, 160, 100, 255},
		bg_color = rl.Color{55, 42, 28, 100},
	},
	.Leather_Cap = {
		glyph = '[',
		color = rl.Color{160, 120, 80, 255},
		bg_color = rl.Color{50, 40, 30, 100},
	},
	.Iron_Helmet = {
		glyph = '[',
		color = rl.Color{190, 200, 210, 255},
		bg_color = rl.Color{45, 50, 60, 100},
	},
	.Steel_Full_Helm = {
		glyph = '[',
		color = rl.Color{225, 235, 250, 255},
		bg_color = rl.Color{50, 60, 75, 100},
	},
	.Wizard_Hat = {
		glyph = '^',
		color = rl.Color{165, 130, 245, 255},
		bg_color = rl.Color{45, 35, 75, 110},
	},
	.Cloth_Tunic = {
		glyph = '[',
		color = rl.Color{140, 170, 190, 255},
		bg_color = rl.Color{35, 45, 55, 100},
	},
	.Robe = {
		glyph = '[',
		color = rl.Color{135, 165, 240, 255},
		bg_color = rl.Color{35, 42, 75, 110},
	},
	.Animal_Skin = {
		glyph = '[',
		color = rl.Color{185, 140, 95, 255},
		bg_color = rl.Color{55, 42, 28, 100},
	},
	.Leather_Armor = {
		glyph = '[',
		color = rl.Color{175, 125, 80, 255},
		bg_color = rl.Color{50, 40, 30, 100},
	},
	.Scale_Mail = {
		glyph = '[',
		color = rl.Color{185, 205, 215, 255},
		bg_color = rl.Color{42, 52, 62, 100},
	},
	.Chainmail = {
		glyph = '[',
		color = rl.Color{200, 205, 220, 255},
		bg_color = rl.Color{45, 50, 65, 100},
	},
	.Plate_Armor = {
		glyph = '[',
		color = rl.Color{230, 235, 245, 255},
		bg_color = rl.Color{55, 60, 75, 100},
	},
	.Cloth_Pants = {
		glyph = '[',
		color = rl.Color{130, 140, 160, 255},
		bg_color = rl.Color{35, 40, 50, 100},
	},
	.Leather_Leggings = {
		glyph = '[',
		color = rl.Color{165, 120, 75, 255},
		bg_color = rl.Color{50, 40, 30, 100},
	},
	.Plate_Greaves = {
		glyph = '[',
		color = rl.Color{210, 220, 230, 255},
		bg_color = rl.Color{50, 55, 70, 100},
	},
	.Leather_Boots = {
		glyph = '[',
		color = rl.Color{150, 110, 70, 255},
		bg_color = rl.Color{45, 35, 25, 100},
	},
	.Iron_Boots = {
		glyph = '[',
		color = rl.Color{190, 200, 215, 255},
		bg_color = rl.Color{45, 50, 60, 100},
	},
	.Wooden_Shield = {
		glyph = ')',
		color = rl.Color{170, 125, 75, 255},
		bg_color = rl.Color{50, 40, 30, 100},
	},
	.Iron_Shield = {
		glyph = ')',
		color = rl.Color{200, 215, 230, 255},
		bg_color = rl.Color{45, 55, 70, 100},
	},
	.Ring_Of_Protection = {
		glyph = '=',
		color = rl.Color{100, 180, 255, 255},
		bg_color = rl.Color{30, 50, 80, 100},
	},
	.Ring_Of_Might = {
		glyph = '=',
		color = rl.Color{255, 120, 100, 255},
		bg_color = rl.Color{80, 40, 35, 100},
	},
	.Ring_Of_Wizardry = {
		glyph = '=',
		color = rl.Color{185, 125, 255, 255},
		bg_color = rl.Color{55, 35, 85, 110},
	},
	.Amulet_Of_Vitality = {
		glyph = '"',
		color = rl.Color{255, 215, 80, 255},
		bg_color = rl.Color{80, 70, 30, 100},
	},
	.Amulet_Of_Magic = {
		glyph = '"',
		color = rl.Color{110, 210, 255, 255},
		bg_color = rl.Color{30, 65, 85, 110},
	},
	.Health_Potion = {
		glyph = '!',
		color = rl.Color{240, 70, 70, 255},
		bg_color = rl.Color{70, 25, 25, 120},
	},
	.Magic_Potion = {
		glyph = '!',
		color = rl.Color{90, 165, 255, 255},
		bg_color = rl.Color{25, 45, 85, 120},
	},
}

// placeholder rune per equipment slot
EQUIPMENT_SLOT_GLYPHS := [core.Equipment_Slot]rune {
	.Head   = 'H',
	.Torso  = 'T',
	.Legs   = 'L',
	.Feet   = 'F',
	.Weapon = 'W',
	.Shield = 'S',
	.Ring   = 'R',
	.Amulet = 'A',
}

// draws a slot icon cleanly, easily swappable with sprites in the future
draw_slot_visual :: proc(
	rect: rl.Rectangle,
	item: core.Item_Kind,
	slot_placeholder: rune,
	is_hovered: bool,
	is_selected: bool,
) {
	// slot base background
	bg_color := rl.Color{26, 26, 36, 255}
	if is_hovered {
		bg_color = rl.Color{38, 42, 58, 255}
	}
	if is_selected {
		bg_color = rl.Color{48, 54, 76, 255}
	}
	rl.DrawRectangleRec(rect, bg_color)

	// draw inner item or slot placeholder
	if item != .None {
		vis := ITEM_VISUALS[item]
		if vis.bg_color.a > 0 && rect.width > 8 {
			inner := rl.Rectangle{rect.x + 1, rect.y + 1, rect.width - 2, rect.height - 2}
			rl.DrawRectangleRec(inner, vis.bg_color)
		}
		glyph_str: [2]u8 = {u8(vis.glyph), 0}
		font_size := math.clamp(i32(rect.height * 0.62), 10, 52)
		tw := measure_text_bold(cstring(&glyph_str[0]), font_size)
		draw_text_bold(
			cstring(&glyph_str[0]),
			i32(rect.x + (rect.width - f32(tw)) / 2),
			i32(rect.y + (rect.height - f32(font_size)) / 2),
			font_size,
			vis.color,
		)
	} else if slot_placeholder != ' ' {
		placeholder_str: [2]u8 = {u8(slot_placeholder), 0}
		font_size := math.clamp(i32(rect.height * 0.50), 8, 42)
		tw := measure_text(cstring(&placeholder_str[0]), font_size)
		draw_text(
			cstring(&placeholder_str[0]),
			i32(rect.x + (rect.width - f32(tw)) / 2),
			i32(rect.y + (rect.height - f32(font_size)) / 2),
			font_size,
			rl.Color{75, 80, 100, 255},
		)
	}

	// border
	border_color := rl.Color{60, 62, 78, 255}
	line_w: f32 = 1.0
	if is_selected {
		border_color = rl.GOLD
		line_w = rect.height > 24 ? 2.0 : 1.0
	} else if is_hovered {
		border_color = rl.Color{130, 140, 170, 255}
	}
	rl.DrawRectangleLinesEx(rect, line_w, border_color)
}
