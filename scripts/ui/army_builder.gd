extends Control

@onready var back_button: Button = $MarginContainer/VBoxContainer/TopBar/BackButton
@onready var currency_label: Label = $MarginContainer/VBoxContainer/TopBar/CurrencyLabel
@onready var size3_button: Button = $MarginContainer/VBoxContainer/SizeBar/Size3Button
@onready var size4_button: Button = $MarginContainer/VBoxContainer/SizeBar/Size4Button
@onready var size5_button: Button = $MarginContainer/VBoxContainer/SizeBar/Size5Button
@onready var saved_armies_list: HBoxContainer = $MarginContainer/VBoxContainer/SavedArmiesPanel/SavedArmiesList
@onready var selection_summary: Label = $MarginContainer/VBoxContainer/SelectionSummary
@onready var roster_grid: GridContainer = $MarginContainer/VBoxContainer/ScrollContainer/RosterGrid
@onready var army_name_edit: LineEdit = $MarginContainer/VBoxContainer/BottomBar/ArmyNameEdit
@onready var save_army_button: Button = $MarginContainer/VBoxContainer/BottomBar/SaveArmyButton
@onready var continue_button: Button = $MarginContainer/VBoxContainer/BottomBar/ContinueButton

var army_size: int = 3
var selected_ids: Array[String] = []
var _size_group: ButtonGroup

func _ready() -> void:
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn"))
	continue_button.pressed.connect(_on_continue)
	save_army_button.pressed.connect(_on_save_army)
	GameState.currency_changed.connect(func(_v): _update_currency())
	GameState.armies_changed.connect(_refresh_saved_armies)

	_size_group = ButtonGroup.new()
	size3_button.button_group = _size_group
	size4_button.button_group = _size_group
	size5_button.button_group = _size_group
	size3_button.pressed.connect(func(): _set_army_size(3))
	size4_button.pressed.connect(func(): _set_army_size(4))
	size5_button.pressed.connect(func(): _set_army_size(5))
	size3_button.button_pressed = true

	_update_currency()
	_refresh_saved_armies()
	_refresh_roster()

func _update_currency() -> void:
	currency_label.text = "Gold: %d" % GameState.currency

func _set_army_size(size: int) -> void:
	army_size = size
	if selected_ids.size() > army_size:
		selected_ids = selected_ids.slice(0, army_size)
	_refresh_roster()

## The race lock: once a non-neutral unit is selected, only that race (plus
## the always-eligible neutral legendaries) can be added -- "only the same
## faction in each army", with the neutral figures as the documented exception.
func _locked_race() -> int:
	for id in selected_ids:
		var unit := _find_unit(id)
		if unit and unit.get_race() != MiniPart.Race.NONE:
			return unit.get_race()
	return -1

func _find_unit(id: String) -> MiniUnit:
	for u in GameState.roster:
		if u.unit_id == id:
			return u
	return null

func _refresh_roster() -> void:
	for child in roster_grid.get_children():
		child.queue_free()

	var lock := _locked_race()
	for unit in GameState.roster:
		var eligible := lock == -1 or unit.get_race() == lock or unit.get_race() == MiniPart.Race.NONE
		var selected := selected_ids.has(unit.unit_id)
		roster_grid.add_child(_build_unit_card(unit, eligible, selected))

	selection_summary.text = "Selected: %d/%d%s" % [
		selected_ids.size(), army_size,
		"  (%s)" % MiniPart.race_name(lock) if lock != -1 else ""
	]
	continue_button.disabled = selected_ids.size() != army_size

func _build_unit_card(unit: MiniUnit, eligible: bool, selected: bool) -> Button:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_pressed = selected
	btn.custom_minimum_size = Vector2(200, 90)
	btn.text = "%s\n%s (%s)\nPower %d" % [
		unit.unit_name, MiniPart.race_name(unit.get_race()), MiniPart.rarity_name(unit.get_rarity()), unit.get_power_score()
	]
	btn.add_theme_color_override("font_color", MiniPart.rarity_color(unit.get_rarity()))
	if not eligible and not selected:
		btn.disabled = true
		btn.modulate = Color(1, 1, 1, 0.4)
	btn.pressed.connect(func(): _on_toggle_unit(unit))
	return btn

func _on_toggle_unit(unit: MiniUnit) -> void:
	if selected_ids.has(unit.unit_id):
		selected_ids.erase(unit.unit_id)
	elif selected_ids.size() < army_size:
		selected_ids.append(unit.unit_id)
	_refresh_roster()

func _refresh_saved_armies() -> void:
	for child in saved_armies_list.get_children():
		child.queue_free()

	if GameState.saved_armies.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No saved armies yet."
		empty_label.modulate = Color(1, 1, 1, 0.5)
		saved_armies_list.add_child(empty_label)
		return

	for i in range(GameState.saved_armies.size()):
		var army: Dictionary = GameState.saved_armies[i]
		var box := HBoxContainer.new()

		var load_button := Button.new()
		load_button.text = "%s (%d, %s)" % [army["name"], army["size"], MiniPart.race_name(army["race"])]
		load_button.pressed.connect(func(): _on_load_army(army))
		box.add_child(load_button)

		var delete_button := Button.new()
		delete_button.text = "x"
		delete_button.pressed.connect(func(): GameState.delete_army(i))
		box.add_child(delete_button)

		saved_armies_list.add_child(box)

func _on_load_army(army: Dictionary) -> void:
	var units := GameState.resolve_army_units(army)
	army_size = army["size"]
	match army_size:
		3: size3_button.button_pressed = true
		4: size4_button.button_pressed = true
		5: size5_button.button_pressed = true
	selected_ids.clear()
	for u in units:
		selected_ids.append(u.unit_id)
	_refresh_roster()

func _on_save_army() -> void:
	if selected_ids.is_empty():
		return
	var units: Array[MiniUnit] = []
	for id in selected_ids:
		var u := _find_unit(id)
		if u:
			units.append(u)
	GameState.save_army(army_name_edit.text.strip_edges(), units)
	army_name_edit.text = ""

func _on_continue() -> void:
	var units: Array[MiniUnit] = []
	for id in selected_ids:
		var u := _find_unit(id)
		if u:
			units.append(u)
	BattleSim.pending_player_units = units
	get_tree().change_scene_to_file("res://scenes/battle/encounter_select.tscn")
