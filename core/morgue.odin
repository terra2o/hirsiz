package core

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"

MORGUE_MAGIC :: [4]u8{'M', 'O', 'R', 'G'}
CURRENT_MORGUE_VERSION: u32 : 1
MAX_MORGUE_ENTRIES :: 24
MAX_KILLER_LEN :: 28

Morgue_Entry :: struct #packed {
	name:       [MAX_NAME_LEN]u8,
	name_len:   u8,
	species:    u8,
	background: u8,
	killer_len: u8,
	killer:     [MAX_KILLER_LEN]u8,
	score:      u32,
	gold:       u32,
	depth:      i32,
	turns:      u32,
	seed:       u64,
}

Morgue_File :: struct #packed {
	magic:   [4]u8,
	version: u32,
	count:   u32,
	entries: [MAX_MORGUE_ENTRIES]Morgue_Entry,
}

compute_run_score :: proc(state: ^Game_State) -> u32 {
	depth_pts := u32(max(1, state.depth)) * 150
	gold_pts := state.player_gold * 5
	turn_pts := u32(min(500, max(0, state.turn_count / 4)))
	return depth_pts + gold_pts + turn_pts
}

load_morgue :: proc() -> Morgue_File {
	res := Morgue_File {
		magic   = MORGUE_MAGIC,
		version = CURRENT_MORGUE_VERSION,
	}

	dir, ok := get_save_directory(context.temp_allocator)
	if !ok do return res

	path, err := filepath.join({dir, "morgue.dat"}, context.temp_allocator)
	if err != nil do return res

	raw_bytes, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil do return res
	defer delete(raw_bytes, context.allocator)

	if len(raw_bytes) != size_of(Morgue_File) do return res

	loaded := (^Morgue_File)(raw_data(raw_bytes))^
	if loaded.magic != MORGUE_MAGIC || loaded.version != CURRENT_MORGUE_VERSION {
		return res
	}
	if loaded.count > MAX_MORGUE_ENTRIES {
		loaded.count = MAX_MORGUE_ENTRIES
	}
	return loaded
}

record_morgue_entry :: proc(state: ^Game_State) -> Morgue_Entry {
	entry := Morgue_Entry {
		name       = state.player_name,
		name_len   = state.player_name_len,
		species    = u8(state.player_species),
		background = u8(state.player_background),
		score      = compute_run_score(state),
		gold       = state.player_gold,
		depth      = i32(state.depth),
		turns      = u32(max(0, state.turn_count)),
		seed       = state.seed,
	}

	killer_str := state.last_killer_name
	if len(killer_str) == 0 {
		killer_str = "misadventure"
	}
	k_len := min(len(killer_str), MAX_KILLER_LEN - 1)
	for i in 0 ..< k_len {
		entry.killer[i] = killer_str[i]
	}
	entry.killer_len = u8(k_len)

	morgue := load_morgue()

	// insert sorted by descending score
	insert_idx := int(morgue.count)
	for i in 0 ..< int(morgue.count) {
		if entry.score >= morgue.entries[i].score {
			insert_idx = i
			break
		}
	}

	if insert_idx < MAX_MORGUE_ENTRIES {
		new_count := min(int(morgue.count) + 1, MAX_MORGUE_ENTRIES)
		for i := new_count - 1; i > insert_idx; i -= 1 {
			morgue.entries[i] = morgue.entries[i - 1]
		}
		morgue.entries[insert_idx] = entry
		morgue.count = u32(new_count)
	}

	if dir, ok := get_save_directory(context.temp_allocator); ok {
		if path, err := filepath.join({dir, "morgue.dat"}, context.temp_allocator); err == nil {
			bytes := mem.byte_slice(&morgue, size_of(Morgue_File))
			_ = os.write_entire_file(path, bytes)
		}
	}

	return entry
}

format_morgue_line :: proc(rank: int, e: ^Morgue_Entry) -> string {
	p_name := character_name_str(&e.name, e.name_len)
	sp := Species(min(int(e.species), SPECIES_COUNT - 1))
	bg := Background(min(int(e.background), BACKGROUND_COUNT - 1))
	k_len := min(int(e.killer_len), MAX_KILLER_LEN)
	killer := k_len > 0 ? string(e.killer[:k_len]) : "unknown"

	return fmt.tprintf(
		"%2d. %5d pts - %s the %s %s (%s%s), slain by %s on D:%d (T:%d)",
		rank,
		e.score,
		p_name,
		SPECIES_DEFS[sp].name,
		BACKGROUND_DEFS[bg].name,
		SPECIES_DEFS[sp].abbrev,
		BACKGROUND_DEFS[bg].abbrev,
		killer,
		e.depth,
		e.turns,
	)
}
