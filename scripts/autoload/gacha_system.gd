extends Node

## Owns the pool of all obtainable MiniParts plus the two neutral legendary
## figures, and handles gacha pulls from the various pack tiers.

## Every pull, regardless of pack, yields this many pieces. Fixed (not
## randomized) so players can predict progress. Chosen as a middle value in
## the requested 5-8 range: enough that most pulls make real progress toward
## a 4-part unit (with leftovers carrying into the next unit), without being
## so generous that pack tier stops mattering.
const PIECES_PER_PULL := 6

const PITY_LIMIT := 15 ## guaranteed a piece of Epic+ by this many pulls without one
var pull_count_since_epic: int = 0

var _all_parts: Array[MiniPart] = []
var _parts_by_id: Dictionary = {}

## Tier multiplier applied to base slot stats, indexed by MiniPart.Rarity
## (COMMON..EPIC). Legendary figures use LEGENDARY_TIER_MULT instead.
const TIER_MULT := [1.0, 1.5, 2.2, 3.2]
const LEGENDARY_TIER_MULT := 4.5

## Base stat contribution per slot before race/archetype/tier scaling.
## WEAPON has no might/prowess here -- that's injected per unit type
## depending on whether it deals physical or magical damage.
const SLOT_BASE := {
	MiniPart.Slot.HEAD: {"armor": 1.0, "resistance": 1.0, "health": 2.0},
	MiniPart.Slot.TORSO: {"armor": 2.0, "resistance": 1.0, "health": 3.0},
	MiniPart.Slot.LEGS: {"speed": 8.0, "dodge_chance": 2.0},
	MiniPart.Slot.WEAPON: {},
}
const WEAPON_DAMAGE_BASE := 4.0

const RACE_MOD := {
	MiniPart.Race.NONE: {"might": 1.0, "prowess": 1.0, "armor": 1.0, "resistance": 1.0, "health": 1.0, "speed": 1.0, "dodge_chance": 1.0},
	MiniPart.Race.IRONCLAD: {"might": 0.9, "prowess": 0.9, "armor": 1.3, "resistance": 1.2, "health": 1.3, "speed": 0.8, "dodge_chance": 0.85},
	MiniPart.Race.SKARRGOR: {"might": 1.4, "prowess": 0.9, "armor": 0.85, "resistance": 0.85, "health": 1.1, "speed": 0.9, "dodge_chance": 1.1},
	MiniPart.Race.WHISPERWOOD: {"might": 0.9, "prowess": 1.3, "armor": 0.75, "resistance": 1.1, "health": 0.8, "speed": 1.4, "dodge_chance": 1.3},
}

## "support" archetype units are this game's casters, so they deal magical
## damage; everything else swings a physical weapon.
const ARCHETYPE_MOD := {
	"balanced": {"might": 1.0, "prowess": 1.0, "armor": 1.0, "resistance": 1.0, "health": 1.0, "speed": 1.0, "dodge_chance": 1.0},
	"tank": {"might": 0.8, "prowess": 0.8, "armor": 1.4, "resistance": 1.3, "health": 1.4, "speed": 0.7, "dodge_chance": 0.8},
	"glass_cannon": {"might": 1.5, "prowess": 1.5, "armor": 0.6, "resistance": 0.6, "health": 0.7, "speed": 1.1, "dodge_chance": 1.2},
	"speedster": {"might": 0.9, "prowess": 0.9, "armor": 0.7, "resistance": 0.7, "health": 0.8, "speed": 1.6, "dodge_chance": 1.4},
	"support": {"might": 0.5, "prowess": 1.6, "armor": 1.0, "resistance": 1.2, "health": 1.1, "speed": 1.0, "dodge_chance": 0.9},
}

## How fast each archetype swings its regular attack (seconds between hits).
## This is what "attack speed" means in this game -- baked in per unit type
## rather than an exposed stat.
const ARCHETYPE_ATTACK_INTERVAL := {
	"balanced": 1.2,
	"tank": 1.6,
	"glass_cannon": 0.9,
	"speedster": 1.0,
	"support": 1.4,
}

const MELEE_RANGE := 40.0
const RANGED_RANGE := 220.0

## Each race gets 10 unit types: 4 common, 3 uncommon, 2 rare, 1 epic. Every
## unit type has a special ability on a cooldown (see PASSIVES below);
## Uncommon+ abilities are additionally themed to the race and may synergize
## with a teammate's ability. Commons get simpler self-buffs or single-target
## crowd control (slow/root/stun/fear) -- something every unit can use to
## help pin down a kiting ranged enemy, not just the rarer units.
const RACE_UNIT_TYPES := {
	MiniPart.Race.IRONCLAD: [
		{"name": "Recruit", "rarity": MiniPart.Rarity.COMMON, "archetype": "balanced", "passive": "common_focus", "ranged": false},
		{"name": "Spearman", "rarity": MiniPart.Rarity.COMMON, "archetype": "balanced", "passive": "ironclad_pin_down", "ranged": false},
		{"name": "Shieldbearer", "rarity": MiniPart.Rarity.COMMON, "archetype": "tank", "passive": "common_brace", "ranged": false},
		{"name": "Crossbowman", "rarity": MiniPart.Rarity.COMMON, "archetype": "glass_cannon", "passive": "ironclad_crippling_shot", "ranged": true},
		{"name": "Sergeant", "rarity": MiniPart.Rarity.UNCOMMON, "archetype": "balanced", "passive": "ironclad_rally", "ranged": false},
		{"name": "Halberdier", "rarity": MiniPart.Rarity.UNCOMMON, "archetype": "tank", "passive": "ironclad_brace", "ranged": false},
		{"name": "Cavalry Rider", "rarity": MiniPart.Rarity.UNCOMMON, "archetype": "speedster", "passive": "ironclad_charge", "ranged": false},
		{"name": "Knight Captain", "rarity": MiniPart.Rarity.RARE, "archetype": "tank", "passive": "ironclad_bulwark", "ranged": false},
		{"name": "Battle Cleric", "rarity": MiniPart.Rarity.RARE, "archetype": "support", "passive": "ironclad_blessing", "ranged": true},
		{"name": "Paladin Lord", "rarity": MiniPart.Rarity.EPIC, "archetype": "tank", "passive": "ironclad_aegis", "ranged": false},
	],
	MiniPart.Race.SKARRGOR: [
		{"name": "Grunt", "rarity": MiniPart.Rarity.COMMON, "archetype": "balanced", "passive": "common_focus", "ranged": false},
		{"name": "Slasher", "rarity": MiniPart.Rarity.COMMON, "archetype": "glass_cannon", "passive": "common_frenzy", "ranged": false},
		{"name": "Brute", "rarity": MiniPart.Rarity.COMMON, "archetype": "tank", "passive": "common_brace", "ranged": false},
		{"name": "Slinger", "rarity": MiniPart.Rarity.COMMON, "archetype": "speedster", "passive": "skarrgor_stone_stun", "ranged": true},
		{"name": "Berserker", "rarity": MiniPart.Rarity.UNCOMMON, "archetype": "glass_cannon", "passive": "skarrgor_bloodlust", "ranged": false},
		{"name": "Warg Rider", "rarity": MiniPart.Rarity.UNCOMMON, "archetype": "speedster", "passive": "skarrgor_packhunt", "ranged": false},
		{"name": "Bonecrusher", "rarity": MiniPart.Rarity.UNCOMMON, "archetype": "tank", "passive": "skarrgor_sunder", "ranged": false},
		{"name": "Chieftain", "rarity": MiniPart.Rarity.RARE, "archetype": "tank", "passive": "skarrgor_warcry", "ranged": false},
		{"name": "Shaman", "rarity": MiniPart.Rarity.RARE, "archetype": "support", "passive": "skarrgor_hex", "ranged": true},
		{"name": "Warlord", "rarity": MiniPart.Rarity.EPIC, "archetype": "glass_cannon", "passive": "skarrgor_wrath", "ranged": false},
	],
	MiniPart.Race.WHISPERWOOD: [
		{"name": "Scout", "rarity": MiniPart.Rarity.COMMON, "archetype": "speedster", "passive": "common_sprint", "ranged": false},
		{"name": "Archer", "rarity": MiniPart.Rarity.COMMON, "archetype": "glass_cannon", "passive": "whisperwood_crippling_shot", "ranged": true},
		{"name": "Sapling Warden", "rarity": MiniPart.Rarity.COMMON, "archetype": "tank", "passive": "whisperwood_entangling_roots", "ranged": false},
		{"name": "Skirmisher", "rarity": MiniPart.Rarity.COMMON, "archetype": "balanced", "passive": "whisperwood_spook", "ranged": false},
		{"name": "Ranger", "rarity": MiniPart.Rarity.UNCOMMON, "archetype": "glass_cannon", "passive": "whisperwood_deadeye", "ranged": true},
		{"name": "Druid", "rarity": MiniPart.Rarity.UNCOMMON, "archetype": "support", "passive": "whisperwood_regrowth", "ranged": true},
		{"name": "Blade Dancer", "rarity": MiniPart.Rarity.UNCOMMON, "archetype": "speedster", "passive": "whisperwood_fleetfoot", "ranged": false},
		{"name": "Spellsinger", "rarity": MiniPart.Rarity.RARE, "archetype": "support", "passive": "whisperwood_weave", "ranged": true},
		{"name": "Moon Hunter", "rarity": MiniPart.Rarity.RARE, "archetype": "glass_cannon", "passive": "whisperwood_moonlit", "ranged": true},
		{"name": "Archdruid", "rarity": MiniPart.Rarity.EPIC, "archetype": "support", "passive": "whisperwood_worldtree", "ranged": true},
	],
}

const LEGENDARY_FIGURE_DEFS := [
	{"name": "The Colossus", "archetype": "tank", "passive": "legend_immovable", "ranged": false},
	{"name": "The Phoenix Knight", "archetype": "glass_cannon", "passive": "legend_rebirth", "ranged": false},
]

## Passive metadata for display (Collection screen, Inventory preview, etc).
## These are periodic, on-cooldown abilities that pulse an effect to nearby
## units when they trigger -- not always-on, battlefield-wide buffs. The
## actual battle effects/cooldowns are implemented in battle_sim.gd, keyed
## by these same ids.
const PASSIVES := {
	"ironclad_rally": {"name": "Rally", "description": "Periodically grants +Armor to nearby allies for a few seconds."},
	"ironclad_brace": {"name": "Brace", "description": "Periodically grants +Resistance to nearby allies for a few seconds."},
	"ironclad_charge": {"name": "Charge", "description": "Periodically grants +Speed to nearby allies for a few seconds."},
	"ironclad_bulwark": {"name": "Bulwark", "description": "Periodically grants +Armor and +Resistance to nearby allies for a few seconds."},
	"ironclad_blessing": {"name": "Blessing", "description": "Healer: periodically heals nearby allies. Generates heavy threat while healing."},
	"ironclad_aegis": {"name": "Aegis", "description": "Periodically grants +Armor and +Resistance to nearby allies for a few seconds."},
	"skarrgor_bloodlust": {"name": "Bloodlust", "description": "Periodically grants +Might to nearby allies for a few seconds."},
	"skarrgor_packhunt": {"name": "Pack Hunt", "description": "Periodically grants +Speed to nearby allies for a few seconds."},
	"skarrgor_sunder": {"name": "Sunder", "description": "Periodically grants nearby allies armor-piercing attacks for a few seconds."},
	"skarrgor_warcry": {"name": "War Cry", "description": "Periodically grants +Might and +Speed to nearby allies for a few seconds."},
	"skarrgor_hex": {"name": "Hex", "description": "Periodically weakens nearby enemies' Armor and Resistance for a few seconds."},
	"skarrgor_wrath": {"name": "Warlord's Wrath", "description": "Periodically grants a large +Might boost to nearby allies for a few seconds."},
	"whisperwood_deadeye": {"name": "Deadeye", "description": "Periodically grants +Might to nearby allies for a few seconds."},
	"whisperwood_regrowth": {"name": "Regrowth", "description": "Healer: periodically heals nearby allies. Generates heavy threat while healing."},
	"whisperwood_fleetfoot": {"name": "Fleetfoot", "description": "Periodically grants +Dodge Chance to nearby allies for a few seconds."},
	"whisperwood_weave": {"name": "Arcane Weave", "description": "Periodically grants +Prowess to nearby allies for a few seconds."},
	"whisperwood_moonlit": {"name": "Moonlit Strike", "description": "Periodically grants nearby allies resistance-piercing attacks for a few seconds."},
	"whisperwood_worldtree": {"name": "World Tree's Blessing", "description": "Healer: periodically heals nearby allies for a large amount. Generates heavy threat while healing."},
	"legend_immovable": {"name": "Immovable", "description": "+30% Armor and +30% Resistance (self only, always active)."},
	"legend_rebirth": {"name": "Rebirth", "description": "Revives once per battle at 50% Health when defeated."},

	## Common-tier special abilities: simpler self-only buffs or single-target
	## crowd control, so ranged units aren't the only ones with a tool to
	## affect the fight -- melee commons can slow, root, stun, or fear a
	## kiting target to close the gap.
	"common_focus": {"name": "Focus", "description": "Periodically boosts this unit's own Might and Prowess for a few seconds."},
	"common_brace": {"name": "Brace Up", "description": "Periodically boosts this unit's own Armor and Resistance for a few seconds."},
	"common_frenzy": {"name": "Frenzy", "description": "Periodically boosts this unit's own Might and Speed for a few seconds."},
	"common_sprint": {"name": "Sprint", "description": "Periodically boosts this unit's own Speed and Dodge Chance for a few seconds."},
	"ironclad_pin_down": {"name": "Pin Down", "description": "Periodically roots the nearest enemy in place, preventing it from moving."},
	"ironclad_crippling_shot": {"name": "Crippling Shot", "description": "Periodically slows the nearest enemy's movement for a few seconds."},
	"skarrgor_stone_stun": {"name": "Stone Throw", "description": "Periodically stuns the nearest enemy, briefly preventing it from acting."},
	"whisperwood_crippling_shot": {"name": "Crippling Shot", "description": "Periodically slows the nearest enemy's movement for a few seconds."},
	"whisperwood_entangling_roots": {"name": "Entangling Roots", "description": "Periodically roots the nearest enemy in place, preventing it from moving."},
	"whisperwood_spook": {"name": "Spook", "description": "Periodically frightens the nearest enemy, forcing it to flee and stop attacking."},
}

## Pack lines: one Neutral line (any race, and the only source of Legendary
## parts since the neutral figures aren't tied to a faction) plus one line
## per playable race (that faction's parts only, no Legendary). Each line
## has 4 tiers with rising cost and rising odds of Uncommon+/Rare+ pieces.
## Piece count is always PIECES_PER_PULL regardless of line or tier.
const TIER_NAMES := ["Recruit", "Veteran", "Elite", "Master"]
const FACTION_TIER_COSTS := [60, 150, 320, 600]
const NEUTRAL_TIER_COSTS := [80, 190, 380, 700]

const FACTION_TIER_WEIGHTS := [
	{MiniPart.Rarity.COMMON: 65.0, MiniPart.Rarity.UNCOMMON: 27.0, MiniPart.Rarity.RARE: 7.0, MiniPart.Rarity.EPIC: 1.0},
	{MiniPart.Rarity.COMMON: 40.0, MiniPart.Rarity.UNCOMMON: 35.0, MiniPart.Rarity.RARE: 20.0, MiniPart.Rarity.EPIC: 5.0},
	{MiniPart.Rarity.COMMON: 20.0, MiniPart.Rarity.UNCOMMON: 32.0, MiniPart.Rarity.RARE: 33.0, MiniPart.Rarity.EPIC: 15.0},
	{MiniPart.Rarity.COMMON: 8.0, MiniPart.Rarity.UNCOMMON: 22.0, MiniPart.Rarity.RARE: 40.0, MiniPart.Rarity.EPIC: 30.0},
]

const NEUTRAL_TIER_WEIGHTS := [
	{MiniPart.Rarity.COMMON: 63.0, MiniPart.Rarity.UNCOMMON: 26.0, MiniPart.Rarity.RARE: 8.0, MiniPart.Rarity.EPIC: 2.5, MiniPart.Rarity.LEGENDARY: 0.5},
	{MiniPart.Rarity.COMMON: 38.0, MiniPart.Rarity.UNCOMMON: 34.0, MiniPart.Rarity.RARE: 20.0, MiniPart.Rarity.EPIC: 7.0, MiniPart.Rarity.LEGENDARY: 1.0},
	{MiniPart.Rarity.COMMON: 18.0, MiniPart.Rarity.UNCOMMON: 30.0, MiniPart.Rarity.RARE: 32.0, MiniPart.Rarity.EPIC: 18.0, MiniPart.Rarity.LEGENDARY: 2.0},
	{MiniPart.Rarity.COMMON: 6.0, MiniPart.Rarity.UNCOMMON: 20.0, MiniPart.Rarity.RARE: 38.0, MiniPart.Rarity.EPIC: 32.0, MiniPart.Rarity.LEGENDARY: 4.0},
]

var _packs: Array = []

func _build_packs() -> void:
	_packs.clear()
	for tier_i in range(4):
		_packs.append({
			"id": "neutral_%d" % (tier_i + 1),
			"line": "neutral",
			"race": MiniPart.Race.NONE,
			"tier": tier_i + 1,
			"name": "Neutral %s Pack" % TIER_NAMES[tier_i],
			"cost": NEUTRAL_TIER_COSTS[tier_i],
			"weights": NEUTRAL_TIER_WEIGHTS[tier_i],
		})
	for race in get_playable_races():
		var race_key := MiniPart.race_name(race).to_lower()
		for tier_i in range(4):
			_packs.append({
				"id": "%s_%d" % [race_key, tier_i + 1],
				"line": race_key,
				"race": race,
				"tier": tier_i + 1,
				"name": "%s %s Pack" % [MiniPart.race_name(race), TIER_NAMES[tier_i]],
				"cost": FACTION_TIER_COSTS[tier_i],
				"weights": FACTION_TIER_WEIGHTS[tier_i],
			})

func _ready() -> void:
	_build_part_pool()
	_build_legendary_units()
	_build_packs()

func get_part_by_id(id: String) -> MiniPart:
	return _parts_by_id.get(id, null)

## Pack line ids in display order: "neutral" first, then one per race.
func get_pack_lines() -> Array[String]:
	var lines: Array[String] = ["neutral"]
	for race in get_playable_races():
		lines.append(MiniPart.race_name(race).to_lower())
	return lines

func get_pack_line_display_name(line: String) -> String:
	return "Neutral" if line == "neutral" else line.capitalize()

## The 4 tier packs for a given line, in tier order.
func get_packs_for_line(line: String) -> Array:
	return _packs.filter(func(p): return p["line"] == line)

func get_pack_by_id(id: String) -> Dictionary:
	for pack in _packs:
		if pack["id"] == id:
			return pack
	return {}

func can_afford_pack(pack_id: String) -> bool:
	var pack := get_pack_by_id(pack_id)
	return not pack.is_empty() and GameState.currency >= int(pack["cost"])

## Returns a random matching 4-part set (same race+unit type) restricted to
## the given race and rarity cap. Used to generate mono-faction enemy squads.
func random_matching_set_for_race_up_to(race: MiniPart.Race, max_rarity: MiniPart.Rarity) -> Dictionary:
	var torsos := _all_parts.filter(func(p): return p.slot == MiniPart.Slot.TORSO and p.race == race and p.rarity <= max_rarity)
	var torso: MiniPart = torsos[randi() % torsos.size()]
	var race_key := MiniPart.race_name(torso.race).to_lower()
	var type_key := torso.unit_type_name.to_lower().replace(" ", "_")
	return {
		"head": get_part_by_id("%s_%s_head" % [race_key, type_key]),
		"torso": torso,
		"legs": get_part_by_id("%s_%s_legs" % [race_key, type_key]),
		"weapon": get_part_by_id("%s_%s_weapon" % [race_key, type_key]),
	}

## Returns the playable races (excludes NONE, which is reserved for the
## neutral legendary figures and isn't a selectable army faction).
func get_playable_races() -> Array[MiniPart.Race]:
	var races: Array[MiniPart.Race] = []
	for race in RACE_UNIT_TYPES.keys():
		races.append(race)
	return races

## Unit-type definitions for a race at a given rarity -- used by the new-game
## draft to offer options at exactly the right power level.
func get_unit_types_for_race(race: MiniPart.Race, rarity: MiniPart.Rarity) -> Array:
	if not RACE_UNIT_TYPES.has(race):
		return []
	return RACE_UNIT_TYPES[race].filter(func(t): return t["rarity"] == rarity)

## Builds a fully assembled MiniUnit directly from a race + unit type name,
## looking up its 4 matching parts. Used by the draft to hand the player a
## complete unit for the type they picked (no gacha/assembly step needed).
func build_unit_from_type(race: MiniPart.Race, unit_type_name: String) -> MiniUnit:
	var race_key := MiniPart.race_name(race).to_lower()
	var type_key := unit_type_name.to_lower().replace(" ", "_")
	var unit := MiniUnit.new()
	unit.unit_name = unit_type_name
	unit.head = get_part_by_id("%s_%s_head" % [race_key, type_key])
	unit.torso = get_part_by_id("%s_%s_torso" % [race_key, type_key])
	unit.legs = get_part_by_id("%s_%s_legs" % [race_key, type_key])
	unit.weapon = get_part_by_id("%s_%s_weapon" % [race_key, type_key])
	return unit

## Performs one pull from the given pack. Returns an Array of result
## dictionaries, one per piece: {"type": "part", "part": MiniPart}. Returns
## [] if unaffordable. Every rarity -- including Legendary -- is granted as
## a part that must be assembled, same as any other unit.
func pull(pack_id: String) -> Array:
	var pack := get_pack_by_id(pack_id)
	if pack.is_empty():
		return []
	if not GameState.spend_currency(int(pack["cost"])):
		return []

	var results: Array = []
	var forced_pity := pull_count_since_epic >= PITY_LIMIT - 1
	var got_epic_plus := false

	for i in range(PIECES_PER_PULL):
		var rarity: MiniPart.Rarity
		if forced_pity and i == 0:
			rarity = MiniPart.Rarity.EPIC
		else:
			rarity = _roll_rarity(pack["weights"])
		if rarity >= MiniPart.Rarity.EPIC:
			got_epic_plus = true

		var part := _random_part_of_rarity(rarity, pack["race"])
		GameState.add_part(part)
		results.append({"type": "part", "part": part})

	pull_count_since_epic = 0 if got_epic_plus else pull_count_since_epic + 1
	return results

func _roll_rarity(weights: Dictionary) -> MiniPart.Rarity:
	var total := 0.0
	for w in weights.values():
		total += w
	var roll := randf() * total
	var acc := 0.0
	for rarity in weights.keys():
		acc += weights[rarity]
		if roll <= acc:
			return rarity
	return MiniPart.Rarity.COMMON

## race_filter == NONE means "any race" (the Neutral pack line); any other
## race restricts the pool to that faction's parts only.
func _random_part_of_rarity(rarity: MiniPart.Rarity, race_filter: MiniPart.Race) -> MiniPart:
	var candidates: Array
	if race_filter == MiniPart.Race.NONE:
		candidates = _all_parts.filter(func(p): return p.rarity == rarity)
	else:
		candidates = _all_parts.filter(func(p): return p.rarity == rarity and p.race == race_filter)
	if candidates.is_empty():
		candidates = _all_parts.filter(func(p): return p.rarity == rarity)
	return candidates[randi() % candidates.size()]

func _make_stat(base: Dictionary, race_mod: Dictionary, archetype_mod: Dictionary, tier_mult: float) -> Dictionary:
	var result := {}
	for key in base.keys():
		result[key] = base[key] * race_mod.get(key, 1.0) * archetype_mod.get(key, 1.0) * tier_mult
	return result

func _build_part_pool() -> void:
	_all_parts.clear()
	_parts_by_id.clear()

	for race in RACE_UNIT_TYPES.keys():
		var race_mod: Dictionary = RACE_MOD[race]
		var race_key := MiniPart.race_name(race).to_lower()
		for unit_type in RACE_UNIT_TYPES[race]:
			var archetype: String = unit_type["archetype"]
			var archetype_mod: Dictionary = ARCHETYPE_MOD[archetype]
			var tier_mult: float = TIER_MULT[unit_type["rarity"]]
			var type_key: String = unit_type["name"].to_lower().replace(" ", "_")
			var dmg_type: MiniPart.DamageType = MiniPart.DamageType.MAGICAL if archetype == "support" else MiniPart.DamageType.PHYSICAL
			var passive_id: String = unit_type.get("passive", "")
			var atk_range: float = RANGED_RANGE if unit_type.get("ranged", false) else MELEE_RANGE
			var atk_interval: float = ARCHETYPE_ATTACK_INTERVAL[archetype]

			for slot in [MiniPart.Slot.HEAD, MiniPart.Slot.TORSO, MiniPart.Slot.LEGS, MiniPart.Slot.WEAPON]:
				var slot_base: Dictionary = SLOT_BASE[slot].duplicate()
				if slot == MiniPart.Slot.WEAPON:
					if dmg_type == MiniPart.DamageType.PHYSICAL:
						slot_base["might"] = WEAPON_DAMAGE_BASE
					else:
						slot_base["prowess"] = WEAPON_DAMAGE_BASE

				var stats := _make_stat(slot_base, race_mod, archetype_mod, tier_mult)
				var part := MiniPart.new()
				part.part_id = "%s_%s_%s" % [race_key, type_key, MiniPart.slot_name(slot).to_lower()]
				part.display_name = "%s %s" % [unit_type["name"], MiniPart.slot_name(slot)]
				part.slot = slot
				part.rarity = unit_type["rarity"]
				part.race = race
				part.unit_type_name = unit_type["name"]
				part.damage_type = dmg_type
				part.attack_range = atk_range
				part.attack_interval = atk_interval
				if passive_id != "":
					part.passive_id = passive_id
					part.passive_name = PASSIVES[passive_id]["name"]
					part.passive_description = PASSIVES[passive_id]["description"]
				part.might = int(round(stats.get("might", 0.0)))
				part.prowess = int(round(stats.get("prowess", 0.0)))
				part.armor = int(round(stats.get("armor", 0.0)))
				part.resistance = int(round(stats.get("resistance", 0.0)))
				part.health = int(round(stats.get("health", 0.0)))
				part.speed = snappedf(stats.get("speed", 0.0), 0.1)
				part.dodge_chance = snappedf(stats.get("dodge_chance", 0.0), 0.1)
				_all_parts.append(part)
				_parts_by_id[part.part_id] = part

## Legendary parts are added to _all_parts just like racial parts, so they
## drop from the Neutral pack and must be assembled in the Inventory like
## any other unit -- they no longer arrive as a complete free-standing unit.
func _build_legendary_units() -> void:
	var neutral_mod: Dictionary = RACE_MOD[MiniPart.Race.NONE]

	for figure in LEGENDARY_FIGURE_DEFS:
		var archetype: String = figure["archetype"]
		var archetype_mod: Dictionary = ARCHETYPE_MOD[archetype]
		var dmg_type: MiniPart.DamageType = MiniPart.DamageType.MAGICAL if archetype == "support" else MiniPart.DamageType.PHYSICAL
		var passive_id: String = figure["passive"]
		var atk_range: float = RANGED_RANGE if figure.get("ranged", false) else MELEE_RANGE
		var atk_interval: float = ARCHETYPE_ATTACK_INTERVAL[archetype]
		var type_key: String = figure["name"].to_lower().replace(" ", "_").replace("'", "")

		for slot in [MiniPart.Slot.HEAD, MiniPart.Slot.TORSO, MiniPart.Slot.LEGS, MiniPart.Slot.WEAPON]:
			var slot_base: Dictionary = SLOT_BASE[slot].duplicate()
			if slot == MiniPart.Slot.WEAPON:
				if dmg_type == MiniPart.DamageType.PHYSICAL:
					slot_base["might"] = WEAPON_DAMAGE_BASE
				else:
					slot_base["prowess"] = WEAPON_DAMAGE_BASE

			var stats := _make_stat(slot_base, neutral_mod, archetype_mod, LEGENDARY_TIER_MULT)
			var part := MiniPart.new()
			part.part_id = "legendary_%s_%s" % [type_key, MiniPart.slot_name(slot).to_lower()]
			part.display_name = "%s %s" % [figure["name"], MiniPart.slot_name(slot)]
			part.slot = slot
			part.rarity = MiniPart.Rarity.LEGENDARY
			part.race = MiniPart.Race.NONE
			part.unit_type_name = figure["name"]
			part.damage_type = dmg_type
			part.attack_range = atk_range
			part.attack_interval = atk_interval
			part.passive_id = passive_id
			part.passive_name = PASSIVES[passive_id]["name"]
			part.passive_description = PASSIVES[passive_id]["description"]
			part.might = int(round(stats.get("might", 0.0)))
			part.prowess = int(round(stats.get("prowess", 0.0)))
			part.armor = int(round(stats.get("armor", 0.0)))
			part.resistance = int(round(stats.get("resistance", 0.0)))
			part.health = int(round(stats.get("health", 0.0)))
			part.speed = snappedf(stats.get("speed", 0.0), 0.1)
			part.dodge_chance = snappedf(stats.get("dodge_chance", 0.0), 0.1)
			_all_parts.append(part)
			_parts_by_id[part.part_id] = part
