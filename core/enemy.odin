package core

import "core:math/rand"

Enemy_Kind :: enum {
	Rat,
	Goblin,
	Skeleton,
	Orc,
}

Enemy_AI_Behavior :: enum {
	Melee_Chaser,
	Wanderer,
}

Enemy_Def :: struct {
	name:      string,
	symbol:    rune,
	color:     Color_RGB,
	max_hp:    int,
	attack:    int,
	defense:   int,
	fov_range: int,
	behavior:  Enemy_AI_Behavior,
	xp_value:  int,
}

ENEMY_DEFS := [Enemy_Kind]Enemy_Def {
	.Rat = {
		name = "Giant Rat",
		symbol = 'r',
		color = {180, 130, 90},
		max_hp = 4,
		attack = 2,
		defense = 0,
		fov_range = 6,
		behavior = .Melee_Chaser,
		xp_value = 5,
	},
	.Goblin = {
		name = "Goblin",
		symbol = 'g',
		color = {90, 200, 100},
		max_hp = 8,
		attack = 3,
		defense = 1,
		fov_range = 8,
		behavior = .Melee_Chaser,
		xp_value = 12,
	},
	.Skeleton = {
		name = "Skeleton",
		symbol = 's',
		color = {220, 220, 220},
		max_hp = 10,
		attack = 4,
		defense = 1,
		fov_range = 8,
		behavior = .Melee_Chaser,
		xp_value = 18,
	},
	.Orc = {
		name = "Orc Warrior",
		symbol = 'o',
		color = {210, 80, 50},
		max_hp = 16,
		attack = 6,
		defense = 2,
		fov_range = 9,
		behavior = .Melee_Chaser,
		xp_value = 30,
	},
}

Enemy :: struct {
	id:       int,
	kind:     Enemy_Kind,
	x:        int,
	y:        int,
	hp:       int,
	max_hp:   int,
	is_alive: bool,
}

Spawn_Entry :: struct {
	kind:      Enemy_Kind,
	weight:    int,
	min_depth: int,
}

SPAWN_TABLE := []Spawn_Entry{{.Rat, 60, 1}, {.Goblin, 35, 1}, {.Skeleton, 25, 2}, {.Orc, 15, 3}}

create_enemy :: proc(kind: Enemy_Kind, x, y, id: int) -> Enemy {
	def := ENEMY_DEFS[kind]
	return Enemy {
		id = id,
		kind = kind,
		x = x,
		y = y,
		hp = def.max_hp,
		max_hp = def.max_hp,
		is_alive = true,
	}
}

pick_random_enemy_kind :: proc(depth: int, rng: rand.Generator) -> Enemy_Kind {
	total_weight := 0
	for entry in SPAWN_TABLE {
		if depth >= entry.min_depth {
			total_weight += entry.weight
		}
	}

	if total_weight <= 0 {
		return .Rat
	}

	roll := rand.int_max(total_weight, rng)
	current := 0
	for entry in SPAWN_TABLE {
		if depth >= entry.min_depth {
			current += entry.weight
			if roll < current {
				return entry.kind
			}
		}
	}

	return .Rat
}
