package core

import "core:math/rand"

DUNGEON_WIDTH :: 80
DUNGEON_HEIGHT :: 45

Tile_Type :: enum u8 {
	Unused,
	Wall,
	Floor,
	Door_Closed,
	Door_Open,
	Stairs_Up,
	Stairs_Down,
}

Tile :: struct {
	type:        Tile_Type,
	walkable:    bool,
	transparent: bool,
}

Color_RGB :: struct {
	r, g, b: u8,
}

COLOR_FLOOR :: Color_RGB{180, 160, 130}
COLOR_WALL :: Color_RGB{90, 80, 95}
COLOR_DOOR :: Color_RGB{165, 110, 42}
COLOR_STAIRS_UP :: Color_RGB{100, 220, 255}
COLOR_STAIRS_DOWN :: Color_RGB{255, 215, 0}
COLOR_EMPTY :: Color_RGB{10, 10, 15}

tile_to_ascii :: proc(type: Tile_Type) -> rune {
	switch type {
	case .Unused:
		return ' '
	case .Wall:
		return '#'
	case .Floor:
		return '.'
	case .Door_Closed:
		return '+'
	case .Door_Open:
		return '\''
	case .Stairs_Up:
		return '<'
	case .Stairs_Down:
		return '>'
	}
	return '?'
}

tile_color :: proc(type: Tile_Type) -> Color_RGB {
	switch type {
	case .Floor:
		return COLOR_FLOOR
	case .Wall:
		return COLOR_WALL
	case .Door_Closed:
		return COLOR_DOOR
	case .Door_Open:
		return COLOR_DOOR
	case .Stairs_Up:
		return COLOR_STAIRS_UP
	case .Stairs_Down:
		return COLOR_STAIRS_DOWN
	case .Unused:
		return COLOR_EMPTY
	}
	return COLOR_EMPTY
}

Room_Kind :: enum {
	Rectangular,
	Cross,
	Round,
	Vault, // feature chamber with special pillar layouts
}

Room :: struct {
	x, y:      int, // top-left coordinate including perimeter
	w, h:      int, // width and height
	center_x:  int,
	center_y:  int,
	connected: bool,
	kind:      Room_Kind,
}

Dungeon_Config :: struct {
	seed:              u64,
	depth:             int,
	width:             int,
	height:            int,
	max_rooms:         int,
	min_room_size:     int,
	max_room_size:     int,
	extra_loop_chance: f32, // chance to connect disjoint nearby rooms with corridors (creates tactical loops)
	door_chance:       f32, // chance for corridor-room entrance to have a door
}

default_dungeon_config :: proc(seed: u64 = 0, depth: int = 1) -> Dungeon_Config {
	return Dungeon_Config {
		seed = seed,
		depth = depth,
		width = DUNGEON_WIDTH,
		height = DUNGEON_HEIGHT,
		max_rooms = 30,
		min_room_size = 5,
		max_room_size = 13,
		extra_loop_chance = 0.35,
		door_chance = 0.40,
	}
}

Dungeon :: struct {
	width:           int,
	height:          int,
	tiles:           []Tile,
	visible:         []bool,
	explored:        []bool,
	rooms:           [dynamic]Room,
	enemies:         [dynamic]Enemy,
	stairs_up_pos:   [2]int,
	stairs_down_pos: [2]int,
}

destroy_dungeon :: proc(d: ^Dungeon) {
	delete(d.tiles)
	delete(d.visible)
	delete(d.explored)
	delete(d.rooms)
	delete(d.enemies)
}

dungeon_in_bounds :: proc(d: ^Dungeon, x, y: int) -> bool {
	return x >= 0 && x < d.width && y >= 0 && y < d.height
}

dungeon_get_tile :: proc(d: ^Dungeon, x, y: int) -> Tile {
	if !dungeon_in_bounds(d, x, y) do return Tile{type = .Unused, walkable = false, transparent = false}
	return d.tiles[y * d.width + x]
}

dungeon_set_tile :: proc(d: ^Dungeon, x, y: int, type: Tile_Type) {
	if !dungeon_in_bounds(d, x, y) do return

	walkable := false
	transparent := false

	switch type {
	case .Floor, .Door_Open, .Stairs_Up, .Stairs_Down:
		walkable = true
		transparent = true
	case .Door_Closed:
		walkable = false
		transparent = false
	case .Wall, .Unused:
		walkable = false
		transparent = false
	}

	d.tiles[y * d.width + x] = Tile {
		type        = type,
		walkable    = walkable,
		transparent = transparent,
	}
}

is_walkable :: proc(d: ^Dungeon, x, y: int) -> bool {
	if !dungeon_in_bounds(d, x, y) do return false
	return d.tiles[y * d.width + x].walkable
}

is_floor_or_corridor :: proc(d: ^Dungeon, x, y: int) -> bool {
	if !dungeon_in_bounds(d, x, y) do return false
	t := d.tiles[y * d.width + x].type
	return(
		t == .Floor ||
		t == .Door_Closed ||
		t == .Door_Open ||
		t == .Stairs_Up ||
		t == .Stairs_Down \
	)
}

rooms_intersect :: proc(a, b: Room, margin: int = 1) -> bool {
	return(
		a.x - margin < b.x + b.w + margin &&
		a.x + a.w + margin > b.x - margin &&
		a.y - margin < b.y + b.h + margin &&
		a.y + a.h + margin > b.y - margin \
	)
}

carve_h_corridor :: proc(d: ^Dungeon, x1, x2, y: int) {
	start_x := min(x1, x2)
	end_x := max(x1, x2)
	for x in start_x ..= end_x {
		if x > 0 && x < d.width - 1 && y > 0 && y < d.height - 1 {
			dungeon_set_tile(d, x, y, .Floor)
		}
	}
}

carve_v_corridor :: proc(d: ^Dungeon, y1, y2, x: int) {
	start_y := min(y1, y2)
	end_y := max(y1, y2)
	for y in start_y ..= end_y {
		if x > 0 && x < d.width - 1 && y > 0 && y < d.height - 1 {
			dungeon_set_tile(d, x, y, .Floor)
		}
	}
}

carve_corridor :: proc(d: ^Dungeon, x1, y1, x2, y2: int, rng: rand.Generator) {
	if rand.float32(rng) < 0.5 {
		carve_h_corridor(d, x1, x2, y1)
		carve_v_corridor(d, y1, y2, x2)
	} else {
		carve_v_corridor(d, y1, y2, x1)
		carve_h_corridor(d, x1, x2, y2)
	}
}

carve_room :: proc(d: ^Dungeon, room: Room, rng: rand.Generator) {
	#partial switch room.kind {
	case .Rectangular:
		for y in room.y + 1 ..< room.y + room.h - 1 {
			for x in room.x + 1 ..< room.x + room.w - 1 {
				dungeon_set_tile(d, x, y, .Floor)
			}
		}

	case .Cross:
		cx := room.center_x
		cy := room.center_y
		arm_w := max(3, room.w / 2)
		arm_h := max(3, room.h / 2)

		for y in cy - arm_h / 2 ..= cy + arm_h / 2 {
			for x in room.x + 1 ..< room.x + room.w - 1 {
				dungeon_set_tile(d, x, y, .Floor)
			}
		}
		for y in room.y + 1 ..< room.y + room.h - 1 {
			for x in cx - arm_w / 2 ..= cx + arm_w / 2 {
				dungeon_set_tile(d, x, y, .Floor)
			}
		}

	case .Round:
		radius_x := f32(room.w - 2) / 2.0
		radius_y := f32(room.h - 2) / 2.0
		cx := f32(room.center_x)
		cy := f32(room.center_y)
		for y in room.y + 1 ..< room.y + room.h - 1 {
			for x in room.x + 1 ..< room.x + room.w - 1 {
				dx := (f32(x) - cx) / radius_x
				dy := (f32(y) - cy) / radius_y
				if (dx * dx + dy * dy) <= 1.05 {
					dungeon_set_tile(d, x, y, .Floor)
				}
			}
		}

	case .Vault:
		for y in room.y + 1 ..< room.y + room.h - 1 {
			for x in room.x + 1 ..< room.x + room.w - 1 {
				dungeon_set_tile(d, x, y, .Floor)
			}
		}
		if room.w >= 8 && room.h >= 8 {
			dungeon_set_tile(d, room.x + 3, room.y + 3, .Wall)
			dungeon_set_tile(d, room.x + room.w - 4, room.y + 3, .Wall)
			dungeon_set_tile(d, room.x + 3, room.y + room.h - 4, .Wall)
			dungeon_set_tile(d, room.x + room.w - 4, room.y + room.h - 4, .Wall)
		}
	}
}

generate_walls :: proc(d: ^Dungeon) {
	for y in 0 ..< d.height {
		for x in 0 ..< d.width {
			if d.tiles[y * d.width + x].type == .Floor {
				for dy in -1 ..= 1 {
					for dx in -1 ..= 1 {
						nx := x + dx
						ny := y + dy
						if dungeon_in_bounds(d, nx, ny) {
							if d.tiles[ny * d.width + nx].type == .Unused {
								dungeon_set_tile(d, nx, ny, .Wall)
							}
						}
					}
				}
			}
		}
	}
}

is_inside_any_room :: proc(d: ^Dungeon, x, y: int) -> bool {
	for r in d.rooms {
		if x > r.x && x < r.x + r.w - 1 && y > r.y && y < r.y + r.h - 1 {
			return true
		}
	}
	return false
}

is_room_perimeter :: proc(d: ^Dungeon, x, y: int) -> bool {
	for r in d.rooms {
		on_x_border := (x == r.x || x == r.x + r.w - 1) && (y >= r.y && y < r.y + r.h)
		on_y_border := (y == r.y || y == r.y + r.h - 1) && (x >= r.x && x < r.x + r.w)
		if on_x_border || on_y_border {
			return true
		}
	}
	return false
}

has_adjacent_door :: proc(d: ^Dungeon, x, y: int) -> bool {
	for dy in -1 ..= 1 {
		for dx in -1 ..= 1 {
			if dx == 0 && dy == 0 do continue
			nx := x + dx
			ny := y + dy
			if dungeon_in_bounds(d, nx, ny) {
				t := d.tiles[ny * d.width + nx].type
				if t == .Door_Closed || t == .Door_Open {
					return true
				}
			}
		}
	}
	return false
}

place_doors :: proc(d: ^Dungeon, door_chance: f32, rng: rand.Generator) {
	for y in 1 ..< d.height - 1 {
		for x in 1 ..< d.width - 1 {
			if d.tiles[y * d.width + x].type != .Floor do continue
			if !is_room_perimeter(d, x, y) do continue
			if has_adjacent_door(d, x, y) do continue

			is_h_doorway :=
				(d.tiles[(y - 1) * d.width + x].type == .Wall &&
					d.tiles[(y + 1) * d.width + x].type == .Wall &&
					is_floor_or_corridor(d, x - 1, y) &&
					is_floor_or_corridor(d, x + 1, y)) &&
				(is_inside_any_room(d, x - 1, y) ~ is_inside_any_room(d, x + 1, y))

			is_v_doorway :=
				(d.tiles[y * d.width + (x - 1)].type == .Wall &&
					d.tiles[y * d.width + (x + 1)].type == .Wall &&
					is_floor_or_corridor(d, x, y - 1) &&
					is_floor_or_corridor(d, x, y + 1)) &&
				(is_inside_any_room(d, x, y - 1) ~ is_inside_any_room(d, x, y + 1))

			if is_h_doorway || is_v_doorway {
				if rand.float32(rng) < door_chance {
					dungeon_set_tile(d, x, y, .Door_Closed)
				}
			}
		}
	}
}

place_stairs :: proc(d: ^Dungeon, rng: rand.Generator) {
	if len(d.rooms) == 0 do return

	first_idx := 0
	last_idx := len(d.rooms) - 1

	room_up := d.rooms[first_idx]
	room_down := d.rooms[last_idx]

	d.stairs_up_pos = {room_up.center_x, room_up.center_y}
	d.stairs_down_pos = {room_down.center_x, room_down.center_y}

	dungeon_set_tile(d, room_up.center_x, room_up.center_y, .Stairs_Up)
	dungeon_set_tile(d, room_down.center_x, room_down.center_y, .Stairs_Down)
}

generate_dungeon :: proc(config: Dungeon_Config) -> Dungeon {
	actual_seed := config.seed
	if actual_seed == 0 {
		actual_seed = u64(rand.int63())
		if actual_seed == 0 do actual_seed = 1337
	}
	state := rand.create(actual_seed)
	rng := rand.default_random_generator(&state)

	dungeon := Dungeon {
		width    = config.width,
		height   = config.height,
		tiles    = make([]Tile, config.width * config.height),
		visible  = make([]bool, config.width * config.height),
		explored = make([]bool, config.width * config.height),
		rooms    = make([dynamic]Room),
	}

	for i in 0 ..< config.width * config.height {
		dungeon.tiles[i] = Tile {
			type        = .Unused,
			walkable    = false,
			transparent = false,
		}
	}

	kinds := [4]Room_Kind{.Rectangular, .Rectangular, .Cross, .Round}

	for _ in 0 ..< config.max_rooms * 3 {
		if len(dungeon.rooms) >= config.max_rooms do break

		rw := rand.int_range(config.min_room_size, config.max_room_size + 1, rng)
		rh := rand.int_range(config.min_room_size, config.max_room_size + 1, rng)

		rx := rand.int_range(1, config.width - rw - 1, rng)
		ry := rand.int_range(1, config.height - rh - 1, rng)

		kind_idx := rand.int_max(len(kinds), rng)
		kind := kinds[kind_idx]
		if rw > 9 && rh > 9 && rand.float32(rng) < 0.25 {
			kind = .Vault
		}

		new_room := Room {
			x         = rx,
			y         = ry,
			w         = rw,
			h         = rh,
			center_x  = rx + rw / 2,
			center_y  = ry + rh / 2,
			connected = false,
			kind      = kind,
		}

		failed := false
		for r in dungeon.rooms {
			if rooms_intersect(new_room, r, 2) {
				failed = true
				break
			}
		}

		if !failed {
			carve_room(&dungeon, new_room, rng)
			append(&dungeon.rooms, new_room)
		}
	}

	if len(dungeon.rooms) > 1 {
		for i in 1 ..< len(dungeon.rooms) {
			prev := dungeon.rooms[i - 1]
			curr := dungeon.rooms[i]
			carve_corridor(
				&dungeon,
				prev.center_x,
				prev.center_y,
				curr.center_x,
				curr.center_y,
				rng,
			)
		}

		for i in 0 ..< len(dungeon.rooms) {
			for j in i + 2 ..< len(dungeon.rooms) {
				r1 := dungeon.rooms[i]
				r2 := dungeon.rooms[j]
				dist := abs(r1.center_x - r2.center_x) + abs(r1.center_y - r2.center_y)
				if dist < 25 && rand.float32(rng) < config.extra_loop_chance {
					carve_corridor(
						&dungeon,
						r1.center_x,
						r1.center_y,
						r2.center_x,
						r2.center_y,
						rng,
					)
				}
			}
		}
	}

	generate_walls(&dungeon)
	place_doors(&dungeon, config.door_chance, rng)
	place_stairs(&dungeon, rng)
	place_enemies(&dungeon, config.depth, rng)

	return dungeon
}

place_enemies :: proc(d: ^Dungeon, depth: int, rng: rand.Generator) {
	if len(d.rooms) <= 1 do return

	enemy_id := 1

	// skip room 0 where the player / stairs up usually start
	for r_idx in 1 ..< len(d.rooms) {
		room := d.rooms[r_idx]
		// spawn 1 to 3 enemies per room depending on room area
		area := room.w * room.h
		max_spawn := 1
		if area > 40 do max_spawn = 2
		if area > 80 do max_spawn = 3

		num_enemies := rand.int_range(0, max_spawn + 1, rng)
		for _ in 0 ..< num_enemies {
			for attempt in 0 ..< 10 {
				ex := rand.int_range(room.x + 1, room.x + room.w - 1, rng)
				ey := rand.int_range(room.y + 1, room.y + room.h - 1, rng)

				tile := dungeon_get_tile(d, ex, ey)
				if !tile.walkable do continue

				// don't spawn on stairs up or down
				if (ex == d.stairs_up_pos.x && ey == d.stairs_up_pos.y) ||
				   (ex == d.stairs_down_pos.x && ey == d.stairs_down_pos.y) {
					continue
				}

				spot_taken := false
				for &other in d.enemies {
					if other.x == ex && other.y == ey {
						spot_taken = true
						break
					}
				}
				if spot_taken do continue

				kind := pick_random_enemy_kind(depth, rng)
				enemy := create_enemy(kind, ex, ey, enemy_id)
				enemy_id += 1
				append(&d.enemies, enemy)
				break
			}
		}
	}
}
