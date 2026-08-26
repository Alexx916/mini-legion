extends Resource
class_name MiniUnit

## A single minifigure in the player's (or an enemy's) army, built from four
## matching parts (same race and unit type).

## Stable identity for this specific unit instance, used by saved army
## presets to reference it even if the roster order changes. Assigned once
## by GameState when the unit is created.
@export var unit_id: String = ""

@export var unit_name: String = "Recruit"
@export var head: MiniPart
@export var torso: MiniPart
@export var legs: MiniPart
@export var weapon: MiniPart

const BASE_MIGHT := 2
const BASE_PROWESS := 2
const BASE_ARMOR := 2
const BASE_RESISTANCE := 2
const BASE_HEALTH := 30
const BASE_SPEED := 60.0
const BASE_DODGE_CHANCE := 3.0

func get_parts() -> Array[MiniPart]:
	var parts: Array[MiniPart] = []
	for p in [head, torso, legs, weapon]:
		if p != null:
			parts.append(p)
	return parts

## True only if every equipped slot is filled and all parts share the same
## race and unit type. An empty/partial build is not considered matching.
func has_matching_parts() -> bool:
	if head == null or torso == null or legs == null or weapon == null:
		return false
	return head.matches_set(torso) and torso.matches_set(legs) and legs.matches_set(weapon)

func get_might() -> int:
	var total := BASE_MIGHT
	for p in get_parts():
		total += p.might
	return total

func get_prowess() -> int:
	var total := BASE_PROWESS
	for p in get_parts():
		total += p.prowess
	return total

func get_armor() -> int:
	var total := BASE_ARMOR
	for p in get_parts():
		total += p.armor
	return total

func get_resistance() -> int:
	var total := BASE_RESISTANCE
	for p in get_parts():
		total += p.resistance
	return total

func get_max_health() -> int:
	var total := BASE_HEALTH
	for p in get_parts():
		total += p.health
	return total

func get_speed() -> float:
	var total := BASE_SPEED
	for p in get_parts():
		total += p.speed
	return total

## Percent chance (0-100) to fully avoid an incoming attack. The actual
## combat roll clamps this to a sane maximum -- see BattleSim.
func get_dodge_chance() -> float:
	var total := BASE_DODGE_CHANCE
	for p in get_parts():
		total += p.dodge_chance
	return total

func get_damage_type() -> MiniPart.DamageType:
	return weapon.damage_type if weapon else MiniPart.DamageType.PHYSICAL

func get_race() -> MiniPart.Race:
	return torso.race if torso else MiniPart.Race.NONE

func get_unit_type_name() -> String:
	return torso.unit_type_name if torso else ""

func get_rarity() -> MiniPart.Rarity:
	return torso.rarity if torso else MiniPart.Rarity.COMMON

func get_passive_id() -> String:
	return torso.passive_id if torso else ""

func get_passive_name() -> String:
	return torso.passive_name if torso else ""

func get_passive_description() -> String:
	return torso.passive_description if torso else ""

func get_attack_range() -> float:
	return weapon.attack_range if weapon else 40.0

func get_attack_interval() -> float:
	return weapon.attack_interval if weapon else 1.2

func is_ranged() -> bool:
	return get_attack_range() > 100.0

func get_power_score() -> int:
	return (get_might() + get_prowess()) * 2 + (get_armor() + get_resistance()) * 2 \
		+ get_max_health() / 5 + int(get_speed() / 10.0) + int(get_dodge_chance())

## Gold received when this unit is sold from the roster. Deliberately below
## the gacha cost of the parts it took to build it, so selling is a way to
## clean up unwanted units rather than a profit loop.
func get_sell_value() -> int:
	return max(10, get_power_score() * 3)

func get_summary_line() -> String:
	var dmg := "PHY" if get_damage_type() == MiniPart.DamageType.PHYSICAL else "MAG"
	return "%s   Might %d   Prowess %d   Armor %d   Resist %d   HP %d   Speed %.0f   Dodge %.0f%%   [%s]   Power %d" % [
		unit_name, get_might(), get_prowess(), get_armor(), get_resistance(),
		get_max_health(), get_speed(), get_dodge_chance(), dmg, get_power_score()
	]
