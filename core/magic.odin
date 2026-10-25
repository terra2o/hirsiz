package core

import "core:fmt"
import "core:math/rand"

MAX_KNOWN_SPELLS :: 6

Spell_Target_Mode :: enum u8 {
	Nearest_Enemy,
	Area_Blast,
	Radial_Burst,
	Chain_Arc,
	Blink_Tile,
	Self_Berserk,
}

Spell_Kind :: enum u8 {
	None = 0,
	Magic_Dart,
	Foxfire,
	Freeze,
	Shock,
	Sandblast,
	Venom_Bolt,
	Vampiric_Drain,
	Blink,
	Searing_Ray,
	Stone_Arrow,
	Mystic_Blast,
	Ice_Blast,
	Fireball,
	Chain_Lightning,
	Berserk_Rage,
}

Spell_Def :: struct {
	kind:           Spell_Kind,
	name:           string,
	school:         string,
	mp_cost:        int,
	range:          int,
	power_cap:      int,
	pierce_defense: bool,
	target_mode:    Spell_Target_Mode,
	desc:           string,
}

SPELL_DEFS := [Spell_Kind]Spell_Def {
	.None = {},
	.Magic_Dart = {
		kind = .Magic_Dart,
		name = "Magic Dart",
		school = "Conjurations",
		mp_cost = 1,
		range = 7,
		power_cap = 25,
		pierce_defense = true,
		target_mode = .Nearest_Enemy,
		desc = "Fires an unerring bolt of pure magical force.",
	},
	.Foxfire = {
		kind = .Foxfire,
		name = "Foxfire",
		school = "Conjurations / Fire",
		mp_cost = 1,
		range = 1,
		power_cap = 25,
		pierce_defense = false,
		target_mode = .Nearest_Enemy,
		desc = "Summons two fleeting flame wisps that track nearby enemies.",
	},
	.Freeze = {
		kind = .Freeze,
		name = "Freeze",
		school = "Ice",
		mp_cost = 1,
		range = 1,
		power_cap = 25,
		pierce_defense = true,
		target_mode = .Nearest_Enemy,
		desc = "Chills an adjacent foe to the core, bypassing mundane armor.",
	},
	.Shock = {
		kind = .Shock,
		name = "Shock",
		school = "Conjurations / Air",
		mp_cost = 1,
		range = 7,
		power_cap = 25,
		pierce_defense = true,
		target_mode = .Nearest_Enemy,
		desc = "Discharges a bolt of electricity that rebounds from solid walls.",
	},
	.Sandblast = {
		kind = .Sandblast,
		name = "Sandblast",
		school = "Earth",
		mp_cost = 1,
		range = 4,
		power_cap = 50,
		pierce_defense = false,
		target_mode = .Nearest_Enemy,
		desc = "Sprays sharp grit and pebbles at a nearby target.",
	},
	.Venom_Bolt = {
		kind = .Venom_Bolt,
		name = "Venom Bolt",
		school = "Conjurations / Alchemy",
		mp_cost = 5,
		range = 5,
		power_cap = 200,
		pierce_defense = true,
		target_mode = .Nearest_Enemy,
		desc = "Launches a corrosive bolt of concentrated venom.",
	},
	.Vampiric_Drain = {
		kind = .Vampiric_Drain,
		name = "Vampiric Draining",
		school = "Necromancy",
		mp_cost = 3,
		range = 1,
		power_cap = 100,
		pierce_defense = true,
		target_mode = .Nearest_Enemy,
		desc = "Siphons vitality from an adjacent living foe into the caster.",
	},
	.Blink = {
		kind = .Blink,
		name = "Blink",
		school = "Translocations",
		mp_cost = 2,
		range = 7,
		power_cap = 50,
		pierce_defense = true,
		target_mode = .Blink_Tile,
		desc = "Instantly teleports the caster to a random visible safe tile.",
	},
	.Searing_Ray = {
		kind = .Searing_Ray,
		name = "Searing Ray",
		school = "Conjurations",
		mp_cost = 2,
		range = 4,
		power_cap = 50,
		pierce_defense = false,
		target_mode = .Nearest_Enemy,
		desc = "Directs an intense beam of concentrated energy through targets.",
	},
	.Stone_Arrow = {
		kind = .Stone_Arrow,
		name = "Stone Arrow",
		school = "Conjurations / Earth",
		mp_cost = 3,
		range = 4,
		power_cap = 50,
		pierce_defense = false,
		target_mode = .Nearest_Enemy,
		desc = "Hurls a razor-sharp shard of stone with high impact velocity.",
	},
	.Mystic_Blast = {
		kind = .Mystic_Blast,
		name = "Mystic Blast",
		school = "Conjurations / Translocations",
		mp_cost = 4,
		range = 2,
		power_cap = 100,
		pierce_defense = true,
		target_mode = .Radial_Burst,
		desc = "Detonates a ring of force, striking and knocking back nearby foes.",
	},
	.Ice_Blast = {
		kind = .Ice_Blast,
		name = "Iceblast",
		school = "Conjurations / Ice",
		mp_cost = 5,
		range = 5,
		power_cap = 200,
		pierce_defense = true,
		target_mode = .Area_Blast,
		desc = "Fires a brittle ice sphere that explodes into freezing shards.",
	},
	.Fireball = {
		kind = .Fireball,
		name = "Fireball",
		school = "Conjurations / Fire",
		mp_cost = 5,
		range = 5,
		power_cap = 200,
		pierce_defense = false,
		target_mode = .Area_Blast,
		desc = "Hurls a fiery orb detonating in an intense 3x3 blast.",
	},
	.Chain_Lightning = {
		kind = .Chain_Lightning,
		name = "Chain Lightning",
		school = "Conjurations / Air",
		mp_cost = 9,
		range = 7,
		power_cap = 200,
		pierce_defense = true,
		target_mode = .Chain_Arc,
		desc = "Calls down devastating lightning arcing repeatedly between targets.",
	},
	.Berserk_Rage = {
		kind = .Berserk_Rage,
		name = "Berserk Rage",
		school = "Invocations",
		mp_cost = 3,
		range = 0,
		power_cap = 0,
		pierce_defense = true,
		target_mode = .Self_Berserk,
		desc = "Channels ferocious combat fury, granting temporary hit points and attack power.",
	},
}

// rolls nds dice
roll_dice :: proc(num, size: int) -> int {
	if num <= 0 || size <= 0 do return 0
	total := 0
	for _ in 0 ..< num {
		total += 1 + int(rand.uint32() % u32(size))
	}
	return total
}

// divides max damage into dice count and rolls
calc_dice :: proc(num_dice, max_damage: int) -> int {
	if max_damage <= 0 do return 0
	if num_dice <= 1 do return roll_dice(1, max_damage)
	if max_damage <= num_dice do return roll_dice(max_damage, 1)

	rem := max_damage % num_dice
	size := max_damage / num_dice
	if rem > 0 && int(rand.uint32() % u32(num_dice)) < rem {
		size += 1
	}
	return roll_dice(num_dice, max(1, size))
}

// calculates spell power from caster intelligence
spell_power :: proc(state: ^Game_State, spell: Spell_Kind) -> int {
	def := SPELL_DEFS[spell]
	if def.power_cap <= 0 do return 0
	raw := max(1, state.player_int * 3)
	return min(def.power_cap, raw)
}

compute_spell_damage :: proc(state: ^Game_State, spell: Spell_Kind) -> int {
	pow := spell_power(state, spell)

	#partial switch spell {
	case .Magic_Dart:
		// 1d(3 + pow / 5)
		return max(1, roll_dice(1, 3 + pow / 5))

	case .Foxfire:
		// 1d(4 + pow / 5)
		return max(1, roll_dice(1, 4 + pow / 5))

	case .Freeze:
		// 1d(3 + 3*pow / 10)
		return max(1, roll_dice(1, 3 + (3 * pow) / 10))

	case .Shock:
		// 1d(3 + pow / 4)
		return max(1, roll_dice(1, 3 + pow / 4))

	case .Sandblast:
		// 2d(4 + pow / 3)
		return max(1, roll_dice(2, 4 + pow / 3))

	case .Stone_Arrow:
		// 3d(7 + pow / 8)
		return max(1, roll_dice(3, 7 + pow / 8))

	case .Searing_Ray:
		// calc_dice(2, 9 + pow / 7)
		return max(1, calc_dice(2, 9 + pow / 7))

	case .Mystic_Blast:
		// calc_dice(2, 6 + pow / 3)
		return max(1, calc_dice(2, 6 + pow / 3))

	case .Venom_Bolt:
		// calc_dice(4, 16 + 3*pow / 5)
		return max(1, calc_dice(4, 16 + (3 * pow) / 5))

	case .Ice_Blast:
		// calc_dice(3, 14 + 3*pow / 5)
		return max(1, calc_dice(3, 14 + (3 * pow) / 5))

	case .Fireball:
		// calc_dice(3, 10 + pow / 2)
		return max(1, calc_dice(3, 10 + pow / 2))

	case .Vampiric_Drain:
		// 2d(6 + pow / 14)
		return max(1, roll_dice(2, 6 + pow / 14))

	case .Chain_Lightning:
		// calc_dice(3, 2 * pow)
		return max(1, calc_dice(3, 2 * pow))

	case:
		return 0
	}
}

find_nearest_visible_enemy :: proc(state: ^Game_State, max_range: int) -> ^Enemy {
	d := &state.dungeon
	best_enemy: ^Enemy = nil
	best_dist_sq := max_range * max_range + 1

	for &enemy in d.enemies {
		if !enemy.is_alive do continue
		idx := enemy.y * d.width + enemy.x
		if idx < 0 || idx >= len(d.visible) || !d.visible[idx] do continue

		dx := enemy.x - state.player_x
		dy := enemy.y - state.player_y
		dist_sq := dx * dx + dy * dy
		if dist_sq <= max_range * max_range && dist_sq < best_dist_sq {
			best_dist_sq = dist_sq
			best_enemy = &enemy
		}
	}
	return best_enemy
}

damage_enemy_with_spell :: proc(
	state: ^Game_State,
	enemy: ^Enemy,
	raw_dmg: int,
	pierce_def: bool,
	spell_name: string,
) -> int {
	def := ENEMY_DEFS[enemy.kind]
	_, enemy_def := get_enemy_stats(enemy)
	damage := raw_dmg
	if !pierce_def {
		damage -= enemy_def / 2
	}
	if damage < 1 do damage = 1

	enemy.hp -= damage
	if enemy.hp <= 0 {
		enemy.is_alive = false
		award_enemy_loot_and_kill_msg(state, enemy, spell_name, damage)
	} else {
		push_message(
			state,
			fmt.tprintf(
				"%s hits %s for %d damage! (HP: %d/%d)",
				spell_name,
				def.name,
				damage,
				enemy.hp,
				enemy.max_hp,
			),
		)
	}
	return damage
}

cast_spell :: proc(state: ^Game_State, spell_slot: int) -> bool {
	if spell_slot < 0 || spell_slot >= state.spell_count do return false
	spell := state.known_spells[spell_slot]
	if spell == .None do return false

	def := SPELL_DEFS[spell]

	// self targeted spells, radial burst, and wisps do not require selecting an external tile
	if def.target_mode == .Self_Berserk ||
	   def.target_mode == .Blink_Tile ||
	   def.target_mode == .Radial_Burst ||
	   spell == .Foxfire {
		return cast_spell_at(state, spell_slot, state.player_x, state.player_y)
	}

	target := find_nearest_visible_enemy(state, def.range)
	if target == nil {
		push_message(
			state,
			fmt.tprintf("No visible target in range (%d) for %s.", def.range, def.name),
		)
		return false
	}
	return cast_spell_at(state, spell_slot, target.x, target.y)
}

cast_spell_at :: proc(state: ^Game_State, spell_slot: int, target_x, target_y: int) -> bool {
	if spell_slot < 0 || spell_slot >= state.spell_count do return false
	spell := state.known_spells[spell_slot]
	if spell == .None do return false

	def := SPELL_DEFS[spell]
	uses_hp := (state.player_species == .Djinni)

	if uses_hp {
		if state.player_hp <= def.mp_cost {
			push_message(state, fmt.tprintf("Not enough HP to cast %s!", def.name))
			return false
		}
	} else {
		if state.player_mp < def.mp_cost {
			push_message(
				state,
				fmt.tprintf("Not enough MP to cast %s! (Need %d MP)", def.name, def.mp_cost),
			)
			return false
		}
	}

	// validate range for targeted spells
	if def.target_mode == .Nearest_Enemy ||
	   def.target_mode == .Area_Blast ||
	   def.target_mode == .Chain_Arc {
		dx := abs(target_x - state.player_x)
		dy := abs(target_y - state.player_y)
		dist := max(dx, dy)
		if dist > def.range {
			push_message(
				state,
				fmt.tprintf("Target is beyond range (%d) for %s.", def.range, def.name),
			)
			return false
		}
		if def.range == 1 && dist == 0 {
			push_message(state, fmt.tprintf("Target must be adjacent for %s.", def.name))
			return false
		}
	}

	switch def.target_mode {
	case .Nearest_Enemy, .Area_Blast, .Chain_Arc:
		// foxfire spawns dual homing wisps on adjacent open spaces
		if spell == .Foxfire {
			if !spawn_foxfire_wisps(state, spell) {
				return false
			}
			consume_spell_cost(state, def.mp_cost, uses_hp)
			state.projectile_timer = 0
		} else {
			proj, ok := create_spell_projectile(state, spell, target_x, target_y)
			if !ok do return false
			consume_spell_cost(state, def.mp_cost, uses_hp)

			if state.projectile_count < MAX_ACTIVE_PROJECTILES {
				state.active_projectiles[state.projectile_count] = proj
				state.projectile_count += 1
			}
			state.projectile_timer = 0
			push_message(state, fmt.tprintf("You cast %s!", def.name))
		}

	case .Radial_Burst:
		// detonates force wave centered on caster hitting all foes within range
		consume_spell_cost(state, def.mp_cost, uses_hp)
		push_message(
			state,
			fmt.tprintf("You cast %s! A ring of force erupts around you!", def.name),
		)

		d := &state.dungeon
		hit_any := false
		dmg := compute_spell_damage(state, spell)

		// hit enemies within range in expanding order
		for radius in 1 ..= def.range {
			for dy in -radius ..= radius {
				for dx in -radius ..= radius {
					if max(abs(dx), abs(dy)) != radius do continue
					nx := state.player_x + dx
					ny := state.player_y + dy
					if !dungeon_in_bounds(d, nx, ny) do continue
					enemy := find_enemy_at(d, nx, ny)
					if enemy != nil && enemy.is_alive {
						damage_enemy_with_spell(state, enemy, dmg, def.pierce_defense, def.name)
						hit_any = true

						// knock back 1 tile away from caster if open
						kx := enemy.x + (dx > 0 ? 1 : (dx < 0 ? -1 : 0))
						ky := enemy.y + (dy > 0 ? 1 : (dy < 0 ? -1 : 0))
						if dungeon_in_bounds(d, kx, ky) {
							ktile := dungeon_get_tile(d, kx, ky)
							if ktile.walkable &&
							   find_enemy_at(d, kx, ky) == nil &&
							   !(kx == state.player_x && ky == state.player_y) {
								enemy.x = kx
								enemy.y = ky
							}
						}
					}
				}
			}
		}

	case .Blink_Tile:
		d := &state.dungeon
		candidates: [64][2]int
		cand_count := 0
		for dy in -def.range ..= def.range {
			for dx in -def.range ..= def.range {
				if dx == 0 && dy == 0 do continue
				dist_sq := dx * dx + dy * dy
				if dist_sq < 4 || dist_sq > def.range * def.range do continue
				nx := state.player_x + dx
				ny := state.player_y + dy
				if nx < 0 || nx >= d.width || ny < 0 || ny >= d.height do continue
				idx := ny * d.width + nx
				if !d.visible[idx] do continue
				if !is_tile_blocked(state, nx, ny) && cand_count < len(candidates) {
					candidates[cand_count] = {nx, ny}
					cand_count += 1
				}
			}
		}
		if cand_count == 0 {
			push_message(state, "There is no safe space to blink to!")
			return false
		}
		consume_spell_cost(state, def.mp_cost, uses_hp)
		pick := int(generate_random_seed() % u64(cand_count))
		state.player_x = candidates[pick][0]
		state.player_y = candidates[pick][1]
		compute_fov(&state.dungeon, state.player_x, state.player_y, player_fov_radius(state))
		push_message(state, "You blink through space!")

	case .Self_Berserk:
		consume_spell_cost(state, def.mp_cost, uses_hp)
		heal := 5 + state.player_str / 3
		state.player_hp = min(state.player_max_hp, state.player_hp + heal)
		state.berserk_turns = 8
		recompute_player_stats(state)
		push_message(
			state,
			fmt.tprintf("A red film covers your vision! (+%d HP, +4 Attack for 8 turns)", heal),
		)
	}

	state.player_last_attack = 0
	state.turn_count += 1

	// if a direct projectile was launched, let the animation step it across frames
	if has_flying_projectiles(state) {
		state.floors[state.depth] = state.dungeon
		return true
	}

	step_all_projectiles(state)
	step_enemy_turns(state)
	state.floors[state.depth] = state.dungeon
	return true
}

consume_spell_cost :: proc(state: ^Game_State, cost: int, uses_hp: bool) {
	if uses_hp {
		state.player_hp = max(1, state.player_hp - cost)
	} else {
		state.player_mp = max(0, state.player_mp - cost)
	}
}
