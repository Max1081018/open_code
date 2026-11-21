extends Node
## Every item and recipe in the game.
##
## Items are plain dictionaries keyed by a string id, so save files store
## readable names rather than indices that shift when the table changes.

enum Kind { BLOCK, ORE, MATERIAL, PICKAXE, AXE, SWORD, PLACEABLE, CONSUMABLE, KEY, SHIELD, HAMMER, RELIC, ROD }

enum Station { HAND, WORKBENCH, ANVIL, CAMPFIRE }

const STATION_NAMES := {
	Station.HAND: "By hand",
	Station.WORKBENCH: "Workbench",
	Station.ANVIL: "Anvil",
	Station.CAMPFIRE: "Campfire",
}

const ICON_ROOT := "res://assets/"

## id -> definition. Fields:
##   name, icon, kind, stack, desc
##   block: tile material placed (blocks)
##   power: mining power (pickaxe/axe), damage (sword), speed (swing seconds)
##   tier: progression tier (tools)
##   object: placeable object id (placeables)
##   heal / glow: consumable effects
var defs := {
	# --- Blocks -----------------------------------------------------------
	"soil": {"name": "Soil", "icon": "blocks/soil", "kind": Kind.BLOCK, "stack": 999,
		"block": 2, "desc": "Loose earth. Packs into anything."},
	"sand": {"name": "Sand", "icon": "blocks/sand", "kind": Kind.BLOCK, "stack": 999,
		"block": 3, "desc": "Warm, dry and shifting."},
	"snow": {"name": "Snow", "icon": "blocks/snow", "kind": Kind.BLOCK, "stack": 999,
		"block": 4, "desc": "Packed snow from the frozen north."},
	"stone": {"name": "Stone", "icon": "blocks/rock", "kind": Kind.BLOCK, "stack": 999,
		"block": 5, "desc": "The grey bones of the world."},
	"brick": {"name": "Brick", "icon": "blocks/brick", "kind": Kind.BLOCK, "stack": 999,
		"block": 6, "desc": "Dressed stone, laid by someone long gone."},
	"crystal_stone": {"name": "Crystal Stone", "icon": "blocks/crystal", "kind": Kind.BLOCK,
		"stack": 999, "block": 7, "desc": "Stone furred with violet crystal."},
	"basalt": {"name": "Basalt", "icon": "blocks/basalt", "kind": Kind.BLOCK, "stack": 999,
		"block": 8, "desc": "Dense rock from the deep. Holds heat."},
	"planks": {"name": "Planks", "icon": "blocks/planks", "kind": Kind.BLOCK, "stack": 999,
		"block": 9, "desc": "Sawn timber, for building."},

	# --- Raw materials ------------------------------------------------------
	"wood": {"name": "Wood", "icon": "rendered/resource-wood", "kind": Kind.MATERIAL, "stack": 999,
		"desc": "Felled timber."},
	"coal": {"name": "Coal", "icon": "items/ore_coal", "kind": Kind.ORE, "stack": 999,
		"desc": "Burns hot. Torches need it."},
	"copper_ore": {"name": "Copper Ore", "icon": "items/ore_iron", "kind": Kind.ORE, "stack": 999,
		"desc": "Green with age. The first metal anyone finds."},
	"iron_ore": {"name": "Iron Ore", "icon": "items/ore_ironAlt", "kind": Kind.ORE, "stack": 999,
		"desc": "Rust-red and heavy."},
	"silver_ore": {"name": "Silver Ore", "icon": "items/ore_silver", "kind": Kind.ORE,
		"stack": 999, "desc": "Bright, and found deep."},
	"gold_ore": {"name": "Gold Ore", "icon": "items/ore_gold", "kind": Kind.ORE, "stack": 999,
		"desc": "Soft, rare and worth the trouble."},
	"glowshard": {"name": "Glowshard", "icon": "items/ore_diamond", "kind": Kind.ORE,
		"stack": 999, "glow": 25.0,
		"desc": "Crystallised light. Feeds your lantern. Grows in the Crystal Hollows."},
	"ruby": {"name": "Ruby", "icon": "items/ore_ruby", "kind": Kind.ORE, "stack": 999,
		"desc": "A warm red gem. Wardstones are set with them."},
	"emerald": {"name": "Emerald", "icon": "items/ore_emerald", "kind": Kind.ORE, "stack": 999,
		"desc": "A cold green gem from the deep."},
	"raw_meat": {"name": "Raw Meat", "icon": "items/meatRaw", "kind": Kind.MATERIAL, "stack": 99,
		"desc": "Cook it on a campfire first."},
	"fish": {"name": "Fish", "icon": "items/fish", "kind": Kind.MATERIAL, "stack": 99,
		"desc": "Fresh from an underground pool."},

	# --- Tools: one family per metal ----------------------------------------
	"wood_pickaxe": {"name": "Wooden Pickaxe", "icon": "items/toolPickaxe", "kind": Kind.PICKAXE,
		"stack": 1, "tier": 1, "power": 2, "speed": 0.36, "damage": 6,
		"desc": "Cracks soil and stone. Not much else."},
	"copper_pickaxe": {"name": "Copper Pickaxe", "icon": "items/pick_bronze", "kind": Kind.PICKAXE,
		"stack": 1, "tier": 2, "power": 3, "speed": 0.30, "damage": 8,
		"desc": "Breaks iron ore and brick."},
	"iron_pickaxe": {"name": "Iron Pickaxe", "icon": "items/pick_iron", "kind": Kind.PICKAXE,
		"stack": 1, "tier": 3, "power": 4, "speed": 0.25, "damage": 10,
		"desc": "Bites into silver, crystal and basalt."},
	"silver_pickaxe": {"name": "Silver Pickaxe", "icon": "items/pick_silver",
		"kind": Kind.PICKAXE, "stack": 1, "tier": 4, "power": 5, "speed": 0.21, "damage": 12,
		"desc": "Fast enough to dig for a living."},
	"gold_pickaxe": {"name": "Gold Pickaxe", "icon": "items/pick_gold", "kind": Kind.PICKAXE,
		"stack": 1, "tier": 5, "power": 6, "speed": 0.17, "damage": 14,
		"desc": "Opens the hardest gem seams."},
	"lumen_pickaxe": {"name": "Lumen Pickaxe", "icon": "items/pick_diamond", "kind": Kind.PICKAXE,
		"stack": 1, "tier": 6, "power": 7, "speed": 0.12, "damage": 18,
		"desc": "Glowshard-edged. Nothing stops it."},

	"wood_axe": {"name": "Wooden Axe", "icon": "items/toolAxe", "kind": Kind.AXE, "stack": 1,
		"tier": 1, "power": 2, "speed": 0.40, "damage": 7, "desc": "Fells trees."},
	"iron_axe": {"name": "Iron Axe", "icon": "items/axe_iron", "kind": Kind.AXE, "stack": 1,
		"tier": 3, "power": 4, "speed": 0.28, "damage": 13, "desc": "Fells trees in a few blows."},

	"wood_sword": {"name": "Starlit Blade", "icon": "items/toolSword", "kind": Kind.SWORD,
		"stack": 1, "tier": 1, "damage": 10, "speed": 0.42, "desc": "Better than fists."},
	"copper_sword": {"name": "Autumn Ember", "icon": "items/sword_bronze", "kind": Kind.SWORD,
		"stack": 1, "tier": 2, "damage": 16, "speed": 0.38, "desc": "A real blade."},
	"iron_sword": {"name": "Crystalline Sword", "icon": "items/sword_iron", "kind": Kind.SWORD,
		"stack": 1, "tier": 3, "damage": 24, "speed": 0.34, "desc": "Heavy and honest."},
	"silver_sword": {"name": "Jadewind Saber", "icon": "items/sword_silver", "kind": Kind.SWORD,
		"stack": 1, "tier": 4, "damage": 32, "speed": 0.31, "desc": "Shades fear it."},
	"gold_sword": {"name": "Sunforged Ember", "icon": "items/sword_gold", "kind": Kind.SWORD,
		"stack": 1, "tier": 5, "damage": 42, "speed": 0.29, "desc": "Ostentatious. Effective."},
	"lumen_sword": {"name": "Starfall Crystal", "icon": "items/sword_diamond", "kind": Kind.SWORD,
		"stack": 1, "tier": 6, "damage": 58, "speed": 0.24,
		"desc": "Sheds light as it cuts."},

	# --- Placeables -----------------------------------------------------------
	"wood_hammer": {"name": "Builder's Hammer", "icon": "items/toolHammer", "kind": Kind.HAMMER,
		"stack": 1, "tier": 1, "speed": 0.32, "damage": 5,
		"desc": "Takes down what you built — planks, brick, benches, torches — in one blow, and hands it back whole."},
	"iron_hammer": {"name": "Iron Hammer", "icon": "items/hammer_iron", "kind": Kind.HAMMER,
		"stack": 1, "tier": 3, "speed": 0.22, "damage": 9,
		"desc": "A builder's hammer with iron in it: quicker, and a fair weapon in a pinch."},
	"wood_shield": {"name": "Wooden Shield", "icon": "equipment/shield_wood", "kind": Kind.SHIELD,
		"stack": 1, "tier": 1, "block": 0.6,
		"desc": "Hold to block: takes the sting out of blows from the front."},
	"iron_shield": {"name": "Iron Shield", "icon": "equipment/shield_iron", "kind": Kind.SHIELD,
		"stack": 1, "tier": 3, "block": 0.8,
		"desc": "Iron-bound. Blocks most of a frontal blow and nearly all its force."},
	"torch": {"name": "Torch", "icon": "props/torch_on_a", "kind": Kind.PLACEABLE, "stack": 99,
		"object": "torch", "desc": "Light that lasts. Shades will not spawn near it."},
	"workbench": {"name": "Workbench", "icon": "rendered/workbench", "kind": Kind.PLACEABLE,
		"stack": 9, "object": "workbench", "desc": "Where tools and furniture are made."},
	"anvil": {"name": "Anvil", "icon": "rendered/workbench-anvil", "kind": Kind.PLACEABLE,
		"stack": 9, "object": "anvil", "desc": "Forges metal tools and wardstones."},
	"campfire": {"name": "Campfire", "icon": "rendered/campfire-pit", "kind": Kind.PLACEABLE,
		"stack": 9, "object": "campfire", "desc": "Cooks food. Its light restores your lantern slowly."},
	"chest": {"name": "Chest", "icon": "rendered/chest", "kind": Kind.PLACEABLE, "stack": 9,
		"object": "chest", "desc": "Stores forty stacks."},
	"wardstone": {"name": "Wardstone", "icon": "rendered/lantern-glass", "kind": Kind.PLACEABLE,
		"stack": 9, "object": "wardstone",
		"desc": "A planted light. Refills your lantern, holds back the dark, and marks a place to return to."},

	# --- Consumables ----------------------------------------------------------
	"apple": {"name": "Apple", "icon": "items/apple", "kind": Kind.CONSUMABLE, "stack": 99,
		"heal": 20, "desc": "Restores a little health."},
	"cooked_meat": {"name": "Cooked Meat", "icon": "items/meatCooked", "kind": Kind.CONSUMABLE,
		"stack": 99, "heal": 45, "desc": "Restores health."},
	"cooked_fish": {"name": "Cooked Fish", "icon": "items/fish_cooked", "kind": Kind.CONSUMABLE,
		"stack": 99, "heal": 40, "desc": "Restores health."},
	"stew": {"name": "Hearty Stew", "icon": "items/stew", "kind": Kind.CONSUMABLE, "stack": 20,
		"heal": 100, "desc": "Restores most of your health."},
	"glow_flask": {"name": "Glow Flask", "icon": "rendered/bottle", "kind": Kind.CONSUMABLE,
		"stack": 20, "glow": 100.0, "desc": "Refills your lantern completely."},
	"heart_crystal": {"name": "Heart Crystal", "icon": "props/heart", "kind": Kind.CONSUMABLE,
		"stack": 9, "max_health": 20, "desc": "Permanently raises your health."},
	"lumen_core": {"name": "Lumen Core", "icon": "props/star", "kind": Kind.CONSUMABLE,
		"stack": 9, "lantern_tier": 1,
		"desc": "The heart of a guardian. Your lantern burns brighter and longer, and the deep dark loosens its grip."},

	# --- Keys -----------------------------------------------------------------
	"vault_key": {"name": "Vault Key", "icon": "props/key_yellow", "kind": Kind.KEY, "stack": 1,
		"desc": "Opens the sealed vault at the bottom of the ruins."},

	# --- Fishing ------------------------------------------------------------------
	"fishing_rod": {"name": "Fishing Rod", "icon": "items/fishingPole", "kind": Kind.ROD, "stack": 1,
		"desc": "Cast at water, wait for the bobber to dip, and tap to strike."},
	"glowfin": {"name": "Glowfin", "icon": "items/glowfin", "kind": Kind.MATERIAL, "stack": 99,
		"desc": "A pale fish from the dark water under the hills. It shines from inside."},
	"pearl": {"name": "Pearl", "icon": "items/shell", "kind": Kind.MATERIAL, "stack": 99,
		"desc": "From a clam on a fishing line. Tobin's customers would pay for it."},
	"glowfin_skewer": {"name": "Glowfin Skewer", "icon": "items/glowfin_skewer", "kind": Kind.CONSUMABLE,
		"stack": 20, "glow": 45.0, "heal": 15, "desc": "Eat the light: restores your lantern and a little health."},

	# --- Treasure ---------------------------------------------------------------
	"gold_coin": {"name": "Old Coin", "icon": "props/coin_gold", "kind": Kind.MATERIAL, "stack": 999,
		"desc": "Struck by people who lived here before the dark. Someone will still trade for them."},

	# --- Relics: found, never made. Worn in three relic slots. -----------------
	"relic_featherbone": {"name": "Featherbone Charm", "icon": "items/relic_featherbone", "kind": Kind.RELIC,
		"stack": 1, "desc": "Light as a wing. You can jump again in the air."},
	"relic_ember_heart": {"name": "Ember Heart", "icon": "items/relic_ember_heart", "kind": Kind.RELIC,
		"stack": 1, "desc": "Still warm. Your blows set the dead alight."},
	"relic_deepsong": {"name": "Deepsong Shell", "icon": "items/relic_deepsong", "kind": Kind.RELIC,
		"stack": 1, "desc": "Hold it to your ear and the rock hums back. Ore nearby glimmers through stone."},
	"relic_moth_lantern": {"name": "Moth Lantern", "icon": "items/relic_moth_lantern", "kind": Kind.RELIC,
		"stack": 1, "desc": "Moths gather in the dark and feed your flame. Glow slowly returns while all is black."},
	"relic_bulwark": {"name": "Bulwark Sigil", "icon": "items/relic_bulwark", "kind": Kind.RELIC,
		"stack": 1, "desc": "A Lightwarden's mark. You take a quarter less harm."},
	"relic_swiftroot": {"name": "Swiftroot Anklet", "icon": "items/relic_swiftroot", "kind": Kind.RELIC,
		"stack": 1, "desc": "Woven from roots that never stop growing. You move faster."},
	"relic_seers_eye": {"name": "Seer's Eye", "icon": "items/relic_seers_eye", "kind": Kind.RELIC,
		"stack": 1, "desc": "Light-runes show themselves to you without a flare, and you remember more of where you have been."},
	"relic_tidecaller": {"name": "Tidecaller's Scale", "icon": "items/relic_tidecaller", "kind": Kind.RELIC,
		"stack": 1, "desc": "From the shrine at the bottom of the Drowned Halls. You breathe water as if it were air, and swim like a fish."},
	"relic_luckstone": {"name": "Luckstone", "icon": "items/relic_luckstone", "kind": Kind.RELIC,
		"stack": 1, "desc": "Chests hold one more find, and rare things fall twice as often."},
}

## What Tobin will sell for Old Coins: [item, count, price].
const TRADES := [
	["torch", 6, 3], ["cooked_meat", 3, 4], ["glow_flask", 1, 9], ["iron_ore", 8, 12],
	["wardstone", 1, 45], ["iron_pickaxe", 1, 35], ["iron_sword", 1, 40], ["heart_crystal", 1, 70],
]

## Every relic, in the order the world hands them out.
const RELICS := ["relic_featherbone", "relic_ember_heart", "relic_deepsong", "relic_moth_lantern",
	"relic_bulwark", "relic_swiftroot", "relic_seers_eye", "relic_luckstone"]

## [result, count, station, {ingredient: count}]
var recipes := [
	["workbench", 1, Station.HAND, {"wood": 10}],
	["torch", 4, Station.HAND, {"wood": 1, "coal": 1}],
	["campfire", 1, Station.HAND, {"wood": 6, "stone": 4}],

	["planks", 4, Station.WORKBENCH, {"wood": 1}],
	["wood_pickaxe", 1, Station.WORKBENCH, {"wood": 8}],
	["wood_axe", 1, Station.WORKBENCH, {"wood": 8}],
	["wood_sword", 1, Station.WORKBENCH, {"wood": 7}],
	["chest", 1, Station.WORKBENCH, {"wood": 12}],
	["brick", 2, Station.WORKBENCH, {"stone": 2}],
	["anvil", 1, Station.WORKBENCH, {"stone": 20, "iron_ore": 6}],
	["wood_shield", 1, Station.WORKBENCH, {"wood": 14}],
	["wood_hammer", 1, Station.WORKBENCH, {"wood": 6, "stone": 3}],
	["iron_hammer", 1, Station.ANVIL, {"iron_ore": 6, "wood": 2}],
	["iron_shield", 1, Station.ANVIL, {"iron_ore": 10, "wood": 4}],

	["copper_pickaxe", 1, Station.ANVIL, {"copper_ore": 12, "wood": 4}],
	["copper_sword", 1, Station.ANVIL, {"copper_ore": 10, "wood": 2}],
	["iron_pickaxe", 1, Station.ANVIL, {"iron_ore": 14, "wood": 4}],
	["iron_axe", 1, Station.ANVIL, {"iron_ore": 10, "wood": 4}],
	["iron_sword", 1, Station.ANVIL, {"iron_ore": 12, "wood": 2}],
	["silver_pickaxe", 1, Station.ANVIL, {"silver_ore": 14, "wood": 4}],
	["silver_sword", 1, Station.ANVIL, {"silver_ore": 12, "wood": 2}],
	["gold_pickaxe", 1, Station.ANVIL, {"gold_ore": 14, "wood": 4}],
	["gold_sword", 1, Station.ANVIL, {"gold_ore": 12, "wood": 2}],
	["lumen_pickaxe", 1, Station.ANVIL, {"glowshard": 20, "gold_ore": 6, "emerald": 2}],
	["lumen_sword", 1, Station.ANVIL, {"glowshard": 18, "gold_ore": 6, "ruby": 2}],
	["wardstone", 1, Station.ANVIL, {"stone": 15, "glowshard": 6, "ruby": 1}],
	["glow_flask", 1, Station.ANVIL, {"glowshard": 3}],

	["cooked_meat", 1, Station.CAMPFIRE, {"raw_meat": 1}],
	["cooked_fish", 1, Station.CAMPFIRE, {"fish": 1}],
	["glowfin_skewer", 1, Station.CAMPFIRE, {"glowfin": 1}],
	["fishing_rod", 1, Station.WORKBENCH, {"wood": 8}],
	["stew", 1, Station.CAMPFIRE, {"raw_meat": 2, "fish": 1, "apple": 1}],
]

var _icon_cache := {}


func def(id: String) -> Dictionary:
	return defs.get(id, {})


func exists(id: String) -> bool:
	return defs.has(id)


func item_name(id: String) -> String:
	return defs.get(id, {}).get("name", id)


func stack_size(id: String) -> int:
	return defs.get(id, {}).get("stack", 99)


func kind(id: String) -> int:
	return defs.get(id, {}).get("kind", Kind.MATERIAL)


func icon(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]

	var path: String = ICON_ROOT + defs.get(id, {}).get("icon", "props/star") + ".png"
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_icon_cache[id] = texture
	return texture


## Recipes craftable at any of `stations` (an Array of Station values).
func recipes_at(stations: Array) -> Array:
	var out := []
	for recipe in recipes:
		if recipe[2] in stations:
			out.append(recipe)
	return out


## The item a mined tile material drops.
func drop_for_tile(material: int) -> String:
	match material:
		1, 2:
			return "soil"
		3:
			return "sand"
		4:
			return "snow"
		5:
			return "stone"
		6:
			return "brick"
		7:
			return "crystal_stone"
		8:
			return "basalt"
		9:
			return "planks"
	return ""


## The item an ore overlay drops. Indices match World.ORES.
const ORE_DROPS := ["coal", "copper_ore", "iron_ore", "silver_ore", "gold_ore", "glowshard",
	"ruby", "emerald"]


func drop_for_ore(ore: int) -> String:
	if ore <= 0 or ore > ORE_DROPS.size():
		return ""
	return ORE_DROPS[ore - 1]



## Rarity, from an item's tier and kind: how special it is, at a glance.
const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_COLORS := [Color(0.78, 0.76, 0.72), Color(0.45, 0.85, 0.45), Color(0.40, 0.70, 1.0),
	Color(0.78, 0.50, 1.0), Color(1.0, 0.78, 0.25)]
const SPECIAL := {"relic_featherbone": 3, "relic_ember_heart": 3, "relic_deepsong": 3,
	"relic_moth_lantern": 3, "relic_bulwark": 3, "relic_swiftroot": 3, "relic_seers_eye": 3,
	"relic_luckstone": 3, "relic_tidecaller": 4, "lumen_core": 4, "heart_crystal": 3, "vault_key": 3, "lumen_pickaxe": 4,
	"lumen_sword": 4, "wardstone": 2, "glow_flask": 1, "ruby": 2, "emerald": 2}


func rarity(id: String) -> int:
	if SPECIAL.has(id):
		return SPECIAL[id]
	var tier: int = def(id).get("tier", 0)
	return clampi(tier - 1, 0, 4) if tier > 0 else 0
