extends Node

## Deterministic-ish auto-battle resolver, decoupled from the visual scene.
## The battle scene can either replay this log frame-by-frame, or the caller
## can request an instant result via simulate() without any visuals.

class UnitState:
	var unit: MiniUnit
	var team: int
	var race: MiniPart.Race
	var passive_id: String
	var damage_type: MiniPart.DamageType
	var position: Vector2
	var health: float
	var max_health: float

	## Immutable baseline for the battle. Effective stats below are
	## recomputed from these plus active_effects every tick, so a timed
	## ability buff naturally expires instead of needing to be "undone".
	var base_might: float
	var base_prowess: float
	var base_armor: float
	var base_resistance: float
	var base_speed: float
	var base_dodge_chance: float

	var might: float
	var prowess: float
	var armor: float
	var resistance: float
	var speed: float
	var dodge_chance: float
	var armor_pen: float = 0.0
	var resist_pen: float = 0.0

	## {"stat": String, "mode": "mult"|"add", "value": float, "expires_at": float}
	var active_effects: Array = []

	var attack_range: float
	var attack_interval: float
	var attack_cooldown: float = 0.0

	var ability_cooldown_max: float = 0.0 ## 0 means "no pulsed ability"
	var ability_cooldown: float = 0.0

	var threat: float = 1.0
	var target: UnitState
	var can_revive: bool = false
	var used_revive: bool = false

	## Crowd control: {"type": "slow"|"root"|"stun"|"fear", "expires_at": float,
	## "magnitude": float (slow only)}. Empty means no CC active.
	var active_cc: Dictionary = {}

	func is_alive() -> bool:
		return health > 0.0

	func cc_type(t: float) -> String:
		if active_cc.is_empty() or active_cc["expires_at"] <= t:
			return ""
		return active_cc["type"]

## Set by the army/encounter selection flow before switching to the battle
## arena scene.
var pending_player_units: Array[MiniUnit] = []
var pending_enemy_units: Array[MiniUnit] = []

const ARENA_SIZE := Vector2(960, 540)
const ARENA_MARGIN := 20.0

## A unit counts as "ranged" above this threshold (matches MiniUnit.is_ranged()).
const MELEE_RANGE_THRESHOLD := 100.0
## Ranged units retreat once the target is closer than this fraction of
## their max range, so they drift back toward max range for safety.
const KITE_FRACTION := 0.6

const DAMAGE_VARIANCE := 0.2 ## rolled damage is base +/- this fraction
const INTERVAL_VARIANCE := 0.15 ## rolled attack interval is base +/- this fraction
const MAX_DODGE_CHANCE := 75.0

## How much threat is generated per point of damage dealt, versus per point
## of healing done. Healers spike well above normal attackers so they draw
## aggro exactly when they're actively healing, per game design.
const THREAT_PER_DAMAGE := 0.3
const THREAT_PER_HEALING := 1.2

## Range within which a pulsed ability affects allies/enemies when it fires.
const ABILITY_RANGE := 160.0
const ABILITY_BUFF_DURATION := 4.0

## "Larger cooldown for stronger abilities": pulsed-ability cooldown by the
## unit's rarity, used unless overridden per-ability below. Legendary
## passives are handled separately (self-only or death-triggered, not pulsed).
const ABILITY_COOLDOWN_BY_RARITY := {
	MiniPart.Rarity.COMMON: 6.0,
	MiniPart.Rarity.UNCOMMON: 8.0,
	MiniPart.Rarity.RARE: 12.0,
	MiniPart.Rarity.EPIC: 16.0,
}

## Crowd control is stronger than a same-rarity stat buff, so specific CC
## abilities get a longer cooldown than the rarity default would give them.
const ABILITY_COOLDOWN_OVERRIDE := {
	"ironclad_pin_down": 10.0,
	"ironclad_crippling_shot": 9.0,
	"skarrgor_stone_stun": 11.0,
	"whisperwood_crippling_shot": 9.0,
	"whisperwood_entangling_roots": 10.0,
	"whisperwood_spook": 10.0,
}

## Stat-buff pulses: passive id -> list of {"stat", "mode", "value"} applied
## to the caster and allies within ABILITY_RANGE for ABILITY_BUFF_DURATION.
const BUFF_ABILITIES := {
	"ironclad_rally": [{"stat": "armor", "mode": "mult", "value": 1.25}],
	"ironclad_brace": [{"stat": "resistance", "mode": "mult", "value": 1.25}],
	"ironclad_charge": [{"stat": "speed", "mode": "mult", "value": 1.3}],
	"ironclad_bulwark": [{"stat": "armor", "mode": "mult", "value": 1.2}, {"stat": "resistance", "mode": "mult", "value": 1.2}],
	"ironclad_aegis": [{"stat": "armor", "mode": "mult", "value": 1.3}, {"stat": "resistance", "mode": "mult", "value": 1.3}],
	"skarrgor_bloodlust": [{"stat": "might", "mode": "mult", "value": 1.3}],
	"skarrgor_packhunt": [{"stat": "speed", "mode": "mult", "value": 1.3}],
	"skarrgor_sunder": [{"stat": "armor_pen", "mode": "add", "value": 0.25}],
	"skarrgor_warcry": [{"stat": "might", "mode": "mult", "value": 1.2}, {"stat": "speed", "mode": "mult", "value": 1.15}],
	"skarrgor_wrath": [{"stat": "might", "mode": "mult", "value": 1.4}],
	"whisperwood_deadeye": [{"stat": "might", "mode": "mult", "value": 1.3}],
	"whisperwood_fleetfoot": [{"stat": "dodge_chance", "mode": "mult", "value": 1.35}],
	"whisperwood_weave": [{"stat": "prowess", "mode": "mult", "value": 1.3}],
	"whisperwood_moonlit": [{"stat": "resist_pen", "mode": "add", "value": 0.25}],
}

## Pulses applied to enemies within ABILITY_RANGE instead of allies.
const DEBUFF_ABILITIES := {
	"skarrgor_hex": [{"stat": "armor", "mode": "mult", "value": 0.8}, {"stat": "resistance", "mode": "mult", "value": 0.8}],
}

## Healers: passive id -> fraction of max health restored to each ally
## within range when the ability fires. Generates big threat (see
## THREAT_PER_HEALING) so healing draws aggro, per game design.
const HEAL_ABILITIES := {
	"ironclad_blessing": 0.18,
	"whisperwood_regrowth": 0.15,
	"whisperwood_worldtree": 0.25,
}

## Common-tier self-only buffs: passive id -> list of {"stat","mode","value"}
## applied to the caster alone (weaker/simpler than the squad-wide auras
## uncommon+ units grant).
const SELF_BUFF_ABILITIES := {
	"common_focus": [{"stat": "might", "mode": "mult", "value": 1.2}, {"stat": "prowess", "mode": "mult", "value": 1.2}],
	"common_brace": [{"stat": "armor", "mode": "mult", "value": 1.25}, {"stat": "resistance", "mode": "mult", "value": 1.25}],
	"common_frenzy": [{"stat": "might", "mode": "mult", "value": 1.2}, {"stat": "speed", "mode": "mult", "value": 1.2}],
	"common_sprint": [{"stat": "speed", "mode": "mult", "value": 1.25}, {"stat": "dodge_chance", "mode": "mult", "value": 1.3}],
}

## Single-target crowd control abilities: passive id -> {"type", "duration",
## "magnitude" (slow only)}. Applied to the nearest living enemy in range,
## per game design ("if there was the ability to slow, stun, root or fear
## them it would be easier to catch [ranged units]").
const CC_ABILITIES := {
	"ironclad_pin_down": {"type": "root", "duration": 2.5},
	"ironclad_crippling_shot": {"type": "slow", "duration": 3.0, "magnitude": 0.5},
	"skarrgor_stone_stun": {"type": "stun", "duration": 1.5},
	"whisperwood_crippling_shot": {"type": "slow", "duration": 3.0, "magnitude": 0.5},
	"whisperwood_entangling_roots": {"type": "root", "duration": 3.0},
	"whisperwood_spook": {"type": "fear", "duration": 2.0},
}

func _make_states(units: Array[MiniUnit], team: int, side_x: float) -> Array:
	var states: Array = []
	var count := units.size()
	for i in range(count):
		var u := units[i]
		var s := UnitState.new()
		s.unit = u
		s.team = team
		s.race = u.get_race()
		s.passive_id = u.get_passive_id()
		s.damage_type = u.get_damage_type()
		s.max_health = float(u.get_max_health())
		s.health = s.max_health
		s.base_might = float(u.get_might())
		s.base_prowess = float(u.get_prowess())
		s.base_armor = float(u.get_armor())
		s.base_resistance = float(u.get_resistance())
		s.base_speed = u.get_speed()
		s.base_dodge_chance = u.get_dodge_chance()
		s.attack_range = u.get_attack_range()
		s.attack_interval = u.get_attack_interval()

		match s.passive_id:
			"legend_immovable":
				s.base_armor *= 1.3
				s.base_resistance *= 1.3
			"legend_rebirth":
				s.can_revive = true
			_:
				if u.get_rarity() != MiniPart.Rarity.LEGENDARY and s.passive_id != "":
					s.ability_cooldown_max = ABILITY_COOLDOWN_OVERRIDE.get(s.passive_id, ABILITY_COOLDOWN_BY_RARITY.get(u.get_rarity(), 0.0))
					s.ability_cooldown = s.ability_cooldown_max

		var y := (ARENA_SIZE.y / float(count + 1)) * (i + 1)
		s.position = Vector2(side_x, y)
		states.append(s)
	return states

## Runs the full battle headlessly and returns a result summary + a replay log
## of {time, positions: {unit_index: Vector2}, events: [...]}.
## winning_team: 0 = player, 1 = enemy, -1 = draw/timeout.
func simulate(player_units: Array[MiniUnit], enemy_units: Array[MiniUnit]) -> Dictionary:
	var player_states := _make_states(player_units, 0, 60.0)
	var enemy_states := _make_states(enemy_units, 1, ARENA_SIZE.x - 60.0)
	var all_states: Array = player_states + enemy_states

	for s in all_states:
		_recompute_effective_stats(s, 0.0)

	var log_frames: Array = []
	var events: Array = []
	var t := 0.0
	var dt := 0.1
	var max_time := 60.0

	while t < max_time:
		var alive_player := player_states.filter(func(s): return s.is_alive())
		var alive_enemy := enemy_states.filter(func(s): return s.is_alive())
		if alive_player.is_empty() or alive_enemy.is_empty():
			break

		for s_variant in all_states:
			var s: UnitState = s_variant
			if not s.is_alive():
				continue
			_recompute_effective_stats(s, t)

		for s_variant in all_states:
			var s: UnitState = s_variant
			if not s.is_alive():
				continue

			var cc := s.cc_type(t)
			if cc == "stun":
				continue ## fully incapacitated: no ability, no movement, no attack

			if s.ability_cooldown_max > 0.0:
				s.ability_cooldown -= dt
				if s.ability_cooldown <= 0.0:
					_cast_ability(s, all_states, t)
					s.ability_cooldown = s.ability_cooldown_max

			if s.target == null or not s.target.is_alive():
				s.target = _find_target(s, all_states)
			if s.target == null:
				continue

			if cc == "fear":
				var away: Vector2 = s.position - s.target.position
				if away.length() > 0.0:
					s.position = _clamp_to_arena(s.position + away.normalized() * s.speed * dt)
				continue ## fleeing: no attack while feared

			var to_target: Vector2 = s.target.position - s.position
			var dist: float = to_target.length()
			var is_ranged := s.attack_range > MELEE_RANGE_THRESHOLD
			var effective_speed: float = s.speed * (1.0 - s.active_cc.get("magnitude", 0.0)) if cc == "slow" else s.speed

			if cc != "root":
				if dist > s.attack_range:
					var move: Vector2 = to_target.normalized() * effective_speed * dt
					s.position = _clamp_to_arena(s.position + move)
				elif is_ranged and dist < s.attack_range * KITE_FRACTION and dist > 0.0:
					var retreat: Vector2 = -to_target.normalized() * effective_speed * dt
					s.position = _clamp_to_arena(s.position + retreat)

			if dist <= s.attack_range:
				s.attack_cooldown -= dt
				if s.attack_cooldown <= 0.0:
					var dmg := _resolve_attack(s, s.target)
					if dmg > 0.0:
						s.threat += dmg * THREAT_PER_DAMAGE
					events.append({"time": t, "attacker": all_states.find(s), "target": all_states.find(s.target), "damage": dmg})
					s.attack_cooldown = randf_range(s.attack_interval * (1.0 - INTERVAL_VARIANCE), s.attack_interval * (1.0 + INTERVAL_VARIANCE))

		var frame_positions := {}
		for i in range(all_states.size()):
			var s_i: UnitState = all_states[i]
			frame_positions[i] = {
				"pos": s_i.position,
				"hp": max(0.0, s_i.health),
				"max_hp": s_i.max_health,
				"ability_cooldown": s_i.ability_cooldown,
				"ability_cooldown_max": s_i.ability_cooldown_max,
			}
		log_frames.append({"time": t, "units": frame_positions})

		t += dt

	var alive_player := player_states.filter(func(s): return s.is_alive())
	var alive_enemy := enemy_states.filter(func(s): return s.is_alive())
	var winning_team := -1
	if alive_player.size() > 0 and alive_enemy.is_empty():
		winning_team = 0
	elif alive_enemy.size() > 0 and alive_player.is_empty():
		winning_team = 1

	return {
		"winning_team": winning_team,
		"duration": t,
		"frames": log_frames,
		"events": events,
		"player_survivors": alive_player.size(),
		"enemy_survivors": alive_enemy.size(),
		"unit_setup": {
			"player_count": player_states.size(),
			"enemy_count": enemy_states.size(),
		},
	}

func _clamp_to_arena(pos: Vector2) -> Vector2:
	return Vector2(
		clamp(pos.x, ARENA_MARGIN, ARENA_SIZE.x - ARENA_MARGIN),
		clamp(pos.y, ARENA_MARGIN, ARENA_SIZE.y - ARENA_MARGIN)
	)

## Rebuilds effective stats from the immutable base stats plus any
## still-active ability pulses (expired ones are dropped here).
func _recompute_effective_stats(s: UnitState, t: float) -> void:
	s.active_effects = s.active_effects.filter(func(e): return e["expires_at"] > t)

	s.might = s.base_might
	s.prowess = s.base_prowess
	s.armor = s.base_armor
	s.resistance = s.base_resistance
	s.speed = s.base_speed
	s.dodge_chance = s.base_dodge_chance
	s.armor_pen = 0.0
	s.resist_pen = 0.0

	for e in s.active_effects:
		if e["stat"] == "armor_pen":
			s.armor_pen += e["value"]
		elif e["stat"] == "resist_pen":
			s.resist_pen += e["value"]
		elif e["mode"] == "mult":
			_mult_stat(s, e["stat"], e["value"])
		else:
			_add_stat(s, e["stat"], e["value"])

func _mult_stat(s: UnitState, stat: String, mult: float) -> void:
	match stat:
		"might": s.might *= mult
		"prowess": s.prowess *= mult
		"armor": s.armor *= mult
		"resistance": s.resistance *= mult
		"dodge_chance": s.dodge_chance *= mult
		"speed": s.speed *= mult

func _add_stat(s: UnitState, stat: String, amount: float) -> void:
	match stat:
		"might": s.might += amount
		"prowess": s.prowess += amount
		"armor": s.armor += amount
		"resistance": s.resistance += amount
		"dodge_chance": s.dodge_chance += amount
		"speed": s.speed += amount

func _allies_in_range(caster: UnitState, all_states: Array, range_limit: float) -> Array:
	var result: Array = []
	for s in all_states:
		if s.team == caster.team and s.is_alive() and caster.position.distance_to(s.position) <= range_limit:
			result.append(s)
	return result

func _enemies_in_range(caster: UnitState, all_states: Array, range_limit: float) -> Array:
	var result: Array = []
	for s in all_states:
		if s.team != caster.team and s.is_alive() and caster.position.distance_to(s.position) <= range_limit:
			result.append(s)
	return result

func _nearest_enemy_in_range(caster: UnitState, all_states: Array, range_limit: float) -> UnitState:
	var nearest: UnitState = null
	var nearest_dist := INF
	for s_variant in _enemies_in_range(caster, all_states, range_limit):
		var s: UnitState = s_variant
		var d := caster.position.distance_to(s.position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = s
	return nearest

## Fires the caster's pulsed special ability: a timed stat buff to nearby
## allies, a timed debuff to nearby enemies, or an instant heal (which
## generates a burst of threat on the healer, per game design).
func _cast_ability(caster: UnitState, all_states: Array, t: float) -> void:
	var pid := caster.passive_id
	if BUFF_ABILITIES.has(pid):
		var effects: Array = BUFF_ABILITIES[pid]
		for ally in _allies_in_range(caster, all_states, ABILITY_RANGE):
			for effect in effects:
				ally.active_effects.append({"stat": effect["stat"], "mode": effect["mode"], "value": effect["value"], "expires_at": t + ABILITY_BUFF_DURATION})
	elif DEBUFF_ABILITIES.has(pid):
		var effects: Array = DEBUFF_ABILITIES[pid]
		for enemy in _enemies_in_range(caster, all_states, ABILITY_RANGE):
			for effect in effects:
				enemy.active_effects.append({"stat": effect["stat"], "mode": effect["mode"], "value": effect["value"], "expires_at": t + ABILITY_BUFF_DURATION})
	elif HEAL_ABILITIES.has(pid):
		var heal_pct: float = HEAL_ABILITIES[pid]
		var total_healing := 0.0
		for ally_variant in _allies_in_range(caster, all_states, ABILITY_RANGE):
			var ally: UnitState = ally_variant
			var before: float = ally.health
			ally.health = min(ally.max_health, ally.health + ally.max_health * heal_pct)
			total_healing += ally.health - before
		caster.threat += total_healing * THREAT_PER_HEALING
	elif SELF_BUFF_ABILITIES.has(pid):
		var effects: Array = SELF_BUFF_ABILITIES[pid]
		for effect in effects:
			caster.active_effects.append({"stat": effect["stat"], "mode": effect["mode"], "value": effect["value"], "expires_at": t + ABILITY_BUFF_DURATION})
	elif CC_ABILITIES.has(pid):
		var cc: Dictionary = CC_ABILITIES[pid]
		var target := _nearest_enemy_in_range(caster, all_states, ABILITY_RANGE)
		if target != null:
			target.active_cc = {
				"type": cc["type"],
				"expires_at": t + cc["duration"],
				"magnitude": cc.get("magnitude", 0.0),
			}

## Picks the highest-threat living enemy, with proximity as a tie-breaker,
## instead of simply the nearest enemy -- so healers actively healing (and
## thus generating heavy threat) get focused down like a real aggro system.
func _find_target(s: UnitState, all_states: Array) -> UnitState:
	var best: UnitState = null
	var best_score := -INF
	for other in all_states:
		if other.team == s.team or not other.is_alive():
			continue
		var d := s.position.distance_to(other.position)
		var score: float = other.threat - d * 0.01
		if score > best_score:
			best_score = score
			best = other
	return best

## Rolls damage for one attack (physical uses Might vs Armor, magical uses
## Prowess vs Resistance), applies it, and handles a one-time revive if the
## target has the Rebirth passive. Returns the damage dealt (0 on a dodge).
func _resolve_attack(attacker: UnitState, target: UnitState) -> float:
	var dodge_roll: float = randf() * 100.0
	if dodge_roll < min(target.dodge_chance, MAX_DODGE_CHANCE):
		return 0.0

	var raw_stat: float
	var mitigation: float
	if attacker.damage_type == MiniPart.DamageType.MAGICAL:
		raw_stat = attacker.prowess
		mitigation = target.resistance * (1.0 - attacker.resist_pen)
	else:
		raw_stat = attacker.might
		mitigation = target.armor * (1.0 - attacker.armor_pen)

	var rolled: float = randf_range(raw_stat * (1.0 - DAMAGE_VARIANCE), raw_stat * (1.0 + DAMAGE_VARIANCE))
	var dmg: float = max(1.0, rolled - mitigation * 0.5)
	target.health -= dmg

	if target.health <= 0.0 and target.can_revive and not target.used_revive:
		target.used_revive = true
		target.health = target.max_health * 0.5

	return dmg

## Reward currency based on battle outcome and enemy difficulty.
func compute_reward(result: Dictionary, enemy_power: int) -> int:
	if result["winning_team"] != 0:
		return int(enemy_power * 0.2)
	return int(enemy_power * 1.0 + result["player_survivors"] * 10)

func squad_power(units: Array[MiniUnit]) -> int:
	var total := 0
	for u in units:
		total += u.get_power_score()
	return total

## Builds a single-faction enemy squad of exactly `size` units, each an
## independent random matching set of the given race up to max_rarity.
func generate_mono_race_squad(race: MiniPart.Race, size: int, max_rarity: MiniPart.Rarity) -> Array[MiniUnit]:
	var units: Array[MiniUnit] = []
	for i in range(size):
		var set := GachaSystem.random_matching_set_for_race_up_to(race, max_rarity)
		var unit := MiniUnit.new()
		unit.unit_id = "enemy_%d_%d" % [race, i]
		unit.unit_name = set["torso"].unit_type_name
		unit.head = set["head"]
		unit.torso = set["torso"]
		unit.legs = set["legs"]
		unit.weapon = set["weapon"]
		units.append(unit)
	return units

const ENCOUNTER_RARITY_TIERS := [MiniPart.Rarity.COMMON, MiniPart.Rarity.UNCOMMON, MiniPart.Rarity.RARE, MiniPart.Rarity.EPIC]

## Generates 3 random single-faction encounter options for the given army
## size, each with a scaled reward estimate based on opponent strength, for
## the encounter-select screen to present as cards.
func generate_encounter_options(army_size: int) -> Array:
	var races := GachaSystem.get_playable_races()
	var options: Array = []
	for i in range(3):
		var race: MiniPart.Race = races[randi() % races.size()]
		var max_rarity: MiniPart.Rarity = ENCOUNTER_RARITY_TIERS[randi() % ENCOUNTER_RARITY_TIERS.size()]
		var enemies := generate_mono_race_squad(race, army_size, max_rarity)
		var power := squad_power(enemies)
		options.append({
			"race": race,
			"max_rarity": max_rarity,
			"enemy_units": enemies,
			"enemy_power": power,
			"reward_estimate": int(power * 1.0 + army_size * 10),
		})
	return options
