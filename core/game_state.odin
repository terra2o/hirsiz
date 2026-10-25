package core

import "core:crypto"
import "core:fmt"
import "core:strings"

floor_seed :: proc(base_seed: u64, depth: int) -> u64 {
	z := base_seed ~ (u64(depth) * 0x9e3779b97f4a7c15)
	z = (z ~ (z >> 30)) * 0xbf58476d1ce4e5b9
	z = (z ~ (z >> 27)) * 0x94d049bb133111eb
	res := z ~ (z >> 31)
	if res == 0 do res = 1
	return res
}

generate_random_seed :: proc() -> u64 {
	buf: [8]u8
	crypto.rand_bytes(buf[:])
	token := (^u64)(&buf[0])^
	if token == 0 do token = 1337
	return token
}

Game_State :: struct {
	seed:               u64,
	player_name:        [MAX_NAME_LEN]u8,
	player_name_len:    u8,
	player_species:     Species,
	player_background:  Background,
	player_x:           int,
	player_y:           int,
	player_hp:          int,
	player_max_hp:      int,
	player_base_max_hp: int,
	player_mp:          int,
	player_max_mp:      int,
	player_base_max_mp: int,
	player_base_str:    int,
	player_base_int:    int,
	player_base_dex:    int,
	player_str:         int,
	player_int:         int,
	player_dex:         int,
	player_gold:        u32,
	player_base_attack: int,
	player_base_def:    int,
	player_attack:      int,
	player_defense:     int,
	player_last_attack: int,
	berserk_turns:      int,
	player_inventory:   Inventory,
	known_spells:       [MAX_KNOWN_SPELLS]Spell_Kind,
	spell_count:        int,
	selected_spell:     int,
	depth:              int,
	turn_count:         int,
	is_running:         bool,
	last_killer_name:   string,
	status_message:     string,
	message_history:    [8]string,
	message_count:      int,
	is_targeting:       bool,
	target_x:           int,
	target_y:           int,
	active_projectiles: [MAX_ACTIVE_PROJECTILES]Projectile,
	projectile_count:   int,
	projectile_timer:   f32,
	dungeon:            Dungeon,
	floors:             map[int]Dungeon,
}

player_fov_radius :: proc(state: ^Game_State) -> int {
	if state.player_species == .Barachi {
		return 10
	}
	return 8
}

push_message :: proc(state: ^Game_State, msg: string) {
	if len(msg) == 0 do return

	// free the previous status message if it's not shared with history,
	// or just let status_message point to the latest history entry
	cloned_msg := strings.clone(msg)
	state.status_message = cloned_msg

	if state.message_count < len(state.message_history) {
		state.message_history[state.message_count] = cloned_msg
		state.message_count += 1
	} else {
		// prevent leaking the oldest message before shifting it out
		delete(state.message_history[0])

		for i in 0 ..< len(state.message_history) - 1 {
			state.message_history[i] = state.message_history[i + 1]
		}
		state.message_history[len(state.message_history) - 1] = cloned_msg
	}
}

recompute_player_stats :: proc(state: ^Game_State) {
	att_b, def_b, hp_b, int_b, mp_b := inventory_stat_bonuses(&state.player_inventory)
	sp_def := SPECIES_DEFS[state.player_species]

	state.player_str = state.player_base_str
	state.player_int = state.player_base_int + int_b
	state.player_dex = state.player_base_dex

	// derive base combat power from attributes and species traits
	state.player_base_attack = max(1, 1 + state.player_str / 3 + sp_def.innate_att)
	state.player_base_def = max(0, state.player_dex / 4 + sp_def.innate_def)

	berserk_bonus := state.berserk_turns > 0 ? 4 : 0
	state.player_attack = state.player_base_attack + att_b + berserk_bonus
	state.player_defense = state.player_base_def + def_b

	old_max := state.player_max_hp
	state.player_max_hp = max(1, state.player_base_max_hp + hp_b)
	if old_max > 0 && state.player_max_hp > old_max {
		state.player_hp += (state.player_max_hp - old_max)
	}
	if state.player_hp > state.player_max_hp {
		state.player_hp = state.player_max_hp
	}

	if state.player_species == .Djinni {
		state.player_max_mp = 0
		state.player_mp = 0
	} else {
		old_mp_max := state.player_max_mp
		state.player_max_mp = max(0, state.player_base_max_mp + mp_b + int_b / 2)
		if old_mp_max > 0 && state.player_max_mp > old_mp_max {
			state.player_mp += (state.player_max_mp - old_mp_max)
		}
		if state.player_mp > state.player_max_mp {
			state.player_mp = state.player_max_mp
		}
	}
}

get_enemy_stats :: proc(enemy: ^Enemy) -> (attack: int, defense: int) {
	def := ENEMY_DEFS[enemy.kind]
	att_b, def_b, _, _, _ := inventory_stat_bonuses(&enemy.inventory)
	return def.attack + att_b, def.defense + def_b
}

learn_spell :: proc(state: ^Game_State, spell: Spell_Kind) -> bool {
	if spell == .None do return false
	for i in 0 ..< state.spell_count {
		if state.known_spells[i] == spell do return false
	}
	if state.spell_count >= MAX_KNOWN_SPELLS do return false
	state.known_spells[state.spell_count] = spell
	state.spell_count += 1
	return true
}

init_game :: proc(seed: u64 = 0, char_cfg: Maybe(Character_Config) = nil) -> Game_State {
	cfg := default_character_config()
	if c, has_cfg := char_cfg.?; has_cfg {
		cfg = c
	}

	actual_seed := seed
	if actual_seed == 0 {
		actual_seed = cfg.seed
	}
	if actual_seed == 0 {
		actual_seed = generate_random_seed()
	}

	floors := make(map[int]Dungeon)

	depth := 1
	d_cfg := default_dungeon_config(floor_seed(actual_seed, depth), depth)
	dung := generate_dungeon(d_cfg)
	floors[depth] = dung

	spawn_x := dung.stairs_up_pos.x
	spawn_y := dung.stairs_up_pos.y

	if spawn_x == 0 && spawn_y == 0 && len(dung.rooms) > 0 {
		spawn_x = dung.rooms[0].center_x
		spawn_y = dung.rooms[0].center_y
	}

	str, intel, dex, max_hp, max_mp := compute_starting_stats(cfg.species, cfg.background)

	// wanderer background adds small random attribute twist
	if cfg.background == .Wanderer {
		twist := int(actual_seed % 3)
		if twist == 0 {
			str += 2; intel -= 1
		} else if twist == 1 {
			intel += 2; dex -= 1
		} else {
			dex += 2; str -= 1
		}
	}

	state := Game_State {
		seed               = actual_seed,
		player_name        = cfg.name,
		player_name_len    = cfg.name_len,
		player_species     = cfg.species,
		player_background  = cfg.background,
		player_x           = spawn_x,
		player_y           = spawn_y,
		player_hp          = max_hp,
		player_max_hp      = max_hp,
		player_base_max_hp = max_hp,
		player_mp          = max_mp,
		player_max_mp      = max_mp,
		player_base_max_mp = max_mp,
		player_base_str    = str,
		player_base_int    = intel,
		player_base_dex    = dex,
		player_str         = str,
		player_int         = intel,
		player_dex         = dex,
		player_gold        = 0,
		depth              = depth,
		turn_count         = 0,
		is_running         = true,
		dungeon            = dung,
		floors             = floors,
	}

	compute_fov(&state.dungeon, spawn_x, spawn_y, player_fov_radius(&state))
	state.floors[depth] = state.dungeon

	bg_def := BACKGROUND_DEFS[cfg.background]
	for eq_item in bg_def.starting_eq {
		if eq_item != .None {
			// felids cannot wear body/head/foot armor
			if cfg.species == .Felid {
				item_d := ITEM_DEFS[eq_item]
				if item_d.slot != .Ring && item_d.slot != .Amulet {
					continue
				}
			}
			force_equip(&state.player_inventory, eq_item)
		}
	}
	for bag_item in bg_def.starting_bag {
		if bag_item != .None {
			inventory_add(&state.player_inventory, bag_item)
		}
	}
	for sp in bg_def.spells {
		if sp != .None {
			learn_spell(&state, sp)
		}
	}

	if cfg.background == .Wanderer {
		rand_spells := [?]Spell_Kind {
			.Magic_Dart,
			.Foxfire,
			.Freeze,
			.Shock,
			.Sandblast,
			.Blink,
			.Vampiric_Drain,
		}
		s1 := rand_spells[int(actual_seed % u64(len(rand_spells)))]
		s2 := rand_spells[int((actual_seed >> 4) % u64(len(rand_spells)))]
		learn_spell(&state, s1)
		learn_spell(&state, s2)
	}

	recompute_player_stats(&state)
	state.player_hp = state.player_max_hp
	state.player_mp = state.player_max_mp

	p_name := character_name_str(&state.player_name, state.player_name_len)
	welcome_msg := fmt.tprintf(
		"Welcome, %s the %s %s! Press ? for help or z to cast spells.",
		p_name,
		SPECIES_DEFS[cfg.species].name,
		BACKGROUND_DEFS[cfg.background].name,
	)
	push_message(&state, welcome_msg)

	return state
}

destroy_game :: proc(state: ^Game_State) {
	for depth, &dung in state.floors {
		destroy_dungeon(&dung)
	}
	delete(state.floors)
	state.floors = nil
}

find_enemy_at :: proc(d: ^Dungeon, x, y: int) -> ^Enemy {
	for &enemy in d.enemies {
		if enemy.is_alive && enemy.x == x && enemy.y == y {
			return &enemy
		}
	}
	return nil
}

is_tile_blocked :: proc(state: ^Game_State, x, y: int) -> bool {
	tile := dungeon_get_tile(&state.dungeon, x, y)
	if !tile.walkable do return true
	if x == state.player_x && y == state.player_y do return true
	if find_enemy_at(&state.dungeon, x, y) != nil do return true
	return false
}

award_enemy_loot_and_kill_msg :: proc(
	state: ^Game_State,
	enemy: ^Enemy,
	source_label: string,
	damage: int,
) {
	def := ENEMY_DEFS[enemy.kind]
	gold_gain := u32(max(1, def.xp_value / 3))
	state.player_gold += gold_gain

	loot_item: Item_Kind = .None
	for slot in Equipment_Slot {
		if enemy.inventory.equipment[slot] != .None {
			loot_item = enemy.inventory.equipment[slot]
			break
		}
	}
	if loot_item == .None && enemy.inventory.item_count > 0 {
		for it in enemy.inventory.items {
			if it != .None {
				loot_item = it
				break
			}
		}
	}

	if loot_item != .None {
		drop_item_on_ground(&state.dungeon, loot_item, enemy.x, enemy.y)
		item_d := ITEM_DEFS[loot_item]
		push_message(
			state,
			fmt.tprintf("You kill %s! It drops %s (+%d gold).", def.name, item_d.name, gold_gain),
		)
	} else {
		push_message(
			state,
			fmt.tprintf(
				"%s hits %s for %d damage and kills it! (+%d gold)",
				source_label,
				def.name,
				damage,
				gold_gain,
			),
		)
	}
}

player_attack :: proc(state: ^Game_State, enemy: ^Enemy) {
	def := ENEMY_DEFS[enemy.kind]
	_, enemy_def := get_enemy_stats(enemy)
	damage := state.player_attack - enemy_def
	if damage < 1 do damage = 1

	enemy.hp -= damage
	if enemy.hp <= 0 {
		enemy.is_alive = false
		award_enemy_loot_and_kill_msg(state, enemy, "Your attack", damage)
	} else {
		push_message(
			state,
			fmt.tprintf(
				"You attack %s for %d damage. (HP: %d/%d)",
				def.name,
				damage,
				enemy.hp,
				enemy.max_hp,
			),
		)
	}
}

step_enemy_turns :: proc(state: ^Game_State) {
	if state.berserk_turns > 0 {
		state.berserk_turns -= 1
		if state.berserk_turns == 0 {
			recompute_player_stats(state)
			push_message(state, "Your berserk rage subsides.")
		}
	}

	d := &state.dungeon
	for &enemy in d.enemies {
		if !enemy.is_alive do continue

		def := ENEMY_DEFS[enemy.kind]
		enemy_att, _ := get_enemy_stats(&enemy)
		dx := state.player_x - enemy.x
		dy := state.player_y - enemy.y
		dist_sq := dx * dx + dy * dy

		if abs(dx) <= 1 && abs(dy) <= 1 {
			damage := enemy_att - state.player_defense
			if damage < 1 do damage = 1
			state.player_hp -= damage
			state.player_last_attack = 0
			if state.player_hp <= 0 {
				state.player_hp = 0
				state.last_killer_name = def.name
				push_message(
					state,
					fmt.tprintf("%s attacks you for %d damage. You died!", def.name, damage),
				)
				state.is_running = false
				return
			} else {
				push_message(state, fmt.tprintf("%s attacks you for %d damage!", def.name, damage))
			}
			continue
		}

		max_dist := def.fov_range
		if dist_sq <= max_dist * max_dist {
			step_x := 0
			step_y := 0
			if dx > 0 do step_x = 1
			else if dx < 0 do step_x = -1

			if dy > 0 do step_y = 1
			else if dy < 0 do step_y = -1

			if abs(dx) >= abs(dy) {
				if step_x != 0 && !is_tile_blocked(state, enemy.x + step_x, enemy.y) {
					enemy.x += step_x
				} else if step_y != 0 && !is_tile_blocked(state, enemy.x, enemy.y + step_y) {
					enemy.y += step_y
				}
			} else {
				if step_y != 0 && !is_tile_blocked(state, enemy.x, enemy.y + step_y) {
					enemy.y += step_y
				} else if step_x != 0 && !is_tile_blocked(state, enemy.x + step_x, enemy.y) {
					enemy.x += step_x
				}
			}
		}
	}
}

player_regen :: proc(state: ^Game_State) {
	if state.player_hp < state.player_max_hp {
		regen_amt := 1
		if state.player_species == .Troll || state.player_species == .Vine_Stalker {
			regen_amt = 2
		}
		state.player_hp = min(state.player_max_hp, state.player_hp + regen_amt)
	}
	if state.player_mp < state.player_max_mp {
		state.player_mp = min(state.player_max_mp, state.player_mp + 1)
	}
}

check_regen :: proc(state: ^Game_State) {
	threshold := 10
	if state.player_species == .Troll || state.player_species == .Vine_Stalker {
		threshold = 6
	}
	if state.player_last_attack >= threshold {
		player_regen(state)
	} else if state.turn_count % 4 == 0 && state.player_mp < state.player_max_mp {
		state.player_mp += 1
	}
}

step_turn :: proc(state: ^Game_State, dx: int, dy: int) {
	new_x := state.player_x + dx
	new_y := state.player_y + dy

	state.player_last_attack += 1

	target_enemy := find_enemy_at(&state.dungeon, new_x, new_y)
	if target_enemy != nil {
		player_attack(state, target_enemy)
		state.player_last_attack = 0
		state.turn_count += 1
		step_all_projectiles(state)
		step_enemy_turns(state)
		state.floors[state.depth] = state.dungeon
		return
	}

	target_tile := dungeon_get_tile(&state.dungeon, new_x, new_y)

	if target_tile.type == .Door_Closed {
		dungeon_set_tile(&state.dungeon, new_x, new_y, .Door_Open)
		compute_fov(&state.dungeon, state.player_x, state.player_y, player_fov_radius(state))
		state.turn_count += 1
		push_message(state, "You open the door.")
		step_all_projectiles(state)
		step_enemy_turns(state)
		state.floors[state.depth] = state.dungeon
		return
	}

	if target_tile.walkable {
		state.player_x = new_x
		state.player_y = new_y
		compute_fov(&state.dungeon, state.player_x, state.player_y, player_fov_radius(state))
		state.turn_count += 1

		#partial switch target_tile.type {
		case .Stairs_Down:
			push_message(state, "There is a staircase leading down here (press > to descend).")
		case .Stairs_Up:
			push_message(state, "There is a staircase leading up here (press < to ascend).")
		}

		item_count_here := ground_items_count_at(&state.dungeon, state.player_x, state.player_y)
		if item_count_here == 1 {
			for it in state.dungeon.ground_items {
				if it.x == state.player_x && it.y == state.player_y {
					push_message(
						state,
						fmt.tprintf("You see %s here (press ',' to pick up).", ITEM_DEFS[it.kind].name),
					)
					break
				}
			}
		} else if item_count_here > 1 {
			push_message(
				state,
				fmt.tprintf(
					"There are %d items here (press ',' to pick up).",
					item_count_here,
				),
			)
		}

		check_regen(state)
		step_all_projectiles(state)
		step_enemy_turns(state)
		state.floors[state.depth] = state.dungeon
	}
}

// descend stairs to next level
go_down_stairs :: proc(state: ^Game_State) -> bool {
	current_tile := dungeon_get_tile(&state.dungeon, state.player_x, state.player_y)
	if current_tile.type != .Stairs_Down {
		push_message(state, "You can't go down here. (Find a > staircase)")
		return false
	}

	state.floors[state.depth] = state.dungeon

	target_depth := state.depth + 1
	if !(target_depth in state.floors) {
		cfg := default_dungeon_config(floor_seed(state.seed, target_depth), target_depth)
		state.floors[target_depth] = generate_dungeon(cfg)
	}

	state.depth = target_depth
	state.dungeon = state.floors[target_depth]

	state.player_x = state.dungeon.stairs_up_pos.x
	state.player_y = state.dungeon.stairs_up_pos.y

	compute_fov(&state.dungeon, state.player_x, state.player_y, player_fov_radius(state))
	state.floors[state.depth] = state.dungeon

	state.turn_count += 1
	push_message(state, "You descend deeper into the dungeon.")
	return true
}

// ascend stairs to previous level
go_up_stairs :: proc(state: ^Game_State) -> bool {
	current_tile := dungeon_get_tile(&state.dungeon, state.player_x, state.player_y)
	if current_tile.type != .Stairs_Up {
		push_message(state, "You can't go up here. (Find a < staircase)")
		return false
	}

	if state.depth <= 1 {
		push_message(state, "You are already at the dungeon entrance! You cannot leave yet.")
		return false
	}

	state.floors[state.depth] = state.dungeon

	target_depth := state.depth - 1
	state.depth = target_depth
	state.dungeon = state.floors[target_depth]

	state.player_x = state.dungeon.stairs_down_pos.x
	state.player_y = state.dungeon.stairs_down_pos.y

	compute_fov(&state.dungeon, state.player_x, state.player_y, player_fov_radius(state))
	state.floors[state.depth] = state.dungeon

	state.turn_count += 1
	push_message(state, "You climb back up the stairs.")
	return true
}

// player attempts to pick up an item on the current tile
player_pick_up :: proc(state: ^Game_State) -> bool {
	// look backwards from end to pick up most recently dropped item
	found_idx := -1
	for i := len(state.dungeon.ground_items) - 1; i >= 0; i -= 1 {
		it := state.dungeon.ground_items[i]
		if it.x == state.player_x && it.y == state.player_y {
			found_idx = i
			break
		}
	}

	if found_idx == -1 {
		push_message(state, "There is nothing here to pick up.")
		return false
	}

	item := state.dungeon.ground_items[found_idx].kind
	item_name := ITEM_DEFS[item].name

	if state.player_inventory.item_count >= MAX_INVENTORY_ITEMS {
		push_message(state, fmt.tprintf("Your inventory is full! Cannot pick up %s.", item_name))
		return false
	}

	if !inventory_add(&state.player_inventory, item) {
		push_message(state, "Your inventory is full!")
		return false
	}

	ordered_remove(&state.dungeon.ground_items, found_idx)
	push_message(state, fmt.tprintf("You pick up %s.", item_name))

	state.turn_count += 1
	check_regen(state)
	step_all_projectiles(state)
	step_enemy_turns(state)
	state.floors[state.depth] = state.dungeon
	return true
}

// player drops an item from inventory to the ground
player_drop_item :: proc(state: ^Game_State, inv_idx: int) -> bool {
	if inv_idx < 0 || inv_idx >= MAX_INVENTORY_ITEMS do return false
	item := inventory_remove_at(&state.player_inventory, inv_idx)
	if item == .None do return false

	item_name := ITEM_DEFS[item].name
	drop_item_on_ground(&state.dungeon, item, state.player_x, state.player_y)
	push_message(state, fmt.tprintf("You drop %s.", item_name))

	state.turn_count += 1
	check_regen(state)
	step_all_projectiles(state)
	step_enemy_turns(state)
	state.floors[state.depth] = state.dungeon
	return true
}

