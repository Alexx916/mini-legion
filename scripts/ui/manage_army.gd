extends Control

@onready var back_button: Button = $MarginContainer/VBoxContainer/TopBar/BackButton
@onready var currency_label: Label = $MarginContainer/VBoxContainer/TopBar/CurrencyLabel
@onready var size3_button: Button = $MarginContainer/VBoxContainer/SizeBar/Size3Button
@onready var size4_button: Button = $MarginContainer/VBoxContainer/SizeBar/Size4Button
@onready var size5_button: Button = $MarginContainer/VBoxContainer/SizeBar/Size5Button
@onready var selection_summary: Label = $MarginContainer/VBoxContainer/SelectionSummary
@onready var roster_grid: GridContainer = $MarginContainer/VBoxContainer/ScrollContainer/RosterGrid
@onready var confirm_button: Button = $MarginContainer/VBoxContainer/ConfirmButton

var army_size: int = 3
var selected_ids: Array[String] = []
var _size_group: ButtonGroup

func _ready() -> void:
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/barracks/barracks.tscn"))
	confirm_button.pressed.connect(_on_confirm)
	GameState.currency_changed.connect(func(_v): _update_currency())

	_size_group = ButtonGroup.new()
	size3_button.button_group = _size_group
	size4_button.button_group = _size_group
	size5_button.button_group = _size_group
	size3_button.pressed.connect(func(): _set_army_size(3))
	size4_button.pressed.connect(func(): _set_army_size(4))
	size5_button.pressed.connect(func(): _set_army_size(5))

	_seed_from_default_army()
	_update_currency()
	_refresh_roster()

## Starts the editor pre-loaded with whatever the current default army is,
## so "Manage Army" feels like editing, not starting from scratch.
func _seed_from_default_army() -> void:
	var default_army := GameState.get_default_army()
	if default_army.is_empty():
		army_size = 3
		size3_button.button_pressed = true
		return

	army_size = default_army["size"]
	match army_size:
		3: size3_button.button_pressed = true
		4: size4_button.button_pressed = true
		5: size5_button.button_pressed = true
	for u in GameState.resolve_army_units(default_army):
		selected_ids.append(u.unit_id)

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
	confirm_button.disabled = selected_ids.size() != army_size

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

## Presents the "next battle only / save as default / discard" choice
## required whenever the player confirms changes here, per game design.
func _on_confirm() -> void:
	var race := _locked_race()
	if race == -1:
		race = MiniPart.Race.NONE

	var dialog := AcceptDialog.new()
	dialog.title = "Save Changes?"
	dialog.dialog_text = "How should this army be used?"
	dialog.get_ok_button().visible = false
	dialog.add_button("Use Once", true, "use_once")
	dialog.add_button("Save as Default", true, "save_default")
	dialog.add_button("Discard", true, "discard")
	add_child(dialog)

	dialog.custom_action.connect(func(action: StringName):
		match String(action):
			"use_once":
				GameState.set_next_battle_override(army_size, race, selected_ids.duplicate())
			"save_default":
				GameState.set_default_army(army_size, race, selected_ids.duplicate())
			"discard":
				pass
		dialog.queue_free()
		get_tree().change_scene_to_file("res://scenes/barracks/barracks.tscn")
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
