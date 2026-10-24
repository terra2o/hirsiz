package core

import "core:crypto"
import "core:mem"
import "core:os"
import "core:path/filepath"

SAVE_MAGIC :: [4]u8{'R', 'O', 'G', 'U'}
CURRENT_SAVE_VERSION: u32 : 4
GAME_NAME :: "hirsiz"
MAX_ENEMIES_PER_FLOOR :: 64
EXPLORED_MAP_BYTES :: (DUNGEON_WIDTH * DUNGEON_HEIGHT + 7) / 8

Inventory_Record :: struct #packed {
	items:     [MAX_INVENTORY_ITEMS]u8,
	equipment: [EQUIPMENT_SLOT_COUNT]u8,
}

Enemy_Record :: struct #packed {
	id:        i32,
	kind:      u8,
	is_alive:  bool,
	_pad:      [2]u8,
	x:         i32,
	y:         i32,
	hp:        i32,
	max_hp:    i32,
	inventory: Inventory_Record,
}

Save_Header :: struct #packed {
	magic:         [4]u8,
	version:       u32,
	session_token: u64,
	dungeon_seed:  u64,
	turn_count:    u64,
}

Player_State :: struct #packed {
	pos_x:         i32,
	pos_y:         i32,
	hp:            i32,
	max_hp:        i32,
	gold:          u32,
	dungeon_depth: i32,
	inventory:     Inventory_Record,
}

Save_Data :: struct #packed {
	header:         Save_Header,
	player:         Player_State,
	enemy_count:    u32,
	enemies:        [MAX_ENEMIES_PER_FLOOR]Enemy_Record,
	explored_tiles: [EXPLORED_MAP_BYTES]u8,
}

get_save_directory :: proc(allocator := context.allocator) -> (string, bool) {
	when ODIN_OS == .Windows {
		app_data := os.get_env("APPDATA", context.temp_allocator)
		if len(app_data) == 0 do return "", false
		dir_path, err := filepath.join({app_data, GAME_NAME}, allocator)
		if err != nil do return "", false
	} else when ODIN_OS == .Linux {
		xdg_config := os.get_env("XDG_CONFIG_HOME", context.temp_allocator)
		base_dir: string
		if len(xdg_config) > 0 {
			base_dir = xdg_config
		} else {
			home := os.get_env("HOME", context.temp_allocator)
			if len(home) == 0 do return "", false
			joined_config, err := filepath.join({home, ".config"}, context.temp_allocator)
			if err != nil do return "", false
			base_dir = joined_config
		}
		dir_path, err := filepath.join({base_dir, GAME_NAME}, allocator)
		if err != nil do return "", false
	} else when ODIN_OS == .Darwin {
		home := os.get_env("HOME", context.temp_allocator)
		if len(home) == 0 do return "", false
		dir_path, err := filepath.join(
			{home, "Library", "Application Support", GAME_NAME},
			allocator,
		)
		if err != nil do return "", false
	} else {
		return "", false
	}

	// os.make_directory returns nil on success; if directory exists, that's fine
	if !os.exists(dir_path) {
		if os.make_directory(dir_path) != nil {
			delete(dir_path, allocator)
			return "", false
		}
	}

	return dir_path, true
}

save_game :: proc(state: ^Save_Data) -> bool {
	dir, ok := get_save_directory(context.temp_allocator)
	if !ok do return false

	save_path, err1 := filepath.join({dir, "save.dat"}, context.temp_allocator)
	if err1 != nil do return false

	tmp_path, err2 := filepath.join({dir, "save.dat.tmp"}, context.temp_allocator)
	if err2 != nil do return false

	state.header.magic = SAVE_MAGIC
	state.header.version = CURRENT_SAVE_VERSION

	// generate non-zero cryptographic session token
	token: u64 = 0
	for token == 0 {
		token_buf: [8]u8
		crypto.rand_bytes(token_buf[:])
		token = (^u64)(&token_buf[0])^
	}
	state.header.session_token = token

	bytes := mem.byte_slice(state, size_of(Save_Data))

	// write to temp file first to ensure atomic swap
	if os.write_entire_file(tmp_path, bytes) != nil {
		return false
	}

	if os.rename(tmp_path, save_path) != nil {
		os.remove(tmp_path)
		return false
	}

	return true
}

load_game :: proc() -> (data: Save_Data, ok: bool, clean_session: bool) {
	dir, dir_ok := get_save_directory(context.temp_allocator)
	if !dir_ok do return {}, false, false

	save_path, path_err := filepath.join({dir, "save.dat"}, context.temp_allocator)
	if path_err != nil do return {}, false, false

	raw_bytes, read_err := os.read_entire_file(save_path, context.allocator)
	if read_err != nil do return {}, false, false
	defer delete(raw_bytes, context.allocator)

	if len(raw_bytes) != size_of(Save_Data) {
		return {}, false, false
	}

	loaded := (^Save_Data)(raw_data(raw_bytes))^

	if loaded.header.magic != SAVE_MAGIC {
		return {}, false, false
	}

	if loaded.header.version != CURRENT_SAVE_VERSION {
		return {}, false, false
	}

	clean_session = (loaded.header.session_token != 0)

	// invalidate active session on disk to detect crashes / alt-f4
	dirty_copy := loaded
	dirty_copy.header.session_token = 0
	dirty_bytes := mem.byte_slice(&dirty_copy, size_of(Save_Data))
	if os.write_entire_file(save_path, dirty_bytes) != nil {
		return {}, false, false
	}

	return loaded, true, clean_session
}

inventory_to_record :: proc(inv: ^Inventory) -> Inventory_Record {
	rec: Inventory_Record
	for item, i in inv.items {
		rec.items[i] = u8(item)
	}
	for slot in Equipment_Slot {
		rec.equipment[int(slot)] = u8(inv.equipment[slot])
	}
	return rec
}

record_to_inventory :: proc(rec: ^Inventory_Record) -> Inventory {
	inv: Inventory
	for b, i in rec.items {
		kind := Item_Kind(b)
		inv.items[i] = kind
		if kind != .None {
			inv.item_count += 1
		}
	}
	for slot in Equipment_Slot {
		inv.equipment[slot] = Item_Kind(rec.equipment[int(slot)])
	}
	return inv
}

auto_save_game :: proc(state: ^Game_State) -> bool {
	data := Save_Data {
		header = {
			magic = SAVE_MAGIC,
			version = CURRENT_SAVE_VERSION,
			session_token = 0,
			dungeon_seed = state.seed,
			turn_count = u64(max(0, state.turn_count)),
		},
		player = {
			pos_x = i32(state.player_x),
			pos_y = i32(state.player_y),
			hp = i32(state.player_hp),
			max_hp = i32(state.player_max_hp),
			gold = state.player_gold,
			dungeon_depth = i32(state.depth),
			inventory = inventory_to_record(&state.player_inventory),
		},
	}

	enemy_count := min(len(state.dungeon.enemies), MAX_ENEMIES_PER_FLOOR)
	data.enemy_count = u32(enemy_count)
	for i in 0 ..< enemy_count {
		e := &state.dungeon.enemies[i]
		data.enemies[i] = Enemy_Record {
			id        = i32(e.id),
			kind      = u8(e.kind),
			is_alive  = e.is_alive,
			x         = i32(e.x),
			y         = i32(e.y),
			hp        = i32(e.hp),
			max_hp    = i32(e.max_hp),
			inventory = inventory_to_record(&e.inventory),
		}
	}

	tile_count := min(len(state.dungeon.explored), DUNGEON_WIDTH * DUNGEON_HEIGHT)
	for i in 0 ..< tile_count {
		if state.dungeon.explored[i] {
			data.explored_tiles[i / 8] |= (1 << u8(i % 8))
		}
	}

	return save_game(&data)
}

delete_save_file :: proc() -> bool {
	dir, ok := get_save_directory(context.temp_allocator)
	if !ok do return false
	save_path, err := filepath.join({dir, "save.dat"}, context.temp_allocator)
	if err != nil do return false
	return os.remove(save_path) == nil
}

restore_game_from_save :: proc(save: ^Save_Data) -> Game_State {
	depth := int(save.player.dungeon_depth)
	if depth < 1 do depth = 1

	state := init_game(save.header.dungeon_seed)

	if depth != state.depth {
		if !(depth in state.floors) {
			cfg := default_dungeon_config(floor_seed(state.seed, depth), depth)
			state.floors[depth] = generate_dungeon(cfg)
		}
		state.depth = depth
		state.dungeon = state.floors[depth]
	}

	if save.enemy_count > 0 {
		clear(&state.dungeon.enemies)
		count := min(int(save.enemy_count), MAX_ENEMIES_PER_FLOOR)
		for i in 0 ..< count {
			rec := &save.enemies[i]
			enemy_inv := record_to_inventory(&rec.inventory)
			append(
				&state.dungeon.enemies,
				Enemy {
					id = int(rec.id),
					kind = Enemy_Kind(rec.kind),
					x = int(rec.x),
					y = int(rec.y),
					hp = int(rec.hp),
					max_hp = int(rec.max_hp),
					is_alive = rec.is_alive,
					inventory = enemy_inv,
				},
			)
		}
	}

	px := int(save.player.pos_x)
	py := int(save.player.pos_y)

	// ensure player position is walkable on the generated map
	tile := dungeon_get_tile(&state.dungeon, px, py)
	if !tile.walkable {
		// fall back to stairs up position or first room center
		if dungeon_get_tile(&state.dungeon, state.dungeon.stairs_up_pos.x, state.dungeon.stairs_up_pos.y).walkable {
			px = state.dungeon.stairs_up_pos.x
			py = state.dungeon.stairs_up_pos.y
		} else if len(state.dungeon.rooms) > 0 {
			px = state.dungeon.rooms[0].center_x
			py = state.dungeon.rooms[0].center_y
		}
	}

	state.player_x = px
	state.player_y = py
	state.player_inventory = record_to_inventory(&save.player.inventory)
	recompute_player_stats(&state)

	state.player_hp = int(save.player.hp)
	if state.player_hp > state.player_max_hp do state.player_hp = state.player_max_hp
	state.player_gold = save.player.gold
	state.turn_count = int(save.header.turn_count)

	tile_count := min(len(state.dungeon.explored), DUNGEON_WIDTH * DUNGEON_HEIGHT)
	for i in 0 ..< tile_count {
		byte_val := save.explored_tiles[i / 8]
		bit_mask := u8(1 << u8(i % 8))
		if (byte_val & bit_mask) != 0 {
			state.dungeon.explored[i] = true
		}
	}

	compute_fov(&state.dungeon, state.player_x, state.player_y)
	state.floors[state.depth] = state.dungeon

	return state
}
