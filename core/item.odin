package core

import "core:fmt"

Equipment_Slot :: enum u8 {
	Head, // helmet / coif / cap
	Torso, // armor / tunic / chainmail
	Legs, // greaves / pants / leggings
	Feet, // boots / shoes
	Weapon, // sword / dagger / mace
	Shield, // buckler / kite shield
	Ring, // ring of protection / power
	Amulet, // amulet / necklace
}

EQUIPMENT_SLOT_COUNT :: 8

Item_Kind :: enum u8 {
	None = 0,
	Rusty_Dagger,
	Iron_Shortsword,
	Steel_Broadsword,
	Battle_Axe,
	Leather_Cap,
	Iron_Helmet,
	Steel_Full_Helm,
	Cloth_Tunic,
	Leather_Armor,
	Chainmail,
	Plate_Armor,
	Cloth_Pants,
	Leather_Leggings,
	Plate_Greaves,
	Leather_Boots,
	Iron_Boots,
	Wooden_Shield,
	Iron_Shield,
	Ring_Of_Protection,
	Ring_Of_Might,
	Amulet_Of_Vitality,
	Health_Potion,
}

Item_Category :: enum u8 {
	Equipment,
	Consumable,
	Misc,
}

Item_Def :: struct {
	kind:          Item_Kind,
	name:          string,
	category:      Item_Category,
	slot:          Equipment_Slot,
	attack_bonus:  int,
	defense_bonus: int,
	hp_bonus:      int,
	heal_amount:   int,
}

ITEM_DEFS := [Item_Kind]Item_Def {
	.None = {},
	.Rusty_Dagger = {
		kind = .Rusty_Dagger,
		name = "Rusty Dagger",
		category = .Equipment,
		slot = .Weapon,
		attack_bonus = 2,
	},
	.Iron_Shortsword = {
		kind = .Iron_Shortsword,
		name = "Iron Shortsword",
		category = .Equipment,
		slot = .Weapon,
		attack_bonus = 4,
	},
	.Steel_Broadsword = {
		kind = .Steel_Broadsword,
		name = "Steel Broadsword",
		category = .Equipment,
		slot = .Weapon,
		attack_bonus = 7,
	},
	.Battle_Axe = {
		kind = .Battle_Axe,
		name = "Battle Axe",
		category = .Equipment,
		slot = .Weapon,
		attack_bonus = 10,
	},
	.Leather_Cap = {
		kind = .Leather_Cap,
		name = "Leather Cap",
		category = .Equipment,
		slot = .Head,
		defense_bonus = 1,
	},
	.Iron_Helmet = {
		kind = .Iron_Helmet,
		name = "Iron Helmet",
		category = .Equipment,
		slot = .Head,
		defense_bonus = 2,
	},
	.Steel_Full_Helm = {
		kind = .Steel_Full_Helm,
		name = "Steel Full Helm",
		category = .Equipment,
		slot = .Head,
		defense_bonus = 3,
		hp_bonus = 2,
	},
	.Cloth_Tunic = {
		kind = .Cloth_Tunic,
		name = "Cloth Tunic",
		category = .Equipment,
		slot = .Torso,
		defense_bonus = 1,
	},
	.Leather_Armor = {
		kind = .Leather_Armor,
		name = "Leather Armor",
		category = .Equipment,
		slot = .Torso,
		defense_bonus = 2,
	},
	.Chainmail = {
		kind = .Chainmail,
		name = "Chainmail Armor",
		category = .Equipment,
		slot = .Torso,
		defense_bonus = 4,
	},
	.Plate_Armor = {
		kind = .Plate_Armor,
		name = "Plate Armor",
		category = .Equipment,
		slot = .Torso,
		defense_bonus = 6,
	},
	.Cloth_Pants = {
		kind = .Cloth_Pants,
		name = "Cloth Pants",
		category = .Equipment,
		slot = .Legs,
		defense_bonus = 0,
	},
	.Leather_Leggings = {
		kind = .Leather_Leggings,
		name = "Leather Leggings",
		category = .Equipment,
		slot = .Legs,
		defense_bonus = 1,
	},
	.Plate_Greaves = {
		kind = .Plate_Greaves,
		name = "Plate Greaves",
		category = .Equipment,
		slot = .Legs,
		defense_bonus = 3,
	},
	.Leather_Boots = {
		kind = .Leather_Boots,
		name = "Leather Boots",
		category = .Equipment,
		slot = .Feet,
		defense_bonus = 1,
	},
	.Iron_Boots = {
		kind = .Iron_Boots,
		name = "Iron Boots",
		category = .Equipment,
		slot = .Feet,
		defense_bonus = 2,
	},
	.Wooden_Shield = {
		kind = .Wooden_Shield,
		name = "Wooden Shield",
		category = .Equipment,
		slot = .Shield,
		defense_bonus = 1,
	},
	.Iron_Shield = {
		kind = .Iron_Shield,
		name = "Iron Shield",
		category = .Equipment,
		slot = .Shield,
		defense_bonus = 3,
	},
	.Ring_Of_Protection = {
		kind = .Ring_Of_Protection,
		name = "Ring of Protection",
		category = .Equipment,
		slot = .Ring,
		defense_bonus = 2,
	},
	.Ring_Of_Might = {
		kind = .Ring_Of_Might,
		name = "Ring of Might",
		category = .Equipment,
		slot = .Ring,
		attack_bonus = 3,
	},
	.Amulet_Of_Vitality = {
		kind = .Amulet_Of_Vitality,
		name = "Amulet of Vitality",
		category = .Equipment,
		slot = .Amulet,
		hp_bonus = 8,
	},
	.Health_Potion = {
		kind = .Health_Potion,
		name = "Health Potion",
		category = .Consumable,
		heal_amount = 15,
	},
}

EQUIPMENT_SLOT_NAMES := [Equipment_Slot]string {
	.Head   = "Head",
	.Torso  = "Torso",
	.Legs   = "Legs",
	.Feet   = "Feet",
	.Weapon = "Weapon",
	.Shield = "Shield",
	.Ring   = "Ring",
	.Amulet = "Amulet",
}

MAX_INVENTORY_ITEMS :: 16

Inventory :: struct {
	items:      [MAX_INVENTORY_ITEMS]Item_Kind,
	item_count: int,
	equipment:  [Equipment_Slot]Item_Kind,
}

inventory_add :: proc(inv: ^Inventory, item: Item_Kind) -> bool {
	if item == .None do return false
	if inv.item_count >= MAX_INVENTORY_ITEMS do return false

	for i in 0 ..< MAX_INVENTORY_ITEMS {
		if inv.items[i] == .None {
			inv.items[i] = item
			inv.item_count += 1
			return true
		}
	}
	return false
}

inventory_remove_at :: proc(inv: ^Inventory, index: int) -> Item_Kind {
	if index < 0 || index >= MAX_INVENTORY_ITEMS do return .None
	item := inv.items[index]
	if item != .None {
		inv.items[index] = .None
		inv.item_count -= 1
	}
	return item
}

// equip an item from inventory slot into wearable slot
equip_item :: proc(inv: ^Inventory, inv_idx: int) -> bool {
	if inv_idx < 0 || inv_idx >= MAX_INVENTORY_ITEMS do return false
	item := inv.items[inv_idx]
	if item == .None do return false

	def := ITEM_DEFS[item]
	if def.category != .Equipment do return false

	slot := def.slot
	old_equipped := inv.equipment[slot]

	inv.equipment[slot] = item
	inv.items[inv_idx] = old_equipped
	if old_equipped == .None {
		inv.item_count -= 1
	}
	return true
}

// unequip wearable item back into first free inventory slot
unequip_item :: proc(inv: ^Inventory, slot: Equipment_Slot) -> bool {
	equipped := inv.equipment[slot]
	if equipped == .None do return false
	if inv.item_count >= MAX_INVENTORY_ITEMS do return false

	if inventory_add(inv, equipped) {
		inv.equipment[slot] = .None
		return true
	}
	return false
}

// directly equip without taking from inventory (e.g. at spawn or loading)
force_equip :: proc(inv: ^Inventory, item: Item_Kind) {
	if item == .None do return
	def := ITEM_DEFS[item]
	if def.category == .Equipment {
		inv.equipment[def.slot] = item
	}
}

// calculate total stats from equipped wearables
inventory_stat_bonuses :: proc(inv: ^Inventory) -> (att: int, def: int, max_hp: int) {
	for slot in Equipment_Slot {
		eq := inv.equipment[slot]
		if eq != .None {
			d := ITEM_DEFS[eq]
			att += d.attack_bonus
			def += d.defense_bonus
			max_hp += d.hp_bonus
		}
	}
	return
}

// use an item from inventory (equip if wearable, consume if consumable)
use_inventory_item :: proc(
	inv: ^Inventory,
	idx: int,
	hp: ^int,
	max_hp: int,
) -> (
	success: bool,
	msg: string,
) {
	if idx < 0 || idx >= MAX_INVENTORY_ITEMS do return false, ""
	item := inv.items[idx]
	if item == .None do return false, ""

	def := ITEM_DEFS[item]
	switch def.category {
	case .Equipment:
		slot_name := EQUIPMENT_SLOT_NAMES[def.slot]
		equip_item(inv, idx)
		return true, fmt.tprintf("Equipped %s on %s.", def.name, slot_name)

	case .Consumable:
		if def.heal_amount > 0 {
			if hp^ >= max_hp {
				return false, "You are already at full health."
			}
			hp^ = min(max_hp, hp^ + def.heal_amount)
			inventory_remove_at(inv, idx)
			return true, fmt.tprintf("Used %s and restored %d HP.", def.name, def.heal_amount)
		}
		inventory_remove_at(inv, idx)
		return true, fmt.tprintf("Used %s.", def.name)

	case .Misc:
		return false, "You cannot use this item."
	}
	return false, ""
}
