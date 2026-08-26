extends Node

## Global game state: currency, owned parts, and the player's army roster.
## Persists to one of 3 save slots (user://save_slot_N.dat).

signal currency_changed(new_amount: int)
signal inventory_changed
signal roster_changed

var currency: int = 500

## All MiniPart resources the player owns, by part_id -> count. A part is
## consumed (count decremented) the moment it's used in assemble_unit(), so
## the same physical piece can never end up on two units.
var owned_parts: Dictionary = {}

## The player's active army.
var roster: Array[MiniUnit] = []

## Lifetime record of every unit type ever assembled or granted, keyed by
## "<race>|<unit_type_name>". Never decremented by selling -- this is a
## collection log, not a live roster count. Each entry:
## {"race": MiniPart.Race, "unit_type_name": String, "rarity": MiniPart.Rarity,
##  "passive_name": String, "passive_description": String, "count": int}
var assembled_log: Dictionary = {}

## Saved army presets, so players don't have to rebuild a squad every battle.
## Each entry: {"name": String, "size": int, "race": MiniPart.Race,
##  "unit_ids": Array[String]}
var saved_armies: Array = []

## Index into saved_armies marking the army used automatically for battle
## without visiting the Army Builder. -1 means no default is set yet.
var default_army_index: int = -1

## A one-battle-only army set via Manage Army's "Use Once" option. Shaped
## like a saved_armies entry ({"size","race","unit_ids"}); {} means none is
## pending. Consumed (cleared) the moment it's used for a battle.
var next_battle_override: Dictionary = {}

signal collection_changed
signal armies_changed

const SLOT_COUNT := 3
const SAVE_SLOT_PATHS: Array[String] = ["user://save_slot_1.dat", "user://save_slot_2.dat", "user://save_slot_3.dat"]

## Which slot the current session is playing. -1 means no slot chosen yet
## (the player is still on the slot-select screen), so save_game() is a
## no-op until a slot is active.
var current_slot: int = -1

## Transient, not persisted: the faction picked on the Faction Select screen,
## read by the Draft screen. Only meaningful mid-new-game-setup.
var draft_race: MiniPart.Race = MiniPart.Race.NONE

var _next_unit_serial: int = 0

func _generate_unit_id() -> String:
	_next_unit_serial += 1
	return "u%d_%d" % [Time.get_ticks_usec(), _next_unit_serial]

func _reset_state() -> void:
	currency = 500
	owned_parts = {}
	roster = []
	assembled_log = {}
	saved_armies = []
	default_army_index = -1
	next_battle_override = {}
	_next_unit_serial = 0

## Reads a slot's save data without disturbing the currently active session
## -- used by the slot-select screen to show a summary for each slot.
## Returns {} if the slot has no save yet.
func get_slot_summary(index: int) -> Dictionary:
	var data := _read_slot_raw(index)
	if data.is_empty():
		return {}

	var roster_units: Array = data.get("roster_units", [])
	var race_name := "Mixed"
	if not roster_units.is_empty():
		var head_id: String = roster_units[0].get("head", "")
		var part := GachaSystem.get_part_by_id(head_id)
		if part:
			race_name = MiniPart.race_name(part.race)

	return {
		"currency": data.get("currency", 0),
		"unit_count": roster_units.size(),
		"race_name": race_name,
	}

func _read_slot_raw(index: int) -> Dictionary:
	var path := SAVE_SLOT_PATHS[index]
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var data = file.get_var()
	file.close()
	return data if typeof(data) == TYPE_DICTIONARY else {}

## Loads an existing slot into the active session.
func load_slot(index: int) -> void:
	current_slot = index
	_reset_state()
	load_game()

## Starts a fresh session in the given slot (does not touch disk until the
## draft finishes and finish_draft() saves for the first time, so backing
## out of character creation leaves the slot untouched/empty).
func start_new_game(index: int) -> void:
	current_slot = index
	_reset_state()

## Called once the player finishes drafting their starting army. Adds the 5
## drafted units to the roster and performs the session's first save.
func finish_draft(drafted_units: Array[MiniUnit]) -> void:
	for unit in drafted_units:
		unit.unit_id = _generate_unit_id()
		roster.append(unit)
		_record_assembly(unit)
	roster_changed.emit()
	save_game()

func delete_slot(index: int) -> void:
	var path := SAVE_SLOT_PATHS[index]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func _record_assembly(unit: MiniUnit) -> void:
	var key := "%d|%s" % [unit.get_race(), unit.get_unit_type_name()]
	if not assembled_log.has(key):
		assembled_log[key] = {
			"race": unit.get_race(),
			"unit_type_name": unit.get_unit_type_name(),
			"rarity": unit.get_rarity(),
			"passive_name": unit.get_passive_name(),
			"passive_description": unit.get_passive_description(),
			"count": 0,
		}
	assembled_log[key]["count"] += 1
	collection_changed.emit()

func add_currency(amount: int) -> void:
	currency += amount
	currency_changed.emit(currency)
	save_game()

func spend_currency(amount: int) -> bool:
	if currency < amount:
		return false
	currency -= amount
	currency_changed.emit(currency)
	save_game()
	return true

func add_part(part: MiniPart) -> void:
	if not owned_parts.has(part.part_id):
		owned_parts[part.part_id] = {"part": part, "count": 0}
	owned_parts[part.part_id]["count"] += 1
	inventory_changed.emit()
	save_game()

func get_owned_part_counts() -> Dictionary:
	return owned_parts

func get_owned_count(part_id: String) -> int:
	if not owned_parts.has(part_id):
		return 0
	return owned_parts[part_id]["count"]

## Consumes one of each given part (by id) and adds the resulting unit to the
## roster. Returns null if any part isn't available, or if the four parts
## don't all belong to the same race+unit-type set (units can only be
## assembled from matching parts).
func assemble_unit(head: MiniPart, torso: MiniPart, legs: MiniPart, weapon: MiniPart, unit_name: String) -> MiniUnit:
	for part in [head, torso, legs, weapon]:
		if part == null or get_owned_count(part.part_id) <= 0:
			return null
	if not (head.matches_set(torso) and torso.matches_set(legs) and legs.matches_set(weapon)):
		return null

	for part in [head, torso, legs, weapon]:
		owned_parts[part.part_id]["count"] -= 1
		if owned_parts[part.part_id]["count"] <= 0:
			owned_parts.erase(part.part_id)

	var unit := MiniUnit.new()
	unit.unit_id = _generate_unit_id()
	unit.unit_name = unit_name if not unit_name.is_empty() else "%s %s" % [MiniPart.race_name(torso.race), torso.unit_type_name]
	unit.head = head
	unit.torso = torso
	unit.legs = legs
	unit.weapon = weapon
	roster.append(unit)
	_record_assembly(unit)

	inventory_changed.emit()
	roster_changed.emit()
	save_game()
	return unit

## Groups owned parts into buildable unit sets (one entry per race+unit-type
## combination present in the inventory), so the Inventory screen can show
## "units to assemble" instead of raw parts. Each entry:
## {"race", "unit_type_name", "rarity", "passive_name", "passive_description",
##  "parts": {Slot: MiniPart}, "counts": {Slot: int}, "buildable_count": int}
## buildable_count is the number of complete 4-part sets available (0 if any
## slot is missing entirely). Sorted with the most-buildable, highest-rarity
## sets first.
func get_buildable_sets() -> Array:
	var groups: Dictionary = {}
	for id in owned_parts.keys():
		var entry: Dictionary = owned_parts[id]
		var part: MiniPart = entry["part"]
		var key := "%d|%s" % [part.race, part.unit_type_name]
		if not groups.has(key):
			groups[key] = {
				"race": part.race,
				"unit_type_name": part.unit_type_name,
				"rarity": part.rarity,
				"passive_name": part.passive_name,
				"passive_description": part.passive_description,
				"parts": {},
				"counts": {},
			}
		groups[key]["parts"][part.slot] = part
		groups[key]["counts"][part.slot] = entry["count"]

	var result: Array = []
	for key in groups.keys():
		var g: Dictionary = groups[key]
		var min_count: int = g["counts"].get(MiniPart.Slot.HEAD, 0)
		min_count = min(min_count, g["counts"].get(MiniPart.Slot.TORSO, 0))
		min_count = min(min_count, g["counts"].get(MiniPart.Slot.LEGS, 0))
		min_count = min(min_count, g["counts"].get(MiniPart.Slot.WEAPON, 0))
		g["buildable_count"] = min_count
		result.append(g)

	result.sort_custom(func(a, b):
		if a["buildable_count"] != b["buildable_count"]:
			return a["buildable_count"] > b["buildable_count"]
		return a["rarity"] > b["rarity"]
	)
	return result

## Assembles one unit from a buildable-set entry returned by
## get_buildable_sets(). Returns null if the set isn't actually complete.
func assemble_from_group(group: Dictionary) -> MiniUnit:
	var parts: Dictionary = group["parts"]
	if not (parts.has(MiniPart.Slot.HEAD) and parts.has(MiniPart.Slot.TORSO) and parts.has(MiniPart.Slot.LEGS) and parts.has(MiniPart.Slot.WEAPON)):
		return null
	return assemble_unit(parts[MiniPart.Slot.HEAD], parts[MiniPart.Slot.TORSO], parts[MiniPart.Slot.LEGS], parts[MiniPart.Slot.WEAPON], "")

## Removes a unit from the roster and pays out its sell value in gold.
func sell_unit(unit: MiniUnit) -> int:
	var index := roster.find(unit)
	if index == -1:
		return 0
	var value := unit.get_sell_value()
	roster.remove_at(index)
	currency += value
	currency_changed.emit(currency)
	roster_changed.emit()
	save_game()
	return value

## Saves the given roster units as a named army preset for quick reuse. Only
## the unit ids are stored -- if a unit is later sold, the preset simply
## loads fewer units next time (resolve_army_units skips missing ones).
func save_army(name: String, units: Array) -> void:
	var unit_ids: Array = []
	for u in units:
		unit_ids.append(u.unit_id)
	var race: MiniPart.Race = units[0].get_race() if not units.is_empty() else MiniPart.Race.NONE
	saved_armies.append({
		"name": name if not name.is_empty() else "Army %d" % (saved_armies.size() + 1),
		"size": units.size(),
		"race": race,
		"unit_ids": unit_ids,
	})
	armies_changed.emit()
	save_game()

func delete_army(index: int) -> void:
	if index < 0 or index >= saved_armies.size():
		return
	saved_armies.remove_at(index)
	if default_army_index == index:
		default_army_index = -1
	elif default_army_index > index:
		default_army_index -= 1
	armies_changed.emit()
	save_game()

## Resolves a saved army's unit ids back into live MiniUnit references,
## silently dropping any that no longer exist in the roster (sold, etc).
func resolve_army_units(army: Dictionary) -> Array[MiniUnit]:
	var units: Array[MiniUnit] = []
	var by_id: Dictionary = {}
	for u in roster:
		by_id[u.unit_id] = u
	for id in army["unit_ids"]:
		if by_id.has(id):
			units.append(by_id[id])
	return units

func get_default_army() -> Dictionary:
	if default_army_index < 0 or default_army_index >= saved_armies.size():
		return {}
	return saved_armies[default_army_index]

## Sets (or replaces) the default army used automatically for battle. If a
## default already exists it's overwritten in place; otherwise a new preset
## is appended and marked default.
func set_default_army(size: int, race: MiniPart.Race, unit_ids: Array) -> void:
	var entry := {
		"name": get_default_army().get("name", "Default Army") if default_army_index != -1 else "Default Army",
		"size": size,
		"race": race,
		"unit_ids": unit_ids,
	}
	if default_army_index != -1:
		saved_armies[default_army_index] = entry
	else:
		saved_armies.append(entry)
		default_army_index = saved_armies.size() - 1
	armies_changed.emit()
	save_game()

func set_default_army_index(index: int) -> void:
	if index >= -1 and index < saved_armies.size():
		default_army_index = index
		armies_changed.emit()
		save_game()

## Sets a one-time army override for the very next battle only. Doesn't
## touch the default army.
func set_next_battle_override(size: int, race: MiniPart.Race, unit_ids: Array) -> void:
	next_battle_override = {"size": size, "race": race, "unit_ids": unit_ids}
	save_game()

## Returns the units to field for the next battle -- the one-time override
## if set (consuming it), otherwise the default army, otherwise []. An empty
## result means the caller should fall back to the Army Builder.
func consume_battle_army() -> Array[MiniUnit]:
	if not next_battle_override.is_empty():
		var units := resolve_army_units(next_battle_override)
		next_battle_override = {}
		save_game()
		return units
	var default_army := get_default_army()
	if default_army.is_empty():
		return []
	return resolve_army_units(default_army)

func save_game() -> void:
	if current_slot == -1:
		return
	var data := {
		"currency": currency,
		"owned_part_ids": [],
		"owned_counts": [],
		"roster_units": [],
		"assembled_log": [],
		"saved_armies": saved_armies,
		"default_army_index": default_army_index,
		"next_battle_override": next_battle_override,
		"next_unit_serial": _next_unit_serial,
	}
	for id in owned_parts.keys():
		data["owned_part_ids"].append(id)
		data["owned_counts"].append(owned_parts[id]["count"])

	for unit in roster:
		data["roster_units"].append({
			"id": unit.unit_id,
			"name": unit.unit_name,
			"head": unit.head.part_id if unit.head else "",
			"torso": unit.torso.part_id if unit.torso else "",
			"legs": unit.legs.part_id if unit.legs else "",
			"weapon": unit.weapon.part_id if unit.weapon else "",
		})

	for entry in assembled_log.values():
		data["assembled_log"].append(entry)

	var file := FileAccess.open(SAVE_SLOT_PATHS[current_slot], FileAccess.WRITE)
	if file:
		file.store_var(data)
		file.close()

func load_game() -> void:
	if current_slot == -1:
		return
	var data := _read_slot_raw(current_slot)
	if data.is_empty():
		return

	currency = data.get("currency", currency)

	var ids: Array = data.get("owned_part_ids", [])
	var counts: Array = data.get("owned_counts", [])
	for i in range(ids.size()):
		var part := GachaSystem.get_part_by_id(ids[i])
		if part:
			owned_parts[ids[i]] = {"part": part, "count": counts[i]}

	var saved_units: Array = data.get("roster_units", [])
	for entry in saved_units:
		var unit := MiniUnit.new()
		unit.unit_id = entry.get("id", _generate_unit_id())
		unit.unit_name = entry.get("name", "Recruit")
		unit.head = GachaSystem.get_part_by_id(entry.get("head", ""))
		unit.torso = GachaSystem.get_part_by_id(entry.get("torso", ""))
		unit.legs = GachaSystem.get_part_by_id(entry.get("legs", ""))
		unit.weapon = GachaSystem.get_part_by_id(entry.get("weapon", ""))
		roster.append(unit)

	var log_entries: Array = data.get("assembled_log", [])
	for entry in log_entries:
		var key := "%d|%s" % [entry["race"], entry["unit_type_name"]]
		assembled_log[key] = entry

	saved_armies = data.get("saved_armies", [])
	default_army_index = data.get("default_army_index", -1)
	next_battle_override = data.get("next_battle_override", {})
	_next_unit_serial = data.get("next_unit_serial", 0)
